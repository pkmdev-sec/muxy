import Foundation
import os

private let agentSessionLogger = Logger(subsystem: "app.muxy", category: "AIAgentSessionStore")

struct AgentPaneCoordinate: Sendable {
    let paneID: UUID?
    let tabID: UUID?
    let areaID: UUID?

    static let empty = AgentPaneCoordinate(paneID: nil, tabID: nil, areaID: nil)
}

struct AgentSessionRegistration: Sendable {
    let providerID: String
    let label: String
    let projectID: UUID
    let worktreeID: UUID
    let worktreePath: String
    let coordinate: AgentPaneCoordinate
    let origin: AIAgentOrigin
    let status: AIAgentStatus

    init(
        providerID: String,
        label: String,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String,
        coordinate: AgentPaneCoordinate = .empty,
        origin: AIAgentOrigin,
        status: AIAgentStatus = .idle
    ) {
        self.providerID = providerID
        self.label = label
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.worktreePath = worktreePath
        self.coordinate = coordinate
        self.origin = origin
        self.status = status
    }
}

@MainActor
@Observable
final class AIAgentSessionStore {
    static let shared = AIAgentSessionStore()

    private(set) var sessions: [AIAgentSession] = []

    private init() {}

    func register(_ registration: AgentSessionRegistration) -> AIAgentSession {
        if let existing = sessions.first(where: {
            matches(
                $0,
                projectID: registration.projectID,
                tabID: registration.coordinate.tabID,
                providerID: registration.providerID
            )
        }) {
            existing.label = registration.label
            existing.paneID = registration.coordinate.paneID ?? existing.paneID
            existing.tabID = registration.coordinate.tabID ?? existing.tabID
            existing.areaID = registration.coordinate.areaID ?? existing.areaID
            existing.worktreeID = registration.worktreeID
            existing.worktreePath = registration.worktreePath
            existing.status = registration.status
            existing.lastActivity = Date()
            return existing
        }
        let session = AIAgentSession(
            providerID: registration.providerID,
            label: registration.label,
            projectID: registration.projectID,
            worktreeID: registration.worktreeID,
            worktreePath: registration.worktreePath,
            paneID: registration.coordinate.paneID,
            tabID: registration.coordinate.tabID,
            areaID: registration.coordinate.areaID,
            status: registration.status,
            origin: registration.origin
        )
        sessions.append(session)
        return session
    }

    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    func clearCompleted() {
        sessions.removeAll { $0.status == .done }
    }

    func clearAll() {
        sessions.removeAll()
    }

    func sessions(projectID: UUID) -> [AIAgentSession] {
        sessions.filter { $0.projectID == projectID }
    }

    func ingestNotification(_ notification: MuxyNotification) {
        guard case let .aiProvider(providerID) = notification.source else { return }
        let inferred = AIAgentStatusInference.status(title: notification.title, body: notification.body)
        let label = AIAgentLabeler.label(providerID: providerID)
        if let existing = sessions.first(where: {
            matches($0, projectID: notification.projectID, tabID: notification.tabID, providerID: providerID)
        }) {
            existing.label = label
            existing.paneID = existing.paneID ?? notification.paneID
            existing.tabID = notification.tabID
            existing.areaID = notification.areaID
            existing.worktreeID = notification.worktreeID
            existing.worktreePath = notification.worktreePath
            existing.status = inferred ?? existing.status
            existing.currentTask = AIAgentTaskExtractor.task(from: notification.body) ?? existing.currentTask
            existing.lastActivity = notification.timestamp
            return
        }
        let session = AIAgentSession(
            providerID: providerID,
            label: label,
            projectID: notification.projectID,
            worktreeID: notification.worktreeID,
            worktreePath: notification.worktreePath,
            paneID: notification.paneID,
            tabID: notification.tabID,
            areaID: notification.areaID,
            status: inferred ?? .idle,
            currentTask: AIAgentTaskExtractor.task(from: notification.body),
            lastActivity: notification.timestamp,
            origin: .notification
        )
        sessions.append(session)
    }

    func navigate(to session: AIAgentSession, appState: AppState) {
        guard let tabID = session.tabID, let areaID = session.areaID else { return }
        if appState.activeProjectID != session.projectID
            || appState.activeWorktreeID[session.projectID] != session.worktreeID
        {
            appState.dispatch(.selectProject(
                projectID: session.projectID,
                worktreeID: session.worktreeID,
                worktreePath: session.worktreePath
            ))
        }
        appState.dispatch(.focusArea(projectID: session.projectID, areaID: areaID))
        appState.dispatch(.selectTab(projectID: session.projectID, areaID: areaID, tabID: tabID))
    }

    private func matches(_ session: AIAgentSession, projectID: UUID, tabID: UUID?, providerID: String) -> Bool {
        guard session.projectID == projectID, session.providerID == providerID else { return false }
        if let tabID, let sessionTab = session.tabID {
            return sessionTab == tabID
        }
        return true
    }
}

enum AIAgentStatusInference {
    static func status(title: String, body: String) -> AIAgentStatus? {
        let haystack = (title + " " + body).lowercased()
        let waitingKeywords = ["awaiting", "permission", "confirm", "approve"]
        if waitingKeywords.contains(where: { haystack.contains($0) }) {
            return .awaitingInput
        }
        if haystack.contains("error") || haystack.contains("failed") || haystack.contains("crash") {
            return .error
        }
        if haystack.contains("finished") || haystack.contains("done") || haystack.contains("complete") || haystack.contains("completed") {
            return .done
        }
        let activeKeywords = ["thinking", "running", "working", "started", "executing"]
        if activeKeywords.contains(where: { haystack.contains($0) }) {
            return .thinking
        }
        return nil
    }
}

enum AIAgentLabeler {
    static func label(providerID: String) -> String {
        switch providerID {
        case "claude-code": "Claude Code"
        case "opencode": "OpenCode"
        case "codex": "Codex"
        case "copilot": "GitHub Copilot"
        case "amp": "Amp"
        case "zai": "Z.AI"
        case "minimax": "MiniMax"
        case "kimi": "Kimi"
        case "factory": "Factory"
        case "cxr": "CXR"
        case "droidx": "DroidX"
        default: providerID.capitalized
        }
    }
}

enum AIAgentTaskExtractor {
    static func task(from body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        let limit = 140
        if firstLine.count <= limit {
            return firstLine
        }
        let idx = firstLine.index(firstLine.startIndex, offsetBy: limit)
        return String(firstLine[..<idx]) + "\u{2026}"
    }
}
