# Session Wins — New Feature Catalogue

This document catalogues 13 user-visible features added in a single focused engineering session, along with the minimum manual validation each one needs. Every feature is independently shippable.

## Quick Reference: New Shortcuts

| Shortcut | Action |
|---|---|
| `⌘⇧P` | Command Palette |
| `⌘⇧F` | Find in Project |
| `⌘⇧T` | Reopen Closed Tab |
| `⌘⇧Z` | Zoom Pane |
| `⌃⌘B` | Toggle Broadcast Input for Focused Pane |
| `⌃⇧⌘B` | Stop All Broadcasts |
| `⌘/` | Keyboard Shortcut Cheat Sheet |
| `⌃⌘R` | Rename Tab (re-aligned with `docs/architecture.md`) |
| `⌘⇧I` | Pin/Unpin Tab (moved from `⌘⇧T` to free it for Reopen Closed Tab) |

## Install & Iterate (Dev Build)

The repo ships `scripts/install-dev.sh` — one-command rebuild, ad-hoc sign, and install to `/Applications/Muxy (Dev).app`:

```bash
scripts/install-dev.sh           # build + install
scripts/install-dev.sh --launch  # build + install + open
```

The dev app sits alongside a stable `Muxy.app` install (if present), sharing the `com.muxy.app` bundle ID so projects, settings, themes, and approved mobile devices carry over automatically. Display name is `Muxy (Dev)` so Finder / Dock / Spotlight distinguish the two. Rollback is `rm -rf "/Applications/Muxy (Dev).app"`.

Warm-cache iteration cycle (kill running app + rebuild + ad-hoc sign + relaunch): **~3 seconds**.

## Feature-by-Feature Smoke Tests

### 1. Command Palette (`⌘⇧P`)
- Press `⌘⇧P`. Search field appears.
- Type "stage" — should see Source Control actions.
- Type "new tab" — runs via `ShortcutActionDispatcher`.
- After running, reopen — last-used command bubbles to top.

### 2. Hunk-Level Staging
- In a repo with uncommitted changes, open the VCS tab.
- Expand any file's diff.
- Each `@@ ... @@` divider shows a "Stage Hunk" pill on the right.
- Click it — that hunk is staged (moves to Staged section).
- Staged hunks show "Unstage Hunk" instead.

### 3. Reopen Closed Tab (`⌘⇧T`)
- Close any terminal/editor tab with `⌘W`.
- Press `⌘⇧T` — tab reopens in the same area with its custom title and pin state restored.
- Does NOT resurrect diff-viewer tabs (session-only by design).
- Entries purged when a project is removed.

### 4. Broadcast Input (`⌃⌘B`)
- Open 2+ terminal tabs.
- Focus one, press `⌃⌘B` — tab icon gets a radiowaves dot.
- Focus the other, press `⌃⌘B` — dot appears there too.
- Type in either — both receive the same keystrokes.
- `⌃⇧⌘B` clears all broadcasts.
- Right-click a terminal tab for menu entries.

### 5. AI Busy Indicator
- Trigger a Claude Code or OpenCode hook (or any `aiProvider(_)` notification) targeting a non-focused tab.
- That tab's icon shows a pulsing accent dot (radiating animation).
- Focus the tab — dot clears immediately.
- 10-minute freshness window — dot auto-fades.

### 6. Merge Conflict Resolver
- Create a merge conflict: `git checkout -b feature; echo "X" > f.txt; git add f.txt && git commit -m feat; git checkout -; echo "Y" > f.txt; git add f.txt && git commit -m main; git merge feature` (expect conflict).
- Open the VCS tab, expand the conflicted file.
- 2-column (or 3-column for diff3) view replaces the diff.
- Click "Keep Ours" / "Keep Theirs" / "Keep Both" — the region is resolved and the file auto-stages when all regions are handled.

### 7. Zoom Pane (`⌘⇧Z`)
- In a split workspace, focus any pane.
- Press `⌘⇧Z` — the split collapses to just that pane, with a "Zoomed" badge top-right.
- Press `⌘⇧Z` again (or click the badge) — the split layout restores.
- Hidden panes keep running processes alive.

### 8. Welcome View Redesign
- Remove all projects, or launch with fresh state.
- See the hero card with app icon + 6 shortcut cards (Command Palette, Quick Open, Reopen, Zoom, Broadcast, Source Control).

