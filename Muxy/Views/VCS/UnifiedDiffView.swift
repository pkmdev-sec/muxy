import SwiftUI

struct UnifiedDiffView: View {
    let rows: [DiffDisplayRow]
    let filePath: String
    var suppressLeadingTopBorder: Bool = false
    var onStageHunk: ((DiffHunkReference) -> Void)? = nil
    var onUnstageHunk: ((DiffHunkReference) -> Void)? = nil
    var onStageLine: ((GitPatchBuilder.LineSelection) -> Void)? = nil
    var onUnstageLine: ((GitPatchBuilder.LineSelection) -> Void)? = nil

    private var chunks: [DiffChunk] {
        buildDiffChunks(from: rows)
    }

    private var numberColumnWidth: CGFloat {
        lineNumberWidth(for: maxLineNumber(in: rows))
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                switch chunk {
                case let .divider(text, hunk):
                    DiffSectionDivider(
                        text: text,
                        showsTopBorder: !(index == 0 && suppressLeadingTopBorder),
                        hunk: hunk,
                        onStageHunk: onStageHunk,
                        onUnstageHunk: onUnstageHunk
                    )
                case let .codeBlock(blockRows):
                    unifiedCodeBlock(blockRows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unified diff, \(filePath)")
    }

    private var gutterWidth: CGFloat {
        numberColumnWidth * 2 + 2 + DiffGutterNSView.prefixColumnWidth
    }

    private func unifiedCodeBlock(_ blockRows: [DiffDisplayRow]) -> some View {
        let height = CGFloat(blockRows.count) * diffLineHeight
        let metadata = buildDiffMetadata(from: blockRows)
        return HStack(alignment: .top, spacing: 0) {
            DiffGutterBridge(
                metadata: metadata,
                filePath: filePath,
                mode: .unified,
                columnWidth: numberColumnWidth,
                onStageLine: onStageLine,
                onUnstageLine: onUnstageLine
            )
            .frame(width: gutterWidth, height: height)

            ScrollView(.horizontal, showsIndicators: false) {
                DiffContentBridge(
                    rows: blockRows,
                    backgroundSide: .both
                )
                .frame(height: height)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}
