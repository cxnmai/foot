const std = @import("std");
const abi = @import("graphics_abi");
const c = if (@import("builtin").is_test) TestABI else abi;

const Geometry = struct {
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
    clip_x: c_int,
    clip_y: c_int,
    clip_width: c_int,
    clip_height: c_int,
};

fn geometry(p: abi.struct_kg_placement, canvas: abi.struct_kg_canvas, foreground: bool) ?Geometry {
    if (p.rgba == null or p.screen != canvas.screen or (p.z >= 0) != foreground or
        canvas.width <= 0 or canvas.height <= 0 or canvas.cell_width <= 0 or
        canvas.cell_height <= 0 or canvas.columns <= 0 or canvas.rows <= 0 or
        p.x_offset >= canvas.cell_width or p.y_offset >= canvas.cell_height or
        p.source_x >= p.image_width or p.source_y >= p.image_height) return null;
    const sw: i64 = @min(if (p.source_width == 0) p.image_width else p.source_width, p.image_width - p.source_x);
    const sh: i64 = @min(if (p.source_height == 0) p.image_height else p.source_height, p.image_height - p.source_y);
    var width: i64 = sw;
    var height: i64 = sh;
    // Offsets consume space inside the requested cell box, not extra cells.
    const box_width = @as(i64, p.columns) * canvas.cell_width - p.x_offset;
    const box_height = @as(i64, p.rows) * canvas.cell_height - p.y_offset;
    if (p.columns != 0 and (box_width <= 0 or box_width > std.math.maxInt(c_int))) return null;
    if (p.rows != 0 and (box_height <= 0 or box_height > std.math.maxInt(c_int))) return null;
    // A checked int32 box times a uint32 source dimension always fits int64.
    if (p.columns != 0 and (p.rows == 0 or box_width * sh <= box_height * sw)) {
        width = box_width;
        height = @divTrunc(width * sh, sw);
    } else if (p.rows != 0) {
        height = box_height;
        width = @divTrunc(height * sw, sh);
    }
    if (width <= 0 or height <= 0) return null;
    const x = @as(i64, canvas.margin_left) + @as(i64, p.col) * canvas.cell_width + p.x_offset;
    const row = @as(i64, p.row) + canvas.history_offset;
    const y = @as(i64, canvas.margin_top) + row * canvas.cell_height + p.y_offset;
    const target_width = std.math.cast(c_int, width) orelse return null;
    const target_height = std.math.cast(c_int, height) orelse return null;
    const target_x = std.math.cast(c_int, x) orelse return null;
    const target_y = std.math.cast(c_int, y) orelse return null;
    const left = @max(0, @as(i64, canvas.margin_left), x);
    const top = @max(0, @as(i64, canvas.margin_top), y);
    const right = @min(@as(i64, canvas.width), @as(i64, canvas.margin_left) + @as(i64, canvas.columns) * canvas.cell_width, x + width);
    const bottom = @min(@as(i64, canvas.height), @as(i64, canvas.margin_top) + @as(i64, canvas.rows) * canvas.cell_height, y + height);
    if (right <= left or bottom <= top) return null;
    return .{
        .x = target_x,
        .y = target_y,
        .width = target_width,
        .height = target_height,
        .source_x = p.source_x,
        .source_y = p.source_y,
        .source_width = @intCast(sw),
        .source_height = @intCast(sh),
        .clip_x = std.math.cast(c_int, left) orelse return null,
        .clip_y = std.math.cast(c_int, top) orelse return null,
        .clip_width = std.math.cast(c_int, right - left) orelse return null,
        .clip_height = std.math.cast(c_int, bottom - top) orelse return null,
    };
}

export fn kg_render(engine: ?*abi.struct_kg_engine, term: ?*abi.struct_terminal, pix: ?*anyopaque, foreground: bool, linear: bool) void {
    const e = engine orelse return;
    const t = term orelse return;
    const pixels = pix orelse return;
    var canvas: abi.struct_kg_canvas = undefined;
    c.kg_native_canvas(t, &canvas);
    const count = c.kg_placement_count(e);
    // The store supplies ascending z order; equal-z placements retain that order.
    for (0..count) |index| {
        var placement: abi.struct_kg_placement = undefined;
        if (!c.kg_get_placement(e, index, &placement)) continue;
        const g = geometry(placement, canvas, foreground) orelse continue;
        c.kg_native_paint(pixels, placement.rgba, placement.image_width, placement.image_height, g.x, g.y, g.width, g.height, g.source_x, g.source_y, g.source_width, g.source_height, g.clip_x, g.clip_y, g.clip_width, g.clip_height, linear);
    }
}

