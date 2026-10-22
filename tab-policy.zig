const c = @import("tab_abi");

// Keep grid geometry authoritative on the active tab. Siblings must honor the
// resulting shared pixel size, even when their font metrics differ.
pub fn resizeGroup(comptime backend: type, win: anytype, width: c_int, height: c_int, opts: u8) bool {
    if (!backend.foot_tab_window_ready(win)) return false;
    const active = backend.foot_tab_active(win) orelse return false;
    const resized = backend.foot_tab_resize_one(active, width, height, opts);
    backend.foot_tab_save_size(win);
    var w: c_int = 0;
    var h: c_int = 0;
    backend.foot_tab_content_size(win, &w, &h);
    for (0..backend.foot_tab_count(win)) |i| {
        const candidate = backend.foot_tab_at(win, i) orelse continue;
        if (candidate != active and backend.foot_tab_is_live(candidate))
            _ = backend.foot_tab_resize_one(candidate, w, h, opts & ~@as(u8, c.FOOT_TAB_RESIZE_KEEP_GRID));
    }
    return resized;
}

const Mock = struct {
    const Session = struct { live: bool = true, calls: usize = 0, opts: u8 = 0, width: c_int = 0, height: c_int = 0 };
    const Window = struct { sessions: [3]Session = .{ .{}, .{}, .{ .live = false } } };
    fn foot_tab_window_ready(_: *Window) bool {
        return true;
    }
    fn foot_tab_active(win: *Window) ?*Session {
        return &win.sessions[0];
    }
    fn foot_tab_count(_: *Window) usize {
        return 3;
    }
    fn foot_tab_at(win: *Window, index: usize) ?*Session {
        return &win.sessions[index];
    }
    fn foot_tab_is_live(session: *Session) bool {
        return session.live;
    }
    fn foot_tab_resize_one(session: *Session, width: c_int, height: c_int, opts: u8) bool {
        session.calls += 1;
        session.opts = opts;
        session.width = width;
        session.height = height;
        return true;
    }
    fn foot_tab_save_size(_: *Window) void {}
    fn foot_tab_content_size(win: *Window, width: *c_int, height: *c_int) void {
        width.* = win.sessions[0].width;
        height.* = win.sessions[0].height;
    }
};

test "active resize retains KEEP_GRID but live siblings receive shared pixel dimensions without it" {
    const std = @import("std");
    var win = Mock.Window{};
    const flags = c.FOOT_TAB_RESIZE_FORCE | c.FOOT_TAB_RESIZE_BY_CELLS | c.FOOT_TAB_RESIZE_KEEP_GRID;
    try std.testing.expect(resizeGroup(Mock, &win, 800, 600, flags));
    try std.testing.expectEqual(@as(u8, flags), win.sessions[0].opts);
    try std.testing.expectEqual(@as(u8, c.FOOT_TAB_RESIZE_FORCE | c.FOOT_TAB_RESIZE_BY_CELLS), win.sessions[1].opts);
    for (win.sessions[0..2]) |session| {
        try std.testing.expectEqual(@as(usize, 1), session.calls);
        try std.testing.expectEqual(@as(c_int, 800), session.width);
        try std.testing.expectEqual(@as(c_int, 600), session.height);
    }
    try std.testing.expectEqual(@as(usize, 0), win.sessions[2].calls);
}