### 9. Find in Project (`⌘⇧F`)
- Press `⌘⇧F` — search overlay appears.
- Type 2+ characters — results stream in (git-grep in repos, grep fallback elsewhere).
- Click or press Enter on a result — file opens with the search bar pre-filled and the match highlighted.
- Press ⌘G in the editor to cycle through more matches in the same file.

### 10. Project-wide Replace
- Inside Find in Project, click the chevron to expand the Replace row.
- Type a replacement → "Replace All".
- Toast confirms `Replaced N in M files`.
- FSEvents watcher refreshes VCS status automatically.

### 11. File Context Palette Actions
- Open Command Palette, type "copy path" / "reveal" / "branch".
- Copy File Path, Copy Relative Path, Copy File Name, Reveal in Finder, Copy Project Path, Copy Worktree Path, Copy Current Branch.
- Each shows its value as the subtitle and posts a toast on completion.

### 12. Shortcut Cheat Sheet (`⌘/`)
- Press `⌘/` — 620x520 overlay lists every action grouped by category.
- Type to filter live; Esc dismisses.
- Unbound actions show "Unbound" in italic.

### 13. Hunk Patch Builder: Line-Level API
- Engine layer only; the UI slice is a follow-up (<1 day).
- Unit-tested via `GitPatchBuilderTests.lineLevelSelectAddition`, `...SelectDeletion`, `...SelectBoth`, `...EmptyReturnsNil`, `...NoOpSkipped`.

## New Cross-Cutting Services

| Service | Purpose | Testable |
|---|---|---|
| `CommandPalette` + `PaletteCommandSource` protocol | Registry-driven palette | 8 tests |
| `PaletteRecentsStore` | UserDefaults-backed LRU (12 items) | covered by CommandPalette suite |
| `BroadcastGroupStore` | Singleton tracking broadcasting paneIDs + reentry guard | 6 tests |
| `ClosedTabHistory` | LIFO of `ClosedTabRecord` (20 slots) | 5 tests |
| `GitPatchBuilder` | Hunk+line-level diff surgery for `git apply --cached` | 13 tests |
| `GitConflictParser` | Standard + diff3 marker parsing with resolution choices | 10 tests |
| `ProjectSearchService` | Streaming git-grep / grep + result parsing | 5 tests |
| `ProjectReplaceService` | Grouped-by-file atomic rewrite | 8 tests |

Total: **55 unit tests across 8 suites**.

## Call-Site Integration Points

Every feature ties into existing infrastructure without adding new ones:

- **ShortcutAction + KeyBinding + Dispatcher + Menu** — extended additively; every new enum case is handled, every default combo is unique, and every shortcut shows in the Cheat Sheet automatically.
- **Notification.Name** — three new names: `.toggleCommandPalette`, `.projectSearch`, `.showShortcutCheatSheet`.
- **PaletteOverlay / PaletteSearchField** — reused across Command Palette, Quick Open, Worktree Switcher, Find in Project, Cheat Sheet.
- **DiffGutterBridge / DiffSectionDivider** — extended with per-hunk Stage/Unstage affordances; base path unchanged.
- **WorkspaceReducer** — untouched. Zoom is render-layer only. Reopen goes through existing `createTab` actions.
- **AppState.openFile** — extended with defaulted `initialSearchNeedle:` parameter; every existing call site remains source-compatible.
- **GitProcessRunner.runGit** — extended with defaulted `stdin:` parameter for `git apply --cached` + `git apply --reverse`.

## What's NOT Shipped (Deferred Honestly)

1. **Persistent Terminals Daemon** — 4-6 weeks of careful work. Design doc delivered in first turn of session. Correct next step: extract `GhosttyHosting` protocol as a no-op refactor first.
2. **OSC 133 Shell Integration (Warp-style blocks)** — needs either a Ghostty fork export or a refactor of `RemoteTerminalStreamer` into a multi-consumer PTY tap. 2-3 days.
3. **Tree-sitter Editor** — replaces the regex grammars under `Muxy/Syntax/`. ~2 weeks for all currently-supported languages.
4. **Native SSH Profiles / Remote Projects** — extends `Project` with `remote: RemoteSpec?`. 1-2 weeks.
5. **Line-Level Staging UI** — engine shipped; gutter click UX is ~60 LOC in `DiffGutterBridge`.
6. **Global Quake Hotkey** — needs `NSEvent.addGlobalMonitorForEvents` wiring; not accessibility-safe without permission.
7. **Workspace Templates** — named layouts with `⌘⇧1/2/…` restore. Single session.
