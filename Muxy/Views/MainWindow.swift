import AppKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(GhosttyService.self) private var ghostty
    @Environment(\.openWindow) private var openWindow
    @State private var dragCoordinator = TabDragCoordinator()
    private enum AttachedVCSLayout {
        static let minWidth: CGFloat = 200
        static let defaultWidth: CGFloat = 400
        static let maxWidth: CGFloat = 800
    }

    private enum FileTreeLayout {
        static let minWidth: CGFloat = 180
        static let defaultWidth: CGFloat = 260
        static let maxWidth: CGFloat = 600
    }

    private enum CloseConfirmationKind {
        case lastTab
        case unsavedEditor
        case runningProcess

        var title: String {
            switch self {
            case .lastTab:
                "Close Project?"
            case .unsavedEditor:
                "Save Changes Before Closing?"
            case .runningProcess:
                "Close Tab?"
            }
        }

        var message: String {
            switch self {
            case .lastTab:
                "This is the last tab. Closing it will remove the project from the sidebar."
            case .unsavedEditor:
                "This file has unsaved changes. If you don't save, your changes will be lost."
            case .runningProcess:
                "A process is still running in this tab. Are you sure you want to close it?"
            }
        }
    }

    @State private var vcsPanelVisible = false
    @State private var vcsPanelWidth: CGFloat = AttachedVCSLayout.defaultWidth
    @State private var vcsStates: [WorktreeKey: VCSTabState] = [:]
    @State private var fileTreePanelVisible = false
    @AppStorage("muxy.fileTreeWidth") private var fileTreePanelWidth: Double = .init(FileTreeLayout.defaultWidth)
    @State private var fileTreeStates: [WorktreeKey: FileTreeState] = [:]
    @State private var showQuickOpen = false
    @State private var showWorktreeSwitcher = false
    @State private var showCommandPalette = false
    @State private var paletteThemes: [ThemePreview] = []
    @State private var showProjectSearch = false
    @State private var showShortcutCheatSheet = false
    @State private var showAgentInbox = false
    @State private var showScrollbackHistory = false
    @State private var scrollbackCheckpointPrompt: ScrollbackCheckpointPromptState?
    @State private var workflowSavePrompt: WorkflowSavePromptState?
    @State private var showConnectPeer = false
    @State private var showDiagnostics = false
    @State private var isFullScreen = false
    @State private var sidebarExpanded = UserDefaults.standard.bool(forKey: "muxy.sidebarExpanded")
    @AppStorage("muxy.notifications.toastPosition") private var toastPositionRaw = ToastPosition.topCenter.rawValue
    private let trafficLightWidth: CGFloat = 75

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !isFullScreen {
                    Color.clear
                        .frame(width: topBarLeadingWidth)
                        .fixedSize(horizontal: true, vertical: false)
                        .overlay(alignment: .trailing) {
                            if sidebarExpanded {
                                HStack(spacing: 0) {
                                    navigationArrows
                                    Rectangle().fill(MuxyTheme.border).frame(width: 1)
                                }
                            }
                        }
                }
                topBarContent
            }
            .frame(height: 32)
            .background(WindowDragRepresentable())
            .background(MuxyTheme.bg)

            Rectangle().fill(MuxyTheme.border).frame(height: 1)
                .background(MuxyTheme.bg)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Sidebar()
                    Rectangle().fill(MuxyTheme.border).frame(width: 1)
                        .accessibilityHidden(true)
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(MuxyTheme.bg)

                ZStack {
                    MuxyTheme.bg
                    if let project = activeProject,
                       appState.workspaceRoot(for: project.id) == nil,
                       let worktree = resolvedActiveWorktree(for: project)
                    {
                        EmptyProjectPlaceholder(project: project) {
                            appState.selectWorktree(projectID: project.id, worktree: worktree)
                        }
                    } else if projectsWithWorkspaces.isEmpty {
                        WelcomeView()
                    } else if let project = activeProjectWithWorkspace,
                              let activeKey = appState.activeWorktreeKey(for: project.id)
                    {
                        ForEach(mountedWorktreeKeys(for: project), id: \.self) { key in
                            TerminalArea(
                                project: project,
                                worktreeKey: key,
                                isActiveProject: key == activeKey
                            )
                            .opacity(key == activeKey ? 1 : 0)
                            .allowsHitTesting(key == activeKey)
                            .zIndex(key == activeKey ? 1 : 0)
                        }
                    }
                }

                if vcsPanelVisible, VCSDisplayMode.current == .attached, let state = activeVCSState {
                    HStack(spacing: 0) {
                        sidePanelResizeHandle { delta in
                            vcsPanelWidth = max(
                                AttachedVCSLayout.minWidth,
                                min(AttachedVCSLayout.maxWidth, vcsPanelWidth - delta)
                            )
                        }
                        VCSTabView(state: state, focused: false, onFocus: {})
                            .frame(width: vcsPanelWidth)
                    }
                } else if fileTreePanelVisible, let treeState = activeFileTreeState {
                    HStack(spacing: 0) {
                        sidePanelResizeHandle { delta in
                            let next = fileTreePanelWidth - Double(delta)
                            fileTreePanelWidth = max(
                                Double(FileTreeLayout.minWidth),
                                min(Double(FileTreeLayout.maxWidth), next)
                            )
                        }
                        FileTreeView(
                            state: treeState,
                            onOpenFile: { filePath in
                                guard let projectID = appState.activeProjectID else { return }
                                appState.openFile(filePath, projectID: projectID)
                            },
                            onOpenTerminal: { directory in
                                guard let projectID = appState.activeProjectID else { return }
                                appState.dispatch(.createTabInDirectory(
                                    projectID: projectID,
                                    areaID: nil,
                                    directory: directory
                                ))
                            },
                            onFileMoved: { oldPath, newPath in
                                appState.handleFileMoved(from: oldPath, to: newPath)
                            }
                        )
                        .id(treeState.rootPath)
                        .frame(width: CGFloat(fileTreePanelWidth))
                    }
                }
            }
        }
        .environment(
            \.overlayActive,
            showQuickOpen || showWorktreeSwitcher || showCommandPalette
                || showProjectSearch || showShortcutCheatSheet || showAgentInbox
                || showScrollbackHistory || scrollbackCheckpointPrompt != nil
                || workflowSavePrompt != nil
        )
        .overlay(alignment: toastAlignment) {
            if let toast = ToastState.shared.message {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.diffAddFg)
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuxyTheme.fg)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(MuxyTheme.bg, in: Capsule())
                .overlay(Capsule().stroke(MuxyTheme.border, lineWidth: 1))
                .padding(toastEdgePadding)
                .transition(.move(edge: toastTransitionEdge).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityLabel(toast)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .overlay {
            if showQuickOpen, let project = activeProject {
                QuickOpenOverlay(
                    projectPath: activeWorktreePath(for: project),
                    onSelect: { filePath in
                        showQuickOpen = false
                        appState.openFile(filePath, projectID: project.id)
                    },
                    onDismiss: { showQuickOpen = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay {
            if showWorktreeSwitcher {
                WorktreeSwitcherOverlay(
                    items: worktreeSwitcherItems,
                    activeKey: activeWorktreeKey,
                    onSelect: { item in
                        showWorktreeSwitcher = false
                        guard let project = projectStore.projects.first(where: { $0.id == item.projectID }) else { return }
                        if appState.activeProjectID == item.projectID {
                            appState.selectWorktree(projectID: item.projectID, worktree: item.worktree)
                        } else {
                            appState.selectProject(project, worktree: item.worktree)
                        }
                    },
                    onDismiss: { showWorktreeSwitcher = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .modifier(MainWindowExtraOverlays(
            showCommandPalette: $showCommandPalette,
            showProjectSearch: $showProjectSearch,
            showShortcutCheatSheet: $showShortcutCheatSheet,
            showAgentInbox: $showAgentInbox,
            showScrollbackHistory: $showScrollbackHistory,
            scrollbackCheckpointPrompt: $scrollbackCheckpointPrompt,
            workflowSavePrompt: $workflowSavePrompt,
            showConnectPeer: $showConnectPeer,
            showDiagnostics: $showDiagnostics,
            activeProject: activeProject,
            activeWorktreePath: activeProject.map { activeWorktreePath(for: $0) } ?? "",
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            appState: appState,
            onAgentInboxSelect: { session in
                AIAgentSessionStore.shared.navigate(to: session, appState: appState)
            },
            onScrollbackSelect: { checkpoint in
                handleScrollbackCheckpointSelect(checkpoint)
            },
            onScrollbackExportBetween: { a, b in
                handleScrollbackExport(a, b)
            },
            onScrollbackPromptSubmit: { state, label in
                _ = TerminalScrollbackStore.shared.addCheckpoint(
                    paneID: state.paneID,
                    label: label,
                    projectID: state.projectID
                )
                ToastState.shared.show("Checkpointed")
            },
            resolveFocusedPane: { resolveFocusedPaneForCheckpoint() },
            buildPalette: buildCommandPalette,
            openFile: { path, projectID, needle in
                appState.openFile(path, projectID: projectID, initialSearchNeedle: needle)
            },
            onPaletteWillOpen: {
                Task { paletteThemes = await ThemeService.shared.loadThemes() }
            },
            onSaveWorkflow: { name, draft in
                let macro = WorkflowMacro(
                    id: draft.id,
                    name: name,
                    symbol: draft.symbol,
                    steps: draft.steps,
                    createdAt: draft.createdAt,
                    updatedAt: Date()
                )
                WorkflowMacroStore.shared.save(macro)
                ToastState.shared.show("Saved workflow \"\(name)\"")
            }
        ))
        .animation(.easeInOut(duration: 0.15), value: showQuickOpen)
        .animation(.easeInOut(duration: 0.15), value: showWorktreeSwitcher)
        .animation(.easeInOut(duration: 0.2), value: ToastState.shared.message != nil)
        .coordinateSpace(name: DragCoordinateSpace.mainWindow)
        .environment(dragCoordinator)
        .background(MainWindowShortcutInterceptor(
            onShortcut: { action in handleShortcutAction(action) },
            onMouseBack: { appState.goBack() },
            onMouseForward: { appState.goForward() }
        ))
        .background(WindowConfigurator(configVersion: ghostty.configVersion))
        .background(WindowTitleUpdater(title: windowTitle))
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
            showQuickOpen.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchWorktree)) { _ in
            showWorktreeSwitcher.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarExpanded.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowFullScreenDidChange)) { notification in
            isFullScreen = notification.userInfo?["isFullScreen"] as? Bool ?? false
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVCSWindow)) { _ in
            openWindow(id: "vcs")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAttachedVCS)) { _ in
            toggleAttachedVCSPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFileTree)) { _ in
            toggleFileTreePanel()
        }
        .onChange(of: vcsPruneSignature) {
            pruneVCSStates()
            pruneFileTreeStates()
        }
        .onChange(of: vcsEnsureSignature) {
            guard let project = activeProject else { return }
            if vcsPanelVisible, VCSDisplayMode.current == .attached {
                ensureVCSState(for: project)
            }
            if fileTreePanelVisible {
                ensureFileTreeState(for: project)
            }
        }
        .modifier(FileTreeSelectionSync(
            filePath: activeEditorFilePath,
            panelVisible: fileTreePanelVisible,
            sync: syncFileTreeSelection
        ))
        .onChange(of: appState.pendingLastTabClose != nil) { _, isPresented in
            guard isPresented else { return }
            presentCloseConfirmation(.lastTab)
        }
        .onChange(of: appState.pendingUnsavedEditorTabClose != nil) { _, isPresented in
            guard isPresented else { return }
            presentCloseConfirmation(.unsavedEditor)
        }
        .onChange(of: appState.pendingProcessTabClose != nil) { _, isPresented in
            guard isPresented else { return }
            presentCloseConfirmation(.runningProcess)
        }
        .onChange(of: appState.pendingSaveErrorMessage != nil) { _, isPresented in
            guard isPresented, let message = appState.pendingSaveErrorMessage else { return }
            presentSaveErrorAlert(message: message)
        }
    }

    private var navigationArrows: some View {
        HStack(spacing: 2) {
            NavigationArrowButton(
                symbol: "chevron.left",
                isEnabled: appState.navigation.canGoBack,
                label: "Back (\(KeyBindingStore.shared.combo(for: .navigateBack).displayString))"
            ) {
                appState.goBack()
            }
            NavigationArrowButton(
                symbol: "chevron.right",
                isEnabled: appState.navigation.canGoForward,
                label: "Forward (\(KeyBindingStore.shared.combo(for: .navigateForward).displayString))"
            ) {
                appState.goForward()
            }
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private var topBarContent: some View {
        if let project = activeProject,
           let root = appState.workspaceRoot(for: project.id),
           case let .tabArea(area) = root
        {
            PaneTabStrip(
                areaID: area.id,
                tabs: PaneTabStrip.snapshots(from: area.tabs),
                activeTabID: area.activeTabID,
                isFocused: true,
                isWindowTitleBar: true,
                showVCSButton: true,
                showDevelopmentBadge: AppEnvironment.isDevelopment,
                projectID: project.id,
                onSelectTab: { tabID in
                    appState.dispatch(.selectTab(projectID: project.id, areaID: area.id, tabID: tabID))
                },
                onCreateTab: {
                    appState.dispatch(.createTab(projectID: project.id, areaID: area.id))
                },
                onCreateVCSTab: {
                    openVCS(for: project, preferredAreaID: area.id)
                },
                onCloseTab: { tabID in
                    appState.closeTab(tabID, areaID: area.id, projectID: project.id)
                },
                onSplit: { dir in
                    appState.dispatch(.splitArea(.init(
                        projectID: project.id,
                        areaID: area.id,
                        direction: dir,
                        position: .second
                    )))
                },
                onDropAction: { result in
                    appState.dispatch(result.action(projectID: project.id))
                },
                onCreateTabAdjacent: { tabID, side in
                    area.createTabAdjacent(to: tabID, side: side)
                },
                onTogglePin: { tabID in
                    area.togglePin(tabID)
                },
                onSetCustomTitle: { tabID, title in
                    area.setCustomTitle(tabID, title: title)
                    appState.saveWorkspaces()
                },
                onSetColorID: { tabID, colorID in
                    area.setColorID(tabID, colorID: colorID)
                    appState.saveWorkspaces()
                },
                onReorderTab: { fromOffsets, toOffset in
                    area.reorderTab(fromOffsets: fromOffsets, toOffset: toOffset)
                }
            )
        } else {
            WindowDragRepresentable(alwaysEnabled: true)
                .overlay {
                    HStack {
                        if let project = activeProject {
                            Text(project.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MuxyTheme.fgMuted)
                                .padding(.leading, 12)
                        }
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        if AppEnvironment.isDevelopment {
                            devModeBadge
                                .padding(.trailing, 6)
                        }
                        if let version = UpdateService.shared.availableUpdateVersion {
                            UpdateBadge(version: version) {
                                UpdateService.shared.checkForUpdates()
                            }
                            .padding(.trailing, 4)
                        }
                        if let project = activeProject, activeProjectHasSplitWorkspace {
                            IconButton(symbol: "doc.text", size: 12, accessibilityLabel: "Quick Open") {
                                NotificationCenter.default.post(name: .quickOpen, object: nil)
                            }
                            .help("Quick Open (\(KeyBindingStore.shared.combo(for: .quickOpen).displayString))")
                            FileDiffIconButton {
                                openVCS(for: project)
                            }
                            FileTreeIconButton {
                                NotificationCenter.default.post(name: .toggleFileTree, object: nil)
                            }
                            .help("File Tree (\(KeyBindingStore.shared.combo(for: .toggleFileTree).displayString))")
                        }
                    }
                    .padding(.trailing, 4)
                }
        }
    }

    private var worktreeSwitcherItems: [WorktreeSwitcherItem] {
        projectStore.projects.flatMap { project in
            worktreeStore.list(for: project.id).map { worktree in
                WorktreeSwitcherItem(
                    projectID: project.id,
                    projectName: project.name,
                    worktree: worktree
                )
            }
        }
    }

    private var toastPosition: ToastPosition {
        ToastPosition(rawValue: toastPositionRaw) ?? .topCenter
    }

    private var toastAlignment: Alignment {
        switch toastPosition {
        case .topCenter: .top
        case .topRight: .topTrailing
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }

    private var toastEdgePadding: EdgeInsets {
        switch toastPosition {
        case .topCenter: EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0)
        case .topRight: EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 16)
        case .bottomCenter: EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        case .bottomRight: EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16)
        }
    }

    private var toastTransitionEdge: Edge {
        switch toastPosition {
        case .topCenter,
             .topRight: .top
        case .bottomCenter,
             .bottomRight: .bottom
        }
    }

    private var topBarLeadingWidth: CGFloat {
        let sidebarWidth = SidebarLayout.resolvedWidth(expanded: sidebarExpanded) + 1
        return max(trafficLightWidth, sidebarWidth)
    }

    private var devModeBadge: some View {
        DevelopmentBadge()
    }

    private var activeWorktreeKey: WorktreeKey? {
        guard let projectID = appState.activeProjectID,
              let worktreeID = appState.activeWorktreeID[projectID]
        else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    private var activeProject: Project? {
        guard let pid = appState.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == pid }
    }

    private var windowTitle: String {
        guard let project = activeProject else { return "Muxy" }
        guard let tabTitle = appState.activeTab(for: project.id)?.title,
              !tabTitle.isEmpty
        else { return project.name }
        return "\(project.name) — \(tabTitle)"
    }

    private var activeProjectWithWorkspace: Project? {
        guard let project = activeProject,
              appState.workspaceRoot(for: project.id) != nil
        else { return nil }
        return project
    }

    private func resolvedActiveWorktree(for project: Project) -> Worktree? {
        worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])
    }

    private var shortcutDispatcher: ShortcutActionDispatcher {
        ShortcutActionDispatcher(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            ghostty: ghostty
        )
    }

    private func mountedWorktreeKeys(for project: Project) -> [WorktreeKey] {
        appState.workspaceRoots.keys
            .filter { $0.projectID == project.id }
            .sorted { $0.worktreeID.uuidString < $1.worktreeID.uuidString }
    }

    private func buildCommandPalette() -> CommandPalette {
        let sources: [PaletteCommandSource] = [
            ShortcutCommandSource(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                ghostty: ghostty,
                keyBindings: .shared,
                openVCS: { project in openVCS(for: project) }
            ),
            NavigationCommandSource(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            ),
            ThemeCommandSource(themes: paletteThemes, themeService: .shared),
            AICommandSource(usage: .shared),
            FileContextCommandSource(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            ),
            VCSCommandSource(resolveActiveVCS: {
                let vcs = activeVCSState
                vcs?.loadStashes()
                return vcs
            }),
            AgentWorkbenchCommandSource(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            ),
            AgentInboxCommandSource(
                appState: appState,
                projectStore: projectStore,
                agentStore: .shared,
                notificationCenter: .default
            ),
            ScrollbackCommandSource(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                store: .shared,
                notificationCenter: .default
            ),
            WorkspaceTemplateCommandSource(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                templateStore: .shared
            ),
            TestRunnerCommandSource(
                appState: appState,
                projectStore: projectStore
            ),
            AgentCanvasCommandSource(
                appState: appState
            ),
            GitLogCommandSource(
                appState: appState
            ),
            PeerConnectionCommandSource(
                notificationCenter: .default
            ),
            PluginCommandSource(
                host: .shared
            ),
            DiagnosticsCommandSource(
                appState: appState,
                projectStore: projectStore,
                notificationCenter: .default
            ),
            WorkflowMacroCommandSource(
                appState: appState,
                macroStore: .shared,
                recorder: .shared,
                notificationCenter: .default,
                paletteProvider: { [self] in buildCommandPalette() }
            ),
            SettingsCommandSource(),
        ]
        return CommandPalette(sources: sources)
    }

    private func handleShortcutAction(_ action: ShortcutAction) -> Bool {
        shortcutDispatcher.perform(action, activeProject: activeProject) { project in
            openVCS(for: project)
        }
    }

    private func resolveFocusedPaneForCheckpoint() -> ScrollbackCheckpointPromptState? {
        guard let projectID = appState.activeProjectID,
              let area = appState.focusedArea(for: projectID),
              let tab = area.activeTab,
              let paneID = tab.content.pane?.id
        else { return nil }
        return ScrollbackCheckpointPromptState(paneID: paneID, projectID: projectID)
    }

    private func handleScrollbackCheckpointSelect(_ checkpoint: TerminalScrollbackCheckpoint) {
        showScrollbackHistory = false
        guard let ctx = NotificationNavigator.resolveContext(
            for: checkpoint.paneID,
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
        ToastState.shared.show("Jumped to \"\(checkpoint.label)\"")
    }

    private func handleScrollbackExport(
        _ a: TerminalScrollbackCheckpoint,
        _ b: TerminalScrollbackCheckpoint
    ) {
        let (earlier, later) = a.seq < b.seq ? (a, b) : (b, a)
        guard let data = TerminalScrollbackStore.shared.bytesBetween(earlier, later) else {
            ToastState.shared.show("Not enough buffered data — try smaller range")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(earlier.label) \u{2192} \(later.label).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
            ToastState.shared.show("Exported \(data.count) bytes")
        }
    }

    private var activeProjectHasSplitWorkspace: Bool {
        guard let project = activeProject,
              let root = appState.workspaceRoot(for: project.id)
        else { return false }
        if case .split = root { return true }
        return false
    }

    private var projectsWithWorkspaces: [Project] {
        projectStore.projects.filter { appState.workspaceRoot(for: $0.id) != nil }
    }

    private func sidePanelResizeHandle(onDrag: @escaping (CGFloat) -> Void) -> some View {
        Rectangle().fill(MuxyTheme.border).frame(width: 1)
            .accessibilityHidden(true)
            .overlay {
                Color.clear
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in onDrag(v.translation.width) }
                    )
                    .onHover { on in
                        if on { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }
    }

    private var activeFileTreeState: FileTreeState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return fileTreeStates[key]
    }

    private func ensureFileTreeState(for project: Project) {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return }
        let path = activeWorktreePath(for: project)
        if let existing = fileTreeStates[key], existing.rootPath == path { return }
        fileTreeStates[key] = FileTreeState(rootPath: path)
    }

    private var activeEditorFilePath: String? {
        guard let project = activeProject else { return nil }
        return appState.activeTab(for: project.id)?.content.editorState?.filePath
    }

    private func syncFileTreeSelection(filePath: String?) {
        guard fileTreePanelVisible,
              let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id),
              let state = fileTreeStates[key]
        else { return }
        if let filePath {
            state.revealFile(at: filePath)
        } else {
            state.clearSelection()
        }
    }

    private func pruneFileTreeStates() {
        let validKeys = validVCSKeys()
        fileTreeStates = fileTreeStates.filter { validKeys.contains($0.key) }
    }

    private func toggleAttachedVCSPanel() {
        guard VCSDisplayMode.current == .attached,
              let project = activeProject
        else {
            vcsPanelVisible = false
            return
        }

        ensureVCSState(for: project)
        let isShowing = !vcsPanelVisible
        vcsPanelVisible = isShowing
        if isShowing {
            fileTreePanelVisible = false
        }
    }

    private func toggleFileTreePanel() {
        guard let project = activeProject else {
            fileTreePanelVisible = false
            return
        }

        ensureFileTreeState(for: project)
        let isShowing = !fileTreePanelVisible
        fileTreePanelVisible = isShowing
        if isShowing {
            vcsPanelVisible = false
        }
    }

    private var activeVCSState: VCSTabState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return vcsStates[key]
    }

    private func ensureVCSState(for project: Project) {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return }
        guard vcsStates[key] == nil else { return }
        vcsStates[key] = VCSTabState(projectPath: activeWorktreePath(for: project))
    }

    private func activeWorktreePath(for project: Project) -> String {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return project.path }
        return worktreeStore
            .worktree(projectID: project.id, worktreeID: key.worktreeID)?
            .path ?? project.path
    }

    private func openVCS(for project: Project, preferredAreaID: UUID? = nil) {
        VCSDisplayMode.current.route(
            tab: {
                let areaID = preferredAreaID
                    ?? appState.focusedAreaID(for: project.id)
                    ?? appState.workspaceRoot(for: project.id)?.allAreas().first?.id
                guard let areaID else { return }
                appState.dispatch(.createVCSTab(projectID: project.id, areaID: areaID))
            },
            window: { openWindow(id: "vcs") },
            attached: {
                toggleAttachedVCSPanel()
            }
        )
    }

    private func pruneVCSStates() {
        let validKeys = validVCSKeys()
        vcsStates = vcsStates.filter { validKeys.contains($0.key) }
    }

    private func validVCSKeys() -> Set<WorktreeKey> {
        var keys: Set<WorktreeKey> = []
        for project in projectStore.projects {
            for worktree in worktreeStore.list(for: project.id) {
                keys.insert(WorktreeKey(projectID: project.id, worktreeID: worktree.id))
            }
        }
        return keys
    }

    private var vcsPruneSignature: [String] {
        var result: [String] = []
        for project in projectStore.projects {
            result.append(project.id.uuidString)
            for worktree in worktreeStore.list(for: project.id) {
                result.append(worktree.id.uuidString)
            }
        }
        return result
    }

    private var vcsEnsureSignature: String {
        let projectID = appState.activeProjectID?.uuidString ?? ""
        let worktreeID = appState.activeProjectID.flatMap { appState.activeWorktreeID[$0] }?.uuidString ?? ""
        return "\(projectID):\(worktreeID)"
    }

    private func presentCloseConfirmation(_ kind: CloseConfirmationKind) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = kind.title
        alert.informativeText = kind.message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage

        switch kind {
        case .unsavedEditor:
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Don't Save")
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}"
            alert.buttons[2].keyEquivalent = "d"
            alert.buttons[2].keyEquivalentModifierMask = [.command]
        case .lastTab,
             .runningProcess:
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}"
        }

        if kind == .runningProcess {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
        }

        alert.beginSheetModal(for: window) { response in
            switch kind {
            case .lastTab:
                if response == .alertFirstButtonReturn {
                    appState.confirmCloseLastTab()
                } else {
                    appState.cancelCloseLastTab()
                }
            case .unsavedEditor:
                switch response {
                case .alertFirstButtonReturn:
                    appState.saveAndCloseUnsavedEditorTab()
                case .alertThirdButtonReturn:
                    appState.confirmCloseUnsavedEditorTab()
                default:
                    appState.cancelCloseUnsavedEditorTab()
                }
            case .runningProcess:
                if response == .alertFirstButtonReturn {
                    if alert.suppressionButton?.state == .on {
                        TabCloseConfirmationPreferences.confirmRunningProcess = false
                    }
                    appState.confirmCloseRunningTab()
                } else {
                    appState.cancelCloseRunningTab()
                }
            }
        }
    }

    private func presentSaveErrorAlert(message: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else {
            appState.pendingSaveErrorMessage = nil
            return
        }

        let alert = NSAlert()
        alert.messageText = "Could Not Save File"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"

        alert.beginSheetModal(for: window) { _ in
            appState.pendingSaveErrorMessage = nil
        }
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window, window.title != title else { return }
        window.title = title
    }
}

