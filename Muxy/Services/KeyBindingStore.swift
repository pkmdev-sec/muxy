import AppKit
import os

private let logger = Logger(subsystem: "app.muxy", category: "KeyBindingStore")

@MainActor
@Observable
final class KeyBindingStore {
    static let shared = KeyBindingStore()

    private(set) var bindings: [KeyBinding] = []
    private let persistence: any KeyBindingPersisting
    @ObservationIgnored private var lookupCache: [LookupKey: ShortcutAction] = [:]
    @ObservationIgnored private var cacheVersion: Int = 0

    private struct LookupKey: Hashable {
        let key: String
        let modifiers: UInt
        let scopes: UInt8
    }

    init(persistence: any KeyBindingPersisting = FileKeyBindingPersistence()) {
        self.persistence = persistence
        load()
        rebuildLookupCache()
    }

    func binding(for action: ShortcutAction) -> KeyBinding {
        bindings.first { $0.action == action }
            ?? KeyBinding.defaults.first { $0.action == action }
            ?? KeyBinding(action: action, combo: KeyCombo(key: "", modifiers: 0))
    }

    func combo(for action: ShortcutAction) -> KeyCombo {
        binding(for: action).combo
    }

    func updateBinding(action: ShortcutAction, combo: KeyCombo) {
        guard let index = bindings.firstIndex(where: { $0.action == action }) else { return }
        bindings[index].combo = combo
        rebuildLookupCache()
        save()
    }

    func resetToDefaults() {
        bindings = KeyBinding.defaults
        rebuildLookupCache()
        save()
    }

    func resetBinding(action: ShortcutAction) {
        guard let defaultBinding = KeyBinding.defaults.first(where: { $0.action == action }) else { return }
        updateBinding(action: defaultBinding.action, combo: defaultBinding.combo)
    }

    func isRegisteredShortcut(event: NSEvent, scopes: Set<ShortcutScope>) -> Bool {
        action(for: event, scopes: scopes) != nil
    }

    func action(for event: NSEvent, scopes: Set<ShortcutScope>) -> ShortcutAction? {
        let normalizedKey = KeyCombo.normalized(
            key: event.charactersIgnoringModifiers ?? "",
            keyCode: event.keyCode
        )
        let flags = event.modifierFlags.intersection(KeyCombo.supportedModifierMask).rawValue
        let lookupKey = LookupKey(
            key: normalizedKey,
            modifiers: flags,
            scopes: Self.scopesMask(scopes)
        )
        return lookupCache[lookupKey]
    }

    private static func scopesMask(_ scopes: Set<ShortcutScope>) -> UInt8 {
        var mask: UInt8 = 0
        for scope in scopes {
            switch scope {
            case .global: mask |= 0b01
            case .mainWindow: mask |= 0b10
            }
        }
        return mask
    }

    private func rebuildLookupCache() {
        var cache: [LookupKey: ShortcutAction] = [:]
        cache.reserveCapacity(bindings.count * 2)
        for binding in bindings {
            let combo = binding.combo
            let normalizedKey = KeyCombo.normalized(key: combo.key)
            let flags = KeyCombo.normalized(modifiers: combo.modifiers)
            guard !normalizedKey.isEmpty else { continue }
            let scope = binding.action.scope
            let scopeBit: UInt8 = scope == .global ? 0b01 : 0b10
            let allScopesMask: UInt8 = 0b11
            var mask: UInt8 = scopeBit
            while true {
                cache[LookupKey(key: normalizedKey, modifiers: flags, scopes: mask)] = binding.action
                if mask == allScopesMask { break }
                mask |= allScopesMask
            }
        }
        lookupCache = cache
        cacheVersion &+= 1
    }

    func conflictingAction(for combo: KeyCombo, excluding: ShortcutAction) -> ShortcutAction? {
        bindings.first { $0.combo == combo && $0.action != excluding }?.action
    }

    private func load() {
        do {
            bindings = try persistence.loadBindings()
        } catch {
            logger.error("Failed to load key bindings: \(error.localizedDescription)")
            bindings = KeyBinding.defaults
        }
        rebuildLookupCache()
    }

    private func save() {
        do {
            try persistence.saveBindings(bindings)
        } catch {
            logger.error("Failed to save key bindings: \(error.localizedDescription)")
        }
    }
}
