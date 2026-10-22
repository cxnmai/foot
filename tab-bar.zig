const std = @import("std");
const label = @import("tab-label.zig");
const c = @import("tab_abi");
const Terminal = c.struct_terminal;
const Options = c.struct_foot_tab_options;

fn options(term: *const Terminal) Options {
    var result: Options = undefined;
    c.foot_tab_options(term, &result);
    return result;
}

fn barHeight(o: Options, count: usize) c_int {
    return if (o.enabled and count >= o.min_tabs and o.cell_height > 0 and
        o.height >= @as(i64, o.cell_height) * 2) o.cell_height else 0;
}

fn barY(o: Options) c_int {
    return if (o.position == 0) 0 else @max(0, o.height - o.cell_height);
}

export fn tab_bar_height(term: ?*const Terminal) c_int {
    const t = term orelse return 0;
    const win = c.foot_tab_window(@constCast(t)) orelse return 0;
    return barHeight(options(t), c.foot_tab_count(win));
}

export fn tab_bar_y(term: ?*const Terminal) c_int {
    return barY(options(term orelse return 0));
}

fn titleIterator(o: Options, tab: *Terminal, active: bool, index: []const u8) label.Iterator {
    const format = if (active and o.active_title_template != null)
        o.active_title_template else o.title_template;
    return label.Iterator.init(if (format == null) "{index}: {title}" else label.boundedString(format), .{
        .index = index,
        .title = label.boundedString(c.foot_tab_title(tab)),
        .activity = c.foot_tab_activity(tab),
        .bell = c.foot_tab_bell(tab),
    });
}

const Metrics = struct {
    width: i32,
    label_width: i32,
    text_columns: i32,
    padding: i32,
    edge: i32,
    separator_columns: i32,
};

fn metrics(o: Options, last: bool, text: label.Iterator) Metrics {
    const columns = @divTrunc(o.width, o.cell_width);
    const fade = o.style == 0;
    const gap: i32 = if (fade and !last and columns > 1) 1 else 0;
    const separator = if (!fade and !last)
        label.measure(label.Iterator.literal(label.boundedString(o.separator)), columns - 1, c.foot_tab_char_width)
    else 0;
    const available = columns - gap - separator;
    const edge = if (fade) @min(4, @divTrunc(available - 1, 2)) else 0;
    const padding = @min(@as(i32, @intCast(@min(o.padding, 32))), @divTrunc(available - 2 * edge - 1, 2));
    const limit = @min(@as(i32, @intCast(std.math.clamp(o.max_title_length, 1, 1024))), available - 2 * (edge + padding));
    const text_columns = label.measure(text, limit, c.foot_tab_char_width);
    const label_columns = @max(text_columns, 1) + 2 * (edge + padding);
    return .{
        .width = (label_columns + separator + gap) * o.cell_width,
        .label_width = label_columns * o.cell_width,
        .text_columns = text_columns,
        .padding = padding,
        .edge = edge,
        .separator_columns = separator,
    };
}

fn tabMetrics(o: Options, tab: *Terminal, active: ?*Terminal, index: usize, count: usize) Metrics {
    var buffer: [32]u8 = undefined;
    const number = std.fmt.bufPrint(&buffer, "{d}", .{index + 1}) catch unreachable;
    return metrics(o, index + 1 == count, titleIterator(o, tab, tab == active, number));
}

fn fadeColor(bar: u32, tab: u32, step: u32) u32 {
    var result: u32 = 0;
    for ([_]u5{ 0, 8, 16 }) |shift| {
        const a = (bar >> shift) & 255;
        const b = (tab >> shift) & 255;
        result |= ((a * (4 - step) + b * step) / 4) << shift;
    }
    return result;
}

fn firstVisible(context: anytype, active: usize, width: i32, widthAt: anytype) usize {
    var first = active;
    var used = widthAt(context, active);
    while (first > 0) {
        const previous = widthAt(context, first - 1);
        if (previous > width - used) break;
        first -= 1;
        used += previous;
    }
    return first;
}

const Placed = struct { tab: *Terminal, index: usize, x: i32, size: Metrics };

