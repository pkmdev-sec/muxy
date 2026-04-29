import AppKit
import Foundation

@MainActor
private func paletteCopyToPasteboard(_ value: String, toast: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(value, forType: .string)
    ToastState.shared.show(toast)
}

@MainActor
struct ShortcutCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let ghostty: GhosttyService
    let keyBindings: KeyBindingStore
    let openVCS: @MainActor (Project) -> Void

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []
        for action in ShortcutAction.allCases {
            guard !shouldHide(action) else { continue }
            let shortcut = keyBindings.combo(for: action)
            let dispatcher = ShortcutActionDispatcher(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                ghostty: ghostty
            )
            let activeProject: Project? = appState.activeProjectID.flatMap { id in
                projectStore.projects.first { $0.id == id }
            }
            let openVCS = openVCS
            out.append(PaletteCommand(
                id: "action.\(action.rawValue)",
                title: action.displayName,
                subtitle: action.category,
                symbol: symbol(for: action),
                group: .action,
                shortcut: shortcut,
                run: {
                    _ = dispatcher.perform(action, activeProject: activeProject, openVCS: openVCS)
                }
            ))
        }
        return out
    }

    private func shouldHide(_ action: ShortcutAction) -> Bool {
        if action.tabSelectionIndex != nil { return true }
        if action.projectSelectionIndex != nil { return true }
        if action == .toggleCommandPalette { return true }
        return false
    }

    private func symbol(for action: ShortcutAction) -> String {
        switch action {
        case .newTab: "plus.square"
        case .closeTab: "xmark.square"
        case .renameTab: "pencil"
        case .pinUnpinTab: "pin"
        case .splitRight: "rectangle.split.2x1"
        case .splitDown: "rectangle.split.1x2"
        case .closePane: "xmark.rectangle"
        case .focusPaneLeft,
             .focusPaneRight,
             .focusPaneUp,
             .focusPaneDown: "arrow.up.and.down.and.arrow.left.and.right"
        case .nextTab,
             .previousTab: "arrow.left.arrow.right"
        case .toggleThemePicker: "paintpalette"
        case .openProject: "folder"
        case .reloadConfig: "arrow.clockwise"
        case .nextProject,
             .previousProject: "square.stack.3d.down.right"
        case .findInTerminal: "magnifyingglass"
        case .openVCSTab: "point.3.connected.trianglepath.dotted"
        case .quickOpen: "doc.text.magnifyingglass"
        case .switchWorktree: "arrow.triangle.branch"
        case .saveFile: "tray.and.arrow.down"
        case .toggleSidebar: "sidebar.left"
        case .toggleFileTree: "list.bullet.indent"
        case .toggleAIUsage: "brain"
        case .navigateBack: "chevron.left"
        case .navigateForward: "chevron.right"
        default: "command"
        }
    }
}

@MainActor
struct ThemeCommandSource: PaletteCommandSource {
    let themes: [ThemePreview]
    let themeService: ThemeService

    func commands() -> [PaletteCommand] {
        themes.map { theme in
            let themeName = theme.name
            return PaletteCommand(
                id: "theme.\(themeName)",
                title: themeName,
                subtitle: "Apply theme",
                symbol: "paintpalette",
                group: .theme,
                shortcut: nil,
                run: { [themeService] in
                    themeService.applyTheme(themeName)
                }
            )
        }
    }
}

@MainActor
struct NavigationCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []

        for project in projectStore.projects {
            let worktrees = worktreeStore.list(for: project.id)
            for worktree in worktrees {
                let isPrimary = worktree.isPrimary
                let subtitle = isPrimary
                    ? project.path
                    : "\(project.name) · \(worktree.branch ?? worktree.name)"
                let title = isPrimary ? project.name : worktree.name
                let worktreeCopy = worktree
                let projectCopy = project
                out.append(PaletteCommand(
                    id: "nav.\(project.id.uuidString).\(worktree.id.uuidString)",
                    title: title,
                    subtitle: subtitle,
                    symbol: isPrimary ? "folder" : "arrow.triangle.branch",
                    group: .navigation,
                    shortcut: nil,
                    run: { [appState] in
                        if appState.activeProjectID == projectCopy.id {
                            appState.selectWorktree(projectID: projectCopy.id, worktree: worktreeCopy)
                        } else {
                            appState.selectProject(projectCopy, worktree: worktreeCopy)
                        }
                    }
                ))
            }
        }

        return out
    }
}

