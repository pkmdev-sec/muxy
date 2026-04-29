import SwiftUI

struct WorkflowSavePromptState: Identifiable {
    let id = UUID()
    let draft: WorkflowMacro
}

struct WorkflowSavePrompt: View {
    let prompt: WorkflowSavePromptState
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    private var stepCount: Int { prompt.draft.steps.count }
    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDiscard() }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "play.square.stack")
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .font(.system(size: 13))
                    Text("Save Workflow")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                }

                Text("\(stepCount) \(stepCount == 1 ? "step" : "steps") captured")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)

                TextField("Name this workflow…", text: $name)
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

                HStack {
                    Spacer()
                    Button("Discard", action: onDiscard)
                        .keyboardShortcut(.cancelAction)
                    Button("Save", action: submit)
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .padding(16)
            .frame(width: 420, height: 180)
            .background(MuxyTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuxyTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .accessibilityAddTraits(.isModal)
            .background(EscapeKeyCatcher(onEscape: onDiscard))
        }
        .onAppear { focused = true }
    }

    private func submit() {
        let value = trimmedName
        guard !value.isEmpty else { return }
        onSave(value)
    }
}

private struct EscapeKeyCatcher: NSViewRepresentable {
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
