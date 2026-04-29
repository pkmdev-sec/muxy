import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("AgentWorkbenchService.buildPlan")
struct AgentWorkbenchBuildPlanTests {
    private func fixedDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 28
        components.hour = 18
        components.minute = 30
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("single agent produces one step with prefix-timestamped branch")
    func singleAgent() {
        let projectID = UUID()
        let agent = AgentDefinition(id: "cxr", label: "CXR", branchPrefix: nil, launchCommand: "cxr", worktreeStrategy: nil)
        let plan = AgentWorkbenchService.buildPlan(
            projectID: projectID,
            projectPath: "/Users/me/muxy",
            agents: [agent],
            timestamp: fixedDate()
        )
        #expect(plan.steps.count == 1)
        #expect(plan.steps[0].agent.id == "cxr")
        #expect(plan.steps[0].branchName.hasPrefix("cxr-"))
        #expect(plan.steps[0].branchName.contains("202604"))
        #expect(plan.steps[0].worktreePath.hasPrefix("/Users/me/"))
        #expect(plan.steps[0].worktreePath.contains("muxy-"))
    }

    @Test("multiple agents produce distinct branches and paths")
    func multipleAgents() {
        let agents = [
            AgentDefinition(id: "cxr", label: "CXR", branchPrefix: nil, launchCommand: "cxr", worktreeStrategy: nil),
            AgentDefinition(id: "droidx", label: "DroidX", branchPrefix: "feat-droidx", launchCommand: "droidx", worktreeStrategy: nil),
        ]
        let plan = AgentWorkbenchService.buildPlan(
            projectID: UUID(),
            projectPath: "/tmp/proj",
            agents: agents,
            timestamp: fixedDate()
        )
        #expect(plan.steps.count == 2)
        #expect(plan.steps[0].branchName.hasPrefix("cxr-"))
        #expect(plan.steps[1].branchName.hasPrefix("feat-droidx-"))
        let paths = Set(plan.steps.map(\.worktreePath))
        #expect(paths.count == 2)
    }

    @Test("collision with existing branch name bumps suffix")
    func collisionSuffix() {
        let agent = AgentDefinition(id: "cxr", label: "CXR", branchPrefix: nil, launchCommand: "cxr", worktreeStrategy: nil)
        let existing = Set(["cxr-20260428-1830"])
        let plan = AgentWorkbenchService.buildPlan(
            projectID: UUID(),
            projectPath: "/tmp/proj",
            agents: [agent],
            timestamp: fixedDate(),
            existingBranchNames: existing
        )
        #expect(plan.steps[0].branchName != "cxr-20260428-1830")
        #expect(plan.steps[0].branchName.hasPrefix("cxr-"))
    }

    @Test("worktree path is sibling of project folder")
    func worktreePathIsSibling() {
        let agent = AgentDefinition(id: "x", label: "X", branchPrefix: nil, launchCommand: "x", worktreeStrategy: nil)
        let plan = AgentWorkbenchService.buildPlan(
            projectID: UUID(),
            projectPath: "/Users/me/code/proj",
            agents: [agent],
            timestamp: fixedDate()
        )
        let parent = (plan.steps[0].worktreePath as NSString).deletingLastPathComponent
        #expect(parent == "/Users/me/code")
    }

    @Test("empty agents list produces empty plan")
    func emptyAgents() {
        let plan = AgentWorkbenchService.buildPlan(
            projectID: UUID(),
            projectPath: "/tmp/p",
            agents: [],
            timestamp: fixedDate()
        )
        #expect(plan.steps.isEmpty)
    }
}

@Suite("WorktreeConfig agents")
struct WorktreeConfigAgentsTests {
    @Test("config without agents decodes with empty list")
    func legacyConfigNoAgents() throws {
        let json = #"""
        { "setup": ["npm install"] }
        """#
        let decoder = JSONDecoder()
        let config = try decoder.decode(WorktreeConfig.self, from: Data(json.utf8))
        #expect(config.setup.count == 1)
        #expect(config.agents.isEmpty)
    }

    @Test("config with agents array decodes populated list")
    func configWithAgents() throws {
        let json = #"""
        {
            "setup": [],
            "agents": [
                {"id": "cxr", "label": "CXR", "launchCommand": "cxr"},
                {"id": "droidx", "label": "DroidX", "launchCommand": "droidx"}
            ]
        }
        """#
        let config = try JSONDecoder().decode(WorktreeConfig.self, from: Data(json.utf8))
        #expect(config.agents.count == 2)
        #expect(config.agents.first?.id == "cxr")
    }

    @Test("config with both legacy-string setup and agents decodes")
    func legacyStringSetupWithAgents() throws {
        let json = #"""
        {
            "setup": ["bundle install"],
            "agents": [
                {"id": "a", "label": "A", "launchCommand": "a"}
            ]
        }
        """#
        let config = try JSONDecoder().decode(WorktreeConfig.self, from: Data(json.utf8))
        #expect(config.setup.count == 1)
        #expect(config.agents.count == 1)
    }
}