@MainActor
struct ScrollbackCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let store: TerminalScrollbackStore
    let notificationCenter: NotificationCenter

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []

        out.append(PaletteCommand(
            id: "scrollback.checkpoint.add",
            title: "Drop Scrollback Checkpoint…",
            subtitle: "Mark the current output position in the focused pane",
            symbol: "bookmark.fill",
            group: .action,
            shortcut: nil,
            run: { [notificationCenter] in
                notificationCenter.post(name: .addScrollbackCheckpoint, object: nil)
            }
        ))

        out.append(PaletteCommand(
            id: "scrollback.history.show",
            title: "Show Scrollback History",
            subtitle: "Jump to any checkpoint across projects and panes",
            symbol: "clock.arrow.circlepath",
            group: .action,
            shortcut: nil,
            run: { [notificationCenter] in
                notificationCenter.post(name: .showScrollbackHistory, object: nil)
            }
        ))

        out.append(PaletteCommand(
            id: "scrollback.checkpoints.clearCurrent",
            title: "Clear Checkpoints in Current Pane",
            subtitle: "Remove all checkpoints for the focused pane",
            symbol: "trash",
            group: .action,
            shortcut: nil,
            run: { [appState, store] in
                guard let projectID = appState.activeProjectID,
                      let area = appState.focusedArea(for: projectID),
                      let tab = area.activeTab,
                      let paneID = tab.content.pane?.id
                else {
                    ToastState.shared.show("No active pane")
                    return
                }
                store.clearCheckpoints(paneID: paneID)
                ToastState.shared.show("Cleared pane checkpoints")
            }
        ))

        for checkpoint in store.checkpoints.sorted(by: { $0.createdAt > $1.createdAt }) {
            let checkpointID = checkpoint.id
            let label = checkpoint.label
            let paneID = checkpoint.paneID
            let projectName = projectStore.projects.first(where: { $0.id == checkpoint.projectID })?.name ?? "Unassigned"
            out.append(PaletteCommand(
                id: "scrollback.jump.\(checkpointID.uuidString)",
                title: "Jump to checkpoint \u{2192} \(label)",
                subtitle: projectName,
                symbol: "bookmark",
                group: .navigation,
                shortcut: nil,
                run: { [appState, worktreeStore] in
                    jumpToScrollbackCheckpoint(
                        checkpointID: checkpointID,
                        paneID: paneID,
                        label: label,
                        appState: appState,
                        worktreeStore: worktreeStore
                    )
                }
            ))
        }

        return out
    }
}

@MainActor
private func jumpToScrollbackCheckpoint(
    checkpointID: UUID,
    paneID: UUID,
    label: String,
    appState: AppState,
    worktreeStore: WorktreeStore
) {
    guard TerminalScrollbackStore.shared.checkpoints.contains(where: { $0.id == checkpointID }) else {
        ToastState.shared.show("Checkpoint no longer available")
        return
    }
    guard let ctx = NotificationNavigator.resolveContext(
        for: paneID,
        appState: appState,
        worktreeStore: worktreeStore
    )
    else {
        ToastState.shared.show("Pane is no longer active")
        return
    }
    appState.dispatch(.selectProject(
        projectID: ctx.projectID,
        worktreeID: ctx.worktreeID,
        worktreePath: ctx.worktreePath
    ))
    appState.dispatch(.focusArea(projectID: ctx.projectID, areaID: ctx.areaID))
    appState.dispatch(.selectTab(projectID: ctx.projectID, areaID: ctx.areaID, tabID: ctx.tabID))
    ToastState.shared.show("Jumped to \"\(label)\"")
}

