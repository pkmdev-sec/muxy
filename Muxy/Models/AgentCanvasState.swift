import Foundation

enum AgentCanvasWireKind: String, Codable, Sendable, Equatable {
    case promptRelay
    case keystrokeBroadcast
    case fileWatch
    case mirror
}

@MainActor
@Observable
final class AgentCanvasNode: Identifiable {
    let id: UUID
    var paneID: UUID?
    var tabID: UUID?
    var areaID: UUID?
    var label: String
    var agentID: String?
    var position: CGPoint

    init(
        id: UUID = UUID(),
        paneID: UUID? = nil,
        tabID: UUID? = nil,
        areaID: UUID? = nil,
        label: String,
        agentID: String? = nil,
        position: CGPoint
    ) {
        self.id = id
        self.paneID = paneID
        self.tabID = tabID
        self.areaID = areaID
        self.label = label
        self.agentID = agentID
        self.position = position
    }
}

@MainActor
@Observable
final class AgentCanvasWire: Identifiable {
    let id: UUID
    var sourceNodeID: UUID
    var targetNodeID: UUID
    var kind: AgentCanvasWireKind
    var label: String?
    var isActive: Bool
    var fileWatchGlob: String?
    var fileWatchCommand: String?

    init(
        id: UUID = UUID(),
        sourceNodeID: UUID,
        targetNodeID: UUID,
        kind: AgentCanvasWireKind,
        label: String? = nil,
        isActive: Bool = true,
        fileWatchGlob: String? = nil,
        fileWatchCommand: String? = nil
    ) {
        self.id = id
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.kind = kind
        self.label = label
        self.isActive = isActive
        self.fileWatchGlob = fileWatchGlob
        self.fileWatchCommand = fileWatchCommand
    }
}

@MainActor
@Observable
final class AgentCanvasState: Identifiable {
    let id = UUID()
    let projectPath: String
    var name: String
    var nodes: [AgentCanvasNode] = []
    var wires: [AgentCanvasWire] = []

    init(projectPath: String, name: String) {
        self.projectPath = projectPath
        self.name = name
    }

    var displayTitle: String { name }

    func node(id: UUID) -> AgentCanvasNode? {
        nodes.first { $0.id == id }
    }

    func node(paneID: UUID) -> AgentCanvasNode? {
        nodes.first { $0.paneID == paneID }
    }

    func node(matchingAgentID agentID: String) -> AgentCanvasNode? {
        nodes.first { $0.agentID == agentID }
    }

    func addNode(_ node: AgentCanvasNode) {
        nodes.append(node)
    }

    func addWire(_ wire: AgentCanvasWire) {
        if wires.contains(where: { existing in
            existing.sourceNodeID == wire.sourceNodeID
                && existing.targetNodeID == wire.targetNodeID
                && existing.kind == wire.kind
        }) {
            return
        }
        wires.append(wire)
    }

    func removeNode(id: UUID) {
        nodes.removeAll { $0.id == id }
        wires.removeAll { $0.sourceNodeID == id || $0.targetNodeID == id }
    }

    func removeWire(id: UUID) {
        wires.removeAll { $0.id == id }
    }

    func wires(involvingNodeID nodeID: UUID) -> [AgentCanvasWire] {
        wires.filter { $0.sourceNodeID == nodeID || $0.targetNodeID == nodeID }
    }

    func serializeGraph() -> AgentCanvasGraphSnapshot {
        AgentCanvasGraphSnapshot(
            nodes: nodes.map { node in
                AgentCanvasNodeSnapshot(
                    id: node.id,
                    paneID: node.paneID,
                    tabID: node.tabID,
                    areaID: node.areaID,
                    label: node.label,
                    agentID: node.agentID,
                    positionX: Double(node.position.x),
                    positionY: Double(node.position.y)
                )
            },
            wires: wires.map { wire in
                AgentCanvasWireSnapshot(
                    id: wire.id,
                    sourceNodeID: wire.sourceNodeID,
                    targetNodeID: wire.targetNodeID,
                    kind: wire.kind.rawValue,
                    label: wire.label,
                    isActive: wire.isActive,
                    fileWatchGlob: wire.fileWatchGlob,
                    fileWatchCommand: wire.fileWatchCommand
                )
            }
        )
    }

    func restore(graph: AgentCanvasGraphSnapshot) {
        nodes.removeAll()
        wires.removeAll()
        for snapshot in graph.nodes {
            nodes.append(AgentCanvasNode(
                id: snapshot.id,
                paneID: snapshot.paneID,
                tabID: snapshot.tabID,
                areaID: snapshot.areaID,
                label: snapshot.label,
                agentID: snapshot.agentID,
                position: CGPoint(x: snapshot.positionX, y: snapshot.positionY)
            ))
        }
        for snapshot in graph.wires {
            let kind = AgentCanvasWireKind(rawValue: snapshot.kind) ?? .promptRelay
            wires.append(AgentCanvasWire(
                id: snapshot.id,
                sourceNodeID: snapshot.sourceNodeID,
                targetNodeID: snapshot.targetNodeID,
                kind: kind,
                label: snapshot.label,
                isActive: snapshot.isActive,
                fileWatchGlob: snapshot.fileWatchGlob,
                fileWatchCommand: snapshot.fileWatchCommand
            ))
        }
    }
}