private struct FileTreeSelectionSync: ViewModifier {
    let filePath: String?
    let panelVisible: Bool
    let sync: (String?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: filePath) { _, newValue in
                sync(newValue)
            }
            .onChange(of: panelVisible) { _, visible in
                guard visible else { return }
                sync(filePath)
            }
    }
}

private struct NavigationArrowButton: View {
    let symbol: String
    let isEnabled: Bool
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return MuxyTheme.fgMuted.opacity(0.35) }
        return hovered ? MuxyTheme.fg : MuxyTheme.fgMuted
    }
}

private struct MainWindowShortcutInterceptor: NSViewRepresentable {
    let onShortcut: (ShortcutAction) -> Bool
    let onMouseBack: () -> Void
    let onMouseForward: () -> Void

    func makeNSView(context: Context) -> ShortcutInterceptingView {
        let view = ShortcutInterceptingView()
        view.onShortcut = onShortcut
        view.onMouseBack = onMouseBack
        view.onMouseForward = onMouseForward
        return view
    }

    func updateNSView(_ nsView: ShortcutInterceptingView, context: Context) {
        nsView.onShortcut = onShortcut
        nsView.onMouseBack = onMouseBack
        nsView.onMouseForward = onMouseForward
    }
}

private final class ShortcutInterceptingView: NSView {
    var onShortcut: ((ShortcutAction) -> Bool)?
    var onMouseBack: (() -> Void)?
    var onMouseForward: (() -> Void)?
    private var mouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitorIfNeeded()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              ShortcutContext.isMainWindow(window)
        else { return super.performKeyEquivalent(with: event) }

