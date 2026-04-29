import Foundation

@MainActor
@Observable
final class TerminalTab: Identifiable {
    enum Kind: String, Codable {
        case terminal
        case vcs
        case editor
        case diffViewer
        case testRunner
        case agentCanvas
        case gitLog
        case remotePane
    }

    enum Content {
        case terminal(TerminalPaneState)
        case vcs(VCSTabState)
        case editor(EditorTabState)
        case diffViewer(DiffViewerTabState)
        case testRunner(TestRunnerTabState)
        case agentCanvas(AgentCanvasState)
        case gitLog(GitLogTabState)
        case remotePane(RemotePaneTabState)

        var kind: Kind {
            switch self {
            case .terminal: .terminal
            case .vcs: .vcs
            case .editor: .editor
            case .diffViewer: .diffViewer
            case .testRunner: .testRunner
            case .agentCanvas: .agentCanvas
            case .gitLog: .gitLog
            case .remotePane: .remotePane
            }
        }

        var pane: TerminalPaneState? {
            guard case let .terminal(pane) = self else { return nil }
            return pane
        }

        var vcsState: VCSTabState? {
            guard case let .vcs(state) = self else { return nil }
            return state
        }

        var editorState: EditorTabState? {
            guard case let .editor(state) = self else { return nil }
            return state
        }

        var diffViewerState: DiffViewerTabState? {
            guard case let .diffViewer(state) = self else { return nil }
            return state
        }

        var testRunnerState: TestRunnerTabState? {
            guard case let .testRunner(state) = self else { return nil }
            return state
        }

        var agentCanvasState: AgentCanvasState? {
            guard case let .agentCanvas(state) = self else { return nil }
            return state
        }

        var gitLogState: GitLogTabState? {
            guard case let .gitLog(state) = self else { return nil }
            return state
        }

        var remotePaneState: RemotePaneTabState? {
            guard case let .remotePane(state) = self else { return nil }
            return state
        }

        var projectPath: String {
            switch self {
            case let .terminal(pane): pane.projectPath
            case let .vcs(state): state.projectPath
            case let .editor(state): state.projectPath
            case let .diffViewer(state): state.projectPath
            case let .testRunner(state): state.projectPath
            case let .agentCanvas(state): state.projectPath
            case let .gitLog(state): state.projectPath
            case let .remotePane(state): state.projectPath
            }
        }
    }

    let id = UUID()
    var customTitle: String?
    var colorID: String?
    var isPinned: Bool = false
    let content: Content

    var kind: Kind { content.kind }

    var title: String {
        if let customTitle {
            return customTitle
        }
        switch content {
        case let .terminal(pane):
            return pane.title
        case .vcs:
            return "Git Diff"
        case let .editor(state):
            return state.displayTitle
        case let .diffViewer(state):
            return state.displayTitle
        case let .testRunner(state):
            return state.displayTitle
        case let .agentCanvas(state):
            return state.displayTitle
        case let .gitLog(state):
            return state.displayTitle
        case let .remotePane(state):
            return state.displayTitle
        }
    }

    init(pane: TerminalPaneState) {
        content = .terminal(pane)
    }

    init(vcsState: VCSTabState) {
        content = .vcs(vcsState)
    }

    init(editorState: EditorTabState) {
        content = .editor(editorState)
    }

    init(diffViewerState: DiffViewerTabState) {
        content = .diffViewer(diffViewerState)
    }

    init(testRunnerState: TestRunnerTabState) {
        content = .testRunner(testRunnerState)
    }

    init(agentCanvasState: AgentCanvasState) {
        content = .agentCanvas(agentCanvasState)
    }

    init(gitLogState: GitLogTabState) {
        content = .gitLog(gitLogState)
    }

    init(remotePaneState: RemotePaneTabState) {
        content = .remotePane(remotePaneState)
    }

    init(restoring snapshot: TerminalTabSnapshot) {
        customTitle = snapshot.customTitle
        colorID = snapshot.colorID
        isPinned = snapshot.isPinned
        switch snapshot.kind {
        case .terminal:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        case .vcs:
            content = .vcs(VCSTabState(projectPath: snapshot.projectPath))
        case .editor:
            if let filePath = snapshot.filePath {
                content = .editor(EditorTabState(projectPath: snapshot.projectPath, filePath: filePath))
            } else {
                content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
            }
        case .diffViewer:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        case .testRunner:
            let commandLine = snapshot.testRunnerCommandLine ?? "swift test"
            content = .testRunner(TestRunnerTabState(projectPath: snapshot.projectPath, commandLine: commandLine))
        case .agentCanvas:
            let name = snapshot.agentCanvasName ?? "Agent Canvas"
            let canvas = AgentCanvasState(projectPath: snapshot.projectPath, name: name)
            if let graph = snapshot.agentCanvasGraph {
                canvas.restore(graph: graph)
            }
            content = .agentCanvas(canvas)
        case .gitLog:
            content = .gitLog(GitLogTabState(projectPath: snapshot.projectPath))
        case .remotePane:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        }
    }

    func snapshot() -> TerminalTabSnapshot {
        TerminalTabSnapshot(
            kind: content.kind,
            customTitle: customTitle,
            colorID: colorID,
            isPinned: isPinned,
            projectPath: content.projectPath,
            paneTitle: content.pane?.title,
            filePath: content.editorState?.filePath,
            testRunnerCommandLine: content.testRunnerState?.commandLine,
            agentCanvasName: content.agentCanvasState?.name,
            agentCanvasGraph: content.agentCanvasState?.serializeGraph()
        )
    }
}
