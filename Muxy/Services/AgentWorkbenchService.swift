import Foundation
import os

private let agentWorkbenchLogger = Logger(subsystem: "app.muxy", category: "AgentWorkbench")

struct AgentWorkbenchBuildPlan: Equatable {
    struct Step: Equatable {
        let agent: AgentDefinition
        let branchName: String
        let worktreePath: String
    }

    let projectID: UUID
    let steps: [Step]
}

enum AgentWorkbenchError: Error, LocalizedError {
    case paneNotReady(agentID: String)

    var errorDescription: String? {
        switch self {
        case let .paneNotReady(agentID):
            "Terminal pane for agent \(agentID) did not come up in time."
        }
    }
}

@MainActor
enum AgentWorkbenchService {
    static func buildPlan(
        projectID: UUID,
        projectPath: String,
        agents: [AgentDefinition],
        timestamp: Date,
        existingBranchNames: Set<String> = []
    ) -> AgentWorkbenchBuildPlan {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: timestamp)

        let projectURL = URL(fileURLWithPath: projectPath)
        let parentURL = projectURL.deletingLastPathComponent()
        let projectFolder = projectURL.lastPathComponent

        var taken = existingBranchNames
        var steps: [AgentWorkbenchBuildPlan.Step] = []
        for agent in agents {
            let base = "\(agent.effectiveBranchPrefix)-\(stamp)"
            var candidate = base
            var suffix = 2
            while taken.contains(candidate) {
                candidate = "\(base)-\(suffix)"
                suffix += 1
            }
            taken.insert(candidate)
            let worktreeURL = parentURL.appendingPathComponent("\(projectFolder)-\(candidate)")
            steps.append(AgentWorkbenchBuildPlan.Step(
                agent: agent,
                branchName: candidate,
                worktreePath: worktreeURL.path
            ))
        }
        return AgentWorkbenchBuildPlan(projectID: projectID, steps: steps)
    }

    static func execute(
        _ plan: AgentWorkbenchBuildPlan,
        projectStore: ProjectStore,
        worktreeStore: WorktreeStore,
        appState: AppState
    ) async throws {
        guard let project = projectStore.projects.first(where: { $0.id == plan.projectID }) else {
            return
        }
        for step in plan.steps {
            try await runStep(
                step,
                project: project,
                worktreeStore: worktreeStore,
                appState: appState
            )
        }
    }

    private static func runStep(
        _ step: AgentWorkbenchBuildPlan.Step,
        project: Project,
        worktreeStore: WorktreeStore,
        appState: AppState
    ) async throws {
        try await GitWorktreeService.shared.addWorktree(
            repoPath: project.path,
            path: step.worktreePath,
            branch: step.branchName,
            createBranch: true
        )

        let worktree = Worktree(
            id: UUID(),
            name: step.branchName,
            path: step.worktreePath,
            branch: step.branchName,
            ownsBranch: true,
            source: .muxy,
            isPrimary: false
        )
        worktreeStore.add(worktree, to: project.id)

        appState.selectWorktree(projectID: project.id, worktree: worktree)

        guard let paneID = await waitForActivePane(appState: appState, projectID: project.id) else {
            throw AgentWorkbenchError.paneNotReady(agentID: step.agent.id)
        }

        let focused = appState.focusedArea(for: project.id)
        _ = AIAgentSessionStore.shared.register(AgentSessionRegistration(
            providerID: step.agent.id,
            label: step.agent.label,
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: step.worktreePath,
            coordinate: AgentPaneCoordinate(
                paneID: paneID,
                tabID: focused?.activeTabID,
                areaID: focused?.id
            ),
            origin: .workbench,
            status: .thinking
        ))

        var parts: [String] = []
        if let setupCommands = setupCommandLine(forWorktreePath: step.worktreePath) {
            parts.append(setupCommands)
        }
        let launch = step.agent.launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !launch.isEmpty {
            parts.append(launch)
        }
        let combined = parts.joined(separator: " && ")

        guard !combined.isEmpty else { return }
        await sendToPane(paneID: paneID, command: combined, agentID: step.agent.id)
    }

    private static func setupCommandLine(forWorktreePath path: String) -> String? {
        guard let config = WorktreeConfig.load(fromProjectPath: path), !config.setup.isEmpty else {
            return nil
        }
        let trimmedCommands = config.setup
            .map(\.command)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = trimmedCommands.joined(separator: " && ")
        return joined.isEmpty ? nil : joined
    }

    private static func waitForActivePane(appState: AppState, projectID: UUID) async -> UUID? {
        for _ in 0 ..< 50 {
            if let paneID = appState.focusedArea(for: projectID)?.activeTab?.content.pane?.id {
                return paneID
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    private static func sendToPane(paneID: UUID, command: String, agentID: String) async {
        for _ in 0 ..< 50 {
            if let view = TerminalViewRegistry.shared.view(for: paneID), view.hasLiveSurface {
                view.sendText(command)
                view.sendReturnKey()
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        agentWorkbenchLogger.error("Timed out waiting for pane \(paneID.uuidString) for agent \(agentID)")
    }
}
