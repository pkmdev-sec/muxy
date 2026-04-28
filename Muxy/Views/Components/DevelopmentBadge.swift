import SwiftUI

struct DevelopmentBadge: View {
    var body: some View {
        Text("DEV")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange,
                                Color(red: 1.0, green: 0.72, blue: 0.25),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
            )
            .shadow(color: Color.orange.opacity(0.35), radius: 3, y: 1)
            .allowsHitTesting(false)
    }
}
