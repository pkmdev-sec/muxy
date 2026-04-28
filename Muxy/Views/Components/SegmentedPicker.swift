import SwiftUI

struct SegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                segmentButton(for: option)

                if index < options.count - 1, selection != option.value,
                   selection != options[index + 1].value
                {
                    Rectangle()
                        .fill(MuxyGlass.borderSoft)
                        .frame(width: 0.5, height: 14)
                        .opacity(0.8)
                }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(MuxyGlass.insetFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(MuxyGlass.borderSoft, lineWidth: 0.5)
        )
        .accessibilityRepresentation {
            Picker(selection: $selection, label: EmptyView()) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Text(option.label).tag(option.value)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentButton(for option: (value: T, label: String)) -> some View {
        let active = selection == option.value

        Button {
            selection = option.value
        } label: {
            Text(option.label)
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? MuxyTheme.fg : MuxyTheme.fgMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(segmentBackground(active: active))
                .overlay(segmentBorder(active: active))
                .animation(MuxyMotion.fast, value: active)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func segmentBackground(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            MuxyGlass.topHighlight.opacity(0.45),
                            MuxyGlass.hoverFill,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func segmentBorder(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(MuxyGlass.borderSoft, lineWidth: 0.5)
        }
    }
}
