import Foundation

/// Active communication route chosen by `FallbackSyncTransport`.
public enum ActiveRoute: String, Sendable, Equatable, CaseIterable {
    case webSocket
    case bonjour
}

/// Fallback hybrid transport that prioritizes WebSocket relay and falls back to
/// local P2P Bonjour if the relay server is unreachable, times out, or fails.
/// If `preferLocalOnly` is set, it connects directly via Bonjour.
public final class FallbackSyncTransport: SyncTransport, @unchecked Sendable {
    public typealias ActiveRoute = SyncKit.ActiveRoute

    public let primary: any SyncTransport
    public let fallback: any SyncTransport
    public let preferLocalOnly: Bool
    public let primaryConnectTimeoutNanoseconds: UInt64

    private let lock = NSLock()
    private var _activeRoute: ActiveRoute?
    private var _state: TransportState = .disconnected
    private var streamContinuations: [UUID: AsyncStream<SyncMessage>.Continuation] = [:]
    private var streamingTask: Task<Void, Never>?
    private var failoverTask: Task<Void, Error>?

    private func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Thread-safe active communication route currently in use.
    public var activeRoute: ActiveRoute? {
        withLock { _activeRoute }
    }

    /// Current transport state, delegating to the active transport if connected.
    public var state: TransportState {
        get async {
            if let transport = activeTransport {
                return await transport.state
            }
            return withLock { _state }
        }
    }

    /// Currently active underlying transport instance.
    public var activeTransport: (any SyncTransport)? {
        withLock {
            switch _activeRoute {
            case .webSocket:
                return primary
            case .bonjour:
                return fallback
            case .none:
                return nil
            }
        }
    }

    public init(
        primary: any SyncTransport,
        fallback: any SyncTransport,
        preferLocalOnly: Bool = false,
        primaryConnectTimeoutNanoseconds: UInt64 = 3_000_000_000
    ) {
        self.primary = primary
        self.fallback = fallback
        self.preferLocalOnly = preferLocalOnly
        self.primaryConnectTimeoutNanoseconds = primaryConnectTimeoutNanoseconds
    }

