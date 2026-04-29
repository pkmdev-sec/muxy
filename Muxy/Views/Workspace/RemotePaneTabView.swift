import SwiftUI

struct RemotePaneTabView: View {
    let state: RemotePaneTabState
    let focused: Bool
    let onFocus: () -> Void

    @State private var autoScroll = true
    private let client = PeerClient.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MuxyTheme.border)
            content
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .onAppear { attachIfNeeded() }
        .onDisappear { detach() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(state.isAttached ? .green : MuxyTheme.fgMuted)
                .font(.system(size: 12, weight: .semibold))
            Text(state.peerDeviceName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("\u{2190}")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text(state.projectName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .clipShape(Capsule())
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
            Button {
                state.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
            .buttonStyle(.plain)
            .help("Clear buffer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusLabel: String {
        state.isAttached ? "Streaming" : "Disconnected"
    }

    private var statusColor: Color {
        state.isAttached ? .green : .red
    }

    @ViewBuilder
    private var content: some View {
        if state.buffer.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for output from \(state.peerDeviceName)\u{2026}")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgMuted)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    Text(state.buffer)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(MuxyTheme.fg)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .id("remote-pane-bottom")
                }
                .onChange(of: state.buffer) { _, _ in
                    guard autoScroll else { return }
                    withAnimation(.linear(duration: 0.05)) {
                        scrollProxy.scrollTo("remote-pane-bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func attachIfNeeded() {
        guard client.state.isConnected else {
            state.isAttached = false
            return
        }
        client.subscribeTerminal(paneID: state.remotePaneID) { bytes in
            state.appendBytes(bytes)
        }
        state.isAttached = true
        Task {
            await client.takeOverPane(paneID: state.remotePaneID)
        }
    }

    private func detach() {
        client.unsubscribeTerminal(paneID: state.remotePaneID)
        state.isAttached = false
        Task {
            await client.releasePane(paneID: state.remotePaneID)
        }
    }
}
