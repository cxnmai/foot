const std = @import("std");
comptime {
    _ = @import("graphics-render.zig");
}
const c = @import("graphics_abi");
const protocol = @import("graphics-command.zig");
const Command = protocol.Command;
const Failure = protocol.Failure;
const allocator = std.heap.c_allocator;
const max_images = 256;
const max_placements = 1024;
const max_dimension = 8192;

const Image = struct { id: u32, number: u32, serial: u64, width: u32, height: u32, rgba: []u8 };
const Placement = struct { image: usize, id: u32, geometry: c.struct_kg_placement };
const Engine = struct {
    term: ?*c.struct_terminal,
    images: [max_images]?Image = @splat(null),
    placements: std.ArrayList(Placement) = .empty,
    bytes: usize = 0,
    next_id: u32 = 1,
    serial: u64 = 0,
    pending_cmd: ?Command = null,
    pending_data: std.ArrayList(u8) = .empty,
    packet: [1 + protocol.max_header + 1 + protocol.max_payload]u8 = undefined,
    packet_len: usize = 0,
    packet_overflow: bool = false,

    fn cancel(self: *Engine) void {
        if (self.pending_cmd != null) {
            self.pending_data.clearRetainingCapacity();
            self.pending_cmd = null;
        }
    }
    fn damage(self: *Engine) void {
        c.kg_native_damage(self.term);
    }
    fn removeImage(self: *Engine, slot: usize) void {
        const image = self.images[slot] orelse return;
        self.bytes -= image.rgba.len;
        allocator.free(image.rgba);
        self.images[slot] = null;
        var index: usize = 0;
        while (index < self.placements.items.len) {
            if (self.placements.items[index].image == slot) {
                _ = self.placements.orderedRemove(index);
            } else index += 1;
        }
    }
    fn find(self: *Engine, cmd: Command) ?usize {
        const id = cmd.unsigned('i', 0);
        const number = cmd.unsigned('I', 0);
        var found: ?usize = null;
        for (self.images, 0..) |entry, slot| {
            const image = entry orelse continue;
            if (id != 0 and image.id == id) return slot;
            if (number != 0 and image.number == number and
                (found == null or image.serial > self.images[found.?].?.serial)) found = slot;
        }
        return found;
    }
    fn freshId(self: *Engine) u32 {
        while (true) {
            const id = self.next_id;
            self.next_id +%= 1;
            if (self.next_id == 0) self.next_id = 1;
            var used = false;
            for (self.images) |entry| {
                if (entry) |image| {
                    if (image.id == id) used = true;
                }
            }
            if (!used) return id;
        }
    }
    fn respond(self: *Engine, cmd: Command, failure: ?Failure, generated: u32) void {
        if (cmd.get('q', 0) == 2 or (failure == null and cmd.get('q', 0) == 1)) return;
        if (cmd.get('i', 0) == 0 and cmd.get('I', 0) == 0 and cmd.get('a', 't') != 'q') return;
        var buf: [192]u8 = undefined;
        var stream = std.Io.Writer.fixed(&buf);
        stream.print("\x1b_Gi={d}", .{if (generated != 0) generated else cmd.unsigned('i', 0)}) catch unreachable;
        if (cmd.get('I', 0) != 0) stream.print(",I={d}", .{cmd.unsigned('I', 0)}) catch unreachable;
        if (cmd.get('p', 0) != 0) stream.print(",p={d}", .{cmd.unsigned('p', 0)}) catch unreachable;
        stream.print(";{s}\x1b\\", .{if (failure) |err| @errorName(err) else "OK"}) catch unreachable;
        const reply = stream.buffered();
        c.kg_native_reply(self.term, reply.ptr, reply.len);
    }
};

