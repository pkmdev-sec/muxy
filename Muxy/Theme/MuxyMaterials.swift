import AppKit
import SwiftUI

enum MuxyMaterials {
    @MainActor
    static var windowChrome: NSVisualEffectView.Material {
        MuxyTheme.colorScheme == .light ? .headerView : .sidebar
    }

    @MainActor
    static var sidebarChrome: NSVisualEffectView.Material {
        .sidebar
    }

    @MainActor
    static var popoverMaterial: NSVisualEffectView.Material {
        .hudWindow
    }

    @MainActor
    static var overlayMaterial: NSVisualEffectView.Material {
        .hudWindow
    }

    @MainActor
    static var sheetMaterial: NSVisualEffectView.Material {
        .underWindowBackground
    }

    @MainActor
    static var elevatedPanel: NSVisualEffectView.Material {
        .menu
    }
}

enum MuxyGlass {
    @MainActor static var topHighlight: Color {
        MuxyTheme.colorScheme == .light
            ? Color.white.opacity(0.55)
            : Color.white.opacity(0.08)
    }

    @MainActor static var bottomShade: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.02)
            : Color.black.opacity(0.12)
    }

    @MainActor static var borderSoft: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.10)
            : Color.white.opacity(0.07)
    }

    @MainActor static var borderStrong: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.16)
            : Color.white.opacity(0.12)
    }

    @MainActor static var shadow: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.12)
            : Color.black.opacity(0.35)
    }

    @MainActor static var ambientShadow: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.05)
            : Color.black.opacity(0.22)
    }

    @MainActor static var insetFill: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.04)
            : Color.white.opacity(0.04)
    }

    @MainActor static var hoverFill: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.06)
            : Color.white.opacity(0.07)
    }

    @MainActor static var pressedFill: Color {
        MuxyTheme.colorScheme == .light
            ? Color.black.opacity(0.11)
            : Color.white.opacity(0.13)
    }

    @MainActor static var selectionFill: Color {
        MuxyTheme.accent.opacity(MuxyTheme.colorScheme == .light ? 0.14 : 0.20)
    }

    @MainActor static var accentGlow: Color {
        MuxyTheme.accent.opacity(0.35)
    }
}

enum MuxyMotion {
    static let fast: Animation = .spring(response: 0.22, dampingFraction: 0.86, blendDuration: 0)
    static let standard: Animation = .spring(response: 0.32, dampingFraction: 0.84, blendDuration: 0)
    static let gentle: Animation = .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    static let hover: Animation = .easeOut(duration: 0.14)
    static let fade: Animation = .easeInOut(duration: 0.18)
}
