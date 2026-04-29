import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("AIAgentSessionStore")
struct AIAgentSessionStoreTests {
    private func makeStore() -> AIAgentSessionStore {
        AIAgentSessionStore.shared.clearAll()
        return AIAgentSessionStore.shared
    }

    @Test("register creates a new session when none match")
    func registerCreatesNew() {
        let store = makeStore()
        let session = store.register(AgentSessionRegistration(
            providerID: "cxr",
            label: "CXR",
            projectID: UUID(),
            worktreeID: UUID(),
            worktreePath: "/tmp/p",
            coordinate: AgentPaneCoordinate(paneID: UUID(), tabID: UUID(), areaID: UUID()),
            origin: .workbench
        ))
        #expect(store.sessions.count == 1)
        #expect(session.label == "CXR")
        #expect(session.origin == .workbench)
    }

    @Test("register upserts by project+tab+provider")
    func registerUpserts() {
        let store = makeStore()
        let projectID = UUID()
        let tabID = UUID()
        _ = store.register(AgentSessionRegistration(providerID: "cxr", label: "CXR", projectID: projectID, worktreeID: UUID(), worktreePath: "/a", coordinate: AgentPaneCoordinate(paneID: UUID(), tabID: tabID, areaID: UUID()), origin: .workbench))
        _ = store.register(AgentSessionRegistration(providerID: "cxr", label: "CXR v2", projectID: projectID, worktreeID: UUID(), worktreePath: "/a", coordinate: AgentPaneCoordinate(paneID: UUID(), tabID: tabID, areaID: UUID()), origin: .workbench, status: .thinking))
        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.label == "CXR v2")
        #expect(store.sessions.first?.status == .thinking)
    }

    @Test("different providers on same tab create distinct sessions")
    func distinctProviders() {
        let store = makeStore()
        let pid = UUID()
        let tabID = UUID()
        _ = store.register(AgentSessionRegistration(providerID: "cxr", label: "CXR", projectID: pid, worktreeID: UUID(), worktreePath: "/a", coordinate: AgentPaneCoordinate(paneID: UUID(), tabID: tabID, areaID: UUID()), origin: .workbench))
        _ = store.register(AgentSessionRegistration(providerID: "droidx", label: "DroidX", projectID: pid, worktreeID: UUID(), worktreePath: "/a", coordinate: AgentPaneCoordinate(paneID: UUID(), tabID: tabID, areaID: UUID()), origin: .workbench))
        #expect(store.sessions.count == 2)
    }

    @Test("clearCompleted removes done sessions")
    func clearCompleted() {
        let store = makeStore()
        let s1 = store.register(AgentSessionRegistration(providerID: "a", label: "A", projectID: UUID(), worktreeID: UUID(), worktreePath: "/a", coordinate: AgentPaneCoordinate(paneID: nil, tabID: nil, areaID: nil), origin: .manual))
        let s2 = store.register(AgentSessionRegistration(providerID: "b", label: "B", projectID: UUID(), worktreeID: UUID(), worktreePath: "/b", coordinate: AgentPaneCoordinate(paneID: nil, tabID: nil, areaID: nil), origin: .manual))
        s1.status = .done
        s2.status = .thinking
        store.clearCompleted()
        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.providerID == "b")
    }

    @Test("sessions(projectID:) filters by project")
    func filterByProject() {
        let store = makeStore()
        let p1 = UUID()
        let p2 = UUID()
        _ = store.register(AgentSessionRegistration(providerID: "a", label: "A", projectID: p1, worktreeID: UUID(), worktreePath: "/a", coordinate: AgentPaneCoordinate(paneID: nil, tabID: nil, areaID: nil), origin: .manual))
        _ = store.register(AgentSessionRegistration(providerID: "b", label: "B", projectID: p2, worktreeID: UUID(), worktreePath: "/b", coordinate: AgentPaneCoordinate(paneID: nil, tabID: nil, areaID: nil), origin: .manual))
        #expect(store.sessions(projectID: p1).count == 1)
        #expect(store.sessions(projectID: p1).first?.providerID == "a")
    }
}

@Suite("AIAgentStatusInference")
struct AIAgentStatusInferenceTests {
    @Test("awaiting input keywords win priority")
    func awaitingInput() {
        #expect(AIAgentStatusInference.status(title: "Codex", body: "Awaiting permission for tool call") == .awaitingInput)
        #expect(AIAgentStatusInference.status(title: "Confirm deletion?", body: "") == .awaitingInput)
    }

    @Test("error keywords map to error")
    func errorStatus() {
        #expect(AIAgentStatusInference.status(title: "Error", body: "Failed to parse") == .error)
    }

    @Test("completion keywords map to done")
    func done() {
        #expect(AIAgentStatusInference.status(title: "Task finished", body: "") == .done)
        #expect(AIAgentStatusInference.status(title: "Completed", body: "") == .done)
    }

    @Test("active keywords map to thinking")
    func thinking() {
        #expect(AIAgentStatusInference.status(title: "Running tests", body: "") == .thinking)
        #expect(AIAgentStatusInference.status(title: "Started build", body: "") == .thinking)
    }

    @Test("unknown text yields nil")
    func unknown() {
        #expect(AIAgentStatusInference.status(title: "neutral", body: "nothing") == nil)
    }
}

@Suite("AIAgentTaskExtractor")
struct AIAgentTaskExtractorTests {
    @Test("extracts first line trimmed")
    func firstLine() {
        let task = AIAgentTaskExtractor.task(from: "Refactor TabReducer\nAlso fix tests")
        #expect(task == "Refactor TabReducer")
    }

    @Test("returns nil on empty body")
    func emptyBody() {
        #expect(AIAgentTaskExtractor.task(from: "   \n\n") == nil)
    }

    @Test("truncates long first lines")
    func truncates() {
        let long = String(repeating: "x", count: 200)
        let out = AIAgentTaskExtractor.task(from: long)
        #expect((out ?? "").count <= 141)
        #expect((out ?? "").hasSuffix("\u{2026}"))
    }
}

@Suite("AIAgentLabeler")
struct AIAgentLabelerTests {
    @Test("known providers map to display names")
    func knownLabels() {
        #expect(AIAgentLabeler.label(providerID: "claude-code") == "Claude Code")
        #expect(AIAgentLabeler.label(providerID: "cxr") == "CXR")
        #expect(AIAgentLabeler.label(providerID: "droidx") == "DroidX")
    }

    @Test("unknown provider is capitalized")
    func unknownCapitalized() {
        #expect(AIAgentLabeler.label(providerID: "myagent") == "Myagent")
    }
}