fn engine(ptr: ?*c.struct_kg_engine) ?*Engine {
    return @ptrCast(@alignCast(ptr));
}
export fn kg_new(term: ?*c.struct_terminal) ?*c.struct_kg_engine {
    const self = allocator.create(Engine) catch return null;
    self.* = .{ .term = term };
    return @ptrCast(self);
}
export fn kg_reset(ptr: ?*c.struct_kg_engine) void {
    const self = engine(ptr) orelse return;
    self.cancel();
    for (0..max_images) |slot| self.removeImage(slot);
    self.packet_len = 0;
    self.packet_overflow = false;
    self.damage();
}
export fn kg_free(ptr: ?*c.struct_kg_engine) void {
    const self = engine(ptr) orelse return;
    kg_reset(ptr);
    self.placements.deinit(allocator);
    allocator.destroy(self);
}
export fn kg_abort(ptr: ?*c.struct_kg_engine) void {
    const self = engine(ptr) orelse return;
    self.cancel();
    self.packet_len = 0;
    self.packet_overflow = false;
}
export fn kg_begin(ptr: ?*c.struct_kg_engine) void {
    const self = engine(ptr) orelse return;
    self.packet_len = 0;
    self.packet_overflow = false;
}
export fn kg_put(ptr: ?*c.struct_kg_engine, byte: u8) void {
    const self = engine(ptr) orelse return;
    if (self.packet_len == self.packet.len) {
        self.packet_overflow = true;
    } else {
        self.packet[self.packet_len] = byte;
        self.packet_len += 1;
    }
}

fn validate(cmd: Command) Failure!void {
    if (cmd.has('i') and cmd.has('I')) return error.EINVAL;
    if (cmd.get('q', 0) > 2 or cmd.get('m', 0) > 1 or cmd.get('C', 0) > 1) return error.EINVAL;
    if (std.mem.indexOfScalar(u8, "tTpqd", @intCast(cmd.get('a', 't'))) == null) return error.ENOTSUP;
    // Static, direct transfers only. Never interpret payload as a host path.
    if (cmd.get('t', 'd') != 'd' or (cmd.has('o') and cmd.get('o', 0) != 'z')) return error.ENOTSUP;
    for (cmd.present, 0..) |present, key| {
        if (present and std.mem.indexOfScalar(u8, "atodfsvimqIpxywhcrXYZCzSN", @intCast(key)) == null)
            return error.ENOTSUP;
    }
    if (cmd.get('f', 32) != 24 and cmd.get('f', 32) != 32 and cmd.get('f', 32) != 100) return error.ENOTSUP;
    if (cmd.get('s', 0) > max_dimension or cmd.get('v', 0) > max_dimension) return error.ENOSPC;
    if (cmd.get('S', 0) > protocol.max_bytes) return error.ENOSPC;
    if (cmd.has('S') and !(cmd.get('f', 32) == 100 and cmd.get('o', 0) == 'z')) return error.ENOTSUP;
    if (cmd.get('c', 0) > max_dimension or cmd.get('r', 0) > max_dimension) return error.ENOSPC;
}

fn rawSize(width: u32, height: u32, channels: u32) Failure!usize {
    if (width == 0 or height == 0) return error.EINVAL;
    if (width > max_dimension or height > max_dimension) return error.ENOSPC;
    const size = @as(u64, width) * height * channels;
    if (size > protocol.max_bytes) return error.ENOSPC;
    return @intCast(size);
}

fn pixels(cmd: Command, input: []const u8) Failure!Image {
    const format = cmd.unsigned('f', 32);
    var width = cmd.unsigned('s', 0);
    var height = cmd.unsigned('v', 0);
    var inflated: ?[]u8 = null;
    defer if (inflated) |buffer| allocator.free(buffer);
    var data = input;
    if (cmd.get('o', 0) == 'z') {
        const size = if (format == 100) cmd.unsigned('S', 0) else try rawSize(width, height, format / 8);
        if (size == 0 or size > protocol.max_bytes) return error.EINVAL;
        const buffer = allocator.alloc(u8, size) catch return error.ENOSPC;
        inflated = buffer;
        if (!c.kg_native_inflate(input.ptr, input.len, buffer.ptr, buffer.len)) return error.EINVAL;
        data = buffer;
    }
    var rgba: []u8 = undefined;
    if (format == 100) {
        // Check IHDR before entering a native allocator/decoder.
        if (data.len < 33 or !std.mem.eql(u8, data[0..8], "\x89PNG\r\n\x1a\n") or
            !std.mem.eql(u8, data[12..16], "IHDR") or std.mem.readInt(u32, data[8..12], .big) != 13) return error.EINVAL;
        width = std.mem.readInt(u32, data[16..20], .big);
        height = std.mem.readInt(u32, data[20..24], .big);
        const size = try rawSize(width, height, 4);
        var decoded_width: u32 = 0;
        var decoded_height: u32 = 0;
        const decoded = c.kg_native_png(data.ptr, data.len, &decoded_width, &decoded_height);
        if (decoded == null) return error.EINVAL;
        rgba = decoded[0..size];
        if (decoded_width != width or decoded_height != height) {
            allocator.free(rgba);
            return error.EINVAL;
        }
    } else {
        const size = try rawSize(width, height, format / 8);
        if (data.len != size) return error.EINVAL;
        rgba = allocator.alloc(u8, try rawSize(width, height, 4)) catch return error.ENOSPC;
        if (format == 32) {
            @memcpy(rgba, data);
        } else {
            for (0..@as(usize, width) * height) |index| {
                @memcpy(rgba[index * 4 ..][0..3], data[index * 3 ..][0..3]);
                rgba[index * 4 + 3] = 255;
            }
        }
    }
    return .{ .id = 0, .number = 0, .serial = 0, .width = width, .height = height, .rgba = rgba };
}

