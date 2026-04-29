# ghostty_surface_inject_output

Additive C export for embedders implementing cross-surface output mirroring.
Parallels `ghostty_surface_send_input_raw` in shape. Unlocks Muxy's "Mirror
wire" feature in Agent Canvas — one pane renders another pane's byte-for-byte
output without spawning a second shell or writing a VT parser in Swift.

## PR Title

`embedded: add ghostty_surface_inject_output for cross-surface mirroring`

## PR Description

This patch adds a single new C export, `ghostty_surface_inject_output`, that
feeds raw bytes into a surface's terminal emulator **as if they had been read
from its PTY**. Intended for embedders (such as Muxy) that implement
cross-surface mirroring by teeing one surface's `set_data_callback` into the
emulator of another surface.

Strictly additive:

- **Three new `termio.Message` variants** that parallel `write_{small,stable,alloc}`.
- **Three matching arms** in the termio mailbox drain loop that call
  `Termio.processOutput` (rather than PTY write).
- **One new C export** in `src/apprt/embedded.zig`.
- **One new line** in `include/ghostty.h`.

No existing code path is touched. `@sizeOf(Message)` is unchanged (new
variants reuse `WriteReq.*` payload shapes). Routing through the termio
mailbox — rather than calling `processOutput` directly — ensures correct
ordering with real PTY reads and reuses existing `WriteReq` allocation
patterns.

Mirror surfaces should be placed in read-only mode on the embedder side so
keystrokes don't reach the mirror's own PTY; the mirror still renders the
source's screen state (cursor position, alt-screen, DECSET modes) byte-for-byte.

## Patch (unified diff)

```diff
diff --git a/src/termio/message.zig b/src/termio/message.zig
--- a/src/termio/message.zig
+++ b/src/termio/message.zig
 pub const Message = union(enum) {
     pub const WriteReq = MessageData(u8, 38);

     color_scheme_report: struct { force: bool, },
     crash: void,
     change_config: struct { alloc: Allocator, ptr: *termio.Termio.DerivedConfig, },
     inspector: bool,
     resize: renderer.Size,
     size_report: SizeReport,
     clear_screen: struct { history: bool, },
     scroll_viewport: terminal.Terminal.ScrollViewport,
     selection_scroll: bool,
     jump_to_prompt: isize,
     start_synchronized_output: void,
     linefeed_mode: bool,
     focused: bool,
     write_small: WriteReq.Small,
     write_stable: WriteReq.Stable,
     write_alloc: WriteReq.Alloc,
+    inject_output_small: WriteReq.Small,
+    inject_output_stable: WriteReq.Stable,
+    inject_output_alloc: WriteReq.Alloc,

     pub fn writeReq(alloc: Allocator, data: anytype) !Message { ... }
 };

diff --git a/src/termio/Thread.zig b/src/termio/Thread.zig
--- a/src/termio/Thread.zig
+++ b/src/termio/Thread.zig
 // In the message-dispatch switch that handles write_small / write_stable /
 // write_alloc, add three arms that route through processOutput instead of
 // PTY write:
+        .inject_output_small => |v| self.termio.processOutput(v.data[0..v.len]),
+        .inject_output_stable => |v| self.termio.processOutput(v),
+        .inject_output_alloc => |v| {
+            defer v.alloc.free(v.data);
+            self.termio.processOutput(v.data);
+        },

diff --git a/src/apprt/embedded.zig b/src/apprt/embedded.zig
--- a/src/apprt/embedded.zig
+++ b/src/apprt/embedded.zig
     export fn ghostty_surface_send_input_raw(
         surface: *Surface,
         ptr: [*]const u8,
         len: usize,
     ) void {
         surface.core_surface.sendInputRaw(ptr[0..len]) catch |err| {
             std.log.err("error sending raw input to surface err={}", .{err});
         };
     }
+
+    export fn ghostty_surface_inject_output(
+        surface: *Surface,
+        ptr: [*]const u8,
+        len: usize,
+    ) void {
+        const alloc = surface.core_surface.alloc;
+        const data = ptr[0..len];
+        const msg = termio.Message.writeReq(alloc, data) catch |err| {
+            std.log.err("error allocating inject_output buffer err={}", .{err});
+            return;
+        };
+        const injected: termio.Message = switch (msg) {
+            .write_small => |v| .{ .inject_output_small = v },
+            .write_alloc => |v| .{ .inject_output_alloc = v },
+            else => unreachable,
+        };
+        surface.core_surface.io.queueMessage(injected, .unlocked);
+    }

diff --git a/include/ghostty.h b/include/ghostty.h
--- a/include/ghostty.h
+++ b/include/ghostty.h
 GHOSTTY_API void ghostty_surface_send_input_raw(ghostty_surface_t, const uint8_t*, uintptr_t);
+GHOSTTY_API void ghostty_surface_inject_output(ghostty_surface_t, const uint8_t*, uintptr_t);
```

## Zig Test Stub

Add to `src/termio/Termio.zig` (or wherever existing `processOutput` tests live):

```zig
test "inject_output renders bytes into cells" {
    var termio = try Termio.init(testing.allocator, .{
        .rows = 4,
        .cols = 20,
    });
    defer termio.deinit();

    const data = "hello";
    termio.processOutput(data);

    const page = termio.renderer_state.terminal.screen.pages.getPage(0);
    try testing.expectEqual(@as(u21, 'h'), page.rows()[0].cells()[0].content.codepoint);
    try testing.expectEqual(@as(u21, 'o'), page.rows()[0].cells()[4].content.codepoint);
}
```

## Muxy-side Follow-ups

- [ ] Merge PR on muxy-app/ghostty.
- [ ] Trigger "Build GhosttyKit" workflow to regenerate `GhosttyKit.xcframework`.
- [ ] On Muxy side: `rm -rf GhosttyKit.xcframework && scripts/setup.sh` (script already auto-resolves the latest release tag via `gh release list --limit 1`).
- [ ] `swift build` → confirm the new symbol `_ghostty_surface_inject_output` is visible (`nm .build/release/Muxy | grep inject_output`).
- [ ] Implement the Swift-side subscriber in `PaneWireBus.dispatch(...)` for the `.mirror` wire kind: subscribe source pane via `TerminalOutputBus`, call `ghostty_surface_inject_output(mirrorSurface, ptr, len)` for each chunk.
- [ ] Toggle mirror surface read-only via existing `ghostty_surface_binding_action(s, "toggle_readonly", ...)`.
- [ ] Update `docs/architecture.md` "Agent Canvas" section to document the mirror wire as live.

## Known Risks

1. **OSC 52 (clipboard-write) leakage on mirror.** If the source emits
   `\e]52;c;...\e\`, the mirror parses it and also writes to the clipboard.
   Mitigations: set `clipboard-write = deny` on the mirror via config, or add
   a "mirror mode" flag to StreamHandler (larger patch, deferred).
2. **Resize/reflow mismatch.** Source 120x40 vs mirror 80x24 = mirror
   reflows injected bytes using its own dimensions. Usually fine; resize
   storms can look rough. Fix: optional "follow source size" toggle in the
   mirror surface.
3. **Alt-screen asymmetry.** Source toggles `\e[?1049h` → mirror's
   alt-screen toggles too (correct). Only diverges if mirror has a live
   shell; keeping mirrors read-only avoids this entirely.
4. **Upstreamability.** The existing `set_data_callback` tee is already
   embedder-only; this is a second additive export on the same concept. A
   future "embedder bridge" grouping could land both upstream together.
5. **Test coverage.** Fork has no test for the data-callback tee; add one
   for `inject_output` at minimum (stub above).
