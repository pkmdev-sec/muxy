import AppKit
import SwiftUI

struct CommandPaletteOverlay: View {
    let palette: CommandPalette
    let onSelect: @MainActor (PaletteCommand) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var highlightedIndex: Int = 0

    private var matches: [PaletteCommandMatch] {
        palette.matches(for: query)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField
                Divider().overlay(MuxyTheme.border)
                resultsList
            }
            .frame(width: 560, height: 420)
            .background(MuxyTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuxyTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityAddTraits(.isModal)
        }
        .onChange(of: query) { _, _ in
            highlightedIndex = 0
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .foregroundStyle(MuxyTheme.fgMuted)
                .font(.system(size: 13))
                .accessibilityHidden(true)
            PaletteSearchField(
                text: $query,
                placeholder: "Run a command…",
                onSubmit: { confirm() },
                onEscape: { onDismiss() },
                onArrowUp: { moveHighlight(-1) },
                onArrowDown: { moveHighlight(1) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var resultsList: some View {
        Group {
            let rows = matches
            if rows.isEmpty {
                VStack {
                    Spacer()
                    Text(query.isEmpty ? "No commands" : "No matching commands")
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fgMuted)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, match in
                                CommandPaletteRow(
                                    match: match,
                                    highlighted: index == highlightedIndex
                                )
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(match.command) }
                                .id(match.id)
                            }
                        }
                    }
                    .onChange(of: highlightedIndex) { _, newIndex in
                        guard newIndex < rows.count else { return }
                        proxy.scrollTo(rows[newIndex].id, anchor: nil)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func confirm() {
        let rows = matches
        guard highlightedIndex < rows.count else { return }
        onSelect(rows[highlightedIndex].command)
    }

    private func moveHighlight(_ delta: Int) {
        let rows = matches
        guard !rows.isEmpty else { return }
        highlightedIndex = max(0, min(rows.count - 1, highlightedIndex + delta))
    }
}

private struct CommandPaletteRow: View {
    let match: PaletteCommandMatch
    let highlighted: Bool
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: match.command.symbol)
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                titleView
                if let subtitle = match.command.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            Text(match.command.group.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MuxyTheme.fgDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
            if let shortcut = match.command.shortcut {
                ShortcutBadge(label: shortcut.displayString, compact: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(highlighted ? MuxyTheme.surface : hovered ? MuxyTheme.hover : .clear)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(match.command.title)
        .accessibilityHint(match.command.subtitle ?? "")
    }

    private var titleView: some View {
        if match.titleRanges.isEmpty {
            return AnyView(
                Text(match.command.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                    .lineLimit(1)
            )
        }
        return AnyView(
            buildHighlightedTitle()
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        )
    }

    private func buildHighlightedTitle() -> Text {
        let title = match.command.title
        var result = Text("")
        var cursor = title.startIndex
        for range in match.titleRanges where cursor <= range.lowerBound {
            if cursor < range.lowerBound {
                result = result
                    + Text(title[cursor ..< range.lowerBound])
                    .foregroundStyle(MuxyTheme.fg)
            }
            result = result
                + Text(title[range])
                .foregroundStyle(MuxyTheme.accent)
                .fontWeight(.semibold)
            cursor = range.upperBound
        }
        if cursor < title.endIndex {
            result = result + Text(title[cursor...]).foregroundStyle(MuxyTheme.fg)
        }
        return result
    }
}