fn nativeMetrics(self: *Engine) c.struct_kg_metrics {
    var m: c.struct_kg_metrics = undefined;
    c.kg_native_metrics(self.term, &m);
    return m;
}

fn crop(cmd: Command, width: u32, height: u32) struct { x: u32, y: u32, w: u32, h: u32 } {
    var x = cmd.unsigned('x', 0);
    var y = cmd.unsigned('y', 0);
    if (x >= width) x = width;
    if (y >= height) y = height;
    var w = cmd.unsigned('w', 0);
    var h = cmd.unsigned('h', 0);
    if (w == 0 or w > width - x) w = width - x;
    if (h == 0 or h > height - y) h = height - y;
    return .{ .x = x, .y = y, .w = w, .h = h };
}

// Number of terminal cells the placement advances the cursor, honoring c/r.
fn advanceCells(cmd: Command, sw: u32, sh: u32, m: c.struct_kg_metrics) struct { cols: u32, rows: u32 } {
    const cw: u32 = @intCast(@max(1, m.cell_width));
    const ch: u32 = @intCast(@max(1, m.cell_height));
    var cols = cmd.unsigned('c', 0);
    var rows = cmd.unsigned('r', 0);
    if (cols == 0 and rows == 0) {
        cols = (sw + cw - 1) / cw;
        rows = (sh + ch - 1) / ch;
    } else if (rows == 0) {
        const pw = cols * cw;
        const ph = pw * sh / @max(1, sw);
        rows = (ph + ch - 1) / ch;
    } else if (cols == 0) {
        const ph = rows * ch;
        const pw = ph * sw / @max(1, sh);
        cols = (pw + cw - 1) / cw;
    }
    return .{ .cols = cols, .rows = rows };
}

fn placementGeometry(self: *Engine, cmd: Command, image: Image) c.struct_kg_placement {
    const m = nativeMetrics(self);
    const source = crop(cmd, image.width, image.height);
    return .{
        .rgba = image.rgba.ptr,
        .image_width = image.width,
        .image_height = image.height,
        .col = m.cursor_col,
        .row = m.cursor_row,
        .screen = m.screen,
        .z = @intCast(cmd.get('z', 0)),
        .columns = cmd.unsigned('c', 0),
        .rows = cmd.unsigned('r', 0),
        .x_offset = cmd.unsigned('X', 0),
        .y_offset = cmd.unsigned('Y', 0),
        .source_x = source.x,
        .source_y = source.y,
        .source_width = source.w,
        .source_height = source.h,
    };
}

fn place(self: *Engine, slot: usize, id: u32, geometry: c.struct_kg_placement) Failure!void {
    if (self.placements.items.len >= max_placements) return error.ENOSPC;
    self.placements.append(allocator, .{ .image = slot, .id = id, .geometry = geometry }) catch return error.ENOSPC;
}

fn freeSlot(self: *Engine) Failure!usize {
    for (self.images, 0..) |entry, slot| {
        if (entry == null) return slot;
    }
    return error.ENOSPC;
}

