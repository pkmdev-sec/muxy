import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("WorkflowRecorder")
struct WorkflowRecorderTests {
    @Test("starts idle and records steps while active")
    func basicLifecycle() {
        let recorder = WorkflowRecorder.shared
        recorder.cancel()
        #expect(recorder.isRecording == false)
        recorder.start()
        #expect(recorder.isRecording == true)
        recorder.recordStep(commandID: "a")
        recorder.recordStep(commandID: "b")
        #expect(recorder.stepCount == 2)
        let macro = recorder.stop()
        #expect(macro?.steps.count == 2)
        #expect(macro?.steps.first?.commandID == "a")
        #expect(recorder.isRecording == false)
    }

    @Test("stop with no steps returns nil and resets")
    func emptyStopReturnsNil() {
        let recorder = WorkflowRecorder.shared
        recorder.cancel()
        recorder.start()
        let macro = recorder.stop()
        #expect(macro == nil)
        #expect(recorder.isRecording == false)
    }

    @Test("cancel discards in-progress recording")
    func cancelsRecording() {
        let recorder = WorkflowRecorder.shared
        recorder.cancel()
        recorder.start()
        recorder.recordStep(commandID: "x")
        recorder.cancel()
        #expect(recorder.isRecording == false)
        #expect(recorder.stepCount == 0)
    }

    @Test("recordStep while idle is ignored")
    func recordIgnoredWhenIdle() {
        let recorder = WorkflowRecorder.shared
        recorder.cancel()
        recorder.recordStep(commandID: "nope")
        #expect(recorder.stepCount == 0)
    }
}

@MainActor
@Suite("WorkflowMacroStore")
struct WorkflowMacroStoreTests {
    private func makeStore() -> WorkflowMacroStore {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxy-workflow-tests-\(UUID().uuidString).json")
        return WorkflowMacroStore(
            store: CodableFileStore(fileURL: tempURL, options: .pretty)
        )
    }

    @Test("save adds new macros and sorts alphabetically")
    func savesAndSorts() {
        let store = makeStore()
        store.save(WorkflowMacro(name: "Zeta", steps: [WorkflowMacroStep(commandID: "a")]))
        store.save(WorkflowMacro(name: "Alpha", steps: [WorkflowMacroStep(commandID: "b")]))
        #expect(store.macros.count == 2)
        #expect(store.macros.first?.name == "Alpha")
    }

    @Test("save with existing id replaces entry")
    func upserts() {
        let store = makeStore()
        let id = UUID()
        store.save(WorkflowMacro(id: id, name: "First", steps: [WorkflowMacroStep(commandID: "a")]))
        store.save(WorkflowMacro(id: id, name: "Renamed", steps: [WorkflowMacroStep(commandID: "a")]))
        #expect(store.macros.count == 1)
        #expect(store.macros.first?.name == "Renamed")
    }

    @Test("remove drops macros by id")
    func removes() {
        let store = makeStore()
        let id = UUID()
        store.save(WorkflowMacro(id: id, name: "Keep", steps: [WorkflowMacroStep(commandID: "k")]))
        store.save(WorkflowMacro(name: "Drop", steps: [WorkflowMacroStep(commandID: "d")]))
        store.remove(id: id)
        #expect(store.macros.count == 1)
        #expect(store.macros.first?.name == "Drop")
    }

    @Test("macro(id:) finds by id")
    func finds() {
        let store = makeStore()
        let id = UUID()
        store.save(WorkflowMacro(id: id, name: "Q", steps: []))
        #expect(store.macro(id: id)?.name == "Q")
    }
}

@MainActor
@Suite("WorkflowPlayer")
struct WorkflowPlayerTests {
    private final class CountingSource: PaletteCommandSource {
        private let counter: PlayerCounter
        let commandIDs: [String]
        init(commandIDs: [String], counter: PlayerCounter) {
            self.commandIDs = commandIDs
            self.counter = counter
        }

        func commands() -> [PaletteCommand] {
            commandIDs.map { id in
                let counterRef = counter
                return PaletteCommand(
                    id: id,
                    title: id,
                    subtitle: nil,
                    symbol: "circle",
                    group: .action,
                    shortcut: nil,
                    run: { counterRef.bump(id: id) }
                )
            }
        }
    }

    private final class PlayerCounter: @unchecked Sendable {
        var calls: [String] = []
        func bump(id: String) { calls.append(id) }
    }

    @Test("runs steps that match commands in the current palette")
    func runsMatching() async {
        let counter = PlayerCounter()
        let palette = CommandPalette(sources: [CountingSource(commandIDs: ["a", "b"], counter: counter)])
        let macro = WorkflowMacro(name: "x", steps: [
            WorkflowMacroStep(commandID: "a"),
            WorkflowMacroStep(commandID: "b"),
        ])
        let executed = await WorkflowPlayer.run(macro, palette: palette)
        #expect(executed == 2)
        #expect(counter.calls == ["a", "b"])
    }

    @Test("skips steps whose commands are no longer available")
    func skipsMissing() async {
        let counter = PlayerCounter()
        let palette = CommandPalette(sources: [CountingSource(commandIDs: ["a"], counter: counter)])
        let macro = WorkflowMacro(name: "y", steps: [
            WorkflowMacroStep(commandID: "missing"),
            WorkflowMacroStep(commandID: "a"),
        ])
        let executed = await WorkflowPlayer.run(macro, palette: palette)
        #expect(executed == 1)
        #expect(counter.calls == ["a"])
    }
}
