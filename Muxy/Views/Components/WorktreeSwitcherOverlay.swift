import SwiftUI

struct WorktreeSwitcherOverlay: View {
    let items: [WorktreeSwitcherItem]
    let activeKey: WorktreeKey?
    let onSelect: (WorktreeSwitcherItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        PaletteOverlay<WorktreeSwitcherItem>(
            placeholder: "Search worktrees by name, branch, or project...",
            emptyLabel: "No worktrees",
            noMatchLabel: "No matching worktrees",
            search: { query in filter(query: query) },
            onSelect: onSelect,
            onDismiss: onDismiss,
            row: { item, isHighlighted in
                AnyView(
                    WorktreeSwitcherRow(
                        item: item,
                        isHighlighted: isHighlighted,
                        isActive: item.key == activeKey
                    )
                )
            }
        )
    }

    private func filter(query: String) -> [WorktreeSwitcherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        let needle = trimmed.lowercased()
        return items.filter { item in
            item.searchKey.localizedCaseInsensitiveContains(needle)
        }
    }
}

struct WorktreeSwitcherItem: Identifiable {
    let projectID: UUID
    let projectName: String
    let worktree: Worktree

    var id: WorktreeKey { WorktreeKey(projectID: projectID, worktreeID: worktree.id) }
    var key: WorktreeKey { id }

    var displayName: String {
        if worktree.isPrimary, worktree.name.isEmpty { return "main" }
        return worktree.name
    }

    var branchSubtitle: String? {
        guard let branch = worktree.branch, !branch.isEmpty else { return nil }
        guard branch.caseInsensitiveCompare(displayName) != .orderedSame else { return nil }
        return branch
    }

    var searchKey: String {
        [displayName, worktree.branch ?? "", projectName].joined(separator: " ")
    }
}

private struct WorktreeSwitcherRow: View {
    let item: WorktreeSwitcherItem
    let isHighlighted: Bool
    let isActive: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuxyTheme.fg)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.worktree.isPrimary {
                        primaryChip
                    }
                }
                HStack(spacing: 6) {
                    if let branch = item.branchSubtitle {
                        Text(branch)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(MuxyTheme.fgDim)
                    }
                    Text(item.projectName)
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MuxyTheme.accent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowFill)
        )
        .padding(.horizontal, 6)
        .onHover { hovered = $0 }
    }

    private var rowFill: Color {
        if isHighlighted { return MuxyGlass.selectionFill }
        if hovered { return MuxyGlass.hoverFill }
        return Color.clear
    }

    private var primaryChip: some View {
        Text("PRIMARY")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(MuxyTheme.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(MuxyTheme.accentSoft)
            )
            .overlay(
                Capsule()
                    .strokeBorder(MuxyTheme.accent.opacity(0.35), lineWidth: 0.5)
            )
    }
}