const TestABI = struct {
    var canvas: abi.struct_kg_canvas = undefined;
    var placements: []const abi.struct_kg_placement = &.{};
    var painted: [16]u32 = undefined;
    var paint_count: usize = 0;
    var paint_linear: bool = false;

    fn kg_native_canvas(_: *abi.struct_terminal, out: *abi.struct_kg_canvas) void {
        out.* = canvas;
    }
    fn kg_placement_count(_: *abi.struct_kg_engine) usize {
        return placements.len;
    }
    fn kg_get_placement(_: *abi.struct_kg_engine, index: usize, out: *abi.struct_kg_placement) bool {
        out.* = placements[index];
        return true;
    }
    fn kg_native_paint(_: *anyopaque, _: [*c]const u8, _: u32, _: u32, _: i32, _: i32, _: i32, _: i32, sx: u32, _: u32, _: u32, _: u32, _: i32, _: i32, _: i32, _: i32, linear: bool) void {
        painted[paint_count] = sx;
        paint_count += 1;
        paint_linear = linear;
    }
};

fn testCanvas() abi.struct_kg_canvas {
    var result = std.mem.zeroes(abi.struct_kg_canvas);
    result.width = 200;
    result.height = 160;
    result.cell_width = 8;
    result.cell_height = 16;
    result.margin_left = 10;
    result.margin_top = 12;
    result.columns = 20;
    result.rows = 8;
    return result;
}

fn testPlacement() abi.struct_kg_placement {
    var result = std.mem.zeroes(abi.struct_kg_placement);
    result.rgba = @ptrFromInt(256);
    result.image_width = 80;
    result.image_height = 40;
    result.col = 2;
    result.row = 1;
    return result;
}

fn expectSize(width: i32, height: i32, g: Geometry) !void {
    try std.testing.expectEqual(width, g.width);
    try std.testing.expectEqual(height, g.height);
}

test "graphics-render defaults use natural pixels and cell plus margin anchor" {
    const g = geometry(testPlacement(), testCanvas(), true).?;
    try expectSize(80, 40, g);
    try std.testing.expectEqual(@as(i32, 26), g.x);
    try std.testing.expectEqual(@as(i32, 28), g.y);
    try std.testing.expectEqual(@as(u32, 80), g.source_width);
    try std.testing.expectEqual(@as(u32, 40), g.source_height);
    try std.testing.expectEqual(g.x, g.clip_x);
    try std.testing.expectEqual(g.y, g.clip_y);
}

test "graphics-render crop intersects image before computing natural size" {
    var p = testPlacement();
    p.source_x = 60;
    p.source_y = 30;
    p.source_width = std.math.maxInt(u32);
    const g = geometry(p, testCanvas(), true).?;
    try expectSize(20, 10, g);
    try std.testing.expectEqual(@as(u32, 60), g.source_x);
    try std.testing.expectEqual(@as(u32, 30), g.source_y);
    try std.testing.expectEqual(@as(u32, 20), g.source_width);
    try std.testing.expectEqual(@as(u32, 10), g.source_height);
    p.source_x = p.image_width;
    try std.testing.expect(geometry(p, testCanvas(), true) == null);
    p.source_x = 0;
    p.source_y = p.image_height;
    try std.testing.expect(geometry(p, testCanvas(), true) == null);
}

test "graphics-render requested cell boxes preserve aspect at upper left" {
    var p = testPlacement();
    p.columns = 5;
    try expectSize(40, 20, geometry(p, testCanvas(), true).?);
    p.columns = 0;
    p.rows = 3;
    try expectSize(96, 48, geometry(p, testCanvas(), true).?);
    p.columns = 5;
    try expectSize(40, 20, geometry(p, testCanvas(), true).?);
    p.columns = 15;
    try expectSize(96, 48, geometry(p, testCanvas(), true).?);
    p.columns = 5;
    p.x_offset = 3;
    p.y_offset = 4;
    const g = geometry(p, testCanvas(), true).?;
    try expectSize(37, 18, g);
    try std.testing.expectEqual(@as(i32, 29), g.x);
    try std.testing.expectEqual(@as(i32, 32), g.y);
}

test "graphics-render clips right bottom and pix extent without resizing image" {
    var p = testPlacement();
    p.col = 19;
    p.row = 7;
    var canvas = testCanvas();
    var g = geometry(p, canvas, true).?;
    try expectSize(80, 40, g);
    try std.testing.expectEqual(@as(i32, 8), g.clip_width);
    try std.testing.expectEqual(@as(i32, 16), g.clip_height);
    canvas.width = 166;
    canvas.height = 132;
    g = geometry(p, canvas, true).?;
    try std.testing.expectEqual(@as(i32, 4), g.clip_width);
    try std.testing.expectEqual(@as(i32, 8), g.clip_height);
    try std.testing.expectEqual(@as(u32, 80), g.source_width);
    p.col = 20;
    try std.testing.expect(geometry(p, canvas, true) == null);
}

test "graphics-render history anchors and alternate screen visibility" {
    var canvas = testCanvas();
    var p = testPlacement();
    p.row = -2;
    try std.testing.expectEqual(@as(i32, 12), geometry(p, canvas, true).?.clip_y);
    canvas.history_offset = 3;
    try std.testing.expectEqual(@as(i32, 28), geometry(p, canvas, true).?.y);
    p.screen = 1;
    try std.testing.expect(geometry(p, canvas, true) == null);
    canvas.screen = 1;
    try std.testing.expect(geometry(p, canvas, true) != null);
    p.screen = 0;
    try std.testing.expect(geometry(p, canvas, true) == null);
}
