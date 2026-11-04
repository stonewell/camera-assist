import Foundation

/// State of an active sync transport channel.
public enum TransportState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

/// Errors raised during transport operations.
public enum TransportError: Error, Equatable, Sendable {
    case notConnected
    case peerUnavailable
    case connectionClosed
    case sendFailed(String)
    case receiveFailed(String)
    case timeout
}

/// Abstract transport protocol for ephemeral cross-device communication.
/// Implementations include InMemoryTransport (unit tests), WebSocketTransport (cloud relay),
/// and BonjourTransport (local P2P fallback).
public protocol SyncTransport: AnyObject, Sendable {
    var state: TransportState { get async }
    func connect() async throws
    func send(message: SyncMessage) async throws
    func send(data: Data) async throws
    func receive() async throws -> SyncMessage
    func makeMessageStream() -> AsyncStream<SyncMessage>
    func close() async
}

/// In-memory bidirectional transport implementation for testing and simulation.
/// Guaranteed 100% pure Swift, zero network dependencies, thread-safe.
public final class InMemoryTransport: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: TransportState = .disconnected
    private weak var peer: InMemoryTransport?

    private var messageQueue: [SyncMessage] = []
    private var waiters: [CheckedContinuation<SyncMessage, Error>] = []
    private var streamContinuations: [AsyncStream<SyncMessage>.Continuation] = []

    public var simulatedLatencySeconds: Double = 0.0

    private func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public var state: TransportState {
        withLock { _state }
    }

    public init() {}

    /// Creates an interconnected pair of in-memory transports (e.g. for owner and guest).
    public static func createPair() -> (InMemoryTransport, InMemoryTransport) {
        let t1 = InMemoryTransport()
        let t2 = InMemoryTransport()
        t1.setPeer(t2)
        t2.setPeer(t1)
        return (t1, t2)
    }

    public func setPeer(_ peer: InMemoryTransport) {
        withLock {
            self.peer = peer
        }
    }

    public func connect() async throws {
        withLock {
            _state = .connected
        }
    }

    public func send(message: SyncMessage) async throws {
        let (peer, latency): (InMemoryTransport?, Double) = try withLock {
            guard _state == .connected else {
                throw TransportError.notConnected
            }
            guard let peer = self.peer else {
                throw TransportError.peerUnavailable
            }
            return (peer, simulatedLatencySeconds)
        }

        if latency > 0 {
            let delayNs = UInt64(latency * 1_000_000_000)
            try await Task.sleep(nanoseconds: delayNs)
        }
        peer?.deliver(message: message)
    }

    public func send(data: Data) async throws {
        let decoder = JSONDecoder()
        do {
            let msg = try decoder.decode(SyncMessage.self, from: data)
            try await send(message: msg)
        } catch {
            throw TransportError.sendFailed("Failed to decode SyncMessage: \(error)")
        }
    }

    /// Internal message delivery called by peer endpoint.
    public func deliver(message: SyncMessage) {
        withLock {
            for cont in streamContinuations {
                cont.yield(message)
            }
            if !waiters.isEmpty {
                let waiter = waiters.removeFirst()
                waiter.resume(returning: message)
            } else {
                messageQueue.append(message)
            }
        }
    }

    public func receive() async throws -> SyncMessage {
        enum ReceiveAction {
            case immediate(SyncMessage)
            case wait
            case closed
        }

        let action: ReceiveAction = withLock {
            if !messageQueue.isEmpty {
                return .immediate(messageQueue.removeFirst())
            }
            if _state == .connected || _state == .connecting {
                return .wait
            }
            return .closed
        }

        switch action {
        case .immediate(let msg):
            return msg
        case .closed:
            throw TransportError.connectionClosed
        case .wait:
            return try await withCheckedThrowingContinuation { continuation in
                withLock {
                    waiters.append(continuation)
                }
            }
        }
    }

    public func makeMessageStream() -> AsyncStream<SyncMessage> {
        AsyncStream<SyncMessage> { continuation in
            withLock {
                streamContinuations.append(continuation)
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(continuation)
            }
        }
    }

    private func removeContinuation(_ target: AsyncStream<SyncMessage>.Continuation) {
        withLock {
            streamContinuations.removeAll { _ in false }
        }
    }

    public func close() async {
        let pending: [CheckedContinuation<SyncMessage, Error>] = withLock {
            _state = .disconnected
            let p = waiters
            waiters.removeAll()
            for cont in streamContinuations {
                cont.finish()
            }
            streamContinuations.removeAll()
            return p
        }

        for waiter in pending {
            waiter.resume(throwing: TransportError.connectionClosed)
        }
    }
}