fn store(self: *Engine, cmd: Command, image: Image) Failure!usize {
    const number = cmd.unsigned('I', 0);
    const explicit = cmd.unsigned('i', 0);
    var id = explicit;
    if (explicit != 0) {
        if (self.find(cmd)) |existing| self.removeImage(existing);
    } else {
        id = self.freshId();
    }
    const slot = try freeSlot(self);
    if (self.bytes + image.rgba.len > protocol.max_bytes) return error.ENOSPC;
    self.bytes += image.rgba.len;
    self.serial +%= 1;
    self.images[slot] = .{
        .id = id,
        .number = number,
        .serial = self.serial,
        .width = image.width,
        .height = image.height,
        .rgba = image.rgba,
    };
    return slot;
}

fn commitPlacement(self: *Engine, cmd: Command, slot: usize) Failure!void {
    const image = self.images[slot] orelse return error.ENOENT;
    const geometry = placementGeometry(self, cmd, image);
    const id = image.id;
    try place(self, slot, id, geometry);
    self.damage();
    if (cmd.get('C', 0) != 1) {
        const m = nativeMetrics(self);
        const cells = advanceCells(cmd, geometry.source_width, geometry.source_height, m);
        c.kg_native_advance(self.term, cells.cols, cells.rows);
    }
}

fn finalize(self: *Engine) void {
    defer {
        self.pending_data.clearRetainingCapacity();
        self.pending_cmd = null;
    }
    const cmd = self.pending_cmd orelse return;
    const image = pixels(cmd, self.pending_data.items) catch |err| {
        self.respond(cmd, err, 0);
        return;
    };
    const slot = store(self, cmd, image) catch |err| {
        allocator.free(image.rgba);
        self.respond(cmd, err, 0);
        return;
    };
    self.respond(cmd, null, self.images[slot].?.id);
    if (cmd.get('a', 't') == 'T') {
        commitPlacement(self, cmd, slot) catch |err| self.respond(cmd, err, 0);
    }
}

fn placeExisting(self: *Engine, cmd: Command) void {
    const slot = self.find(cmd) orelse {
        self.respond(cmd, error.ENOENT, 0);
        return;
    };
    commitPlacement(self, cmd, slot) catch |err| self.respond(cmd, err, 0);
    self.respond(cmd, null, 0);
}

fn query(self: *Engine, cmd: Command, data: []const u8) void {
    _ = pixels(cmd, data) catch |err| {
        self.respond(cmd, err, 0);
        return;
    };
    self.respond(cmd, null, 0);
}

fn removePlacementsOfImage(self: *Engine, slot: usize, free_data: bool) void {
    var i: usize = 0;
    while (i < self.placements.items.len) {
        if (self.placements.items[i].image == slot)
            _ = self.placements.orderedRemove(i)
        else
            i += 1;
    }
    if (free_data and self.images[slot] != null) self.removeImage(slot);
}

fn sweep(self: *Engine) void {
    var slot: usize = 0;
    while (slot < max_images) : (slot += 1) {
        if (self.images[slot] == null) continue;
        var referenced = false;
        for (self.placements.items) |placement| {
            if (placement.image == slot) {
                referenced = true;
                break;
            }
        }
        if (!referenced) self.removeImage(slot);
    }
}

fn delete(self: *Engine, cmd: Command) void {
    const selector = cmd.get('d', 'a');
    const m = nativeMetrics(self);
    var changed = false;
    switch (selector) {
        'a', 'A' => {
            var i: usize = 0;
            while (i < self.placements.items.len) {
                if (self.placements.items[i].geometry.screen == m.screen)
                    _ = self.placements.orderedRemove(i)
                else
                    i += 1;
            }
            changed = true;
            if (selector == 'A') sweep(self);
        },
        'i', 'I' => {
            if (self.find(cmd)) |slot| {
                removePlacementsOfImage(self, slot, selector == 'I');
                changed = true;
            }
        },
        'c', 'C' => {
            const x = cmd.unsigned('x', @intCast(m.cursor_col + 1));
            const y = cmd.unsigned('y', @intCast(m.cursor_row + 1));
            var i: usize = 0;
            while (i < self.placements.items.len) {
                const p = &self.placements.items[i];
                const g = p.geometry;
                const col = g.col;
                const row = g.row;
                const cols: i64 = @max(1, g.columns);
                const rows: i64 = @max(1, g.rows);
                const hit = row < y and y <= row + rows and col < x and x <= col + cols and g.screen == m.screen;
                if (hit)
                    _ = self.placements.orderedRemove(i)
                else
                    i += 1;
            }
            changed = true;
            if (selector == 'C') sweep(self);
        },
        else => {
            self.respond(cmd, error.ENOTSUP, 0);
            return;
        },
    }
    if (changed) self.damage();
    self.respond(cmd, null, 0);
}

