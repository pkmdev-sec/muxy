import SwiftUI

struct MergeConflictView: View {
    let filePath: String
    let state: VCSTabState

    var body: some View {
        Group {
            if let error = state.conflictErrorsByPath[filePath] {
                errorPanel(message: error)
            } else if let regions = state.conflictRegionsByPath[filePath] {
                if regions.isEmpty {
                    allResolvedPanel
                } else {
                    VStack(spacing: 0) {
                        headerBanner(remaining: regions.count)
                        ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
                            ConflictRegionRow(
                                filePath: filePath,
                                regionIndex: index,
                                region: region,
                                state: state
                            )
                            if index < regions.count - 1 {
                                Rectangle().fill(MuxyTheme.border).frame(height: 1)
                            }
                        }
                    }
                }
            } else {
                loadingPanel
            }
        }
        .background(MuxyTheme.bg)
        .onAppear {
            state.ensureConflictsLoaded(filePath: filePath)
        }
    }

    private func headerBanner(remaining: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Text("\(remaining) unresolved conflict\(remaining == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuxyTheme.fg)
            Spacer(minLength: 0)
            Text("Choose a side for each region, or edit manually in the file.")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MuxyTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
        }
    }

    private var allResolvedPanel: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(MuxyTheme.diffAddFg)
            Text("All conflicts resolved.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MuxyTheme.fg)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingPanel: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(14)
    }

    private func errorPanel(message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(MuxyTheme.fgMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }
}

private struct ConflictRegionRow: View {
    let filePath: String
    let regionIndex: Int
    let region: GitConflictRegion
    let state: VCSTabState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            regionHeader
            columns
            actionRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var regionHeader: some View {
        HStack(spacing: 8) {
            Text("Conflict #\(regionIndex + 1)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("line \(region.startLineIndex + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgDim)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: 8) {
            column(title: label(region.oursLabel, fallback: "Ours"), lines: region.oursLines, accent: .ours)
            if let base = region.baseLines {
                column(title: "Base", lines: base, accent: .base)
            }
            column(title: label(region.theirsLabel, fallback: "Theirs"), lines: region.theirsLines, accent: .theirs)
        }
    }

    private func label(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func column(title: String, lines: [String], accent: ConflictColumnAccent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(accent.foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.background.opacity(0.18))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if lines.isEmpty {
                        Text("(empty)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgDim)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 180)
            .background(accent.background.opacity(0.06))
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(MuxyTheme.border, lineWidth: 0.5))
        .frame(maxWidth: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            resolveButton("Keep Ours", choice: .keepOurs)
            resolveButton("Keep Theirs", choice: .keepTheirs)
            resolveButton("Keep Both", choice: .keepBoth)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func resolveButton(_ label: String, choice: GitConflictResolutionChoice) -> some View {
        Button(label) {
            state.resolveConflict(filePath: filePath, regionIndex: regionIndex, choice: choice)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(MuxyTheme.fg)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(MuxyTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
    }
}

private enum ConflictColumnAccent {
    case ours
    case base
    case theirs

    @MainActor var background: Color {
        switch self {
        case .ours: MuxyTheme.diffAddFg
        case .base: MuxyTheme.fgMuted
        case .theirs: MuxyTheme.accent
        }
    }

    @MainActor var foreground: Color {
        switch self {
        case .ours: MuxyTheme.diffAddFg
        case .base: MuxyTheme.fgMuted
        case .theirs: MuxyTheme.accent
        }
    }
}
