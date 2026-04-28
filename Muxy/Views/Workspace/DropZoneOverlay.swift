import SwiftUI

struct DropZoneHighlight: View {
    let zone: DropZone

    var body: some View {
        GeometryReader { geo in
            let rect = highlightRect(in: geo.size)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MuxyTheme.accent.opacity(0.22),
                            MuxyTheme.accent.opacity(0.10),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(MuxyTheme.accent.opacity(0.65), lineWidth: 1.25)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [MuxyGlass.topHighlight, Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1
                        )
                        .blendMode(MuxyTheme.colorScheme == .light ? .normal : .plusLighter)
                )
                .shadow(color: MuxyTheme.accent.opacity(0.35), radius: 10, y: 0)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: zone)
        .accessibilityHidden(true)
    }

    private func highlightRect(in size: CGSize) -> CGRect {
        let inset: CGFloat = 4
        switch zone {
        case .left:
            return CGRect(x: inset, y: inset, width: size.width / 2 - inset * 1.5, height: size.height - inset * 2)
        case .right:
            let halfW = size.width / 2 + inset * 0.5
            return CGRect(x: halfW, y: inset, width: size.width - halfW - inset, height: size.height - inset * 2)
        case .top:
            return CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height / 2 - inset * 1.5)
        case .bottom:
            let halfH = size.height / 2 + inset * 0.5
            return CGRect(x: inset, y: halfH, width: size.width - inset * 2, height: size.height - halfH - inset)
        case .center:
            return CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        }
    }
}

typealias AreaFramePreferenceKey = UUIDFramePreferenceKey<AreaFrameTag>