@MainActor
struct AgentWorkbenchCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore

    func commands() -> [PaletteCommand] {
        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID }),
              let config = WorktreeConfig.load(fromProjectPath: project.path),
              !config.agents.isEmpty
        else { return [] }

        let projectPath = project.path
        let agents = config.agents
        var out: [PaletteCommand] = []

        out.append(PaletteCommand(
            id: "agent.workbench.startAll",
            title: "Start Agent Workbench \u{2192} All Agents (\(agents.count))",
            subtitle: "Create worktrees and launch: \(agents.map(\.label).joined(separator: ", "))",
            symbol: "square.stack.3d.up",
            group: .action,
            shortcut: nil,
            run: { [appState, projectStore, worktreeStore] in
                let plan = AgentWorkbenchService.buildPlan(
                    projectID: projectID,
                    projectPath: projectPath,
                    agents: agents,
                    timestamp: Date(),
                    existingBranchNames: Set(worktreeStore.list(for: projectID).compactMap(\.branch))
                )
                Task {
                    do {
                        try await AgentWorkbenchService.execute(
                            plan,
                            projectStore: projectStore,
                            worktreeStore: worktreeStore,
                            appState: appState
                        )
                        ToastState.shared.show("Started \(plan.steps.count) agent worktrees")
                    } catch {
                        ToastState.shared.show("Agent workbench failed: \(error.localizedDescription)")
                    }
                }
            }
        ))

        for agent in agents {
            let agentCopy = agent
            out.append(PaletteCommand(
                id: "agent.workbench.start.\(agent.id)",
                title: "Start Agent \u{2192} \(agent.label)",
                subtitle: "Launch '\(agent.launchCommand)' in a new worktree",
                symbol: "play.rectangle",
                group: .action,
                shortcut: nil,
                run: { [appState, projectStore, worktreeStore] in
                    let plan = AgentWorkbenchService.buildPlan(
                        projectID: projectID,
                        projectPath: projectPath,
                        agents: [agentCopy],
                        timestamp: Date(),
                        existingBranchNames: Set(worktreeStore.list(for: projectID).compactMap(\.branch))
                    )
                    Task {
                        do {
                            try await AgentWorkbenchService.execute(
                                plan,
                                projectStore: projectStore,
                                worktreeStore: worktreeStore,
                                appState: appState
                            )
                            ToastState.shared.show("Started \(agentCopy.label)")
                        } catch {
                            ToastState.shared.show("Failed to start \(agentCopy.label): \(error.localizedDescription)")
                        }
                    }
                }
            ))
        }
        return out
    }
}

@MainActor
struct AICommandSource: PaletteCommandSource {
    let usage: AIUsageService

    func commands() -> [PaletteCommand] {
        [
            PaletteCommand(
                id: "ai.refresh",
                title: "Refresh AI Usage",
                subtitle: "Re-query every enabled provider",
                symbol: "arrow.clockwise",
                group: .ai,
                shortcut: nil,
                run: { [usage] in
                    Task { await usage.refresh(force: true) }
                }
            ),
        ]
    }
}

@MainActor
struct SettingsCommandSource: PaletteCommandSource {
    func commands() -> [PaletteCommand] {
        [
            PaletteCommand(
                id: "settings.open",
                title: "Open Settings",
                subtitle: "Appearance, shortcuts, mobile, AI usage…",
                symbol: "gearshape",
                group: .settings,
                shortcut: KeyCombo(key: ",", command: true),
                run: {
                    if #available(macOS 14, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            ),
        ]
    }
}

@MainActor
struct FileContextCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []

        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return out }

        let activeWorktree = activeWorktree(for: projectID)
        let worktreePath = activeWorktree?.path ?? project.path
        let projectPath = project.path

