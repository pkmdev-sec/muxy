import Foundation
import os

private let workflowStoreLogger = Logger(subsystem: "app.muxy", category: "WorkflowMacroStore")

@MainActor
@Observable
final class WorkflowMacroStore {
    static let shared = WorkflowMacroStore()

    private(set) var macros: [WorkflowMacro] = []

    @ObservationIgnored private let store: CodableFileStore<[WorkflowMacro]>
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(
        store: CodableFileStore<[WorkflowMacro]> = CodableFileStore(
            fileURL: MuxyFileStorage.fileURL(filename: "workflows.json"),
            options: .pretty
        )
    ) {
        self.store = store
        macros = Self.loadFromDisk(store)
    }

    func save(_ macro: WorkflowMacro) {
        if let index = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[index] = macro
        } else {
            macros.append(macro)
        }
        macros.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        scheduleSave()
    }

    func remove(id: UUID) {
        macros.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearAll() {
        macros.removeAll()
        scheduleSave()
    }

    func macro(id: UUID) -> WorkflowMacro? {
        macros.first { $0.id == id }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            await self?.persistNow()
        }
    }

    private func persistNow() {
        do {
            try store.save(macros)
        } catch {
            workflowStoreLogger.error("Failed to save workflows: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk(_ store: CodableFileStore<[WorkflowMacro]>) -> [WorkflowMacro] {
        do {
            return (try store.load() ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            workflowStoreLogger.error("Failed to load workflows: \(error.localizedDescription)")
            return []
        }
    }
}
