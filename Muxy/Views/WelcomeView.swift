import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            WindowDragRepresentable()
                .frame(height: 32)
            Spacer(minLength: 24)
            content
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }

    private var content: some View {
        VStack(spacing: 24) {
            iconHero

            VStack(spacing: 8) {
                Text("Welcome to Muxy")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(MuxyTheme.fg)

                Text("A native macOS terminal multiplexer.\nAdd a project folder to begin.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .frame(maxWidth: 360)
            }

            addProjectButton
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(MuxyMotion.gentle, value: appeared)
        .padding(.horizontal, 32)
    }

    private var iconHero: some View {
        ZStack {
            Circle()
                .fill(MuxyTheme.accent.opacity(MuxyTheme.colorScheme == .light ? 0.10 : 0.18))
                .frame(width: 108, height: 108)
                .blur(radius: 10)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MuxyTheme.accent.opacity(MuxyTheme.colorScheme == .light ? 0.12 : 0.18))
                .frame(width: 96, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(MuxyGlass.topHighlight, lineWidth: 1)
                        .blendMode(MuxyTheme.colorScheme == .light ? .normal : .plusLighter)
                )
                .shadow(color: MuxyTheme.accent.opacity(0.35), radius: 24, y: 6)

            Image(systemName: "terminal.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            MuxyTheme.accent,
                            MuxyTheme.accent.opacity(0.65),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private var addProjectButton: some View {
        Button {
            ProjectOpenService.openProject(
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 12, weight: .bold))
                Text("Add Project")
                    .font(.system(size: 13, weight: .semibold))
                Text(KeyBindingStore.shared.combo(for: .openProject).displayString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.72)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [MuxyTheme.accent, MuxyTheme.accent.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: MuxyTheme.accent.opacity(0.45), radius: 12, y: 4)
            }
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }
}