        let activeFilePath = activeEditorPath(projectID: projectID)
        if let activeFilePath {
            let fileName = (activeFilePath as NSString).lastPathComponent
            let relative = relativePath(of: activeFilePath, under: worktreePath)

            out.append(PaletteCommand(
                id: "file.copyAbsolutePath",
                title: "Copy File Path",
                subtitle: activeFilePath,
                symbol: "doc.on.clipboard",
                group: .action,
                shortcut: nil,
                run: { paletteCopyToPasteboard(activeFilePath, toast: "Copied path") }
            ))

            out.append(PaletteCommand(
                id: "file.copyRelativePath",
                title: "Copy Relative Path",
                subtitle: relative,
                symbol: "arrow.right.doc.on.clipboard",
                group: .action,
                shortcut: nil,
                run: { paletteCopyToPasteboard(relative, toast: "Copied relative path") }
            ))

            out.append(PaletteCommand(
                id: "file.copyName",
                title: "Copy File Name",
                subtitle: fileName,
                symbol: "textformat",
                group: .action,
                shortcut: nil,
                run: { paletteCopyToPasteboard(fileName, toast: "Copied file name") }
            ))

            out.append(PaletteCommand(
                id: "file.revealInFinder",
                title: "Reveal in Finder",
                subtitle: activeFilePath,
                symbol: "macwindow",
                group: .action,
                shortcut: nil,
                run: {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: activeFilePath)])
                }
            ))
        }

        out.append(PaletteCommand(
            id: "project.copyPath",
            title: "Copy Project Path",
            subtitle: projectPath,
            symbol: "folder",
            group: .action,
            shortcut: nil,
            run: { paletteCopyToPasteboard(projectPath, toast: "Copied project path") }
        ))

        if worktreePath != projectPath {
            out.append(PaletteCommand(
                id: "project.copyWorktreePath",
                title: "Copy Worktree Path",
                subtitle: worktreePath,
                symbol: "arrow.triangle.branch",
                group: .action,
                shortcut: nil,
                run: { paletteCopyToPasteboard(worktreePath, toast: "Copied worktree path") }
            ))
        }

        if let branch = activeWorktree?.branch, !branch.isEmpty {
            out.append(PaletteCommand(
                id: "project.copyBranch",
                title: "Copy Current Branch",
                subtitle: branch,
                symbol: "arrow.triangle.branch",
                group: .action,
                shortcut: nil,
                run: { paletteCopyToPasteboard(branch, toast: "Copied branch name") }
            ))
        }

        return out
    }

    private func activeEditorPath(projectID: UUID) -> String? {
        guard let tab = appState.activeTab(for: projectID) else { return nil }
        if let editorState = tab.content.editorState {
            return editorState.filePath
        }
        return nil
    }

    private func activeWorktree(for projectID: UUID) -> Worktree? {
        guard let worktreeID = appState.activeWorktreeID[projectID] else { return nil }
        return worktreeStore.list(for: projectID).first(where: { $0.id == worktreeID })
    }

    private func relativePath(of absolute: String, under base: String) -> String {
        let prefix = base.hasSuffix("/") ? base : base + "/"
        if absolute.hasPrefix(prefix) {
            return String(absolute.dropFirst(prefix.count))
        }
        return absolute
    }
}

@MainActor
struct VCSCommandSource: PaletteCommandSource {
    let resolveActiveVCS: () -> VCSTabState?

    func commands() -> [PaletteCommand] {
        guard let vcs = resolveActiveVCS() else { return [] }
        var out: [PaletteCommand] = []

        out.append(PaletteCommand(
            id: "vcs.stash.push",
            title: "Stash Current Changes",
            subtitle: "Save tracked changes on a stash entry",
            symbol: "tray.and.arrow.down",
            group: .action,
            shortcut: nil,
            run: { [vcs] in vcs.pushStash(message: nil, includeUntracked: false) }
        ))

        out.append(PaletteCommand(
            id: "vcs.stash.pushIncludeUntracked",
            title: "Stash Including Untracked",
            subtitle: "Include new files not yet tracked by git",
            symbol: "tray.and.arrow.down.fill",
            group: .action,
            shortcut: nil,
            run: { [vcs] in vcs.pushStash(message: nil, includeUntracked: true) }
        ))

        for stash in vcs.stashes {
            let slot = stash.slot
            let subtitle = stash.trailingMessage.isEmpty ? stash.message : stash.trailingMessage
            out.append(PaletteCommand(
                id: "vcs.stash.pop.\(slot)",
                title: "Pop \(slot)",
                subtitle: subtitle,
                symbol: "tray.and.arrow.up",
                group: .action,
                shortcut: nil,
                run: { [vcs] in vcs.popStash(slot: slot) }
            ))
            out.append(PaletteCommand(
                id: "vcs.stash.apply.\(slot)",
                title: "Apply \(slot)",
                subtitle: subtitle,
                symbol: "arrow.down.to.line",
                group: .action,
                shortcut: nil,
                run: { [vcs] in vcs.applyStash(slot: slot) }
            ))
            out.append(PaletteCommand(
                id: "vcs.stash.drop.\(slot)",
                title: "Drop \(slot)",
                subtitle: subtitle,
                symbol: "trash",
                group: .action,
                shortcut: nil,
                run: { [vcs] in vcs.dropStash(slot: slot) }
            ))
        }

        return out
    }
}

