import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// WebSocket transport implementation connecting to ephemeral cloud relay server.
/// Zero-knowledge blind forwarding pipeline: relay server only sees encrypted blobs.
public final class WebSocketTransport: SyncTransport, @unchecked Sendable {

    /// Reconnection and keepalive configuration options.
    public struct Configuration: Sendable, Equatable {
        public var initialBackoffSeconds: Double
        public var maxBackoffSeconds: Double
        public var heartbeatIntervalSeconds: Double
        public var maxOutboxSize: Int
        public var autoReconnect: Bool

        public init(
            initialBackoffSeconds: Double = 1.0,
            maxBackoffSeconds: Double = 30.0,
            heartbeatIntervalSeconds: Double = 15.0,
            maxOutboxSize: Int = 32,
            autoReconnect: Bool = true
        ) {
            self.initialBackoffSeconds = initialBackoffSeconds
            self.maxBackoffSeconds = maxBackoffSeconds
            self.heartbeatIntervalSeconds = heartbeatIntervalSeconds
            self.maxOutboxSize = maxOutboxSize
            self.autoReconnect = autoReconnect
        }
    }

    public let configuration: Configuration
    public var initialBackoffSeconds: Double { configuration.initialBackoffSeconds }
    public var maxBackoffSeconds: Double { configuration.maxBackoffSeconds }
    public var heartbeatIntervalSeconds: Double { configuration.heartbeatIntervalSeconds }
    public var maxOutboxSize: Int { configuration.maxOutboxSize }
    public var autoReconnect: Bool { configuration.autoReconnect }

    private let url: URL
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?

    private let lock = NSLock()
    private var _state: TransportState = .disconnected
    private var _currentBackoffSeconds: Double
    private var isExplicitlyClosed: Bool = false
    private var isClosedByUser: Bool {
        get { isExplicitlyClosed }
        set { isExplicitlyClosed = newValue }
    }
    private var isFlushingOutbox: Bool = false

    private var outboxQueue: [Data] = []
    private var messageWaiters: [CheckedContinuation<SyncMessage, Error>] = []
    private var messageQueue: [SyncMessage] = []
    private var streamContinuations: [UUID: AsyncStream<SyncMessage>.Continuation] = [:]

    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    private func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    public var state: TransportState {
        withLock { _state }
    }

    /// Current exponential backoff delay in seconds.
    public var currentBackoffSeconds: Double {
        withLock { _currentBackoffSeconds }
    }

    /// Number of queued messages waiting in outbox while reconnecting.
    public var outboxCount: Int {
        withLock { outboxQueue.count }
    }

    /// Snapshot copy of queued messages in outbox.
    public var outbox: [Data] {
        withLock { outboxQueue }
    }

    public init(
        url: URL,
        session: URLSession = .shared,
        initialBackoffSeconds: Double = 1.0,
        maxBackoffSeconds: Double = 30.0,
        heartbeatIntervalSeconds: Double = 15.0,
        maxOutboxSize: Int = 32,
        autoReconnect: Bool = true
    ) {
        self.url = url
        self.session = session
        self.configuration = Configuration(
            initialBackoffSeconds: initialBackoffSeconds,
            maxBackoffSeconds: maxBackoffSeconds,
            heartbeatIntervalSeconds: heartbeatIntervalSeconds,
            maxOutboxSize: maxOutboxSize,
            autoReconnect: autoReconnect
        )
        self._currentBackoffSeconds = initialBackoffSeconds
    }

    public convenience init(
        url: URL,
        session: URLSession = .shared,
        configuration: Configuration
    ) {
        self.init(
            url: url,
            session: session,
            initialBackoffSeconds: configuration.initialBackoffSeconds,
            maxBackoffSeconds: configuration.maxBackoffSeconds,
            heartbeatIntervalSeconds: configuration.heartbeatIntervalSeconds,
            maxOutboxSize: configuration.maxOutboxSize,
            autoReconnect: configuration.autoReconnect
        )
    }

    public func connect() async throws {
        try await performConnect()
    }

