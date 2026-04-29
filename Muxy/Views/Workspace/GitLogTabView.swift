import SwiftUI

struct GitLogTabView: View {
    let state: GitLogTabState
    let focused: Bool
    let onFocus: () -> Void

    private static let rowHeight: CGFloat = 24
    private static let columnWidth: CGFloat = 14
    private static let railLeading: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MuxyTheme.border)
            content
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .onAppear {
            if state.commits.isEmpty {
                state.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.accent)
            Text("Commit Graph")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("\(state.commits.count) commits")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgMuted)
            if state.isLoading {
                ProgressView().controlSize(.small).padding(.leading, 4)
            }
            Spacer()
            Button("Refresh") { state.load() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MuxyTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(MuxyTheme.border, lineWidth: 0.5))
                .foregroundStyle(MuxyTheme.fg)
                .disabled(state.isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if state.commits.isEmpty, !state.isLoading {
            empty
        } else {
            HStack(spacing: 0) {
                commitList
                Divider().overlay(MuxyTheme.border)
                sidePanel
                    .frame(width: 300)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("No commits yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            if let err = state.lastError {
                Text(err)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commitList: some View {
        GeometryReader { _ in
            ScrollView(.vertical, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    graphLayer
                        .frame(width: graphWidth, height: CGFloat(state.commits.count) * Self.rowHeight, alignment: .top)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(state.commits.enumerated()), id: \.element.id) { index, commit in
                            row(for: commit, index: index)
                        }
                    }
                    .padding(.leading, graphWidth + 6)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var graphWidth: CGFloat {
        let maxColumn = state.graphRows.map { row in
            max(row.column, row.activeColumnsAfter.count - 1)
        }.max() ?? 0
        return Self.railLeading + CGFloat(maxColumn + 1) * Self.columnWidth
    }

    private var graphLayer: some View {
        Canvas { context, _ in
            for row in state.graphRows {
                let rowOriginY = CGFloat(row.commitIndex) * Self.rowHeight
                let dotY = rowOriginY + Self.rowHeight / 2
                let dotX = Self.railLeading + CGFloat(row.column) * Self.columnWidth

                if row.commitIndex < state.graphRows.count - 1 {
                    let nextRow = state.graphRows[row.commitIndex + 1]
                    for parentColumn in row.parentColumns {
                        let endY = rowOriginY + Self.rowHeight + Self.rowHeight / 2
                        let endX = Self.railLeading + CGFloat(parentColumn) * Self.columnWidth
                        var path = Path()
                        path.move(to: CGPoint(x: dotX, y: dotY))
                        path.addLine(to: CGPoint(x: endX, y: endY))
                        let color = railColor(column: parentColumn)
                        context.stroke(path, with: .color(color.opacity(0.75)), lineWidth: 1.5)
                    }
                    for (column, _) in nextRow.activeColumnsAfter.enumerated()
                        where column != nextRow.column && nextRow.activeColumnsAfter[column] != nil
                    {
                        let startY = rowOriginY + Self.rowHeight / 2
                        let endY = rowOriginY + Self.rowHeight + Self.rowHeight / 2
                        let rowX = Self.railLeading + CGFloat(column) * Self.columnWidth
                        var path = Path()
                        path.move(to: CGPoint(x: rowX, y: startY))
                        path.addLine(to: CGPoint(x: rowX, y: endY))
                        let color = railColor(column: column)
                        context.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 1.5)
                    }
                }

                let dotRect = CGRect(x: dotX - 4, y: dotY - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dotRect), with: .color(railColor(column: row.column)))
                context.stroke(Path(ellipseIn: dotRect), with: .color(MuxyTheme.bg), lineWidth: 1)
            }
        }
    }

    private func railColor(column: Int) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .yellow, .red, .teal]
        return palette[column % palette.count]
    }

    private func row(for commit: GitCommit, index: Int) -> some View {
        HStack(spacing: 6) {
            Text(commit.shortHash)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: 58, alignment: .leading)
            Text(commit.subject)
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            ForEach(commit.refs.prefix(3), id: \.name) { ref in
                refBadge(ref)
            }
            Spacer(minLength: 6)
            Text(commit.authorName)
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
            Text(relativeDate(commit.authorDate))
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight, alignment: .leading)
        .background(state.selectedCommitHash == commit.hash ? MuxyTheme.accent.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { state.select(hash: commit.hash) }
    }

    private func refBadge(_ ref: GitRef) -> some View {
        let (color, label): (Color, String) = {
            switch ref.kind {
            case .head: (.yellow, "HEAD")
            case .localBranch: (.green, ref.name)
            case .remoteBranch: (.blue, ref.name)
            case .tag: (.purple, "\u{1F3F7} \(ref.name)")
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.22))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let commit = state.selectedCommit {
                Text(commit.subject)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text(commit.hash)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Divider().overlay(MuxyTheme.border)
                row(label: "Author", value: commit.authorName)
                row(label: "Date", value: commit.authorDate.formatted(date: .abbreviated, time: .shortened))
                if !commit.parentHashes.isEmpty {
                    row(label: "Parents", value: commit.parentHashes.map { String($0.prefix(7)) }.joined(separator: " "))
                }
                if !commit.refs.isEmpty {
                    row(label: "Refs", value: commit.refs.map { $0.name }.joined(separator: ", "))
                }
                Spacer()
            } else {
                Spacer()
                Text("Select a commit")
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MuxyTheme.surface.opacity(0.35))
    }

    private func row(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }
}
