import AppKit
import SwiftUI

enum GlassElevation {
    case flat
    case raised
    case floating
    case overlay

    var shadowRadius: CGFloat {
        switch self {
        case .flat: 0
        case .raised: 6
        case .floating: 14
        case .overlay: 28
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .flat: 0
        case .raised: 2
        case .floating: 6
        case .overlay: 14
        }
    }

    var ambientRadius: CGFloat {
        switch self {
        case .flat: 0
        case .raised: 2
        case .floating: 4
        case .overlay: 8
        }
    }
}

struct GlassPanel<Content: View>: View {
    var material: NSVisualEffectView.Material?
    var cornerRadius: CGFloat = 12
    var elevation: GlassElevation = .floating
    var showsHighlight: Bool = true
    var showsBorder: Bool = true
    var paddingInsets: EdgeInsets = .init()
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(paddingInsets)
            .background {
                GlassPanelBackground(
                    material: material ?? MuxyMaterials.popoverMaterial,
                    cornerRadius: cornerRadius,
                    showsHighlight: showsHighlight,
                    showsBorder: showsBorder
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: MuxyGlass.shadow,
                radius: elevation.shadowRadius,
                y: elevation.shadowY
            )
            .shadow(
                color: MuxyGlass.ambientShadow,
                radius: elevation.ambientRadius,
                y: 0
            )
    }
}

struct GlassPanelBackground: View {
    let material: NSVisualEffectView.Material
    let cornerRadius: CGFloat
    var showsHighlight: Bool = true
    var showsBorder: Bool = true

    var body: some View {
        ZStack {
            VisualEffectView(
                material: material,
                blendingMode: .behindWindow,
                state: .followsWindowActiveState,
                isMaskingEnabled: true,
                cornerRadius: cornerRadius
            )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(MuxyTheme.bg.opacity(MuxyTheme.colorScheme == .light ? 0.15 : 0.32))

            if showsHighlight {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                MuxyGlass.topHighlight,
                                Color.clear,
                                MuxyGlass.bottomShade,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .blendMode(MuxyTheme.colorScheme == .light ? .normal : .plusLighter)
                    .opacity(0.85)
            }

            if showsBorder {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(MuxyGlass.borderSoft, lineWidth: 0.5)
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 10
    var padding: CGFloat = 14
    var elevation: GlassElevation = .raised
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MuxyGlass.insetFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(MuxyGlass.borderSoft, lineWidth: 0.5)
                    )
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [MuxyGlass.topHighlight, Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1
                            )
                            .blendMode(MuxyTheme.colorScheme == .light ? .normal : .plusLighter)
                            .opacity(0.7)
                    }
            }
            .shadow(color: MuxyGlass.ambientShadow, radius: elevation.ambientRadius, y: 1)
    }
}

struct GlassChip: View {
    let symbol: String?
    let text: String
    var tint: Color?
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.2)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(background, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }

    private var resolvedTint: Color { tint ?? MuxyTheme.accent }

    private var foreground: Color {
        emphasized ? Color.white : resolvedTint
    }

    private var background: AnyShapeStyle {
        if emphasized {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [resolvedTint, resolvedTint.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(resolvedTint.opacity(MuxyTheme.colorScheme == .light ? 0.12 : 0.18))
    }

    private var borderColor: Color {
        emphasized ? Color.white.opacity(0.22) : resolvedTint.opacity(0.32)
    }
}
