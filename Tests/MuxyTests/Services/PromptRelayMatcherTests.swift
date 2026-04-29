import Foundation
import Testing

@testable import Muxy

@Suite("PromptRelayMatcher")
struct PromptRelayMatcherTests {
    @Test("single complete relay tag produces one match")
    func singleMatch() {
        let matcher = PromptRelayMatcher()
        let matches = matcher.ingest(Data(#"""
        Thinking...
        <muxy:ask target="droidx">what do you think of this merge?</muxy:ask>
        Done.
        """#.utf8))
        #expect(matches.count == 1)
        #expect(matches.first?.target == "droidx")
        #expect(matches.first?.body == "what do you think of this merge?")
    }

    @Test("chunked data across multiple ingests still matches once")
    func chunkedMatch() {
        let matcher = PromptRelayMatcher()
        let a = matcher.ingest(Data(#"<muxy:ask target="cxr">please reviewer "#.utf8))
        let b = matcher.ingest(Data(#"this plan</muxy:ask>"#.utf8))
        #expect(a.isEmpty)
        #expect(b.count == 1)
        #expect(b.first?.target == "cxr")
        #expect(b.first?.body.hasPrefix("please reviewer") == true)
    }

    @Test("multiple tags in one ingest both yielded in order")
    func multipleTags() {
        let matcher = PromptRelayMatcher()
        let matches = matcher.ingest(Data(#"""
        <muxy:ask target="a">hi a</muxy:ask>
        filler
        <muxy:ask target="b">hi b</muxy:ask>
        """#.utf8))
        #expect(matches.count == 2)
        #expect(matches[0].target == "a")
        #expect(matches[1].target == "b")
    }

    @Test("tag without target attribute produces empty target")
    func missingTarget() {
        let matcher = PromptRelayMatcher()
        let matches = matcher.ingest(Data(#"<muxy:ask>hello</muxy:ask>"#.utf8))
        #expect(matches.count == 1)
        #expect(matches.first?.target.isEmpty == true)
    }

    @Test("unclosed tag does not produce a match")
    func unclosedTag() {
        let matcher = PromptRelayMatcher()
        let matches = matcher.ingest(Data(#"<muxy:ask target="droidx">partial..."#.utf8))
        #expect(matches.isEmpty)
    }

    @Test("reply attribute is captured")
    func replyAttribute() {
        let matcher = PromptRelayMatcher()
        let matches = matcher.ingest(Data(#"<muxy:ask target="a" reply="b">q</muxy:ask>"#.utf8))
        #expect(matches.first?.replyChannel == "b")
    }
}

@MainActor
@Suite("AgentCanvasState")
struct AgentCanvasStateTests {
    @Test("adding wires deduplicates by (source, target, kind)")
    func dedupeWires() {
        let canvas = AgentCanvasState(projectPath: "/tmp/p", name: "Test")
        let a = AgentCanvasNode(label: "A", position: CGPoint(x: 0, y: 0))
        let b = AgentCanvasNode(label: "B", position: CGPoint(x: 100, y: 0))
        canvas.addNode(a)
        canvas.addNode(b)
        canvas.addWire(AgentCanvasWire(sourceNodeID: a.id, targetNodeID: b.id, kind: .promptRelay))
        canvas.addWire(AgentCanvasWire(sourceNodeID: a.id, targetNodeID: b.id, kind: .promptRelay))
        #expect(canvas.wires.count == 1)
    }

    @Test("removing a node removes its wires")
    func removeNodeRemovesWires() {
        let canvas = AgentCanvasState(projectPath: "/tmp/p", name: "Test")
        let a = AgentCanvasNode(label: "A", position: CGPoint(x: 0, y: 0))
        let b = AgentCanvasNode(label: "B", position: CGPoint(x: 100, y: 0))
        canvas.addNode(a)
        canvas.addNode(b)
        canvas.addWire(AgentCanvasWire(sourceNodeID: a.id, targetNodeID: b.id, kind: .promptRelay))
        canvas.removeNode(id: a.id)
        #expect(canvas.nodes.count == 1)
        #expect(canvas.wires.isEmpty)
    }

    @Test("lookup by paneID returns the node")
    func lookupByPaneID() {
        let canvas = AgentCanvasState(projectPath: "/tmp/p", name: "Test")
        let paneID = UUID()
        let node = AgentCanvasNode(paneID: paneID, label: "X", position: .zero)
        canvas.addNode(node)
        #expect(canvas.node(paneID: paneID)?.id == node.id)
    }
}


@MainActor
@Suite("AgentCanvas persistence")
struct AgentCanvasPersistenceTests {
    @Test("serialize + restore round-trips nodes and wires")
    func roundTrip() {
        let original = AgentCanvasState(projectPath: "/tmp/p", name: "Graph")
        let a = AgentCanvasNode(paneID: UUID(), label: "A", position: CGPoint(x: 50, y: 60))
        let b = AgentCanvasNode(paneID: UUID(), label: "B", agentID: "droidx", position: CGPoint(x: 200, y: 100))
        original.addNode(a)
        original.addNode(b)
        original.addWire(AgentCanvasWire(sourceNodeID: a.id, targetNodeID: b.id, kind: .keystrokeBroadcast, isActive: true))

        let snapshot = original.serializeGraph()
        let encoded = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode(AgentCanvasGraphSnapshot.self, from: encoded)

        let restored = AgentCanvasState(projectPath: "/tmp/p", name: "Graph")
        restored.restore(graph: decoded)

        #expect(restored.nodes.count == 2)
        #expect(restored.wires.count == 1)
        #expect(restored.nodes.first(where: { $0.label == "B" })?.agentID == "droidx")
        #expect(restored.wires.first?.kind == .keystrokeBroadcast)
        #expect(restored.nodes.first(where: { $0.label == "A" })?.position == CGPoint(x: 50, y: 60))
    }

    @Test("restore replaces existing graph rather than appending")
    func restoreReplaces() {
        let canvas = AgentCanvasState(projectPath: "/tmp/p", name: "Graph")
        canvas.addNode(AgentCanvasNode(label: "Stale", position: .zero))
        let snapshot = AgentCanvasGraphSnapshot(nodes: [], wires: [])
        canvas.restore(graph: snapshot)
        #expect(canvas.nodes.isEmpty)
        #expect(canvas.wires.isEmpty)
    }
}