export fn kg_end(ptr: ?*c.struct_kg_engine) void {
    const self = engine(ptr) orelse return;
    if (self.packet_overflow or self.packet_len == 0) {
        self.cancel();
        self.packet_overflow = false;
        self.packet_len = 0;
        return;
    }
    const packet = self.packet[0..self.packet_len];
    self.packet_len = 0;
    self.packet_overflow = false;
    const semi = std.mem.indexOfScalar(u8, packet, ';');
    const header = if (semi) |s| packet[0..s] else packet;
    const payload = if (semi) |s| packet[s + 1 ..] else "";
    const cmd = protocol.parse(header) catch {
        self.cancel();
        return;
    };
    var decoded: [protocol.max_payload]u8 = undefined;
    const more = cmd.get('m', 0) == 1;
    const count = protocol.decode(payload, more, &decoded) catch {
        self.cancel();
        return;
    };
    if (cmd.continuation()) {
        if (self.pending_cmd == null) {
            self.respond(cmd, error.EINVAL, 0);
            return;
        }
        self.pending_data.appendSlice(allocator, decoded[0..count]) catch {
            self.cancel();
            return;
        };
        if (cmd.get('m', 0) == 0)
            finalize(self);
        return;
    }
    self.cancel();
    const action = cmd.get('a', 't');
    switch (action) {
        't', 'T' => {
            self.pending_cmd = cmd;
            self.pending_data.clearRetainingCapacity();
            self.pending_data.appendSlice(allocator, decoded[0..count]) catch {
                self.cancel();
                return;
            };
            if (cmd.get('m', 0) == 1)
                return;
            finalize(self);
        },
        'p' => placeExisting(self, cmd),
        'q' => query(self, cmd, decoded[0..count]),
        'd' => delete(self, cmd),
        else => self.respond(cmd, error.ENOTSUP, 0),
    }
}

export fn kg_placement_count(ptr: ?*c.struct_kg_engine) usize {
    const self = engine(ptr) orelse return 0;
    return self.placements.items.len;
}

export fn kg_get_placement(ptr: ?*c.struct_kg_engine, index: usize, out: *c.struct_kg_placement) bool {
    const self = engine(ptr) orelse return false;
    if (index >= self.placements.items.len) return false;
    out.* = self.placements.items[index].geometry;
    return true;
}

export fn kg_clear_screen(ptr: ?*c.struct_kg_engine, screen: c_int) void {
    const self = engine(ptr) orelse return;
    var i: usize = 0;
    var changed = false;
    while (i < self.placements.items.len) {
        if (self.placements.items[i].geometry.screen == screen) {
            _ = self.placements.orderedRemove(i);
            changed = true;
        } else i += 1;
    }
    if (changed) self.damage();
}

export fn kg_scroll(ptr: ?*c.struct_kg_engine, screen: c_int, top: c_int, bottom: c_int, rows: c_int, history_limit: c_int) void {
    const self = engine(ptr) orelse return;
    const m = nativeMetrics(self);
    const full_screen = top == 0 and bottom == m.rows;
    var changed = false;
    var i: usize = 0;
    while (i < self.placements.items.len) {
        const placement = &self.placements.items[i];
        if (placement.geometry.screen != screen) {
            i += 1;
            continue;
        }
        const row = placement.geometry.row;
        if (row >= top and row < bottom) {
            const moved = row - rows;
            if (full_screen) {
                if (moved < -history_limit) {
                    _ = self.placements.orderedRemove(i);
                    changed = true;
                    continue;
                }
            } else if (moved < top or moved >= bottom) {
                _ = self.placements.orderedRemove(i);
                changed = true;
                continue;
            }
            placement.geometry.row = moved;
            changed = true;
        }
        i += 1;
    }
    if (changed) self.damage();
}