    public func connect() async throws {
        withLock {
            _state = .connecting
            _activeRoute = nil
        }

        if preferLocalOnly {
            do {
                try await fallback.connect()
                withLock {
                    _activeRoute = .bonjour
                    _state = .connected
                }
                attachStreamForwarding(to: fallback)
            } catch {
                withLock {
                    _activeRoute = nil
                    _state = .failed(error.localizedDescription)
                }
                throw error
            }
            return
        }

        var primarySucceeded = false
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.primary.connect()
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: self.primaryConnectTimeoutNanoseconds)
                    throw TransportError.timeout
                }
                try await group.next()
                group.cancelAll()
            }
            primarySucceeded = true
        } catch {
            primarySucceeded = false
        }

        if primarySucceeded {
            withLock {
                _activeRoute = .webSocket
                _state = .connected
            }
            attachStreamForwarding(to: primary)
        } else {
            await primary.close()
            do {
                try await fallback.connect()
                withLock {
                    _activeRoute = .bonjour
                    _state = .connected
                }
                attachStreamForwarding(to: fallback)
            } catch {
                withLock {
                    _activeRoute = nil
                    _state = .failed(error.localizedDescription)
                }
                throw error
            }
        }
    }

    private func performFailover() async throws {
        let task: Task<Void, Error> = withLock {
            if _activeRoute == .bonjour {
                return Task { }
            }
            if let existing = failoverTask {
                return existing
            }
            let newTask = Task { [weak self] () throws -> Void in
                guard let self = self else { return }
                await self.primary.close()
                do {
                    try await self.fallback.connect()
                    self.withLock {
                        self._activeRoute = .bonjour
                        self._state = .connected
                        self.failoverTask = nil
                    }
                    self.attachStreamForwarding(to: self.fallback)
                } catch {
                    self.withLock {
                        self._activeRoute = nil
                        self._state = .failed(error.localizedDescription)
                        self.failoverTask = nil
                    }
                    throw error
                }
            }
            self.failoverTask = newTask
            return newTask
        }

        try await task.value
    }

    public func send(message: SyncMessage) async throws {
        guard let currentRoute = activeRoute else {
            throw TransportError.notConnected
        }

        if currentRoute == .bonjour || preferLocalOnly {
            guard let transport = activeTransport else {
                throw TransportError.notConnected
            }
            try await transport.send(message: message)
            return
        }

        var shouldFailover = false
        let primaryState = await primary.state
        if case .failed = primaryState {
            shouldFailover = true
        } else {
            do {
                try await primary.send(message: message)
                return
            } catch {
                if error is CancellationError {
                    throw error
                }
                shouldFailover = true
            }
        }

        if shouldFailover {
            try await performFailover()
            try await fallback.send(message: message)
        }
    }

    public func send(data: Data) async throws {
        guard let currentRoute = activeRoute else {
            throw TransportError.notConnected
        }

        if currentRoute == .bonjour || preferLocalOnly {
            guard let transport = activeTransport else {
                throw TransportError.notConnected
            }
            try await transport.send(data: data)
            return
        }

        var shouldFailover = false
        let primaryState = await primary.state
        if case .failed = primaryState {
            shouldFailover = true
        } else {
            do {
                try await primary.send(data: data)
                return
            } catch {
                if error is CancellationError {
                    throw error
                }
                shouldFailover = true
            }
        }

        if shouldFailover {
            try await performFailover()
            try await fallback.send(data: data)
        }
    }

    public func receive() async throws -> SyncMessage {
        guard let currentRoute = activeRoute else {
            throw TransportError.notConnected
        }

        if currentRoute == .bonjour || preferLocalOnly {
            guard let transport = activeTransport else {
                throw TransportError.notConnected
            }
            return try await transport.receive()
        }

        var shouldFailover = false
        let primaryState = await primary.state
        if case .failed = primaryState {
            shouldFailover = true
        } else {
            do {
                return try await primary.receive()
            } catch {
                if error is CancellationError {
                    throw error
                }
                shouldFailover = true
            }
        }

        if shouldFailover {
            try await performFailover()
            return try await fallback.receive()
        }

        throw TransportError.notConnected
    }

    public func makeMessageStream() -> AsyncStream<SyncMessage> {
        if let transport = activeTransport {
            return transport.makeMessageStream()
        }
        let id = UUID()
        return AsyncStream<SyncMessage> { continuation in
            withLock {
                streamContinuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.withLock {
                    _ = self?.streamContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    private func attachStreamForwarding(to transport: any SyncTransport) {
        let hasContinuations = withLock { !streamContinuations.isEmpty }
        guard hasContinuations else { return }

        let stream = transport.makeMessageStream()
        let newTask = Task { [weak self] in
            for await msg in stream {
                guard let self = self else { break }
                let conts = self.withLock { Array(self.streamContinuations.values) }
                for c in conts {
                    c.yield(msg)
                }
            }
        }

        let oldTask: Task<Void, Never>? = withLock {
            let prev = streamingTask
            if _state == .connected {
                streamingTask = newTask
            } else {
                streamingTask = nil
                newTask.cancel()
            }
            return prev
        }
        oldTask?.cancel()
    }

    /// Disconnects the transport session. Calls `close()`.
    public func disconnect() async {
        await close()
    }

    /// Closes and tears down both primary and fallback transports.
    public func close() async {
        let (task, conts, fTask): (Task<Void, Never>?, [AsyncStream<SyncMessage>.Continuation], Task<Void, Error>?) = withLock {
            _activeRoute = nil
            _state = .disconnected
            let t = streamingTask
            streamingTask = nil
            let f = failoverTask
            failoverTask = nil
            let list = Array(streamContinuations.values)
            streamContinuations.removeAll()
            return (t, list, f)
        }

        fTask?.cancel()
        task?.cancel()
        for c in conts {
            c.finish()
        }

        await primary.close()
        await fallback.close()
    }
}
