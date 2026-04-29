import SwiftUI

struct ScrollbackCheckpointPromptState: Identifiable {
    let id = UUID()
    let paneID: UUID
    let projectID: UUID?
}

struct ScrollbackCheckpointPrompt: View {
    let prompt: ScrollbackCheckpointPromptState
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var label: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .font(.system(size: 13))
                    Text("Checkpoint pane output")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                }

                TextField("Label this checkpoint…", text: $label)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MuxyTheme.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6).stroke(MuxyTheme.border, lineWidth: 1)
                    )
                    .focused($focused)
                    .onSubmit { submit() }

                Text("Captures current stream position for jump-to + export.")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
            .padding(16)
            .frame(width: 420, height: 140)
            .background(MuxyTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuxyTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .accessibilityAddTraits(.isModal)
            .background(
                KeyEventCatcher(onEscape: onDismiss)
            )
        }
        .onAppear { focused = true }
    }

    private func submit() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            onDismiss()
            return
        }
        onSubmit(trimmed)
        onDismiss()
    }
}

private struct KeyEventCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = EscapeCatcherView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EscapeCatcherView)?.onEscape = onEscape
    }
}

private final class EscapeCatcherView: NSView {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
