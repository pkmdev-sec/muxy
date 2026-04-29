import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("WorkspaceTemplateStore")
struct WorkspaceTemplateStoreTests {
    private func freshStore() -> WorkspaceTemplateStore {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("muxy-tpl-\(UUID().uuidString).json")
        return WorkspaceTemplateStore(fileURL: tempURL)
    }

    private func makeTemplate(name: String) -> WorkspaceTemplate {
        let tab = WorkspaceTemplateTab(kind: .terminal)
        let area = WorkspaceTemplateTabArea(tabs: [tab], activeTabIndex: 0)
        return WorkspaceTemplate(name: name, root: .tabArea(area))
    }

    @Test("add inserts and sorts alphabetically")
    func addSorts() {
        let store = freshStore()
        store.add(makeTemplate(name: "Zeta"))
        store.add(makeTemplate(name: "Alpha"))
        store.add(makeTemplate(name: "mango"))
        let names = store.templates.map(\.name)
        #expect(names == ["Alpha", "mango", "Zeta"])
    }

    @Test("adding a template with existing id replaces it")
    func addReplacesById() {
        let store = freshStore()
        let original = makeTemplate(name: "Original")
        store.add(original)
        let updated = WorkspaceTemplate(
            id: original.id,
            name: "Updated",
            root: original.root
        )
        store.add(updated)
        #expect(store.templates.count == 1)
        #expect(store.templates.first?.name == "Updated")
    }

    @Test("rename resorts and persists new name")
    func renameResorts() {
        let store = freshStore()
        store.add(makeTemplate(name: "Beta"))
        let alpha = makeTemplate(name: "Alpha")
        store.add(alpha)
        store.rename(id: alpha.id, to: "Zeta")
        let names = store.templates.map(\.name)
        #expect(names == ["Beta", "Zeta"])
    }

    @Test("remove deletes by id")
    func removeById() {
        let store = freshStore()
        let target = makeTemplate(name: "Target")
        store.add(target)
        store.add(makeTemplate(name: "Keeper"))
        store.remove(id: target.id)
        #expect(store.templates.count == 1)
        #expect(store.templates.first?.name == "Keeper")
    }

    @Test("clear empties the store")
    func clearEmpties() {
        let store = freshStore()
        store.add(makeTemplate(name: "A"))
        store.add(makeTemplate(name: "B"))
        store.clear()
        #expect(store.templates.isEmpty)
    }

    @Test("applier with tab area produces a matching root")
    func applierBuildsTabArea() {
        let template = makeTemplate(name: "Solo")
        let root = WorkspaceTemplateApplier.splitNode(from: template, basePath: "/tmp/project")
        guard case let .tabArea(area) = root else {
            Issue.record("Expected tabArea root")
            return
        }
        #expect(area.projectPath == "/tmp/project")
        #expect(area.tabs.count == 1)
    }

    @Test("applier with nested splits preserves structure")
    func applierRebuildsSplits() {
        let leftTab = WorkspaceTemplateTab(kind: .terminal)
        let rightTab = WorkspaceTemplateTab(kind: .vcs)
        let left = WorkspaceTemplateNode.tabArea(
            WorkspaceTemplateTabArea(tabs: [leftTab], activeTabIndex: 0)
        )
        let right = WorkspaceTemplateNode.tabArea(
            WorkspaceTemplateTabArea(tabs: [rightTab], activeTabIndex: 0)
        )
        let split = WorkspaceTemplateSplit(direction: .horizontal, ratio: 0.4, first: left, second: right)
        let template = WorkspaceTemplate(name: "Two", root: .split(split))
        let root = WorkspaceTemplateApplier.splitNode(from: template, basePath: "/tmp/project")
        guard case let .split(branch) = root else {
            Issue.record("Expected split root")
            return
        }
        #expect(branch.direction == .horizontal)
        #expect(branch.ratio == 0.4)
    }
}
