import SwiftUI

private struct ScrollbackProjectGroup: Identifiable {
    let projectID: UUID?
    let projectName: String
    let checkpoints: [TerminalScrollbackCheckpoint]

    var id: String { projectID?.uuidString ?? "__unassigned__" }
}

struct ScrollbackHistoryOverlay: View {
    let store: TerminalScrollbackStore
    let projectStore: ProjectStore
    let appState: AppState
    let onSelect: (TerminalScrollbackCheckpoint) -> Void
    let onExportBetween: (TerminalScrollbackCheckpoint, TerminalScrollbackCheckpoint) -> Void
    let onDelete: (TerminalScrollbackCheckpoint) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var hoveredID: UUID?
    @State private var selectedIndex: Int = 0
    @State private var rangeAnchor: TerminalScrollbackCheckpoint?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var filteredCheckpoints: [TerminalScrollbackCheckpoint] {
        let sorted = store.checkpoints.sorted { $0.createdAt > $1.createdAt }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { checkpoint in
            let projectName = projectName(for: checkpoint.projectID).lowercased()
            let paneTitle = paneTitle(for: checkpoint.paneID).lowercased()
            return checkpoint.label.lowercased().contains(needle)
                || projectName.contains(needle)
                || paneTitle.contains(needle)
        }
    }

    private var groupedCheckpoints: [ScrollbackProjectGroup] {
        let checkpoints = filteredCheckpoints
        var order: [String] = []
        var names: [String: String] = [:]
        var ids: [String: UUID?] = [:]
        var buckets: [String: [TerminalScrollbackCheckpoint]] = [:]
        for checkpoint in checkpoints {
            let key = checkpoint.projectID?.uuidString ?? "__unassigned__"
            if buckets[key] == nil {
                order.append(key)
                names[key] = projectName(for: checkpoint.projectID)
                ids[key] = checkpoint.projectID
                buckets[key] = []
            }
            buckets[key]?.append(checkpoint)
        }
        return order.map { key in
            ScrollbackProjectGroup(
                projectID: ids[key].flatMap { $0 },
                projectName: names[key] ?? "Unassigned",
                checkpoints: buckets[key] ?? []
            )
        }
    }

    var body: some View {
        ZStack {
            MuxyOverlayScrim(onDismiss: onDismiss)
            GlassPanel(
                material: MuxyMaterials.overlayMaterial,
                cornerRadius: 14,
                elevation: .overlay
            ) {
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(MuxyGlass.borderSoft).frame(height: 1)
                    contentList
                    if rangeAnchor != nil {
                        Rectangle().fill(MuxyGlass.borderSoft).frame(height: 1)
                        rangeBar
                    }
                }
            }
            .frame(width: 620, height: 520)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityAddTraits(.isModal)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(MuxyTheme.fgMuted)
                .font(.system(size: 13))
            PaletteSearchField(
                text: $query,
                placeholder: "Filter checkpoints…",
                onSubmit: { confirmSelection() },
                onEscape: { onDismiss() },
                onArrowUp: { moveSelection(-1) },
                onArrowDown: { moveSelection(1) }
            )
            Text("\(store.checkpoints.count) checkpoints")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var contentList: some View {
        if store.checkpoints.isEmpty {
            emptyState
        } else if filteredCheckpoints.isEmpty {
            VStack {
                Spacer()
                Text("No checkpoints match.")
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let flat = filteredCheckpoints
                    ForEach(groupedCheckpoints) { group in
                        sectionHeader(group.projectName)
                        ForEach(group.checkpoints) { checkpoint in
                            let flatIndex = flat.firstIndex(where: { $0.id == checkpoint.id }) ?? 0
                            checkpointRow(checkpoint, highlighted: flatIndex == selectedIndex)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bookmark")
                .font(.system(size: 32))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("No checkpoints yet — drop one with ⌘⇧K during any terminal output.")
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fgMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MuxyTheme.fgMuted)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func checkpointRow(
        _ checkpoint: TerminalScrollbackCheckpoint,
        highlighted: Bool
    ) -> some View {
        let hovered = hoveredID == checkpoint.id
        let paneTitle = paneTitle(for: checkpoint.paneID)
        let bytesSince = store.bytesSince(checkpoint)?.count ?? 0
        let secondary = "\(paneTitle) · \(bytesSince) bytes since"
        let isAnchor = rangeAnchor?.id == checkpoint.id

        return HStack(spacing: 10) {
            Image(systemName: isAnchor ? "bookmark.circle.fill" : "bookmark.fill")
                .foregroundStyle(isAnchor ? Color.accentColor : MuxyTheme.fgMuted)
                .font(.system(size: 12))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                Text(secondary)
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Self.relativeFormatter.localizedString(for: checkpoint.createdAt, relativeTo: Date()))
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgDim)
            if hovered {
                Button(
                    action: { onExportBetween(checkpoint, latestCheckpoint(for: checkpoint.paneID) ?? checkpoint) },
                    label: {
                        Text("Export from here")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MuxyTheme.fgMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                )
                .buttonStyle(.plain)

                Button(
                    action: { onDelete(checkpoint) },
                    label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MuxyTheme.fgMuted)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                )
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(highlighted ? MuxyTheme.surface : hovered ? MuxyTheme.hover : .clear)
        .contentShape(Rectangle())
        .onTapGesture { handleTap(checkpoint) }
        .onHover { inside in
            hoveredID = inside ? checkpoint.id : (hoveredID == checkpoint.id ? nil : hoveredID)
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var rangeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square")
                .foregroundStyle(MuxyTheme.fgMuted)
                .font(.system(size: 11))
            if let anchor = rangeAnchor {
                Text("Anchored: \(anchor.label)")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fg)
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel") {
                rangeAnchor = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(MuxyTheme.fgMuted)
            Text("⌘-click another row to export range")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgDim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MuxyTheme.surface)
    }

    private func handleTap(_ checkpoint: TerminalScrollbackCheckpoint) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if let anchor = rangeAnchor, anchor.id != checkpoint.id {
                onExportBetween(anchor, checkpoint)
                rangeAnchor = nil
                return
            }
            rangeAnchor = checkpoint
            return
        }
        onSelect(checkpoint)
    }

    private func latestCheckpoint(for paneID: UUID) -> TerminalScrollbackCheckpoint? {
        store.checkpoints(paneID: paneID).max(by: { $0.seq < $1.seq })
    }

    private func confirmSelection() {
        let rows = filteredCheckpoints
        guard selectedIndex < rows.count else { return }
        onSelect(rows[selectedIndex])
    }

    private func moveSelection(_ delta: Int) {
        let rows = filteredCheckpoints
        guard !rows.isEmpty else { return }
        selectedIndex = max(0, min(rows.count - 1, selectedIndex + delta))
    }

    private func projectName(for projectID: UUID?) -> String {
        guard let projectID else { return "Unassigned" }
        return projectStore.projects.first(where: { $0.id == projectID })?.name ?? "Unknown Project"
    }

    private func paneTitle(for paneID: UUID) -> String {
        for (_, root) in appState.workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs where tab.content.pane?.id == paneID {
                    return tab.title
                }
            }
        }
        return "Detached pane"
    }
}