@MainActor
struct WorkspaceTemplateCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let templateStore: WorkspaceTemplateStore

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []

        if appState.activeProjectID != nil {
            out.append(PaletteCommand(
                id: "workspace.saveTemplate",
                title: "Save Layout as Template",
                subtitle: "Capture current splits + tab kinds for reuse",
                symbol: "square.and.arrow.down",
                group: .action,
                shortcut: nil,
                run: { [appState] in
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    let name = "Layout \(formatter.string(from: Date()))"
                    if appState.saveCurrentLayoutAsTemplate(named: name) != nil {
                        ToastState.shared.show("Saved template \"\(name)\"")
                    } else {
                        ToastState.shared.show("No active workspace to save")
                    }
                }
            ))
        }

        for template in templateStore.templates {
            let templateID = template.id
            let templateName = template.name
            out.append(PaletteCommand(
                id: "workspace.applyTemplate.\(templateID.uuidString)",
                title: "Apply Template \u{2192} \(templateName)",
                subtitle: "Replace current workspace layout",
                symbol: "square.grid.2x2",
                group: .action,
                shortcut: nil,
                run: { [appState, projectStore, worktreeStore, templateStore] in
                    guard let template = templateStore.templates.first(where: { $0.id == templateID }),
                          let projectID = appState.activeProjectID,
                          let worktreeID = appState.activeWorktreeID[projectID]
                    else {
                        ToastState.shared.show("No active workspace to apply template")
                        return
                    }
                    let worktrees = worktreeStore.list(for: projectID)
                    guard let worktree = worktrees.first(where: { $0.id == worktreeID }) else {
                        ToastState.shared.show("Active worktree unavailable")
                        return
                    }
                    _ = projectStore
                    appState.applyTemplate(
                        template,
                        projectID: projectID,
                        worktreeID: worktreeID,
                        worktreePath: worktree.path
                    )
                    ToastState.shared.show("Applied template \"\(templateName)\"")
                }
            ))

            out.append(PaletteCommand(
                id: "workspace.deleteTemplate.\(templateID.uuidString)",
                title: "Delete Template \u{2192} \(templateName)",
                subtitle: "Remove this saved layout",
                symbol: "trash",
                group: .action,
                shortcut: nil,
                run: { [templateStore] in
                    templateStore.remove(id: templateID)
                    ToastState.shared.show("Deleted template \"\(templateName)\"")
                }
            ))
        }

        return out
    }
}

@MainActor
struct AgentInboxCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore
    let agentStore: AIAgentSessionStore
    let notificationCenter: NotificationCenter

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []

        out.append(PaletteCommand(
            id: "agent.inbox.open",
            title: "Show Agent Inbox",
            subtitle: "Live status of every AI agent across projects",
            symbol: "sparkles.rectangle.stack",
            group: .action,
            shortcut: nil,
            run: { [notificationCenter] in
                notificationCenter.post(name: .showAgentInbox, object: nil)
            }
        ))

        out.append(PaletteCommand(
            id: "agent.inbox.clearCompleted",
            title: "Clear Completed Agents",
            subtitle: "Remove done sessions from the Agent Inbox",
            symbol: "checkmark.circle",
            group: .action,
            shortcut: nil,
            run: { [agentStore] in
                agentStore.clearCompleted()
                ToastState.shared.show("Cleared completed agents")
            }
        ))

        for session in agentStore.sessions.sorted(by: { $0.lastActivity > $1.lastActivity }) {
            let sessionID = session.id
            let label = session.label
            let projectName = projectStore.projects.first(where: { $0.id == session.projectID })?.name ?? "project"
            out.append(PaletteCommand(
                id: "agent.jump.\(sessionID.uuidString)",
                title: "Jump to Agent \u{2192} \(label)",
                subtitle: "\(projectName) \u{2192} \(session.status.displayName)",
                symbol: session.status.symbolName,
                group: .navigation,
                shortcut: nil,
                run: { [appState, agentStore] in
                    guard let session = agentStore.sessions.first(where: { $0.id == sessionID }) else {
                        ToastState.shared.show("Agent session no longer active")
                        return
                    }
                    guard session.tabID != nil, session.areaID != nil else {
                        ToastState.shared.show("Agent pane is not yet ready")
                        return
                    }
                    agentStore.navigate(to: session, appState: appState)
                }
            ))
        }

        return out
    }
}

