import SwiftUI

struct WorkflowRecordingBanner: View {
    let stepCount: Int
    let onStop: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .opacity(pulse ? 0.35 : 1.0)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)

            Text("Recording · \(stepCount) \(stepCount == 1 ? "step" : "steps")")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)

            Rectangle()
                .fill(MuxyTheme.border)
                .frame(width: 1, height: 14)

            Button(action: onStop) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording and save workflow")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(MuxyTheme.bg.opacity(0.95), in: Capsule())
        .overlay(Capsule().stroke(Color.red.opacity(0.65), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(.top, 44)
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
    }
}
