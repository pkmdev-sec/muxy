import Foundation
import os

private let paneWireLogger = Logger(subsystem: "app.muxy", category: "PaneWireBus")

@MainActor
@Observable
final class PaneWireBus {
    static let shared = PaneWireBus()

    private struct Wiring {
        let wireID: UUID
        let canvasID: UUID
        let sourcePaneID: UUID
        let targetPaneID: UUID
        let kind: AgentCanvasWireKind
        let subscription: TerminalOutputSubscription?
        let matcher: PromptRelayMatcher?
        let fileWatcher: FileWatchStream?
    }

    @ObservationIgnored private var wiringByID: [UUID: Wiring] = [:]

    private init() {}

    func activate(wire: AgentCanvasWire, on canvas: AgentCanvasState) {
        guard let source = canvas.node(id: wire.sourceNodeID),
              let target = canvas.node(id: wire.targetNodeID),
              let sourcePaneID = source.paneID,
              let targetPaneID = target.paneID
        else {
            paneWireLogger.info("Skipping activation: wire missing source/target paneID")
            return
        }
        if wiringByID[wire.id] != nil { return }

        let canvasID = canvas.id
        let wireID = wire.id
        let kind = wire.kind

        if kind == .keystrokeBroadcast {
            BroadcastGroupStore.shared.add(sourcePaneID)
            BroadcastGroupStore.shared.add(targetPaneID)
            wiringByID[wire.id] = Wiring(
                wireID: wireID,
                canvasID: canvasID,
                sourcePaneID: sourcePaneID,
                targetPaneID: targetPaneID,
                kind: kind,
                subscription: nil,
                matcher: nil,
                fileWatcher: nil
            )
            return
        }

        if kind == .fileWatch {
            guard let watcher = makeFileWatcher(wire: wire, canvas: canvas, targetPaneID: targetPaneID) else {
                paneWireLogger.info("File watch wire requires fileWatchCommand and a valid project path")
                return
            }
            wiringByID[wire.id] = Wiring(
                wireID: wireID,
                canvasID: canvasID,
                sourcePaneID: sourcePaneID,
                targetPaneID: targetPaneID,
                kind: kind,
                subscription: nil,
                matcher: nil,
                fileWatcher: watcher
            )
            return
        }

        let matcher = (kind == .promptRelay) ? PromptRelayMatcher() : nil

        let context = WiringContext(
            wireID: wireID,
            canvasID: canvasID,
            sourcePaneID: sourcePaneID,
            targetPaneID: targetPaneID,
            kind: kind
        )
        let subscription = TerminalOutputBus.shared.subscribe(paneID: sourcePaneID) { [weak self] data, _ in
            self?.dispatch(context: context, matcher: matcher, data: data)
        }

        wiringByID[wire.id] = Wiring(
            wireID: wireID,
            canvasID: canvasID,
            sourcePaneID: sourcePaneID,
            targetPaneID: targetPaneID,
            kind: kind,
            subscription: subscription,
            matcher: matcher,
            fileWatcher: nil
        )
    }

    private func makeFileWatcher(
        wire: AgentCanvasWire,
        canvas: AgentCanvasState,
        targetPaneID: UUID
    ) -> FileWatchStream? {
        let trimmedCommand = (wire.fileWatchCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return nil }
        let glob = wire.fileWatchGlob?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rootPath = canvas.projectPath
        return FileWatchStream(rootPath: rootPath, glob: glob) { _ in
            Task { @MainActor in
                guard let view = TerminalViewRegistry.shared.view(for: targetPaneID), view.hasLiveSurface else { return }
                view.sendText(trimmedCommand)
                view.sendReturnKey()
            }
        }
    }

    func deactivate(wireID: UUID) {
        guard let wiring = wiringByID.removeValue(forKey: wireID) else { return }
        if let subscription = wiring.subscription {
            TerminalOutputBus.shared.unsubscribe(subscription)
        }
        if wiring.kind == .keystrokeBroadcast {
            if !hasAnotherBroadcast(forPaneID: wiring.sourcePaneID, excluding: wireID) {
                BroadcastGroupStore.shared.remove(wiring.sourcePaneID)
            }
            if !hasAnotherBroadcast(forPaneID: wiring.targetPaneID, excluding: wireID) {
                BroadcastGroupStore.shared.remove(wiring.targetPaneID)
            }
        }
    }

    private func hasAnotherBroadcast(forPaneID paneID: UUID, excluding wireID: UUID) -> Bool {
        wiringByID.values.contains { existing in
            guard existing.kind == .keystrokeBroadcast, existing.wireID != wireID else { return false }
            return existing.sourcePaneID == paneID || existing.targetPaneID == paneID
        }
    }

    func deactivateAll(canvasID: UUID) {
        let toRemove = wiringByID.values.filter { $0.canvasID == canvasID }
        for wiring in toRemove {
            deactivate(wireID: wiring.wireID)
        }
    }

    func deactivateAll() {
        let ids = Array(wiringByID.keys)
        for id in ids {
            deactivate(wireID: id)
        }
    }

    func isActive(wireID: UUID) -> Bool {
        wiringByID[wireID] != nil
    }

    private struct WiringContext: Sendable {
        let wireID: UUID
        let canvasID: UUID
        let sourcePaneID: UUID
        let targetPaneID: UUID
        let kind: AgentCanvasWireKind
    }

    private func dispatch(context: WiringContext, matcher: PromptRelayMatcher?, data: Data) {
        switch context.kind {
        case .promptRelay:
            guard let matcher else { return }
            let matches = matcher.ingest(data)
            for match in matches {
                relay(match: match, targetPaneID: context.targetPaneID)
            }
        case .keystrokeBroadcast:
            paneWireLogger.debug("Keystroke broadcast via bus is not yet implemented")
        case .fileWatch:
            paneWireLogger.debug("File-watch wire receives no pty bytes directly")
        case .mirror:
            paneWireLogger.debug("Mirror wire needs ghostty_surface_inject_output export")
        }
    }

    private func relay(match: PromptRelayMatch, targetPaneID: UUID) {
        guard !match.body.isEmpty else { return }
        guard let view = TerminalViewRegistry.shared.view(for: targetPaneID), view.hasLiveSurface else {
            paneWireLogger.info("Target pane not live; dropping relay")
            return
        }
        view.sendText(match.body)
        view.sendReturnKey()
    }
}
