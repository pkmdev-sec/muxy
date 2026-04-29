import SwiftUI

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        badgeShape
            .shadow(color: MuxyTheme.accent.opacity(0.6), radius: 3)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var badgeShape: some View {
        if count >= 2 {
            Text(displayText)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(MuxyTheme.accent))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
        } else {
            Circle()
                .fill(MuxyTheme.accent)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                )
        }
    }

    private var displayText: String {
        count > 99 ? "99+" : "\(count)"
    }

    private var accessibilityText: String {
        "\(count) unread notification\(count == 1 ? "" : "s")"
    }
}
