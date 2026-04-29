import AppKit
import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 0) {
            WindowDragRepresentable()
                .frame(height: 32)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heroSection
                    tipCardSection
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 40)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Muxy")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("A terminal multiplexer for macOS, built around projects and split panes.")
                    .font(.system(size: 13))
                    .foregroundStyle(MuxyTheme.fgMuted)
                HStack(spacing: 10) {
                    shortcutPill(label: "Open Project", combo: "⌘O")
                    shortcutPill(label: "Command Palette", combo: "⌘⇧P")
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var tipCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Power-user shortcuts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgMuted)
                .textCase(.uppercase)

            VStack(spacing: 1) {
                tipRow(
                    symbol: "command",
                    title: "Command Palette",
                    description: "Run any action, theme, or navigation",
                    combo: "⌘⇧P"
                )
                tipRow(
                    symbol: "sparkles.rectangle.stack",
                    title: "Agent Inbox",
                    description: "Live cross-project status of every AI agent running in Muxy",
                    combo: "⌘⇧A"
                )
                tipRow(
                    symbol: "square.stack.3d.up",
                    title: "Start Agent Workbench",
                    description: "Spin up each agent in its own worktree from .muxy/worktree.json",
                    combo: "⌘⇧P"
                )
                tipRow(
                    symbol: "bookmark",
                    title: "Scrollback Checkpoint",
                    description: "Mark a spot in terminal output, jump back or export the range",
                    combo: "⌘⇧M"
                )
                tipRow(
                    symbol: "record.circle",
                    title: "Workflow Recorder",
                    description: "Capture a palette sequence, replay as a macro",
                    combo: "⌘⌥R"
                )
                tipRow(
                    symbol: "checkmark.square",
                    title: "Test Runner Tab",
                    description: "Structured pass/fail tree for Swift Testing and XCTest runs",
                    combo: "⌘⇧P"
                )
                tipRow(
                    symbol: "doc.text.magnifyingglass",
                    title: "Quick Open",
                    description: "Fuzzy-find any file in the active project",
                    combo: "⌘P"
                )
                tipRow(
                    symbol: "arrow.triangle.branch",
                    title: "Source Control",
                    description: "Stage per-hunk, resolve merge conflicts, open PRs",
                    combo: "⌘K"
                )
            }
            .background(MuxyTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MuxyTheme.border, lineWidth: 0.5))
        }
    }

    private func shortcutPill(label: String, combo: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MuxyTheme.fg)
            Text(combo)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MuxyTheme.fgMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MuxyTheme.bg, in: Capsule())
                .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(MuxyTheme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
    }

    private func tipRow(symbol: String, title: String, description: String, combo: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
            Spacer(minLength: 12)
            Text(combo)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MuxyTheme.fgMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MuxyTheme.bg, in: Capsule())
                .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
