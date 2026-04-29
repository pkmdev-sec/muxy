import Foundation
import os

private let recorderLogger = Logger(subsystem: "app.muxy", category: "WorkflowRecorder")

@MainActor
@Observable
final class WorkflowRecorder {
    static let shared = WorkflowRecorder()

    enum State: Equatable {
        case idle
        case recording(steps: [WorkflowMacroStep], startedAt: Date)

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }

        var steps: [WorkflowMacroStep] {
            if case let .recording(steps, _) = self { return steps }
            return []
        }
    }

    private(set) var state: State = .idle

    private init() {}

    var isRecording: Bool { state.isRecording }

    var stepCount: Int { state.steps.count }

    func start() {
        guard !isRecording else { return }
        state = .recording(steps: [], startedAt: Date())
    }

    func recordStep(commandID: String) {
        guard case let .recording(steps, startedAt) = state else { return }
        var updatedSteps = steps
        updatedSteps.append(WorkflowMacroStep(commandID: commandID))
        state = .recording(steps: updatedSteps, startedAt: startedAt)
    }

    @discardableResult
    func stop() -> WorkflowMacro? {
        guard case let .recording(steps, _) = state else { return nil }
        state = .idle
        guard !steps.isEmpty else { return nil }
        return WorkflowMacro(name: "Untitled Workflow", steps: steps)
    }

    func cancel() {
        state = .idle
    }
}
