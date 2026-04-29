import SwiftUI

struct FileWatchWirePromptState: Identifiable, Sendable {
    let id = UUID()
    let sourceNodeID: UUID
    let targetNodeID: UUID
}

struct FileWatchWirePrompt: View {
    let prompt: FileWatchWirePromptState
    let onSubmit: (_ command: String, _ glob: String?) -> Void
    let onDismiss: () -> Void

    @State private var command: String = ""
    @State private var glob: String = ""

    var body: some View {
        ZStack {
            MuxyOverlayScrim(onDismiss: onDismiss)
            GlassPanel(
                material: MuxyMaterials.overlayMaterial,
                cornerRadius: 14,
                elevation: .overlay
            ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.accent)
                    Text("File-watch wire")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fg)
                }
                Text("Runs the command in the target pane whenever a file under the project changes.")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)
                TextField("Command (e.g. swift test or npm run lint)", text: $command)
                    .textFieldStyle(.roundedBorder)
                TextField("Glob filter (optional, e.g. *.swift,*.md)", text: $glob)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { onDismiss() }
                        .keyboardShortcut(.escape)
                    Button("Create") {
                        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedCommand.isEmpty else { return }
                        let trimmedGlob = glob.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSubmit(trimmedCommand, trimmedGlob.isEmpty ? nil : trimmedGlob)
                    }
                    .keyboardShortcut(.return)
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
            }
            .frame(width: 440)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }
}