        let scopes = ShortcutContext.activeScopes(for: window)
        guard let action = KeyBindingStore.shared.action(for: event, scopes: scopes) else {
            return super.performKeyEquivalent(with: event)
        }

        if onShortcut?(action) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isKeyWindow,
                  ShortcutContext.isMainWindow(window)
            else { return event }
            return self.handleNavigationEvent(event)
        }
    }

    private func handleNavigationEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .otherMouseDown:
            switch event.buttonNumber {
            case 3:
                onMouseBack?()
                return nil
            case 4:
                onMouseForward?()
                return nil
            default:
                return event
            }
        case .swipe:
            if event.deltaX > 0 {
                onMouseBack?()
                return nil
            }
            if event.deltaX < 0 {
                onMouseForward?()
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func removeMouseMonitor() {
        guard let mouseMonitor else { return }
        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }
}

private struct MainWindowExtraOverlays: ViewModifier {
    @Binding var showCommandPalette: Bool
    @Binding var showProjectSearch: Bool
    @Binding var showShortcutCheatSheet: Bool
    @Binding var showAgentInbox: Bool
    @Binding var showScrollbackHistory: Bool
    @Binding var scrollbackCheckpointPrompt: ScrollbackCheckpointPromptState?
    @Binding var workflowSavePrompt: WorkflowSavePromptState?
    @Binding var showConnectPeer: Bool
    @Binding var showDiagnostics: Bool
    let activeProject: Project?
    let activeWorktreePath: String
    let projectStore: ProjectStore
    let worktreeStore: WorktreeStore
    let appState: AppState
    let onAgentInboxSelect: (AIAgentSession) -> Void
    let onScrollbackSelect: (TerminalScrollbackCheckpoint) -> Void
    let onScrollbackExportBetween: (TerminalScrollbackCheckpoint, TerminalScrollbackCheckpoint) -> Void
    let onScrollbackPromptSubmit: (ScrollbackCheckpointPromptState, String) -> Void
    let resolveFocusedPane: () -> ScrollbackCheckpointPromptState?
    let buildPalette: () -> CommandPalette
    let openFile: (String, UUID, String?) -> Void
    let onPaletteWillOpen: () -> Void
    let onSaveWorkflow: (String, WorkflowMacro) -> Void

