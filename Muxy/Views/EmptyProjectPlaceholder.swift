import SwiftUI

struct EmptyProjectPlaceholder: View {
    let project: Project
    let onCreateTab: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            backdrop
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                iconHero
                VStack(spacing: 6) {
                    Text("No tabs in \(project.name)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(MuxyTheme.fg)
                    Text("Open a new terminal to start working in this project.")
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }

                primaryButton
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.98)
            .animation(MuxyMotion.gentle, value: appeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }

    private var iconHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MuxyTheme.accent.opacity(MuxyTheme.colorScheme == .light ? 0.12 : 0.18))
                .frame(width: 96, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(MuxyGlass.topHighlight, lineWidth: 1)
                        .blendMode(MuxyTheme.colorScheme == .light ? .normal : .plusLighter)
                )
                .shadow(color: MuxyTheme.accent.opacity(0.35), radius: 24, y: 6)

            Image(systemName: "macwindow.badge.plus")
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

    private var primaryButton: some View {
        Button(action: onCreateTab) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New Tab")
                    .font(.system(size: 12, weight: .semibold))
                Text(KeyBindingStore.shared.combo(for: .newTab).displayString)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.72)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [MuxyTheme.accent, MuxyTheme.accent.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: MuxyTheme.accent.opacity(0.45), radius: 10, y: 3)
            }
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    private var backdrop: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [
                        MuxyTheme.accent.opacity(0.12),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: max(geo.size.width, geo.size.height) * 0.6
                )
            }
        }
        .blendMode(MuxyTheme.colorScheme == .light ? .normal : .plusLighter)
    }
}
