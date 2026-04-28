import SwiftUI

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var color: Color = MuxyTheme.fgMuted
    var hoverColor: Color = MuxyTheme.fg
    let accessibilityLabel: String
    let action: () -> Void
    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 24, height: 24)
                .background(backgroundFill)
                .contentShape(Rectangle())
                .scaleEffect(pressed ? 0.92 : 1)
                .animation(MuxyMotion.fast, value: pressed)
                .animation(MuxyMotion.hover, value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundColor: Color {
        hovered || pressed ? hoverColor : color
    }

    @ViewBuilder
    private var backgroundFill: some View {
        if hovered {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(MuxyGlass.hoverFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(MuxyGlass.borderSoft, lineWidth: 0.5)
                )
                .padding(2)
        }
    }
}