    func body(content: Content) -> some View {
        applyScrollbackHooks(
            applyAnimations(
                applyNotifications(
                    applyOverlays(content)
                )
            )
        )
    }

    private func applyOverlays(_ view: some View) -> some View {
        view
            .overlay { commandPaletteOverlay }
            .overlay { projectSearchOverlay }
            .overlay { cheatSheetOverlay }
            .overlay { agentInboxOverlay }
            .overlay { scrollbackHistoryOverlay }
            .overlay { scrollbackPromptOverlay }
            .overlay { workflowSavePromptOverlay }
            .overlay(alignment: .top) { workflowRecordingBannerOverlay }
    }

    private func applyAnimations(_ view: some View) -> some View {
        view
            .animation(.easeInOut(duration: 0.15), value: showCommandPalette)
            .animation(.easeInOut(duration: 0.15), value: showProjectSearch)
            .animation(.easeInOut(duration: 0.15), value: showShortcutCheatSheet)
            .animation(.easeInOut(duration: 0.15), value: showAgentInbox)
            .animation(.easeInOut(duration: 0.15), value: showScrollbackHistory)
            .animation(.easeInOut(duration: 0.15), value: scrollbackCheckpointPrompt != nil)
            .animation(.easeInOut(duration: 0.15), value: workflowSavePrompt != nil)
            .animation(.easeInOut(duration: 0.2), value: WorkflowRecorder.shared.isRecording)
    }

