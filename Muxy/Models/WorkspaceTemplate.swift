import Foundation

struct WorkspaceTemplate: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    let root: WorkspaceTemplateNode

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), root: WorkspaceTemplateNode) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.root = root
    }
}

indirect enum WorkspaceTemplateNode: Codable, Sendable {
    case tabArea(WorkspaceTemplateTabArea)
    case split(WorkspaceTemplateSplit)

    private enum CodingKeys: String, CodingKey {
        case type, tabArea, split
    }

    private enum NodeType: String, Codable {
        case tabArea, split
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
        case .tabArea:
            self = try .tabArea(container.decode(WorkspaceTemplateTabArea.self, forKey: .tabArea))
        case .split:
            self = try .split(container.decode(WorkspaceTemplateSplit.self, forKey: .split))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .tabArea(area):
            try container.encode(NodeType.tabArea, forKey: .type)
            try container.encode(area, forKey: .tabArea)
        case let .split(branch):
            try container.encode(NodeType.split, forKey: .type)
            try container.encode(branch, forKey: .split)
        }
    }
}

struct WorkspaceTemplateSplit: Codable, Sendable {
    let direction: SplitDirectionSnapshot
    let ratio: Double
    let first: WorkspaceTemplateNode
    let second: WorkspaceTemplateNode
}

struct WorkspaceTemplateTabArea: Codable, Sendable {
    let tabs: [WorkspaceTemplateTab]
    let activeTabIndex: Int?
}

struct WorkspaceTemplateTab: Codable, Sendable {
    let kind: TerminalTab.Kind
    let customTitle: String?
    let colorID: String?
    let relativeStartupDirectory: String?

    init(
        kind: TerminalTab.Kind,
        customTitle: String? = nil,
        colorID: String? = nil,
        relativeStartupDirectory: String? = nil
    ) {
        self.kind = kind
        self.customTitle = customTitle
        self.colorID = colorID
        self.relativeStartupDirectory = relativeStartupDirectory
    }
}
