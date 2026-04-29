import SwiftUI

struct ShortcutCheatSheetOverlay: View {
    let keyBindings: KeyBindingStore
    let onDismiss: () -> Void

    @State private var query: String = ""

    private var groupedEntries: [(category: String, entries: [ShortcutCheatSheetEntry])] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        var grouped: [String: [ShortcutCheatSheetEntry]] = [:]

        for action in ShortcutAction.allCases {
            let entry = ShortcutCheatSheetEntry(
                action: action,
                displayName: action.displayName,
                comboDisplay: keyBindings.combo(for: action).displayString,
                category: action.category
            )
            if !query.isEmpty {
                let haystack = (entry.displayName + " " + entry.comboDisplay + " " + entry.category).lowercased()
                guard haystack.contains(query) else { continue }
            }
            grouped[entry.category, default: []].append(entry)
        }

        for key in grouped.keys {
            grouped[key]?.sort { $0.displayName < $1.displayName }
        }

        return ShortcutAction.categories.compactMap { category in
            guard let entries = grouped[category], !entries.isEmpty else { return nil }
            return (category, entries)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header
                Divider().overlay(MuxyTheme.border)
                contentList
            }
            .frame(width: 620, height: 520)
            .background(MuxyTheme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MuxyTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityAddTraits(.isModal)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(MuxyTheme.fgMuted)
                .font(.system(size: 13))
            PaletteSearchField(
                text: $query,
                placeholder: "Filter shortcuts…",
                onSubmit: {},
                onEscape: { onDismiss() },
                onArrowUp: {},
                onArrowDown: {}
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var contentList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groupedEntries, id: \.category) { group in
                    sectionHeader(group.category)
                    ForEach(group.entries, id: \.action) { entry in
                        shortcutRow(entry)
                    }
                }
                if groupedEntries.isEmpty {
                    Text("No shortcuts match.")
                        .font(.system(size: 12))
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MuxyTheme.fgMuted)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcutRow(_ entry: ShortcutCheatSheetEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.displayName)
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fg)
            Spacer(minLength: 12)
            if entry.comboDisplay.isEmpty {
                Text("Unbound")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .italic()
            } else {
                Text(entry.comboDisplay)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MuxyTheme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(MuxyTheme.border, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }
}

private struct ShortcutCheatSheetEntry: Identifiable {
    let action: ShortcutAction
    let displayName: String
    let comboDisplay: String
    let category: String

    var id: ShortcutAction { action }
}
