import AppKit
import SwiftUI

struct AgentCanvasTabView: View {
    let state: AgentCanvasState
    let focused: Bool
    let onFocus: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @State private var selectedNodeID: UUID?
    @State private var pendingWireSource: UUID?
    @State private var pendingWireKind: AgentCanvasWireKind = .promptRelay
    @State private var fileWatchPrompt: FileWatchWirePromptState?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(MuxyTheme.border)
            if state.nodes.isEmpty {
                emptyState
            } else {
                canvas
            }
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .onTapGesture {
            onFocus()
            pendingWireSource = nil
        }
        .overlay {
            if let prompt = fileWatchPrompt {
                FileWatchWirePrompt(
                    prompt: prompt,
                    onSubmit: { command, glob in
                        commitFileWatchWire(prompt: prompt, command: command, glob: glob)
                        fileWatchPrompt = nil
                    },
                    onDismiss: { fileWatchPrompt = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: fileWatchPrompt != nil)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.accent)
            Text(state.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("\(state.nodes.count) nodes \u{00B7} \(state.wires.count) wires")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgMuted)
            Spacer()
            Menu {
                ForEach(availablePanes, id: \.tab.id) { entry in
                    Button(entry.label) {
                        add(entry: entry)
                    }
                }
                if availablePanes.isEmpty {
                    Text("No terminal panes in this project")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.square.on.square").font(.system(size: 11, weight: .semibold))
                    Text("Add pane").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MuxyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(MuxyTheme.border, lineWidth: 0.5))
                .foregroundStyle(MuxyTheme.fg)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            Menu {
                Button("Prompt Relay") { pendingWireKind = .promptRelay }
                Button("Keystroke Broadcast") { pendingWireKind = .keystrokeBroadcast }
                Button("Mirror (gated on fork)") { pendingWireKind = .mirror }.disabled(true)
                Button("File Watch") { pendingWireKind = .fileWatch }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                    Text("Wire kind: \(wireLabel(pendingWireKind))").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MuxyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(MuxyTheme.border, lineWidth: 0.5))
                .foregroundStyle(MuxyTheme.fg)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(state.nodes.count < 2)
            toolbarButton(symbol: "bolt.slash", label: "Stop all wires") {
                PaneWireBus.shared.deactivateAll(canvasID: state.id)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolbarButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MuxyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(MuxyTheme.border, lineWidth: 0.5))
            .foregroundStyle(MuxyTheme.fg)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 34))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("Nothing wired yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("Focus a terminal pane, then hit \u{201C}Add current pane\u{201D} to place it on the canvas.")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text(verbatim:
                "Emit <muxy:ask target=\"droidx\">your prompt</muxy:ask>"
                + "  \u{2014}  source pane emits this to talk to the wired target."
            )
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                wireLayer(in: geo.size)
                ForEach(state.nodes, id: \.id) { node in
                    card(for: node)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func wireLayer(in size: CGSize) -> some View {
        ZStack {
            Canvas { context, _ in
                for wire in state.wires {
                    guard let source = state.node(id: wire.sourceNodeID),
                          let target = state.node(id: wire.targetNodeID) else { continue }
                    let path = wirePath(from: source.position, to: target.position)
                    let color = wireColor(wire.kind, active: PaneWireBus.shared.isActive(wireID: wire.id))
                    let style = StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        dash: wire.kind == .mirror ? [4, 4] : []
                    )
                    context.stroke(path, with: .color(color), style: style)
                }
            }
            ForEach(state.wires, id: \.id) { wire in
                if let source = state.node(id: wire.sourceNodeID),
                   let target = state.node(id: wire.targetNodeID)
                {
                    wireBadge(wire: wire, sourcePosition: source.position, targetPosition: target.position)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func wirePath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        let control1 = CGPoint(x: (start.x + end.x) / 2, y: start.y)
        let control2 = CGPoint(x: (start.x + end.x) / 2, y: end.y)
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    private func wireBadge(wire: AgentCanvasWire, sourcePosition: CGPoint, targetPosition: CGPoint) -> some View {
        let midpoint = CGPoint(
            x: (sourcePosition.x + targetPosition.x) / 2,
            y: (sourcePosition.y + targetPosition.y) / 2
        )
        let kind = wire.kind
        let active = PaneWireBus.shared.isActive(wireID: wire.id)
        return Menu {
            Button(active ? "Deactivate wire" : "Activate wire") {
                if active {
                    PaneWireBus.shared.deactivate(wireID: wire.id)
                } else {
                    PaneWireBus.shared.activate(wire: wire, on: state)
                }
            }
            Divider()
            Button("Delete wire", role: .destructive) {
                PaneWireBus.shared.deactivate(wireID: wire.id)
                state.removeWire(id: wire.id)
            }
        } label: {
            HStack(spacing: 3) {
                Circle()
                    .fill(wireColor(kind, active: active))
                    .frame(width: 6, height: 6)
                Text(wireLabel(kind))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(MuxyTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(wireColor(kind, active: active), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .position(midpoint)
    }

    private func wireLabel(_ kind: AgentCanvasWireKind) -> String {
        switch kind {
        case .promptRelay: "prompt"
        case .keystrokeBroadcast: "broadcast"
        case .fileWatch: "watch"
        case .mirror: "mirror"
        }
    }

    private func wireColor(_ kind: AgentCanvasWireKind, active: Bool) -> Color {
        let base: Color
        switch kind {
        case .promptRelay: base = .blue
        case .keystrokeBroadcast: base = .purple
        case .fileWatch: base = .orange
        case .mirror: base = .green
        }
        return active ? base : base.opacity(0.35)
    }

    private func card(for node: AgentCanvasNode) -> some View {
        CardView(
            node: node,
            isSelected: selectedNodeID == node.id,
            isPendingWireSource: pendingWireSource == node.id,
            onTap: { handleCardTap(node) },
            onLongPress: { selectedNodeID = node.id }
        )
        .position(x: node.position.x, y: node.position.y)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    node.position = value.location
                }
        )
    }

    private func handleCardTap(_ node: AgentCanvasNode) {
        if let sourceID = pendingWireSource {
            if sourceID != node.id {
                if pendingWireKind == .fileWatch {
                    fileWatchPrompt = FileWatchWirePromptState(sourceNodeID: sourceID, targetNodeID: node.id)
                    pendingWireSource = nil
                    return
                }
                let wire = AgentCanvasWire(
                    sourceNodeID: sourceID,
                    targetNodeID: node.id,
                    kind: pendingWireKind
                )
                state.addWire(wire)
                PaneWireBus.shared.activate(wire: wire, on: state)
            }
            pendingWireSource = nil
            return
        }
        if selectedNodeID == node.id {
            pendingWireSource = node.id
        } else {
            selectedNodeID = node.id
        }
    }

    private func commitFileWatchWire(prompt: FileWatchWirePromptState, command: String, glob: String?) {
        let wire = AgentCanvasWire(
            sourceNodeID: prompt.sourceNodeID,
            targetNodeID: prompt.targetNodeID,
            kind: .fileWatch,
            fileWatchGlob: glob,
            fileWatchCommand: command
        )
        state.addWire(wire)
        PaneWireBus.shared.activate(wire: wire, on: state)
    }

    private struct AvailablePane: Identifiable {
        let id: UUID
        let paneID: UUID
        let tab: TerminalTab
        let areaID: UUID
        let label: String
    }

    private var availablePanes: [AvailablePane] {
        guard let projectID = appState.activeProjectID else { return [] }
        var entries: [AvailablePane] = []
        for area in appState.allAreas(for: projectID) {
            for tab in area.tabs {
                guard let paneID = tab.content.pane?.id else { continue }
                if state.node(paneID: paneID) != nil { continue }
                entries.append(AvailablePane(
                    id: tab.id,
                    paneID: paneID,
                    tab: tab,
                    areaID: area.id,
                    label: tab.title
                ))
            }
        }
        return entries
    }

    private func add(entry: AvailablePane) {
        let baseX: CGFloat = 140 + CGFloat(state.nodes.count % 3) * 240
        let baseY: CGFloat = 140 + CGFloat(state.nodes.count / 3) * 150
        let agentID = agentID(forPaneID: entry.paneID)
        let node = AgentCanvasNode(
            paneID: entry.paneID,
            tabID: entry.tab.id,
            areaID: entry.areaID,
            label: entry.label,
            agentID: agentID,
            position: CGPoint(x: baseX, y: baseY)
        )
        state.addNode(node)
    }

    private func agentID(forPaneID paneID: UUID) -> String? {
        AIAgentSessionStore.shared.sessions.first { $0.paneID == paneID }?.providerID
    }
}

private struct CardView: View {
    let node: AgentCanvasNode
    let isSelected: Bool
    let isPendingWireSource: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: agentIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.accent)
                Text(node.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                    .lineLimit(1)
            }
            if let agentID = node.agentID {
                Text(agentID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 140, maxWidth: 200)
        .background(isPendingWireSource ? MuxyTheme.accent.opacity(0.18) : MuxyTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isSelected ? MuxyTheme.accent : MuxyTheme.border, lineWidth: isSelected ? 1.5 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(perform: onLongPress)
    }

    private var agentIcon: String {
        if node.agentID != nil { return "sparkles" }
        return "terminal"
    }
}
