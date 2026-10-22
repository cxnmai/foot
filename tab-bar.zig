const std = @import("std");
const label = @import("tab-label.zig");
const c = @cImport({ @cInclude("tab-bridge.h"); });
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
