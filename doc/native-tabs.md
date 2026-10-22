# Native tabs (Zig)

This fork adds independent terminal sessions inside one Wayland window.
The tab policy, title formatting, layout, fade styling and hit testing are
implemented in `tabs.zig`, `tab-policy.zig`, `tab-label.zig` and `tab-bar.zig`. The narrow
`tab-bridge.h` ABI keeps foot's C/Wayland/PTY internals out of Zig.
`tab-bridge.c` and `tab-draw.c` adapt existing native operations.

## Build and test

In addition to foot's normal dependencies, install **Zig 0.17.0 or newer**.
Meson uses `zig translate-c` to generate an ABI module in the build directory,
then builds a position-independent Zig object in safe optimization mode.
The generated bindings are not checked into the source tree.

```sh
meson setup bld/tabs -Ddocs=disabled -Dterminfo=disabled
meson compile -C bld/tabs
meson test -C bld/tabs --print-errorlogs
```

The `zig-tabs` test includes UTF-8/title sanitization, bounded literal template
expansion, overflow visibility, fade colors, and shared paint/hit-test geometry.
`zig-tab-policy` verifies that only the active tab retains the keep-grid resize
flag, while siblings receive the resulting shared pixel dimensions.

## Controls and lifetime

- `Ctrl+Shift+t`: create a tab running the configured shell in the current cwd.
- `Ctrl+Shift+w`: close the current tab.
- `Ctrl+Shift+1` through `9`: select that literal, 1-based tab number.
- `Ctrl+Shift+h` / `l`: previous / next tab, wrapping at either end.
- Click a tab label to select it. Mouse events over the bar do not reach the PTY.
- `Ctrl+Shift+n` still creates a separate terminal window.

Navigation remains available in search, URL and Unicode-entry modes. Creation
and closing do not repeat while held; previous/next navigation may repeat.
Missing numbered tabs are consumed as no-ops. Closing the final tab closes the
window; a compositor close request closes every tab in that window.

Each tab keeps its own shell, PTY, terminal modes, scrollback and selection.
Background sessions continue reading output. Window resizing updates all tabs;
only the active tab paints the shared surfaces. A resize retains foot's existing
behavior of leaving URL mode. In-progress selection/IME gestures are finalized
or reset on switching, not transferred to another session.

Local tabs own cloned configurations. In server mode, `footclient` still tracks
its original command/session and returns that command's exit status when it
ends. Locally created sibling tabs can outlive that client. Standalone foot
likewise preserves the original command's exit status but stays running until
all sessions have closed.

Bindings use foot's existing XKB matching, including shifted digits. Number
symbols on non-US layouts may differ from US physical number-row positions;
use explicit overrides for the desired layout.

## Kitty comparison profile

```sh
./bld/tabs/foot --config=contrib/kitty-compare.ini
```

`contrib/kitty-compare.ini` snapshots Chin's configured kitty palette,
JetBrains Mono 11pt, 70% matching-background opacity, selection/cursor colors,
frameless appearance, and bottom fade labels. Active labels are bold italic.
No extra label padding is added; each full fade edge has four cells.
The cursor blink interval is mapped from the system's 1200ms full cycle.

`contrib/kitty-compare.kdl` adds the equivalent niri blur/xray rule, scoped to
`foot`, `footclient`, and `foot-kitty-compare`. Existing global niri settings already apply 12px rounded
corners with clipping, no borders, a 2px focus ring and 10px gaps. Do not modify
the packaged niri `shell/` files or replace the existing kitty rule.
The rule also sets `draw-border-with-background false`: otherwise niri can
paint a solid focus-ring background behind the entire focused window, hiding
the wallpaper even though foot's surface remains translucent.

The profile explicitly enables native blur as well as transparency:

```ini
[colors-dark]
alpha=0.70
alpha-mode=matching
blur=yes
```

Blur requires `ext-background-effect-v1` support or a compositor-enforced rule.
The `[colors-light]` section has independent settings if you switch themes.
Foot currently makes fullscreen windows opaque; test in tiled, maximized or
floating mode. To make ordinary launches use the comparison styling, put this
in `~/.config/foot/foot.ini` (only if you want to change the default profile):

```ini
include=~/.config/foot/kitty-compare.ini
app-id=foot
```

This is a visual/configuration match, not kitty configuration compatibility.
Font rasterization and renderer details can differ. Python template expressions,
custom Python tab drawing, kitty-specific progress/security indicators, dynamic
opacity shortcuts, splits, reordering and detachable tabs are not implemented.
Use the documented safe `{title}`, `{index}`, `{activity}` and `{bell}` fields
when customizing labels. The comparison profile intentionally uses plain titles
rather than pretending to evaluate kitty's Python/status-color template.

See `[tab-bar]` in `foot.ini` and `foot.ini(5)` for the configurable colors,
fonts, templates, fade/separator styles, padding and minimum tab count.
