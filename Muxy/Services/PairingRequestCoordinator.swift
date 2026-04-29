import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "PairingRequestCoordinator")

struct PairingRequest: Identifiable, Equatable {
    let id = UUID()
    let deviceID: UUID
    let deviceName: String
    let token: String
    let receivedAt: Date
}

enum PairingDecision: Sendable {
    case approved
    case denied
    case timedOut
}

@MainActor
@Observable
final class PairingRequestCoordinator {
    static let shared = PairingRequestCoordinator()
    static let defaultTimeout: Duration = .seconds(60)

    private(set) var pendingRequest: PairingRequest?

    private var continuations: [UUID: CheckedContinuation<PairingDecision, Never>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var queue: [PairingRequest] = []
    private var activeAlert: NSAlert?

    private init() {}

    func requestApproval(
        deviceID: UUID,
        deviceName: String,
        token: String,
        timeout: Duration = PairingRequestCoordinator.defaultTimeout
    ) async -> PairingDecision {
        let request = PairingRequest(
            deviceID: deviceID,
            deviceName: deviceName,
            token: token,
            receivedAt: Date()
        )
        return await withCheckedContinuation { continuation in
            continuations[request.id] = continuation
            scheduleTimeout(for: request, duration: timeout)
            if pendingRequest == nil {
                present(request)
            } else {
                queue.append(request)
            }
        }
    }

    func approve(_ request: PairingRequest) {
        ApprovedDevicesStore.shared.approve(
            deviceID: request.deviceID,
            name: request.deviceName,
            token: request.token
        )
        finish(request, decision: .approved)
    }

    func deny(_ request: PairingRequest) {
        finish(request, decision: .denied)
    }

    private func scheduleTimeout(for request: PairingRequest, duration: Duration) {
        let id = request.id
        timeoutTasks[id]?.cancel()
        timeoutTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.timeoutFired(id)
        }
    }

    private func timeoutFired(_ id: UUID) {
        guard continuations[id] != nil else { return }
        timeoutTasks.removeValue(forKey: id)?.cancel()
        if let pending = pendingRequest, pending.id == id {
            logger.info("Pairing request timed out for device \(pending.deviceName, privacy: .public)")
            if activeAlert != nil {
                NSApp.abortModal()
            }
            finish(pending, decision: .timedOut)
            return
        }
        queue.removeAll { $0.id == id }
        if let continuation = continuations.removeValue(forKey: id) {
            continuation.resume(returning: .timedOut)
        }
    }

    private func finish(_ request: PairingRequest, decision: PairingDecision) {
        timeoutTasks.removeValue(forKey: request.id)?.cancel()
        guard let continuation = continuations.removeValue(forKey: request.id) else { return }
        continuation.resume(returning: decision)
        if pendingRequest?.id == request.id {
            pendingRequest = nil
            activeAlert = nil
            if let next = queue.first {
                queue.removeFirst()
                present(next)
            }
        } else {
            queue.removeAll { $0.id == request.id }
        }
    }

    private func present(_ request: PairingRequest) {
        pendingRequest = request
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.runAlert(for: request)
        }
    }

    private func runAlert(for request: PairingRequest) {
        guard pendingRequest?.id == request.id else { return }

        let alert = NSAlert()
        alert.messageText = "Allow \(request.deviceName) to connect?"
        alert.informativeText = "This device is requesting access to Muxy. Only approve devices you recognize."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Approve")
        alert.addButton(withTitle: "Deny")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        activeAlert = alert
        let response = alert.runModal()
        activeAlert = nil
        guard pendingRequest?.id == request.id else { return }

        if response == .alertFirstButtonReturn {
            approve(request)
        } else if response != .abort {
            deny(request)
        }
    }
}