@MainActor
struct WorkflowMacroCommandSource: PaletteCommandSource {
    let appState: AppState
    let macroStore: WorkflowMacroStore
    let recorder: WorkflowRecorder
    let notificationCenter: NotificationCenter
    let paletteProvider: @MainActor () -> CommandPalette

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []

        let toggleTitle = recorder.isRecording ? "Stop Recording Workflow" : "Record Workflow\u{2026}"
        let toggleSymbol = recorder.isRecording ? "stop.circle" : "record.circle"
        let toggleSubtitle = recorder.isRecording
            ? "Stop and save the current recording"
            : "Capture the next palette actions as a replayable macro"
        out.append(PaletteCommand(
            id: "workflow.toggleRecording",
            title: toggleTitle,
            subtitle: toggleSubtitle,
            symbol: toggleSymbol,
            group: .action,
            shortcut: nil,
            run: { [notificationCenter] in
                notificationCenter.post(name: .toggleWorkflowRecording, object: nil)
            }
        ))

        for macro in macroStore.macros {
            let macroID = macro.id
            let macroName = macro.name
            let macroSymbol = macro.symbol
            let stepLabel = macro.steps.count == 1 ? "step" : "steps"
            out.append(PaletteCommand(
                id: "workflow.run.\(macroID.uuidString)",
                title: "Run Workflow \u{2192} \(macroName)",
                subtitle: "Replay \(macro.steps.count) \(stepLabel)",
                symbol: macroSymbol,
                group: .action,
                shortcut: nil,
                run: { [macroStore, paletteProvider] in
                    guard let macro = macroStore.macro(id: macroID) else {
                        ToastState.shared.show("Workflow no longer exists")
                        return
                    }
                    let palette = paletteProvider()
                    Task {
                        let executed = await WorkflowPlayer.run(macro, palette: palette)
                        ToastState.shared.show("Ran workflow \"\(macroName)\" (\(executed)/\(macro.steps.count) steps)")
                    }
                }
            ))

            out.append(PaletteCommand(
                id: "workflow.delete.\(macroID.uuidString)",
                title: "Delete Workflow \u{2192} \(macroName)",
                subtitle: "Remove saved macro",
                symbol: "trash",
                group: .action,
                shortcut: nil,
                run: { [macroStore] in
                    macroStore.remove(id: macroID)
                    ToastState.shared.show("Deleted workflow \"\(macroName)\"")
                }
            ))
        }

        return out
    }
}

@MainActor
struct TestRunnerCommandSource: PaletteCommandSource {
    let appState: AppState
    let projectStore: ProjectStore

    func commands() -> [PaletteCommand] {
        guard let projectID = appState.activeProjectID,
              let project = projectStore.projects.first(where: { $0.id == projectID })
        else { return [] }
        let detection = TestFrameworkDetector.detect(projectPath: project.path)
        var out: [PaletteCommand] = []
        out.append(PaletteCommand(
            id: "tests.open",
            title: "Run Tests in Project",
            subtitle: "Open a Test Runner tab and execute: \(detection.commandLine)",
            symbol: "checkmark.square",
            group: .action,
            shortcut: nil,
            run: { [appState] in
                appState.createTestRunnerTab(
                    projectID: projectID,
                    commandLine: detection.commandLine,
                    framework: detection.framework
                )
            }
        ))
        out.append(PaletteCommand(
            id: "tests.open.swiftTesting",
            title: "Run Swift Tests",
            subtitle: "swift test",
            symbol: "swift",
            group: .action,
            shortcut: nil,
            run: { [appState] in
                appState.createTestRunnerTab(
                    projectID: projectID,
                    commandLine: "swift test",
                    framework: .swiftTesting
                )
            }
        ))
        return out
    }
}

