# Muxy Plugin API (v1)

Drop a `.js` file into `~/Library/Application Support/Muxy/Plugins/` and
run "Reload Plugins" from the Command Palette.

## The `muxy` global

Inside any plugin, the global `muxy` object exposes:

- `muxy.registerCommand({ id, title, subtitle?, symbol?, run })` —
  adds a palette entry. `run` is a zero-argument function invoked when
  the user selects the command. The palette entry is tagged
  `plugin.<filename>.<id>`.
- `muxy.log(message)` — writes to Muxy's unified log under
  `subsystem=app.muxy category=MuxyPluginHost`.
- `muxy.showToast(message)` — transient in-app toast.
- `muxy.postOSNotification(title, body)` — delivers a native macOS
  notification.

## Optional globals

Plugins can set `MUXY_PLUGIN_NAME` (display name) and
`MUXY_PLUGIN_VERSION` at the top level for nicer listing.

## Example: `hello.js`

```js
const MUXY_PLUGIN_NAME = "Hello World";
const MUXY_PLUGIN_VERSION = "0.1.0";

muxy.registerCommand({
  id: "say-hi",
  title: "Hello World -> Say Hi",
  subtitle: "Demo plugin palette entry",
  symbol: "hand.wave",
  run: function () {
    muxy.showToast("Hello from a Muxy plugin!");
    muxy.log("say-hi fired");
    muxy.postOSNotification("Muxy Plugin", "Hello from hello.js");
  },
});
```

Save as `~/Library/Application Support/Muxy/Plugins/hello.js`, then
in Muxy: `⌘⇧P` → "Reload Plugins" → `⌘⇧P` → "Hello World \u2192 Say Hi".

## Runtime

Plugins run in a JavaScriptCore `JSContext` that:
- Is created lazily per `.js` file on first `loadAll()`.
- Shares nothing between plugins — each file is sandboxed.
- Uses a `@unchecked Sendable` box (`PluginCallbackBox`) to cross the
  @MainActor boundary; JSC manages its own thread safety.
- Logs uncaught exceptions to the `MuxyPluginHost` logger.

## Limitations (v1)

- No access to `appState` / `projectStore` / `worktreeStore` yet —
  only toasts, notifications, and palette commands.
- No event subscriptions (file changes, notifications, pane output).
- No persistent state — plugins are re-evaluated on reload.

## Roadmap (v2+)

- `muxy.projects.list()` / `muxy.projects.activeID`
- `muxy.notifications.subscribe(handler)`
- `muxy.terminal.subscribe(paneID, handler)` (reads bytes via
  `TerminalOutputBus`)
- `muxy.agents.list()` / `muxy.agents.route(id, prompt)`
- Per-plugin preferences bag persisted to `~/Library/Application
  Support/Muxy/Plugins/<id>.prefs.json`
- TypeScript types published as `@muxy/plugin-api`
