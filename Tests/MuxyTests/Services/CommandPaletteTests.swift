import Foundation
import Testing

@testable import Muxy

@MainActor
@Suite("CommandPalette")
struct CommandPaletteTests {
    private func makeCommand(
        id: String,
        title: String,
        subtitle: String? = nil,
        group: PaletteCommandGroup = .action
    ) -> PaletteCommand {
        PaletteCommand(
            id: id,
            title: title,
            subtitle: subtitle,
            symbol: "command",
            group: group,
            shortcut: nil,
            run: {}
        )
    }

    private struct StaticSource: PaletteCommandSource {
        let commandsList: [PaletteCommand]
        func commands() -> [PaletteCommand] { commandsList }
    }

    private func makeTransientRecents() -> PaletteRecentsStore {
        PaletteRecentsStore.shared.clear()
        return PaletteRecentsStore.shared
    }

    @Test("empty query ranks by group weight then title")
    func emptyQueryGroupOrder() {
        _ = makeTransientRecents()
        let palette = CommandPalette(sources: [
            StaticSource(commandsList: [
                makeCommand(id: "z", title: "Zeta", group: .settings),
                makeCommand(id: "a", title: "Alpha", group: .action),
                makeCommand(id: "b", title: "Beta", group: .action),
            ]),
        ])
        let ids = palette.matches(for: "").map(\.command.id)
        #expect(ids == ["a", "b", "z"])
    }

    @Test("recent commands bubble to the top with empty query")
    func recentsBubble() {
        let recents = makeTransientRecents()
        let cmds = [
            makeCommand(id: "a", title: "Alpha"),
            makeCommand(id: "b", title: "Beta"),
            makeCommand(id: "c", title: "Gamma"),
        ]
        let palette = CommandPalette(sources: [StaticSource(commandsList: cmds)], recents: recents)
        recents.bump("c")
        recents.bump("b")
        let ids = palette.matches(for: "").map(\.command.id)
        #expect(ids.prefix(2) == ["b", "c"])
    }

    @Test("fuzzy scorer prefers prefix matches over scattered ones")
    func fuzzyPrefers() {
        _ = makeTransientRecents()
        let palette = CommandPalette(sources: [
            StaticSource(commandsList: [
                makeCommand(id: "a", title: "Close Tab"),
                makeCommand(id: "b", title: "Connection Logs"),
                makeCommand(id: "c", title: "Currency Calculator"),
            ]),
        ])
        let ids = palette.matches(for: "clo").map(\.command.id)
        #expect(ids.first == "a")
    }

    @Test("fuzzy scorer finds scattered matches")
    func fuzzyScatter() {
        _ = makeTransientRecents()
        let palette = CommandPalette(sources: [
            StaticSource(commandsList: [
                makeCommand(id: "a", title: "Pin Active Tab"),
                makeCommand(id: "b", title: "Random Unrelated"),
            ]),
        ])
        let ids = palette.matches(for: "pat").map(\.command.id)
        #expect(ids.contains("a"))
        #expect(!ids.contains("b"))
    }

    @Test("unknown query returns empty")
    func unknownQuery() {
        _ = makeTransientRecents()
        let palette = CommandPalette(sources: [
            StaticSource(commandsList: [makeCommand(id: "a", title: "Alpha")]),
        ])
        #expect(palette.matches(for: "zzzz").isEmpty)
    }

    @Test("duplicate ids across sources collapse to first instance")
    func deduplicatesIds() {
        _ = makeTransientRecents()
        let shared = makeCommand(id: "same", title: "First")
        let other = makeCommand(id: "same", title: "Second")
        let palette = CommandPalette(sources: [
            StaticSource(commandsList: [shared]),
            StaticSource(commandsList: [other]),
        ])
        let results = palette.matches(for: "")
        #expect(results.count == 1)
        #expect(results.first?.command.title == "First")
    }

    @Test("run bumps recents and invokes the closure")
    func runBumpsAndInvokes() {
        let recents = makeTransientRecents()
        var called = 0
        let cmd = PaletteCommand(
            id: "boom",
            title: "Boom",
            subtitle: nil,
            symbol: "command",
            group: .action,
            shortcut: nil,
            run: { called += 1 }
        )
        let palette = CommandPalette(sources: [StaticSource(commandsList: [cmd])], recents: recents)
        palette.run(cmd)
        #expect(called == 1)
        #expect(recents.recent().first == "boom")
    }

    @Test("recents store caps at the configured limit")
    func recentsLimit() {
        let recents = makeTransientRecents()
        for i in 0 ..< 20 {
            recents.bump("id\(i)")
        }
        #expect(recents.recent().count <= 12)
        #expect(recents.recent().first == "id19")
    }
}
