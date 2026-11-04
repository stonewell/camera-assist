import Foundation

#if canImport(Network)
import Network

/// Local P2P Bonjour / Multipeer transport implementation using Network.framework.
/// Used for offline fallback in locations without cellular signal (canyons, cruises, mountains).
public final class BonjourTransport: SyncTransport, @unchecked Sendable {
    public enum Mode {
        case listener(serviceType: String)
        case browser(serviceType: String)
    }

    private let mode: Mode
    private let queue = DispatchQueue(label: "com.cameraassist.synckit.bonjour", qos: .userInitiated)

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var activeConnection: NWConnection?

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

    public init(mode: Mode = .browser(serviceType: "_camera-assist._tcp")) {
        self.mode = mode
    }

    public func connect() async throws {
        withLock {
            _state = .connecting
        }

        switch mode {
        case .listener(let serviceType):
            try startListener(serviceType: serviceType)
        case .browser(let serviceType):
            try startBrowser(serviceType: serviceType)
        }
    }

    private func startListener(serviceType: String) throws {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params)
        listener.service = NWListener.Service(type: serviceType)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            let shouldAccept: Bool = self.withLock {
                if self.activeConnection == nil {
                    self.activeConnection = connection
                    self._state = .connected
                    return true
                }
                return false
            }
            if shouldAccept {
                self.setupConnection(connection)
            } else {
                connection.cancel()
            }
        }

        listener.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            self.withLock {
                switch newState {
                case .ready:
                    self._state = .connecting
                case .failed(let err):
                    self._state = .failed(err.localizedDescription)
                case .cancelled:
                    self._state = .disconnected
                default:
                    break
                }
            }
        }

        listener.start(queue: queue)
    }

    private func startBrowser(serviceType: String) throws {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let params = NWParameters.tcp
        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            let connectionToSetup: NWConnection? = self.withLock {
                if self.activeConnection == nil, let endpoint = results.first?.endpoint {
                    let connection = NWConnection(to: endpoint, using: params)
                    self.activeConnection = connection
                    return connection
                }
                return nil
            }
            if let conn = connectionToSetup {
                self.setupConnection(conn)
            }
        }

        browser.start(queue: queue)
    }

    private func setupConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            var shouldStartReading = false
            self.withLock {
                switch newState {
                case .ready:
                    self._state = .connected
                    shouldStartReading = true
                case .failed(let err):
                    self._state = .failed(err.localizedDescription)
                case .cancelled:
                    self._state = .disconnected
                default:
                    break
                }
            }
            if shouldStartReading {
                self.readNextFramedMessage()
            }
        }
        connection.start(queue: queue)
    }

    private func readNextFramedMessage() {
        let connection: NWConnection? = withLock { activeConnection }
        guard let connection = connection else { return }

        // Read 4-byte big endian length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.handleFailure(error)
                return
            }
            guard let content = content, content.count == 4 else {
                if isComplete { self.handleClose() }
                return
            }
            let length = content.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.readMessagePayload(length: Int(length))
        }
    }

    private func readMessagePayload(length: Int) {
        let connection: NWConnection? = withLock { activeConnection }
        guard let connection = connection else { return }

        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.handleFailure(error)
                return
            }
            guard let content = content, content.count == length else {
                if isComplete { self.handleClose() }
                return
            }
            let decoder = JSONDecoder()
            if let msg = try? decoder.decode(SyncMessage.self, from: content) {
                self.deliverMessage(msg)
            }
            self.readNextFramedMessage()
        }
    }

    private func deliverMessage(_ msg: SyncMessage) {
        withLock {
            for cont in streamContinuations {
                cont.yield(msg)
            }
            if !messageWaiters.isEmpty {
                let waiter = messageWaiters.removeFirst()
                waiter.resume(returning: msg)
            } else {
                messageQueue.append(msg)
            }
        }
    }

    public func send(message: SyncMessage) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        try await send(data: data)
    }

    public func send(data: Data) async throws {
        let connection: NWConnection? = withLock { activeConnection }
        guard let connection = connection else {
            throw TransportError.notConnected
        }
        var length = UInt32(data.count).bigEndian
        var framedData = Data(bytes: &length, count: 4)
        framedData.append(data)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framedData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: TransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
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

    private func handleFailure(_ error: Error) {
        let waiters: [CheckedContinuation<SyncMessage, Error>] = withLock {
            _state = .failed(error.localizedDescription)
            let w = messageWaiters
            messageWaiters.removeAll()
            for cont in streamContinuations { cont.finish() }
            streamContinuations.removeAll()
            return w
        }

        for w in waiters {
            w.resume(throwing: TransportError.receiveFailed(error.localizedDescription))
        }
    }

    private func handleClose() {
        let waiters: [CheckedContinuation<SyncMessage, Error>] = withLock {
            _state = .disconnected
            let w = messageWaiters
            messageWaiters.removeAll()
            for cont in streamContinuations { cont.finish() }
            streamContinuations.removeAll()
            return w
        }

        for w in waiters {
            w.resume(throwing: TransportError.connectionClosed)
        }
    }

    public func close() async {
        let (conn, list, brw, waiters): (NWConnection?, NWListener?, NWBrowser?, [CheckedContinuation<SyncMessage, Error>]) = withLock {
            _state = .disconnected
            let c = activeConnection
            activeConnection = nil
            let l = listener
            listener = nil
            let b = browser
            browser = nil
            let w = messageWaiters
            messageWaiters.removeAll()
            for cont in streamContinuations { cont.finish() }
            streamContinuations.removeAll()
            return (c, l, b, w)
        }

        conn?.cancel()
        list?.cancel()
        brw?.cancel()

        for w in waiters {
            w.resume(throwing: TransportError.connectionClosed)
        }
    }
}
#endif
