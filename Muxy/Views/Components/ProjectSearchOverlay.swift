import AppKit
import SwiftUI

struct ProjectSearchOverlay: View {
    let projectPath: String
    let onSelect: (ProjectSearchResult, String) -> Void
    let onReplaceAll: (String, String, [ProjectSearchResult]) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var replacement = ""
    @State private var results: [ProjectSearchResult] = []
    @State private var highlightedIndex: Int = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @State private var replaceVisible = false

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
            .frame(width: 640, height: 460)
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
            scheduleSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var searchField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    replaceVisible.toggle()
                } label: {
                    Image(systemName: replaceVisible ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(replaceVisible ? "Hide Replace" : "Show Replace")
                .accessibilityLabel(replaceVisible ? "Hide Replace" : "Show Replace")

                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                PaletteSearchField(
                    text: $query,
                    placeholder: "Search in project files…",
                    onSubmit: { confirm() },
                    onEscape: { onDismiss() },
                    onArrowUp: { moveHighlight(-1) },
                    onArrowDown: { moveHighlight(1) }
                )
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if replaceVisible {
                replaceRow
            }
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 14)
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(MuxyTheme.fgMuted)
                .font(.system(size: 13))
                .accessibilityHidden(true)
            TextField("Replace with…", text: $replacement)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fg)
            Button("Replace All") {
                runReplaceAll()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(canReplaceAll ? MuxyTheme.accent : MuxyTheme.fgDim)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MuxyTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
            .disabled(!canReplaceAll)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(MuxyTheme.border).frame(height: 1).accessibilityHidden(true)
        }
    }

    private var canReplaceAll: Bool {
        !results.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runReplaceAll() {
        guard canReplaceAll else { return }
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        onReplaceAll(trimmedQuery, replacement, results)
    }

    private var resultsList: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).count < 2 {
                emptyStateView(text: "Type 2 or more characters to search.")
            } else if results.isEmpty, !isSearching {
                emptyStateView(text: "No matches.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                ProjectSearchRow(result: result, highlighted: index == highlightedIndex)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(result, query) }
                                    .id(result.id)
                            }
                        }
                    }
                    .onChange(of: highlightedIndex) { _, newIndex in
                        guard newIndex < results.count else { return }
                        proxy.scrollTo(results[newIndex].id, anchor: nil)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func emptyStateView(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fgMuted)
            Spacer()
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let currentQuery = query
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let fetched = await ProjectSearchService.search(query: currentQuery, in: projectPath)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                results = fetched
                isSearching = false
            }
        }
    }

    private func confirm() {
        guard highlightedIndex < results.count else { return }
        onSelect(results[highlightedIndex], query)
    }

    private func moveHighlight(_ delta: Int) {
        guard !results.isEmpty else { return }
        highlightedIndex = max(0, min(results.count - 1, highlightedIndex + delta))
    }
}

private struct ProjectSearchRow: View {
    let result: ProjectSearchResult
    let highlighted: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .frame(width: 14)
                Text(result.relativePath)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 8)
                Text("\(result.lineNumber):\(result.columnNumber)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            Text(result.matchText.trimmingCharacters(in: .whitespaces))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(highlighted ? MuxyTheme.surface : hovered ? MuxyTheme.hover : .clear)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.relativePath) line \(result.lineNumber): \(result.matchText)")
    }
}