    private func applyNotifications(_ view: some View) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .toggleCommandPalette)) { _ in
                showCommandPalette.toggle()
                if showCommandPalette {
                    onPaletteWillOpen()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .projectSearch)) { _ in
                showProjectSearch.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showShortcutCheatSheet)) { _ in
                showShortcutCheatSheet.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showAgentInbox)) { _ in
                showAgentInbox.toggle()
            }
    }

    private func applyScrollbackHooks(_ view: some View) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .showScrollbackHistory)) { _ in
                showScrollbackHistory.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .addScrollbackCheckpoint)) { _ in
                guard let state = resolveFocusedPane() else {
                    ToastState.shared.show("No active pane to checkpoint")
                    return
                }
                scrollbackCheckpointPrompt = state
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleWorkflowRecording)) { _ in
                handleToggleWorkflowRecording()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showConnectPeer)) { _ in
                showConnectPeer.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showDiagnostics)) { _ in
                showDiagnostics.toggle()
            }
            .overlay { connectPeerOverlay }
            .overlay { diagnosticsOverlayView }
            .animation(.easeInOut(duration: 0.15), value: showConnectPeer)
            .animation(.easeInOut(duration: 0.15), value: showDiagnostics)
    }

    @ViewBuilder
    private var connectPeerOverlay: some View {
        if showConnectPeer {
            ConnectPeerOverlay(onDismiss: { showConnectPeer = false })
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var diagnosticsOverlayView: some View {
        if showDiagnostics {
            DiagnosticsOverlay(onDismiss: { showDiagnostics = false })
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func handleToggleWorkflowRecording() {
        if WorkflowRecorder.shared.isRecording {
            if let draft = WorkflowRecorder.shared.stop() {
                workflowSavePrompt = WorkflowSavePromptState(draft: draft)
            } else {
                ToastState.shared.show("Recorded 0 steps — discarded")
            }
            return
        }
        WorkflowRecorder.shared.start()
        ToastState.shared.show("Recording started — pick commands from the palette")
    }

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if showCommandPalette {
            CommandPaletteOverlay(
                palette: buildPalette(),
                onSelect: { command in
                    showCommandPalette = false
                    PaletteRecentsStore.shared.bump(command.id)
                    WorkflowRecorder.shared.recordStep(commandID: command.id)
                    command.run()
                },
                onDismiss: { showCommandPalette = false }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var projectSearchOverlay: some View {
        if showProjectSearch, let project = activeProject {
            ProjectSearchOverlay(
                projectPath: activeWorktreePath,
                onSelect: { result, query in
                    showProjectSearch = false
                    let trimmed = query.trimmingCharacters(in: .whitespaces)
                    openFile(result.absolutePath, project.id, trimmed.isEmpty ? nil : trimmed)
                },
                onReplaceAll: { query, replacement, results in
                    Task {
                        let outcome = await ProjectReplaceService.replace(
                            query: query,
                            replacement: replacement,
                            in: results
                        )
                        await MainActor.run {
                            showProjectSearch = false
                            let filesWord = outcome.filesChanged == 1 ? "file" : "files"
                            let message = "Replaced \(outcome.occurrencesReplaced) in \(outcome.filesChanged) \(filesWord)"
                            ToastState.shared.show(message)
                        }
                    }
                },
                onDismiss: { showProjectSearch = false }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var cheatSheetOverlay: some View {
        if showShortcutCheatSheet {
            ShortcutCheatSheetOverlay(
                keyBindings: .shared,
                onDismiss: { showShortcutCheatSheet = false }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var agentInboxOverlay: some View {
        if showAgentInbox {
            AgentInboxOverlay(
                store: .shared,
                projectStore: projectStore,
                onSelect: { session in
                    showAgentInbox = false
                    onAgentInboxSelect(session)
                },
                onClear: { session in
                    AIAgentSessionStore.shared.remove(id: session.id)
                },
                onDismiss: { showAgentInbox = false }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var scrollbackHistoryOverlay: some View {
        if showScrollbackHistory {
            ScrollbackHistoryOverlay(
                store: .shared,
                projectStore: projectStore,
                appState: appState,
                onSelect: { checkpoint in
                    onScrollbackSelect(checkpoint)
                },
                onExportBetween: { a, b in
                    onScrollbackExportBetween(a, b)
                },
                onDelete: { checkpoint in
                    TerminalScrollbackStore.shared.removeCheckpoint(id: checkpoint.id)
                },
                onDismiss: { showScrollbackHistory = false }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var scrollbackPromptOverlay: some View {
        if let prompt = scrollbackCheckpointPrompt {
            ScrollbackCheckpointPrompt(
                prompt: prompt,
                onSubmit: { label in
                    onScrollbackPromptSubmit(prompt, label)
                },
                onDismiss: { scrollbackCheckpointPrompt = nil }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var workflowSavePromptOverlay: some View {
        if let prompt = workflowSavePrompt {
            WorkflowSavePrompt(
                prompt: prompt,
                onSave: { name in
                    onSaveWorkflow(name, prompt.draft)
                    workflowSavePrompt = nil
                },
                onDiscard: { workflowSavePrompt = nil }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var workflowRecordingBannerOverlay: some View {
        if WorkflowRecorder.shared.isRecording {
            WorkflowRecordingBanner(
                stepCount: WorkflowRecorder.shared.stepCount,
                onStop: {
                    NotificationCenter.default.post(name: .toggleWorkflowRecording, object: nil)
                }
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
