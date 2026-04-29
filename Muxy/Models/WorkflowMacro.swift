import Foundation

struct WorkflowMacroStep: Codable, Equatable, Sendable {
    let commandID: String
    let recordedAt: Date

    init(commandID: String, recordedAt: Date = Date()) {
        self.commandID = commandID
        self.recordedAt = recordedAt
    }
}

struct WorkflowMacro: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var symbol: String
    var steps: [WorkflowMacroStep]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String = "play.square.stack",
        steps: [WorkflowMacroStep],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
