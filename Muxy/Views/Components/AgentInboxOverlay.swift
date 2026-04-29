import SwiftUI

private struct AgentInboxProjectGroup: Identifiable {
    let projectID: UUID
    let projectName: String
    let sessions: [AIAgentSession]

    var id: UUID { projectID }
}

struct AgentInboxOverlay: View {
    let store: AIAgentSessionStore
    let projectStore: ProjectStore
    let onSelect: (AIAgentSession) -> Void
    let onClear: (AIAgentSession) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var hoveredID: UUID?
    @State private var selectedIndex: Int = 0

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var filteredSessions: [AIAgentSession] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = store.sessions.sorted { $0.lastActivity > $1.lastActivity }
        guard !needle.isEmpty else { return sorted }
        return sorted.filter { session in
            let haystack = (
                session.label + " " +
                session.providerID + " " +
                session.worktreePath + " " +
                (session.currentTask ?? "")
            ).lowercased()
            return haystack.contains(needle)
        }
    }

    private var groupedSessions: [AgentInboxProjectGroup] {
        let sessions = filteredSessions
        var order: [UUID] = []
        var buckets: [UUID: [AIAgentSession]] = [:]
        for session in sessions {
            if buckets[session.projectID] == nil {
                order.append(session.projectID)
                buckets[session.projectID] = []
            }
            buckets[session.projectID]?.append(session)
        }
        return order.map { projectID in
            let name = projectStore.projects.first(where: { $0.id == projectID })?.name ?? "Unknown Project"
            return AgentInboxProjectGroup(projectID: projectID, projectName: name, sessions: buckets[projectID] ?? [])
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header
                Divider().overlay(MuxyTheme.border)
                contentList
            }
            .frame(width: 620, height: 520)
            .background(MuxyTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuxyTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityAddTraits(.isModal)
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(MuxyTheme.fgMuted)
                .font(.system(size: 13))
            PaletteSearchField(
                text: $query,
                placeholder: "Filter agents…",
                onSubmit: { confirmSelection() },
                onEscape: { onDismiss() },
                onArrowUp: { moveSelection(-1) },
                onArrowDown: { moveSelection(1) }
            )
            Text("\(store.sessions.count) agents")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var contentList: some View {
        if store.sessions.isEmpty {
            emptyState
        } else if filteredSessions.isEmpty {
            VStack {
                Spacer()
                Text("No agents match.")
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let flat = filteredSessions
                    ForEach(groupedSessions, id: \.projectID) { group in
                        sectionHeader(group.projectName)
                        ForEach(group.sessions) { session in
                            let flatIndex = flat.firstIndex(where: { $0.id == session.id }) ?? 0
                            sessionRow(session, highlighted: flatIndex == selectedIndex)
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
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 32))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("No active agents yet — launch one with ⌘⇧P → Start Agent…")
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

    private func sessionRow(_ session: AIAgentSession, highlighted: Bool) -> some View {
        let hovered = hoveredID == session.id
        let worktreeName = (session.worktreePath as NSString).lastPathComponent
        var secondaryParts: [String] = [worktreeName, session.status.displayName]
        if let task = session.currentTask, !task.isEmpty {
            secondaryParts.append(truncate(task, limit: 60))
        }
        let secondary = secondaryParts.joined(separator: " · ")

        return HStack(spacing: 10) {
            Image(systemName: session.status.symbolName)
                .foregroundStyle(statusColor(session.status))
                .font(.system(size: 12))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                Text(secondary)
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Self.relativeFormatter.localizedString(for: session.lastActivity, relativeTo: Date()))
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgDim)
            if hovered {
                Button(
                    action: { onClear(session) },
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
        .onTapGesture { onSelect(session) }
        .onHover { inside in
            hoveredID = inside ? session.id : (hoveredID == session.id ? nil : hoveredID)
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func statusColor(_ status: AIAgentStatus) -> Color {
        switch status {
        case .idle: MuxyTheme.fgMuted
        case .thinking: .blue
        case .awaitingInput: .yellow
        case .error: .red
        case .done: .green
        }
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let idx = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<idx]) + "…"
    }

    private func confirmSelection() {
        let rows = filteredSessions
        guard selectedIndex < rows.count else { return }
        onSelect(rows[selectedIndex])
    }

    private func moveSelection(_ delta: Int) {
        let rows = filteredSessions
        guard !rows.isEmpty else { return }
        selectedIndex = max(0, min(rows.count - 1, selectedIndex + delta))
    }
}
