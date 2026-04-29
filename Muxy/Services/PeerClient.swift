import Foundation
import MuxyShared
import os

private let peerClientLogger = Logger(subsystem: "app.muxy", category: "PeerClient")

enum PeerConnectionState: Sendable, Equatable {
    case idle
    case connecting
    case pairing
    case connected(deviceName: String, clientID: UUID)
    case failed(message: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayLabel: String {
        switch self {
        case .idle: "Disconnected"
        case .connecting: "Connecting\u{2026}"
        case .pairing: "Pairing\u{2026}"
        case let .connected(name, _): "Connected: \(name)"
        case let .failed(message): "Failed: \(message)"
        }
    }
}

@MainActor
@Observable
final class PeerClient {
    static let shared = PeerClient()
    static let defaultPort: UInt16 = 7683

    private(set) var state: PeerConnectionState = .idle
    private(set) var currentHost: String?
    private(set) var currentPort: UInt16?
    private(set) var remoteProjects: [ProjectDTO] = []

    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var webSocket: URLSessionWebSocketTask?
    @ObservationIgnored private var pendingRequests: [String: CheckedContinuation<MuxyResponse, Error>] = [:]
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var pairingTask: Task<Void, Never>?

    private init() {}

    enum PeerClientError: LocalizedError {
        case transport(String)
        case decoding(String)
        case rejected(MuxyError)
        case notConnected

        var errorDescription: String? {
            switch self {
            case let .transport(msg): msg
            case let .decoding(msg): "Decoding failed: \(msg)"
            case let .rejected(err): "\(err.message) (code \(err.code))"
            case .notConnected: "Not connected to a peer"
            }
        }
    }

    func connect(host: String, port: UInt16, deviceName: String) {
        disconnect()
        currentHost = host
        currentPort = port
        state = .connecting

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        self.session = session

        guard let url = URL(string: "ws://\(host):\(port)/ws") else {
            state = .failed(message: "Invalid host")
            return
        }
        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()

        startReceiveLoop()
        beginPairing(deviceName: deviceName)
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        pairingTask?.cancel()
        pairingTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        failPending(with: PeerClientError.notConnected)
        state = .idle
        currentHost = nil
        currentPort = nil
        remoteProjects = []
    }

    func refreshProjects() async {
        guard state.isConnected else { return }
        do {
            let response = try await send(method: .listProjects, params: nil)
            if case let .projects(list) = response.result {
                remoteProjects = list
            }
        } catch {
            peerClientLogger.error("listProjects failed: \(error.localizedDescription)")
        }
    }

    func send(method: MuxyMethod, params: MuxyParams?) async throws -> MuxyResponse {
        guard let webSocket else { throw PeerClientError.notConnected }
        let request = MuxyRequest(id: UUID().uuidString, method: method, params: params)
        let message = MuxyMessage.request(request)
        let data = try MuxyCodec.encode(message)
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[request.id] = continuation
            webSocket.send(.data(data)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    self?.pendingRequests.removeValue(forKey: request.id)
                }
                continuation.resume(throwing: PeerClientError.transport(error.localizedDescription))
            }
        }
    }

    private func beginPairing(deviceName: String) {
        guard let host = currentHost else { return }
        let credentials = PeerDeviceCredentialsStore.load(host: host)
        pairingTask = Task { [weak self] in
            await self?.pair(deviceName: deviceName, credentials: credentials)
        }
    }

    private func pair(deviceName: String, credentials: PeerCredentials) async {
        state = .pairing
        let params = AuthenticateDeviceParams(
            deviceID: credentials.deviceID,
            deviceName: deviceName,
            token: credentials.token
        )
        do {
            let response = try await send(method: .authenticateDevice, params: .authenticateDevice(params))
            if let error = response.error {
                state = .failed(message: error.message)
                return
            }
            guard case let .pairing(dto) = response.result else {
                state = .failed(message: "Unexpected response")
                return
            }
            state = .connected(deviceName: dto.deviceName, clientID: dto.clientID)
            await refreshProjects()
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private func startReceiveLoop() {
        guard let webSocket else { return }
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await webSocket.receive()
                    await self?.handle(message: message)
                } catch {
                    await MainActor.run {
                        guard let self else { return }
                        if case .connecting = self.state {
                            self.state = .failed(message: error.localizedDescription)
                        }
                    }
                    return
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case let .data(raw): data = raw
        case let .string(text): data = Data(text.utf8)
        @unknown default: return
        }
        do {
            let decoded = try MuxyCodec.decode(data)
            switch decoded {
            case let .response(response):
                guard let continuation = pendingRequests.removeValue(forKey: response.id) else { return }
                continuation.resume(returning: response)
            case .request, .event:
                break
            }
        } catch {
            peerClientLogger.error("Decode failed: \(error.localizedDescription)")
        }
    }

    private func failPending(with error: Error) {
        let continuations = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in continuations {
            continuation.resume(throwing: error)
        }
    }
}
