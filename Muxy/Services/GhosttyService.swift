import AppKit
import Foundation
import GhosttyKit
import os

private let logger = Logger(subsystem: "app.muxy", category: "GhosttyService")

@MainActor @Observable
final class GhosttyService {
    static let shared = GhosttyService()

    @ObservationIgnored private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private(set) var configVersion = 0
    @ObservationIgnored private let runtimeEvents: any GhosttyRuntimeEventHandling = GhosttyRuntimeEventAdapter()
    @ObservationIgnored private let muxyConfig: MuxyConfig
    @ObservationIgnored private var cachedBackground: NSColor?
    @ObservationIgnored private var cachedForeground: NSColor?
    @ObservationIgnored private var cachedAccent: NSColor?
    @ObservationIgnored private var cachedPalette: [Int: NSColor] = [:]

    private init(muxyConfig: MuxyConfig = .shared) {
        self.muxyConfig = muxyConfig
        initializeGhostty()
    }

    private func initializeGhostty() {
        resolveGhosttyResources()

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            logger.error("ghostty_init failed: \(String(describing: result))")
            return
        }

        guard let cfg = loadMuxyGhosttyConfig() else {
            logger.error("ghostty_config failed")
            return
        }

        var rt = ghostty_runtime_config_s()
        rt.userdata = Unmanaged.passUnretained(self).toOpaque()
        rt.supports_selection_clipboard = true
        rt.wakeup_cb = { _ in
            GhosttyService.shared.runtimeEvents.wakeup()
        }
        rt.action_cb = { app, target, action in
            GhosttyService.shared.runtimeEvents.action(app: app, target: target, action: action)
        }
        rt.read_clipboard_cb = { userdata, location, state in
            GhosttyService.shared.runtimeEvents.readClipboard(userdata: userdata, location: location, state: state)
        }
        rt.confirm_read_clipboard_cb = { userdata, content, state, _ in
            GhosttyService.shared.runtimeEvents.confirmReadClipboard(userdata: userdata, content: content, state: state)
        }
        rt.write_clipboard_cb = { _, location, content, len, _ in
            GhosttyService.shared.runtimeEvents.writeClipboard(location: location, content: content, len: UInt(len))
        }
        rt.close_surface_cb = { userdata, needsConfirm in
            GhosttyService.shared.runtimeEvents.closeSurface(userdata: userdata, needsConfirm: needsConfirm)
        }

        guard let createdApp = ghostty_app_new(&rt, cfg) else {
            logger.error("ghostty_app_new failed")
            ghostty_config_free(cfg)
            return
        }

        self.app = createdApp
        self.config = cfg
    }

    var backgroundColor: NSColor {
        if let cached = cachedBackground { return cached }
        let color = configColor("background") ?? NSColor(srgbRed: 0.098, green: 0.090, blue: 0.122, alpha: 1)
        cachedBackground = color
        return color
    }

    var foregroundColor: NSColor {
        if let cached = cachedForeground { return cached }
        let color = configColor("foreground") ?? .white
        cachedForeground = color
        return color
    }

    var accentColor: NSColor {
        if let cached = cachedAccent { return cached }
        let color = paletteColor(at: 4) ?? foregroundColor
        cachedAccent = color
        return color
    }

    func paletteColor(at index: Int) -> NSColor? {
        guard let config, index >= 0, index < 256 else { return nil }
        if let cached = cachedPalette[index] { return cached }
        var palette = ghostty_config_palette_s()
        guard ghostty_config_get(config, &palette, "palette", 7) else { return nil }
        let c = withUnsafePointer(to: &palette.colors) {
            $0.withMemoryRebound(to: ghostty_config_color_s.self, capacity: 256) { $0[index] }
        }
        let color = NSColor(
            srgbRed: CGFloat(c.r) / 255,
            green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255,
            alpha: 1
        )
        cachedPalette[index] = color
        return color
    }

    private func configColor(_ key: String) -> NSColor? {
        guard let config else { return nil }
        var color = ghostty_config_color_s()
        guard ghostty_config_get(config, &color, key, UInt(key.lengthOfBytes(using: .utf8))) else {
            return nil
        }
        return NSColor(
            srgbRed: CGFloat(color.r) / 255,
            green: CGFloat(color.g) / 255,
            blue: CGFloat(color.b) / 255,
            alpha: 1
        )
    }

    func reloadConfig() {
        guard let app else { return }
        guard let newConfig = loadMuxyGhosttyConfig() else { return }
        ghostty_app_update_config(app, newConfig)
        let oldConfig = self.config
        self.config = newConfig
        if let oldConfig { ghostty_config_free(oldConfig) }
        configVersion += 1
        invalidateColorCaches()
    }

    private func invalidateColorCaches() {
        cachedBackground = nil
        cachedForeground = nil
        cachedAccent = nil
        cachedPalette.removeAll(keepingCapacity: true)
    }

    private func loadMuxyGhosttyConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        let configPath = muxyConfig.ghosttyConfigPath
        configPath.withCString { ptr in
            ghostty_config_load_file(cfg, ptr)
        }
        ghostty_config_finalize(cfg)
        return cfg
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    nonisolated static func scheduleTick() {
        coalescedTickScheduler.schedule {
            MainActor.assumeIsolated {
                GhosttyService.shared.tick()
            }
        }
    }

    nonisolated static let coalescedTickScheduler = CoalescedTickScheduler()

    private static let allowedResourceParents = [
        "/Applications/Ghostty.app/Contents/Resources/ghostty",
        NSHomeDirectory() + "/Applications/Ghostty.app/Contents/Resources/ghostty",
    ]

    private func resolveGhosttyResources() {
        if let existing = getenv("GHOSTTY_RESOURCES_DIR").map({ String(cString: $0) }) {
            guard Self.allowedResourceParents.contains(where: { existing.hasPrefix($0) }) else {
                unsetenv("GHOSTTY_RESOURCES_DIR")
                return
            }
            return
        }

        for path in Self.allowedResourceParents {
            guard FileManager.default.fileExists(atPath: path + "/shell-integration") else { continue }
            setenv("GHOSTTY_RESOURCES_DIR", path, 1)
            return
        }
    }
}

final class CoalescedTickScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false

    func schedule(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        if pending {
            lock.unlock()
            return
        }
        pending = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.lock.lock()
            self?.pending = false
            self?.lock.unlock()
            work()
        }
    }
}
