import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// WebSocket transport implementation connecting to ephemeral cloud relay server.
/// Zero-knowledge blind forwarding pipeline: relay server only sees encrypted blobs.
public final class WebSocketTransport: SyncTransport, @unchecked Sendable {
    private let url: URL
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?

    private let lock = NSLock()
    private var _state: TransportState = .disconnected
    private var messageWaiters: [CheckedContinuation<SyncMessage, Error>] = []
    private var messageQueue: [SyncMessage] = []
    private var streamContinuations: [AsyncStream<SyncMessage>.Continuation] = []

    private func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public var state: TransportState {
        withLock { _state }
    }

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func connect() async throws {
        let task = session.webSocketTask(with: url)
        withLock {
            self.webSocketTask = task
            self._state = .connected
        }

        task.resume()
        startListening()
    }

    public func send(message: SyncMessage) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        try await send(data: data)
    }

    public func send(data: Data) async throws {
        let task: URLSessionWebSocketTask? = withLock {
            self.webSocketTask
        }
        guard let task = task else {
            throw TransportError.notConnected
        }
        let wsMessage = URLSessionWebSocketTask.Message.data(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(wsMessage) { error in
                if let error = error {
                    continuation.resume(throwing: TransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
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
                    messageWaiters.append(continuation)
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
                self?.removeStreamContinuation(continuation)
            }
        }
    }

    private func removeStreamContinuation(_ target: AsyncStream<SyncMessage>.Continuation) {
        withLock {
            streamContinuations.removeAll { _ in false }
        }
    }

    private func startListening() {
        let task: URLSessionWebSocketTask? = withLock {
            self.webSocketTask
        }
        guard let task = task else { return }
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                self.handleIncomingWebSocketMessage(message)
                self.startListening()
            case .failure(let error):
                self.handleFailure(error)
            }
        }
    }

    private func handleIncomingWebSocketMessage(_ wsMessage: URLSessionWebSocketTask.Message) {
        let data: Data
        switch wsMessage {
        case .data(let d):
            data = d
        case .string(let s):
            data = Data(s.utf8)
        @unknown default:
            return
        }

        let decoder = JSONDecoder()
        guard let syncMessage = try? decoder.decode(SyncMessage.self, from: data) else {
            return
        }

        withLock {
            for cont in streamContinuations {
                cont.yield(syncMessage)
            }
            if !messageWaiters.isEmpty {
                let waiter = messageWaiters.removeFirst()
                waiter.resume(returning: syncMessage)
            } else {
                messageQueue.append(syncMessage)
            }
        }
    }

    private func handleFailure(_ error: Error) {
        let waiters: [CheckedContinuation<SyncMessage, Error>] = withLock {
            _state = .failed(error.localizedDescription)
            let w = messageWaiters
            messageWaiters.removeAll()
            for cont in streamContinuations {
                cont.finish()
            }
            streamContinuations.removeAll()
            return w
        }

        for w in waiters {
            w.resume(throwing: TransportError.receiveFailed(error.localizedDescription))
        }
    }

    public func close() async {
        let (task, waiters): (URLSessionWebSocketTask?, [CheckedContinuation<SyncMessage, Error>]) = withLock {
            _state = .disconnected
            let t = webSocketTask
            webSocketTask = nil
            let w = messageWaiters
            messageWaiters.removeAll()
            for cont in streamContinuations {
                cont.finish()
            }
            streamContinuations.removeAll()
            return (t, w)
        }

        task?.cancel(with: .normalClosure, reason: nil)
        for w in waiters {
            w.resume(throwing: TransportError.connectionClosed)
        }
    }
}
