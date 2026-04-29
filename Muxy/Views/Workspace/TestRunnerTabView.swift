import SwiftUI

struct TestRunnerTabView: View {
    let state: TestRunnerTabState
    let focused: Bool
    let onFocus: () -> Void

    @State private var expandedNodeIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MuxyTheme.border)
            if state.root.children.isEmpty, state.recentOutputLines.isEmpty {
                empty
            } else {
                content
            }
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isRunning ? "arrow.triangle.2.circlepath" : "checkmark.square.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.isRunning ? Color.blue : summaryTint)
            Text(headerText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Spacer(minLength: 12)
            Text(state.commandLine)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.head)
            Button(action: run) {
                HStack(spacing: 4) {
                    Image(systemName: state.isRunning ? "stop.circle.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(state.isRunning ? "Stop" : "Run")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(state.isRunning ? Color.red.opacity(0.85) : Color.accentColor.opacity(0.85))
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var headerText: String {
        let summary = state.root.summary()
        if state.isRunning {
            return "Running\u{2026} (\(summary.passed)\u{2713} \(summary.failed)\u{2717} \(summary.total) total)"
        }
        if summary.total == 0 {
            return "Idle"
        }
        if summary.failed > 0 {
            let dur = summary.durationSeconds.map { String(format: " \u{00B7} %.2fs", $0) } ?? ""
            return "\(summary.failed) failing, \(summary.passed) passing\(dur)"
        }
        let dur = summary.durationSeconds.map { String(format: " \u{00B7} %.2fs", $0) } ?? ""
        return "\(summary.passed) passing\(dur)"
    }

    private var summaryTint: Color {
        let summary = state.root.summary()
        if summary.failed > 0 { return .red }
        if summary.total > 0 { return .green }
        return MuxyTheme.fgMuted
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.square")
                .font(.system(size: 28))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("No test run yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("Press Run to execute: \(state.commandLine)")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        HStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(flattenedNodes(), id: \.node.id) { entry in
                        row(for: entry.node, depth: entry.depth)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
            Divider().overlay(MuxyTheme.border)
            outputTail
                .frame(width: 340)
        }
    }

    private func flattenedNodes() -> [FlattenedNode] {
        var out: [FlattenedNode] = []
        for child in state.root.children {
            appendNode(child, depth: 0, into: &out)
        }
        return out
    }

    private func appendNode(_ node: TestNode, depth: Int, into out: inout [FlattenedNode]) {
        out.append(FlattenedNode(node: node, depth: depth))
        guard node.isSuite, expandedNodeIDs.contains(node.id) || node.children.count <= 12 else { return }
        for child in node.children {
            appendNode(child, depth: depth + 1, into: &out)
        }
    }

    private func row(for node: TestNode, depth: Int) -> some View {
        let isFailureLeaf = !node.isSuite && node.status == .failed && !node.failures.isEmpty
        return HStack(spacing: 6) {
            if node.isSuite {
                Image(systemName: expandedNodeIDs.contains(node.id) || node.children.count <= 12 ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                    .foregroundStyle(MuxyTheme.fgMuted)
            } else {
                Spacer().frame(width: 10)
            }
            Image(systemName: statusSymbol(node.status))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(statusTint(node.status))
                .frame(width: 14)
            Text(node.name)
                .font(.system(size: 12, weight: node.isSuite ? .semibold : .regular))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let duration = node.durationSeconds {
                Text(String(format: "%.2fs", duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(isFailureLeaf ? Color.red.opacity(0.08) : Color.clear)
        .onTapGesture {
            if node.isSuite {
                toggleExpanded(node.id)
                return
            }
            if let failure = node.failures.first, let path = failure.filePath, let line = failure.line {
                openEditor(filePath: path, line: line)
            }
        }
    }

    private func statusSymbol(_ status: TestStatus) -> String {
        switch status {
        case .pending: "circle"
        case .running: "arrow.triangle.2.circlepath"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "slash.circle"
        }
    }

    private func statusTint(_ status: TestStatus) -> Color {
        switch status {
        case .pending: MuxyTheme.fgMuted
        case .running: .blue
        case .passed: .green
        case .failed: .red
        case .skipped: MuxyTheme.fgMuted
        }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedNodeIDs.contains(id) {
            expandedNodeIDs.remove(id)
        } else {
            expandedNodeIDs.insert(id)
        }
    }

    private var outputTail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Raw output")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(state.recentOutputLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fgMuted)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: state.recentOutputLines.count) { _, newValue in
                    guard newValue > 0 else { return }
                    scrollProxy.scrollTo(newValue - 1, anchor: .bottom)
                }
            }
        }
    }

    private func run() {
        if state.isRunning {
            TestRunnerService.shared.cancel(state: state)
            return
        }
        Task { await TestRunnerService.shared.run(state: state) }
    }

    private func openEditor(filePath: String, line: Int) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        delegate.handleOpenProjectPath(filePath)
    }
}

private struct FlattenedNode {
    let node: TestNode
    let depth: Int
}