    private func performConnect() async throws {
        let shouldConnect: Bool = withLock {
            if _state == .connected || _state == .connecting {
                return false
            }
            _state = .connecting
            isExplicitlyClosed = false
            _currentBackoffSeconds = configuration.initialBackoffSeconds
            return true
        }
        guard shouldConnect else { return }

        // Cancel any pending background reconnect task and heartbeat task strictly inside withLock
        withLock {
            self.reconnectTask?.cancel()
            self.reconnectTask = nil
            self.heartbeatTask?.cancel()
            self.heartbeatTask = nil
        }

        let task = session.webSocketTask(with: url)
        let installed = withLock { () -> Bool in
            if isExplicitlyClosed || Task.isCancelled {
                return false
            }
            self.webSocketTask = task
            return true
        }
        guard installed else {
            task.cancel(with: .goingAway, reason: nil)
            throw TransportError.connectionClosed
        }

        task.resume()

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    task.sendPing { error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } onCancel: {
                task.cancel(with: .goingAway, reason: nil)
            }

            // Check if close() or cancellation occurred during ping
            let isAborted: Bool = withLock {
                if self.isExplicitlyClosed || Task.isCancelled || self.webSocketTask !== task {
                    return true
                }
                self._state = .connected
                self._currentBackoffSeconds = self.configuration.initialBackoffSeconds
                return false
            }

            if isAborted {
                task.cancel(with: .goingAway, reason: nil)
                withLock {
                    self.heartbeatTask?.cancel()
                    self.heartbeatTask = nil
                    if self.webSocketTask === task {
                        self.webSocketTask = nil
                    }
                    if !self.isExplicitlyClosed {
                        self._state = .disconnected
                    }
                }
                throw TransportError.connectionClosed
            }

            startListening(for: task)
            startHeartbeat(for: task)

            // Re-verify under lock that close() wasn't invoked concurrently
            let closedAfterStart: Bool = withLock {
                if self.isExplicitlyClosed || Task.isCancelled || self.webSocketTask !== task {
                    return true
                }
                return false
            }

            if closedAfterStart {
                task.cancel(with: .goingAway, reason: nil)
                withLock {
                    self.heartbeatTask?.cancel()
                    self.heartbeatTask = nil
                    if self.webSocketTask === task {
                        self.webSocketTask = nil
                    }
                }
                throw TransportError.connectionClosed
            }

            Task { [weak self] in
                await self?.flushOutbox(task: task)
            }
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            withLock {
                self.heartbeatTask?.cancel()
                self.heartbeatTask = nil
                if self.webSocketTask === task {
                    self.webSocketTask = nil
                }
                if !self.isExplicitlyClosed {
                    self._state = .failed(error.localizedDescription)
                }
            }
            if let transportError = error as? TransportError {
                throw transportError
            } else {
                throw TransportError.peerUnavailable
            }
        }
    }

    public func send(message: SyncMessage) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        try await send(data: data)
    }

    public func send(data: Data) async throws {
        enum SendRoute {
            case direct(URLSessionWebSocketTask)
            case queuedInOutbox
            case outboxFull
            case notConnected
        }

        let route: SendRoute = withLock {
            if isExplicitlyClosed {
                return .notConnected
            }
            if case .failed = _state {
                return .notConnected
            }
            if _state == .disconnected {
                return .notConnected
            }

            // Queued while reconnecting / connecting
            if _state == .connecting {
                if outboxQueue.count >= configuration.maxOutboxSize {
                    return .outboxFull
                }
                outboxQueue.append(data)
                return .queuedInOutbox
            }

            // If connected, preserve strict FIFO order if outbox is currently being flushed
            if _state == .connected {
                if isFlushingOutbox || !outboxQueue.isEmpty {
                    if outboxQueue.count >= configuration.maxOutboxSize {
                        return .outboxFull
                    }
                    outboxQueue.append(data)
                    return .queuedInOutbox
                }
                if let task = self.webSocketTask {
                    return .direct(task)
                } else {
                    return .notConnected
                }
            }

            return .notConnected
        }

        switch route {
        case .queuedInOutbox:
            return
        case .outboxFull:
            throw TransportError.sendFailed("Outbox full (max: \(configuration.maxOutboxSize))")
        case .notConnected:
            throw TransportError.notConnected
        case .direct(let task):
            try await sendRaw(data: data, on: task)
        }
    }

    private func sendRaw(data: Data, on task: URLSessionWebSocketTask) async throws {
        let wsMessage = URLSessionWebSocketTask.Message.data(data)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(wsMessage) { [weak self] error in
                if let error = error {
                    self?.handleUnexpectedDrop(task: task, error: error)
                    continuation.resume(throwing: TransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func flushOutbox(task: URLSessionWebSocketTask) async {
        let canFlush: Bool = withLock {
            if isFlushingOutbox { return false }
            isFlushingOutbox = true
            return true
        }
        guard canFlush else { return }
        defer { withLock { isFlushingOutbox = false } }

        while true {
            let isAborted = withLock {
                self.isExplicitlyClosed || self._state != .connected || self.webSocketTask !== task
            }
            if isAborted { break }

            let nextData: Data? = withLock {
                if outboxQueue.isEmpty {
                    return nil
                }
                return outboxQueue.removeFirst()
            }
            guard let data = nextData else { break }

            do {
                try await sendRaw(data: data, on: task)
            } catch {
                // Re-insert failed item at head of outbox for subsequent retry
                withLock {
                    outboxQueue.insert(data, at: 0)
                }
                break
            }
        }
    }

    public func receive() async throws -> SyncMessage {
        let fastPath: Result<SyncMessage, Error>? = withLock {
            if !messageQueue.isEmpty {
                return .success(messageQueue.removeFirst())
            }
            if isExplicitlyClosed || (_state != .connected && _state != .connecting) {
                return .failure(TransportError.connectionClosed)
            }
            return nil
        }

        if let fastPath = fastPath {
            switch fastPath {
            case .success(let msg):
                return msg
            case .failure(let error):
                throw error
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            withLock {
                if !messageQueue.isEmpty {
                    continuation.resume(returning: messageQueue.removeFirst())
                    return
                }
                if isExplicitlyClosed || (_state != .connected && _state != .connecting) {
                    continuation.resume(throwing: TransportError.connectionClosed)
                    return
                }
                messageWaiters.append(continuation)
            }
        }
    }

    public func makeMessageStream() -> AsyncStream<SyncMessage> {
        let id = UUID()
        return AsyncStream<SyncMessage> { continuation in
            withLock {
                streamContinuations[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeStreamContinuation(id: id)
            }
        }
    }

    private func removeStreamContinuation(id: UUID) {
        withLock {
            _ = streamContinuations.removeValue(forKey: id)
        }
    }

    private func startListening(for task: URLSessionWebSocketTask) {
        let isClosed = withLock {
            isExplicitlyClosed || webSocketTask !== task
        }
        guard !isClosed else { return }

        task.receive { [weak self] result in
            guard let self = self else { return }
            let isCurrent = self.withLock {
                !self.isExplicitlyClosed && self.webSocketTask === task
            }
            guard isCurrent else { return }

            switch result {
            case .success(let message):
                self.handleIncomingWebSocketMessage(message)
                self.startListening(for: task)
            case .failure(let error):
                self.handleUnexpectedDrop(task: task, error: error)
            }
        }
    }

    private func startHeartbeat(for task: URLSessionWebSocketTask) {
        withLock {
            heartbeatTask?.cancel()
            heartbeatTask = nil

            guard !isExplicitlyClosed && webSocketTask === task else { return }

            heartbeatTask = Task { [weak self] in
                guard let self = self else { return }
                let interval = self.configuration.heartbeatIntervalSeconds

                while !Task.isCancelled {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }

                    let shouldPing = self.withLock {
                        !Task.isCancelled && !self.isExplicitlyClosed && self._state == .connected && self.webSocketTask === task
                    }
                    guard shouldPing else { break }

                    let pingSuccess: Bool = await withCheckedContinuation { continuation in
                        task.sendPing { error in
                            continuation.resume(returning: error == nil)
                        }
                    }

                    if Task.isCancelled { break }

                    let stillActive = self.withLock {
                        !Task.isCancelled && !self.isExplicitlyClosed && self.webSocketTask === task
                    }
                    guard stillActive else { break }

                    if !pingSuccess {
                        // Keepalive failed; trigger reconnection
                        self.handleUnexpectedDrop(task: task, error: TransportError.timeout)
                        break
                    }
                }
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
            for cont in streamContinuations.values {
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

    private func handleUnexpectedDrop(task: URLSessionWebSocketTask, error: Error) {
        let (shouldReconnect, waitersToFail): (Bool, [CheckedContinuation<SyncMessage, Error>]) = withLock {
            heartbeatTask?.cancel()
            heartbeatTask = nil

            guard !isExplicitlyClosed else { return (false, []) }
            if webSocketTask === task {
                webSocketTask = nil
            }
            task.cancel(with: .goingAway, reason: nil)

            if configuration.autoReconnect {
                _state = .connecting
                return (true, [])
            } else {
                _state = .failed(error.localizedDescription)
                let waiters = messageWaiters
                messageWaiters.removeAll()
                for cont in streamContinuations.values {
                    cont.finish()
                }
                streamContinuations.removeAll()
                return (false, waiters)
            }
        }

        for w in waitersToFail {
            w.resume(throwing: TransportError.receiveFailed(error.localizedDescription))
        }

        if shouldReconnect {
            startReconnectLoop()
        }
    }

    private func startReconnectLoop() {
        withLock {
            guard !isExplicitlyClosed else { return }
            if reconnectTask != nil {
                return
            }

            reconnectTask = Task { [weak self] in
                guard let self = self else { return }

                while !Task.isCancelled {
                    // Check Task.isCancelled and isExplicitlyClosed under lock BEFORE sleeping
                    let (shouldAbortBeforeSleep, backoff, maxBackoff): (Bool, Double, Double) = self.withLock {
                        if Task.isCancelled || self.isExplicitlyClosed {
                            return (true, 0.0, 0.0)
                        }
                        return (false, self._currentBackoffSeconds, self.configuration.maxBackoffSeconds)
                    }
                    if shouldAbortBeforeSleep || Task.isCancelled { break }

                    // Exponential backoff sleep: 1s -> 2s -> 4s ... capped at maxBackoffSeconds (30s)
                    do {
                        try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }

                    // Check Task.isCancelled and isExplicitlyClosed under lock BEFORE reconnecting
                    let shouldAbortBeforeConnect: Bool = self.withLock {
                        Task.isCancelled || self.isExplicitlyClosed
                    }
                    if shouldAbortBeforeConnect || Task.isCancelled { break }

                    let candidateTask = self.session.webSocketTask(with: self.url)
                    let installed: Bool = self.withLock {
                        if Task.isCancelled || self.isExplicitlyClosed {
                            return false
                        }
                        self.webSocketTask = candidateTask
                        return true
                    }
                    guard installed else {
                        candidateTask.cancel(with: .goingAway, reason: nil)
                        break
                    }

                    candidateTask.resume()

                    let pingSuccess: Bool = await withCheckedContinuation { continuation in
                        candidateTask.sendPing { error in
                            continuation.resume(returning: error == nil)
                        }
                    }

                    let shouldAbortAfterPing: Bool = self.withLock {
                        Task.isCancelled || self.isExplicitlyClosed || self.webSocketTask !== candidateTask
                    }
                    if shouldAbortAfterPing || Task.isCancelled {
                        candidateTask.cancel(with: .goingAway, reason: nil)
                        self.withLock {
                            if self.webSocketTask === candidateTask {
                                self.webSocketTask = nil
                            }
                        }
                        break
                    }

                    if pingSuccess {
                        let activated: Bool = self.withLock {
                            if Task.isCancelled || self.isExplicitlyClosed || self.webSocketTask !== candidateTask {
                                return false
                            }
                            self._state = .connected
                            self._currentBackoffSeconds = self.configuration.initialBackoffSeconds
                            self.reconnectTask = nil
                            return true
                        }
                        if !activated {
                            candidateTask.cancel(with: .goingAway, reason: nil)
                            self.withLock {
                                if self.webSocketTask === candidateTask {
                                    self.webSocketTask = nil
                                }
                            }
                            break
                        }
                        self.startListening(for: candidateTask)
                        self.startHeartbeat(for: candidateTask)
                        await self.flushOutbox(task: candidateTask)
                        return
                    } else {
                        candidateTask.cancel(with: .goingAway, reason: nil)
                        self.withLock {
                            if self.webSocketTask === candidateTask {
                                self.webSocketTask = nil
                            }
                            let nextBackoff = min(backoff * 2.0, maxBackoff)
                            self._currentBackoffSeconds = nextBackoff
                        }
                    }
                }

                self.withLock {
                    self.reconnectTask = nil
                }
            }
        }
    }

    /// Disconnects the transport session and cancels all background reconnection loops.
    public func disconnect() async {
        withLock {
            reconnectTask?.cancel()
            reconnectTask = nil
        }
        await close()
    }

    public func close() async {
        let (task, waiters): (
            URLSessionWebSocketTask?,
            [CheckedContinuation<SyncMessage, Error>]
        ) = withLock {
            isExplicitlyClosed = true
            _state = .disconnected
            let t = webSocketTask
            webSocketTask = nil
            reconnectTask?.cancel()
            reconnectTask = nil
            heartbeatTask?.cancel()
            heartbeatTask = nil
            let w = messageWaiters
            messageWaiters.removeAll()
            for cont in streamContinuations.values {
                cont.finish()
            }
            streamContinuations.removeAll()
            outboxQueue.removeAll()
            isFlushingOutbox = false
            return (t, w)
        }

        task?.cancel(with: .normalClosure, reason: nil)
        for w in waiters {
            w.resume(throwing: TransportError.connectionClosed)
        }
    }
}
