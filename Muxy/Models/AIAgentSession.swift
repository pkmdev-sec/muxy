import Foundation

enum AIAgentStatus: String, Codable, Sendable, CaseIterable {
    case idle
    case thinking
    case awaitingInput
    case error
    case done

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .awaitingInput: "Awaiting Input"
        case .error: "Error"
        case .done: "Done"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: "circle"
        case .thinking: "sparkles"
        case .awaitingInput: "bell.badge"
        case .error: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle.fill"
        }
    }
}

enum AIAgentOrigin: String, Codable, Sendable {
    case workbench
    case notification
    case manual
}

@MainActor
@Observable
final class AIAgentSession: Identifiable {
    let id: UUID
    let providerID: String
    var label: String
    var projectID: UUID
    var worktreeID: UUID
    var worktreePath: String
    var paneID: UUID?
    var tabID: UUID?
    var areaID: UUID?
    var status: AIAgentStatus
    var currentTask: String?
    var lastActivity: Date
    let origin: AIAgentOrigin

    init(
        id: UUID = UUID(),
        providerID: String,
        label: String,
        projectID: UUID,
        worktreeID: UUID,
        worktreePath: String,
        paneID: UUID? = nil,
        tabID: UUID? = nil,
        areaID: UUID? = nil,
        status: AIAgentStatus = .idle,
        currentTask: String? = nil,
        lastActivity: Date = Date(),
        origin: AIAgentOrigin
    ) {
        self.id = id
        self.providerID = providerID
        self.label = label
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.worktreePath = worktreePath
        self.paneID = paneID
        self.tabID = tabID
        self.areaID = areaID
        self.status = status
        self.currentTask = currentTask
        self.lastActivity = lastActivity
        self.origin = origin
    }
}
