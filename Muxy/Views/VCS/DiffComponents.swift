import AppKit
import SwiftUI

struct DiffSectionDivider: View {
    let text: String
    var showsTopBorder: Bool = true
    var hunk: DiffHunkReference? = nil
    var onStageHunk: ((DiffHunkReference) -> Void)? = nil
    var onUnstageHunk: ((DiffHunkReference) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 10)
            Spacer(minLength: 8)
            if let hunk {
                actionButton(for: hunk)
                    .padding(.trailing, 8)
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(MuxyTheme.bg)
        .overlay(alignment: .top) {
            if showsTopBorder {
                Rectangle().fill(MuxyTheme.border).frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diff section: \(text)")
    }

    @ViewBuilder
    private func actionButton(for hunk: DiffHunkReference) -> some View {
        switch hunk.source {
        case .unstaged:
            if let onStageHunk {
                DiffHunkActionButton(label: "Stage Hunk", symbol: "plus.square") {
                    onStageHunk(hunk)
                }
            }
        case .staged:
            if let onUnstageHunk {
                DiffHunkActionButton(label: "Unstage Hunk", symbol: "minus.square") {
                    onUnstageHunk(hunk)
                }
            }
        case .untracked:
            EmptyView()
        }
    }
}

private struct DiffHunkActionButton: View {
    let label: String
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(hovered ? MuxyTheme.surface : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
    }
}

func hunkLabel(_ raw: String) -> String {
    guard raw.count > 2,
          let closingRange = raw.range(of: "@@", range: raw.index(raw.startIndex, offsetBy: 2) ..< raw.endIndex)
    else { return raw }
    let after = raw[closingRange.upperBound...].trimmingCharacters(in: .whitespaces)
    return after.isEmpty ? raw : after
}

func lineNumberWidth(for maxLineNumber: Int) -> CGFloat {
    let digitCount = max(String(maxLineNumber).count, 1)
    return CGFloat(digitCount) * 8 + 12
}

func maxLineNumber(in rows: [DiffDisplayRow]) -> Int {
    rows.reduce(0) { result, row in
        max(result, row.oldLineNumber ?? 0, row.newLineNumber ?? 0)
    }
}

enum DiffBackgroundSide {
    case left
    case right
    case both
}

struct DiffHighlightRule: @unchecked Sendable {
    let regex: NSRegularExpression
    let color: NSColor
}

struct DiffRenderTheme: @unchecked Sendable {
    let rules: [DiffHighlightRule]
    let additionColor: NSColor
    let deletionColor: NSColor
    let defaultColor: NSColor
    let additionBackground: NSColor
    let deletionBackground: NSColor
    let hunkBackground: NSColor
    let collapsedBackground: NSColor
    let font: NSFont

    @MainActor
    static func current() -> DiffRenderTheme {
        DiffRenderTheme(
            rules: Self.buildRules(),
            additionColor: MuxyTheme.nsDiffAdd,
            deletionColor: MuxyTheme.nsDiffRemove,
            defaultColor: GhosttyService.shared.foregroundColor,
            additionBackground: MuxyTheme.nsDiffAdd.withAlphaComponent(0.16),
            deletionBackground: MuxyTheme.nsDiffRemove.withAlphaComponent(0.16),
            hunkBackground: MuxyTheme.nsDiffHunk.withAlphaComponent(0.1),
            collapsedBackground: MuxyTheme.nsBg,
            font: DiffMetrics.font
        )
    }

    private struct RuleDefinition {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options
    }

    @MainActor
    private static func buildRules() -> [DiffHighlightRule] {
        let definitions: [RuleDefinition] = [
            RuleDefinition(pattern: #"'(?:\\.|[^'\\])*'"#, color: MuxyTheme.nsDiffString, options: []),
            RuleDefinition(pattern: #""(?:\\.|[^"\\])*""#, color: MuxyTheme.nsDiffString, options: []),
            RuleDefinition(pattern: #"`(?:\\.|[^`\\])*`"#, color: MuxyTheme.nsDiffString, options: []),
            RuleDefinition(pattern: #"\b\d+(?:\.\d+)?\b"#, color: MuxyTheme.nsDiffNumber, options: []),
            RuleDefinition(pattern: #"//.*$"#, color: MuxyTheme.nsDiffComment, options: [.anchorsMatchLines]),
        ]

        var result: [DiffHighlightRule] = []
        for definition in definitions {
            guard let regex = try? NSRegularExpression(pattern: definition.pattern, options: definition.options)
            else { continue }
            result.append(DiffHighlightRule(regex: regex, color: definition.color))
        }
        return result
    }
}
