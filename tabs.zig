comptime {
    _ = @import("tab-bar.zig");
}

const c = @import("tab_abi");
const policy = @import("tab-policy.zig");
const Term = c.struct_terminal;
const Window = c.struct_wl_window;

export fn tabs_is_active(term: ?*const Term) bool {
    return term != null and c.foot_tab_is_active(term);
}

export fn tabs_activate(term: *Term) void {
    const win = c.foot_tab_window(term) orelse return;
    if (c.foot_tab_active(win) != term)
        c.foot_tab_activate_native(term);
}

// Indices are zero-based internally; nonexistent selections are consumed by input.c.
export fn tabs_select(term: *Term, index: c_uint) void {
    const win = c.foot_tab_window(term) orelse return;
    var live: usize = 0;
    for (0..c.foot_tab_count(win)) |i| {
        const candidate = c.foot_tab_at(win, i) orelse continue;
        if (!c.foot_tab_is_live(candidate)) continue;
        if (live == index) {
            tabs_activate(candidate);
            return;
        }
        live += 1;
    }
}

export fn tabs_step(term: *Term, direction: c_int) void {
    const win = c.foot_tab_window(term) orelse return;
    var count: usize = 0;
    var active: usize = 0;
    for (0..c.foot_tab_count(win)) |i| {
        const candidate = c.foot_tab_at(win, i) orelse continue;
        if (!c.foot_tab_is_live(candidate)) continue;
        if (candidate == term) active = count;
        count += 1;
    }
    if (count > 0) {
        const next = if (direction < 0) (active + count - 1) % count else (active + 1) % count;
        tabs_select(term, @intCast(next));
    }
}

export fn tabs_new(term: *Term) bool {
    if (!tabs_is_active(term)) return false;
    const next = c.foot_tab_spawn(term) orelse return false;
    tabs_activate(next);
    tabs_refresh_layout(c.foot_tab_window(next) orelse return false);
    return true;
}

export fn tabs_resize(win: *Window, width: c_int, height: c_int, opts: u8) bool {
    return policy.resizeGroup(c, win, width, height, opts);
}

export fn tabs_refresh_layout(win: *Window) void {
    if (!c.foot_tab_window_ready(win)) return;
    var width: c_int = 0;
    var height: c_int = 0;
    c.foot_tab_content_size(win, &width, &height);
    _ = tabs_resize(win, width, height, c.FOOT_TAB_RESIZE_FORCE);
}

export fn tabs_close_window(win: *Window) void {
    c.foot_tab_close_begin(win);
    // Shutdown is deferred by foot: membership stays stable throughout this loop.
    for (0..c.foot_tab_count(win)) |i| {
        if (c.foot_tab_at(win, i)) |term| c.foot_tab_shutdown(term);
    }
}

export fn tabs_detach(term: *Term) void {
    const win = c.foot_tab_window(term) orelse return;
    c.foot_tab_remove(term);
    const count = c.foot_tab_count(win);
    if (count == 0) {
        // Keep the last session as the window's teardown anchor through roundtrips.
        c.foot_tab_destroy_window(term);
    } else {
        if (c.foot_tab_active(win) == term) {
            var next = c.foot_tab_at(win, 0).?;
            for (0..count) |i| {
                const candidate = c.foot_tab_at(win, i) orelse continue;
                if (c.foot_tab_is_live(candidate)) {
                    next = candidate;
                    break;
                }
            }
            tabs_activate(next);
        }
        tabs_refresh_layout(win);
    }
    c.foot_tab_finish_detach(term);
}

export fn tabs_mark_activity(term: *Term, bell: bool) void {
    c.foot_tab_mark_activity(term, bell);
}
