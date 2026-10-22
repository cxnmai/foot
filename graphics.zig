const std = @import("std");
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
const Pending = struct { command: Command, data: std.ArrayList(u8) = .empty };
const Engine = struct {
    term: ?*c.struct_terminal,
    images: [max_images]?Image = @splat(null),
    placements: std.ArrayList(Placement) = .empty,
    bytes: usize = 0,
    next_id: u32 = 1,
    serial: u64 = 0,
    pending: ?Pending = null,
    packet: [1 + protocol.max_header + 1 + protocol.max_payload]u8 = undefined,
    packet_len: usize = 0,
    packet_overflow: bool = false,

    fn cancel(self: *Engine) void {
        if (self.pending) |*pending| pending.data.deinit(allocator);
        self.pending = null;
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
