import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "WorkspaceTemplateStore")

@MainActor
@Observable
final class WorkspaceTemplateStore {
    static let shared = WorkspaceTemplateStore()

    private(set) var templates: [WorkspaceTemplate] = []
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(fileURL: URL = MuxyFileStorage.fileURL(filename: "workspace-templates.json")) {
        self.fileURL = fileURL
        self.templates = Self.loadFromDisk(fileURL: fileURL)
    }

    func add(_ template: WorkspaceTemplate) {
        templates.removeAll { $0.id == template.id }
        templates.append(template)
        templates.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        scheduleSave()
    }

    func rename(id: UUID, to name: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].name = name
        templates.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        scheduleSave()
    }

    func remove(id: UUID) {
        templates.removeAll { $0.id == id }
        scheduleSave()
    }

    func clear() {
        templates.removeAll()
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = templates
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder.muxy.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                logger.error("Failed to persist workspace templates: \(error.localizedDescription)")
            }
        }
    }

    private static func loadFromDisk(fileURL: URL) -> [WorkspaceTemplate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let templates = try JSONDecoder.muxy.decode([WorkspaceTemplate].self, from: data)
            return templates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            logger.error("Failed to load workspace templates: \(error.localizedDescription)")
            return []
        }
    }
}

extension JSONEncoder {
    static let muxy: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let muxy: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
enum WorkspaceTemplateBuilder {
    static func template(name: String, from root: SplitNode, basePath: String) -> WorkspaceTemplate {
        WorkspaceTemplate(name: name, root: convert(node: root, basePath: basePath))
    }

    private static func convert(node: SplitNode, basePath: String) -> WorkspaceTemplateNode {
        switch node {
        case let .tabArea(area):
            let tabs = area.tabs.map { convert(tab: $0, basePath: basePath) }
            let active = area.activeTabID.flatMap { active in
                area.tabs.firstIndex(where: { $0.id == active })
            }
            return .tabArea(WorkspaceTemplateTabArea(tabs: tabs, activeTabIndex: active))
        case let .split(branch):
            let direction: SplitDirectionSnapshot = branch.direction == .horizontal ? .horizontal : .vertical
            return .split(WorkspaceTemplateSplit(
                direction: direction,
                ratio: branch.ratio,
                first: convert(node: branch.first, basePath: basePath),
                second: convert(node: branch.second, basePath: basePath)
            ))
        }
    }

    private static func convert(tab: TerminalTab, basePath: String) -> WorkspaceTemplateTab {
        let startupDir = tab.content.pane?.projectPath
        let relative = startupDir.flatMap { relativePath(of: $0, basePath: basePath) }
        return WorkspaceTemplateTab(
            kind: tab.kind,
            customTitle: tab.customTitle,
            colorID: tab.colorID,
            relativeStartupDirectory: relative
        )
    }

    private static func relativePath(of absolute: String, basePath: String) -> String? {
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        if absolute == basePath { return nil }
        if absolute.hasPrefix(base) {
            let tail = String(absolute.dropFirst(base.count))
            return tail.isEmpty ? nil : tail
        }
        return nil
    }
}

@MainActor
enum WorkspaceTemplateApplier {
    static func splitNode(from template: WorkspaceTemplate, basePath: String) -> SplitNode {
        build(node: template.root, basePath: basePath)
    }

    private static func build(node: WorkspaceTemplateNode, basePath: String) -> SplitNode {
        switch node {
        case let .tabArea(area):
            return .tabArea(makeTabArea(area, basePath: basePath))
        case let .split(branch):
            let direction: SplitDirection = branch.direction == .horizontal ? .horizontal : .vertical
            let first = build(node: branch.first, basePath: basePath)
            let second = build(node: branch.second, basePath: basePath)
            return .split(SplitBranch(
                direction: direction,
                ratio: CGFloat(branch.ratio),
                first: first,
                second: second
            ))
        }
    }

    private static func makeTabArea(_ area: WorkspaceTemplateTabArea, basePath: String) -> TabArea {
        let created = TabArea(projectPath: basePath)
        created.tabs.removeAll()
        for templateTab in area.tabs {
            let newTab = makeTab(templateTab, basePath: basePath)
            created.tabs.append(newTab)
        }
        if created.tabs.isEmpty {
            let fallback = TerminalTab(pane: TerminalPaneState(projectPath: basePath))
            created.tabs.append(fallback)
            created.activeTabID = fallback.id
        } else {
            let clampedIndex: Int
            if let index = area.activeTabIndex, index >= 0, index < created.tabs.count {
                clampedIndex = index
            } else {
                clampedIndex = 0
            }
            created.activeTabID = created.tabs[clampedIndex].id
        }
        return created
    }

    private static func makeTab(_ templateTab: WorkspaceTemplateTab, basePath: String) -> TerminalTab {
        let startupPath = makeAbsolutePath(relative: templateTab.relativeStartupDirectory, basePath: basePath)
        let newTab: TerminalTab
        switch templateTab.kind {
        case .terminal:
            newTab = TerminalTab(pane: TerminalPaneState(projectPath: startupPath))
        case .vcs:
            newTab = TerminalTab(vcsState: VCSTabState(projectPath: basePath))
        case .editor,
             .diffViewer,
             .testRunner,
             .agentCanvas,
             .gitLog:
            newTab = TerminalTab(pane: TerminalPaneState(projectPath: startupPath))
        }
        if let title = templateTab.customTitle { newTab.customTitle = title }
        if let color = templateTab.colorID { newTab.colorID = color }
        return newTab
    }

    private static func makeAbsolutePath(relative: String?, basePath: String) -> String {
        guard let relative, !relative.isEmpty else { return basePath }
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        return base + relative
    }
}
