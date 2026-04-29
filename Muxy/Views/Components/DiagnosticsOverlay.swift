import AppKit
import SwiftUI

struct DiagnosticsOverlay: View {
    let onDismiss: () -> Void
    @State private var query = ""
    private let client = LSPClient.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header
                Divider().overlay(MuxyTheme.border)
                body(for: filtered())
            }
            .frame(width: 640, height: 520)
            .background(MuxyTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuxyTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "ladybug")
                .foregroundStyle(MuxyTheme.accent)
                .font(.system(size: 13, weight: .semibold))
            Text("Diagnostics")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text(stateLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MuxyTheme.surface)
                .clipShape(Capsule())
            severityCount(.error, color: .red)
            severityCount(.warning, color: .yellow)
            Spacer()
            TextField("Filter\u{2026}", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MuxyTheme.fgMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func severityCount(_ severity: LSPDiagnosticSeverity, color: Color) -> some View {
        let count = client.totalCount(severity: severity)
        return HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var stateLabel: String {
        switch client.state {
        case .idle: "Idle"
        case .starting: "Starting\u{2026}"
        case .ready: "Ready"
        case let .failed(msg): "Failed: \(msg)"
        }
    }

    @ViewBuilder
    private func body(for list: [LSPDiagnostic]) -> some View {
        if list.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 24))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Text(client.state.isReady ? "No diagnostics" : "LSP not running\u{2014}open a Swift file to start")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { diagnostic in
                        row(for: diagnostic)
                    }
                }
            }
        }
    }

    private func row(for diagnostic: LSPDiagnostic) -> some View {
        Button {
            open(diagnostic: diagnostic)
            onDismiss()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName(for: diagnostic.severity))
                    .foregroundStyle(color(for: diagnostic.severity))
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(diagnostic.message)
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fg)
                        .lineLimit(3)
                    HStack(spacing: 5) {
                        Text((diagnostic.filePath as NSString).lastPathComponent)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgMuted)
                        Text("\(diagnostic.line):\(diagnostic.column)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgMuted)
                        if let source = diagnostic.source {
                            Text(source)
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.fgMuted)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(MuxyTheme.surface)
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filtered() -> [LSPDiagnostic] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = client.allDiagnostics()
        guard !needle.isEmpty else { return all }
        return all.filter { d in
            d.message.lowercased().contains(needle) || d.filePath.lowercased().contains(needle)
        }
    }

    private func iconName(for severity: LSPDiagnosticSeverity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .information: "info.circle"
        case .hint: "lightbulb"
        }
    }

    private func color(for severity: LSPDiagnosticSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .yellow
        case .information: .blue
        case .hint: .purple
        }
    }

    private func open(diagnostic: LSPDiagnostic) {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        delegate.handleOpenProjectPath(diagnostic.filePath)
    }
}
