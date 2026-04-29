import SwiftUI

struct TerminalArea: View {
    let project: Project
    let worktreeKey: WorktreeKey
    let isActiveProject: Bool
    @Environment(AppState.self) private var appState
    @Environment(TabDragCoordinator.self) private var dragCoordinator
    @Environment(\.openWindow) private var openWindow

    private var root: SplitNode? {
        appState.workspaceRoots[worktreeKey]
    }

    private var focusedAreaID: UUID? {
        appState.focusedAreaID[worktreeKey]
    }

    private var rootIsTabArea: Bool {
        guard let root else { return false }
        if case .tabArea = root { return true }
        return false
    }

    private var zoomedNode: SplitNode? {
        guard let root,
              let zoomedID = appState.zoomedAreaID[worktreeKey],
              let area = root.findArea(id: zoomedID)
        else { return nil }
        return .tabArea(area)
    }

    var body: some View {
        if let root {
            let renderedRoot = zoomedNode ?? root
            let renderedIsTabArea: Bool = {
                if case .tabArea = renderedRoot { return true }
                return false
            }()
            let isZoomed = zoomedNode != nil
            PaneNode(
                node: renderedRoot,
                focusedAreaID: focusedAreaID,
                isActiveProject: isActiveProject,
                showTabStrip: !renderedIsTabArea,
                showVCSButton: false,
                projectID: project.id,
                onFocusArea: { areaID in
                    appState.dispatch(.focusArea(projectID: project.id, areaID: areaID))
                },
                onSelectTab: { areaID, tabID in
                    appState.dispatch(.selectTab(projectID: project.id, areaID: areaID, tabID: tabID))
                },
                onCreateTab: { areaID in
                    appState.dispatch(.createTab(projectID: project.id, areaID: areaID))
                },
                onCreateVCSTab: { areaID in
                    VCSDisplayMode.current.route(
                        tab: { appState.dispatch(.createVCSTab(projectID: project.id, areaID: areaID)) },
                        window: { openWindow(id: "vcs") },
                        attached: { NotificationCenter.default.post(name: .toggleAttachedVCS, object: nil) }
                    )
                },
                onCloseTab: { areaID, tabID in
                    appState.closeTab(tabID, areaID: areaID, projectID: project.id)
                },
                onForceCloseTab: { areaID, tabID in
                    appState.forceCloseTab(tabID, areaID: areaID, projectID: project.id)
                },
                onSplit: { areaID, dir in
                    appState.dispatch(.splitArea(.init(
                        projectID: project.id,
                        areaID: areaID,
                        direction: dir,
                        position: .second
                    )))
                },
                onCloseArea: { areaID in
                    appState.dispatch(.closeArea(projectID: project.id, areaID: areaID))
                },
                onDropAction: { result in
                    appState.dispatch(result.action(projectID: project.id))
                }
            )
            .environment(\.activeWorktreeKey, worktreeKey)
            .onPreferenceChange(AreaFramePreferenceKey.self) { frames in
                guard isActiveProject, dragCoordinator.activeDrag != nil else { return }
                dragCoordinator.setAreaFrames(frames, forProject: project.id)
            }
            .overlay(alignment: .topTrailing) {
                if isZoomed {
                    ZoomedPaneBadge {
                        appState.toggleZoomedArea(projectID: project.id)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                }
            }
        }
    }
}

private struct ZoomedPaneBadge: View {
    let onExit: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onExit) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Zoomed")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(hovered ? MuxyTheme.fg : MuxyTheme.fgMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MuxyTheme.bg, in: Capsule())
            .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("Exit zoomed pane")
        .help("Exit zoom (⌘⇧Z)")
    }
}
