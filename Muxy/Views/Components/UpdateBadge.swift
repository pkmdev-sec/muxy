import SwiftUI

struct UpdateBadge: View {
    let version: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MuxyTheme.accent)
                    .shadow(
                        color: hovered ? MuxyGlass.accentGlow : Color.clear,
                        radius: hovered ? 3 : 0
                    )
                Text("Update \(version)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .background(
                Capsule()
                    .fill(MuxyTheme.accentSoft.opacity(hovered ? 1.0 : 0.65))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        MuxyTheme.accent.opacity(hovered ? 0.55 : 0.35),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: hovered ? MuxyGlass.accentGlow : MuxyGlass.ambientShadow,
                radius: hovered ? 6 : 2,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(MuxyMotion.hover) { hovered = isHovered }
        }
        .accessibilityLabel("Update available: version \(version)")
        .accessibilityHint("Activates to check for updates")
    }
}