@MainActor
struct GitLogCommandSource: PaletteCommandSource {
    let appState: AppState

    func commands() -> [PaletteCommand] {
        guard let projectID = appState.activeProjectID else { return [] }
        var out: [PaletteCommand] = []
        out.append(PaletteCommand(
            id: "vcs.log.open",
            title: "Open Commit Graph",
            subtitle: "Interactive git log with rails, refs, and commit detail panel",
            symbol: "chart.line.uptrend.xyaxis",
            group: .action,
            shortcut: nil,
            run: { [appState] in
                appState.createGitLogTab(projectID: projectID)
            }
        ))
        return out
    }
}

@MainActor
struct AgentCanvasCommandSource: PaletteCommandSource {
    let appState: AppState

    func commands() -> [PaletteCommand] {
        guard let projectID = appState.activeProjectID else { return [] }
        var out: [PaletteCommand] = []
        out.append(PaletteCommand(
            id: "agent.canvas.open",
            title: "Open Agent Canvas",
            subtitle: "Wire agent panes together with prompt-relay, broadcast, and mirror wires",
            symbol: "point.3.connected.trianglepath.dotted",
            group: .action,
            shortcut: nil,
            run: { [appState] in
                appState.createAgentCanvasTab(projectID: projectID, name: "Agent Canvas")
            }
        ))
        out.append(PaletteCommand(
            id: "agent.canvas.stopAllWires",
            title: "Stop All Agent Canvas Wires",
            subtitle: "Disconnect every live relay across all canvases",
            symbol: "bolt.slash",
            group: .action,
            shortcut: nil,
            run: {
                PaneWireBus.shared.deactivateAll()
                ToastState.shared.show("All Agent Canvas wires stopped")
            }
        ))
        return out
    }
}

@MainActor
struct PeerConnectionCommandSource: PaletteCommandSource {
    let notificationCenter: NotificationCenter

    func commands() -> [PaletteCommand] {
        [
            PaletteCommand(
                id: "peer.connect.open",
                title: "Connect to Muxy Peer\u{2026}",
                subtitle: "Pair with another Muxy over your local network",
                symbol: "network",
                group: .action,
                shortcut: nil,
                run: { [notificationCenter] in
                    notificationCenter.post(name: .showConnectPeer, object: nil)
                }
            ),
        ]
    }
}

@MainActor
struct PluginCommandSource: PaletteCommandSource {
    let host: MuxyPluginHost

    func commands() -> [PaletteCommand] {
        var out: [PaletteCommand] = []
        for command in host.paletteCommands {
            let commandID = command.id
            out.append(PaletteCommand(
                id: commandID,
                title: command.title,
                subtitle: command.subtitle,
                symbol: command.symbol,
                group: .action,
                shortcut: nil,
                run: { [host] in
                    host.invoke(commandID: commandID)
                }
            ))
        }
        out.append(PaletteCommand(
            id: "plugin.reload",
            title: "Reload Plugins",
            subtitle: "Re-scan ~/Library/Application Support/Muxy/Plugins",
            symbol: "arrow.clockwise",
            group: .action,
            shortcut: nil,
            run: { [host] in
                host.loadAll()
                ToastState.shared.show("Reloaded \(host.loadedPlugins.count) plugin(s)")
            }
        ))
        out.append(PaletteCommand(
            id: "plugin.openFolder",
            title: "Open Plugins Folder",
            subtitle: "Drop .js files here and reload",
            symbol: "folder",
            group: .action,
            shortcut: nil,
            run: { [host] in
                host.openPluginsDirectoryInFinder()
            }
        ))
        return out
    }
}