// Both rendering and hit testing traverse this exact whole-tab viewport.
const Layout = struct {
    o: Options,
    win: *c.struct_wl_window,
    active: ?*Terminal,
    count: usize,
    index: usize = 0,
    x: i32 = 0,

    fn widthAt(self: *const Layout, index: usize) i32 {
        const tab = c.foot_tab_at(self.win, index) orelse return self.o.width;
        return tabMetrics(self.o, tab, self.active, index, self.count).width;
    }

    fn init(term: *Terminal, o: Options) ?Layout {
        const win = c.foot_tab_window(term) orelse return null;
        const count = c.foot_tab_count(win);
        if (count == 0 or barHeight(o, count) == 0 or
            o.cell_width <= 0 or o.width < o.cell_width) return null;
        var self = Layout{ .o = o, .win = win, .active = c.foot_tab_active(win), .count = count };
        var active: usize = 0;
        for (0..count) |i| {
            if (c.foot_tab_at(win, i) == self.active) {
                active = i;
                break;
            }
        }
        self.index = firstVisible(&self, active, o.width, Layout.widthAt);
        return self;
    }

    fn next(self: *Layout) ?Placed {
        if (self.index >= self.count) return null;
        const tab = c.foot_tab_at(self.win, self.index) orelse return null;
        const size = tabMetrics(self.o, tab, self.active, self.index, self.count);
        if (size.width > self.o.width - self.x) return null;
        const placed = Placed{ .tab = tab, .index = self.index, .x = self.x, .size = size };
        self.x += size.width;
        self.index += 1;
        return placed;
    }
};

export fn tab_bar_hit_test(term: ?*Terminal, x: c_int, y: c_int) ?*Terminal {
    const t = term orelse return null;
    const o = options(t);
    var layout = Layout.init(t, o) orelse return null;
    if (x < 0 or x >= o.width or y < barY(o) or y - barY(o) >= o.cell_height) return null;
    while (layout.next()) |tab| {
        if (x >= tab.x and x - tab.x < tab.size.label_width) return tab.tab;
    }
    return null;
}

fn paintText(term: *Terminal, pix: *anyopaque, o: Options, text: label.Iterator,
    columns: i32, x: i32, style: u32, foreground: u32, srgb: bool) void
{
    var scanner = label.Scanner{ .iterator = text, .limit = columns };
    while (scanner.next(c.foot_tab_char_width)) |ch| {
        c.foot_tab_glyph(pix, term, if (style < 4) style else 0, ch.codepoint,
            x + ch.column * o.cell_width, barY(o), x, columns * o.cell_width, foreground, srgb);
    }
}

fn renderTab(term: *Terminal, pix: *anyopaque, o: Options, active: ?*Terminal, tab: Placed, srgb: bool) void {
    const selected = tab.tab == active;
    const bg = if (selected) o.active_background else o.inactive_background;
    const fg = if (selected) o.active_foreground else o.inactive_foreground;
    const style = if (selected) o.active_font_style else o.inactive_font_style;
    const end = tab.x + tab.size.label_width;
    const y = barY(o);
    c.foot_tab_fill(pix, tab.x, y, tab.size.label_width, o.cell_height, bg, 65535, srgb);
    var i: i32 = 0;
    while (i < tab.size.edge) : (i += 1) {
        const color = fadeColor(o.background, bg, @intCast(i + 1));
        c.foot_tab_fill(pix, tab.x + i * o.cell_width, y, o.cell_width, o.cell_height, color, 65535, srgb);
        c.foot_tab_fill(pix, end - (i + 1) * o.cell_width, y, o.cell_width, o.cell_height, color, 65535, srgb);
    }
    var buffer: [32]u8 = undefined;
    const number = std.fmt.bufPrint(&buffer, "{d}", .{tab.index + 1}) catch unreachable;
    paintText(term, pix, o, titleIterator(o, tab.tab, selected, number), tab.size.text_columns,
        tab.x + (tab.size.edge + tab.size.padding) * o.cell_width, style, fg, srgb);
    if (tab.size.separator_columns > 0) {
        const width = tab.size.separator_columns * o.cell_width;
        c.foot_tab_fill(pix, end, y, width, o.cell_height, o.inactive_background, 65535, srgb);
        paintText(term, pix, o, label.Iterator.literal(label.boundedString(o.separator)),
            tab.size.separator_columns, end, 0, o.inactive_foreground, srgb);
    }
}

export fn tab_bar_render(term: ?*Terminal, image: ?*anyopaque, srgb: bool) void {
    const t = term orelse return;
    const pix = image orelse return;
    const o = options(t);
    const win = c.foot_tab_window(t) orelse return;
    if (barHeight(o, c.foot_tab_count(win)) == 0 or o.width <= 0) return;
    c.foot_tab_fill(pix, 0, barY(o), o.width, o.cell_height, o.background, o.alpha, srgb);
    var layout = Layout.init(t, o) orelse return;
    while (layout.next()) |tab| renderTab(t, pix, o, layout.active, tab, srgb);
}
