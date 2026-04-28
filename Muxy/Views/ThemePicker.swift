import SwiftUI

struct ThemePicker: View {
    @Environment(ThemeService.self) private var themeService
    @State private var themes: [ThemePreview] = []
    @State private var currentTheme: String?

    var body: some View {
        SearchableListPicker(
            items: themes,
            filterKey: \.name,
            placeholder: "Search themes",
            emptyLabel: "No themes found",
            onSelect: { selectTheme($0) },
            row: { theme, isHighlighted in
                ThemeRow(
                    theme: theme,
                    isActive: theme.name == currentTheme,
                    isHighlighted: isHighlighted
                )
            }
        )
        .frame(width: 280, height: 400)
        .task {
            themes = await themeService.loadThemes()
            currentTheme = themeService.currentThemeName()
        }
    }

    private func selectTheme(_ theme: ThemePreview) {
        currentTheme = theme.name
        themeService.applyTheme(theme.name)
    }
}

private struct ThemeRow: View {
    let theme: ThemePreview
    let isActive: Bool
    let isHighlighted: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(theme.name)
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fg)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MuxyTheme.accent)
                }
            }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(nsColor: theme.background))
                    .overlay(
                        Text("Ab")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(nsColor: theme.foreground))
                    )
                    .frame(width: 24)

                ForEach(Array(theme.palette.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(Color(nsColor: color))
                }
            }
            .frame(height: 14)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(MuxyGlass.borderSoft, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowFill)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .onHover { hovered = $0 }
    }

    private var rowFill: Color {
        if isHighlighted { return MuxyGlass.selectionFill }
        if hovered { return MuxyGlass.hoverFill }
        return Color.clear
    }
}
