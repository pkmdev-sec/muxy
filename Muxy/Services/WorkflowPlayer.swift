import Foundation
import os

private let playerLogger = Logger(subsystem: "app.muxy", category: "WorkflowPlayer")

@MainActor
enum WorkflowPlayer {
    @discardableResult
    static func run(_ macro: WorkflowMacro, palette: CommandPalette) async -> Int {
        var executed = 0
        let commands = palette.sources.flatMap { $0.commands() }
        var byID: [String: PaletteCommand] = [:]
        for command in commands where byID[command.id] == nil {
            byID[command.id] = command
        }
        for step in macro.steps {
            let lookup = byID[step.commandID]
            guard let command = lookup else {
                playerLogger.info("Skipping missing command during workflow replay: \(step.commandID, privacy: .public)")
                continue
            }
            command.run()
            executed += 1
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return executed
    }
}
