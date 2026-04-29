import Foundation
import Testing

@testable import Muxy

@Suite("AgentDefinition")
struct AgentDefinitionTests {
    @Test("decodes minimal required fields")
    func decodesMinimal() throws {
        let json = #"""
        {"id": "cxr", "label": "CXR", "launchCommand": "cxr"}
        """#
        let agent = try JSONDecoder().decode(AgentDefinition.self, from: Data(json.utf8))
        #expect(agent.id == "cxr")
        #expect(agent.label == "CXR")
        #expect(agent.launchCommand == "cxr")
        #expect(agent.branchPrefix == nil)
        #expect(agent.worktreeStrategy == nil)
        #expect(agent.effectiveBranchPrefix == "cxr")
        #expect(agent.effectiveStrategy == .newBranch)
    }

    @Test("decodes with all fields present")
    func decodesFull() throws {
        let json = #"""
        {
            "id": "droidx",
            "label": "DroidX",
            "branchPrefix": "feat-droidx",
            "launchCommand": "droidx --repo .",
            "worktreeStrategy": "reuseWorktree"
        }
        """#
        let agent = try JSONDecoder().decode(AgentDefinition.self, from: Data(json.utf8))
        #expect(agent.id == "droidx")
        #expect(agent.label == "DroidX")
        #expect(agent.branchPrefix == "feat-droidx")
        #expect(agent.launchCommand == "droidx --repo .")
        #expect(agent.worktreeStrategy == .reuseWorktree)
        #expect(agent.effectiveBranchPrefix == "feat-droidx")
        #expect(agent.effectiveStrategy == .reuseWorktree)
    }

    @Test("effectiveBranchPrefix falls back to id and normalizes spaces")
    func effectivePrefixFallback() {
        let agent = AgentDefinition(
            id: "my agent",
            label: "My Agent",
            branchPrefix: nil,
            launchCommand: "run",
            worktreeStrategy: nil
        )
        #expect(agent.effectiveBranchPrefix == "my-agent")
    }

    @Test("empty branchPrefix is treated as missing")
    func emptyBranchPrefix() {
        let agent = AgentDefinition(
            id: "cxr",
            label: "CXR",
            branchPrefix: "",
            launchCommand: "cxr",
            worktreeStrategy: nil
        )
        #expect(agent.effectiveBranchPrefix == "cxr")
    }

    @Test("strategy defaults to newBranch when omitted")
    func strategyDefault() {
        let agent = AgentDefinition(id: "a", label: "A", branchPrefix: nil, launchCommand: "a", worktreeStrategy: nil)
        #expect(agent.effectiveStrategy == .newBranch)
    }
}
