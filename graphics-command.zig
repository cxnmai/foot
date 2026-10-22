const std = @import("std");

pub const max_header = 4096;
pub const max_payload = 8192;
pub const max_bytes = 64 * 1024 * 1024;
pub const Failure = error{ EINVAL, ENOSPC, ENOENT, ENOTSUP };

// Presence is distinct from zero: continuation packets may only carry m/q.
pub const Command = struct {
    values: [128]i64 = @splat(0),
    present: [128]bool = @splat(false),

    pub fn has(self: Command, key: u7) bool {
        return self.present[key];
    }
    pub fn get(self: Command, key: u7, default: i64) i64 {
        return if (self.has(key)) self.values[key] else default;
    }
    pub fn unsigned(self: Command, key: u7, default: u32) u32 {
        return @intCast(self.get(key, default));
    }
    pub fn continuation(self: Command) bool {
        for (self.present, 0..) |present, key| {
            if (present and key != 'm' and key != 'q') return false;
        }
        return true;
    }
};

pub fn parse(header: []const u8) Failure!Command {
    if (header.len > max_header) return error.ENOSPC;
    var cmd = Command{};
    if (header.len == 0) return cmd;
    var parts = std.mem.splitScalar(u8, header, ',');
    while (parts.next()) |part| {
        if (part.len < 3 or part[1] != '=' or !std.ascii.isAlphabetic(part[0])) return error.EINVAL;
        const key: u7 = @intCast(part[0]);
        if (cmd.has(key)) return error.EINVAL;
        const value = part[2..];
        const number: i64 = if (std.mem.indexOfScalar(u8, "atod", key) != null) blk: {
            if (value.len != 1 or !std.ascii.isAlphabetic(value[0])) return error.EINVAL;
            break :blk value[0];
        } else blk: {
            if (value.len == 0 or value[0] == '+') return error.EINVAL;
            const n = std.fmt.parseInt(i64, value, 10) catch return error.EINVAL;
            if (key == 'z' or key == 'H' or key == 'V') {
                if (n < std.math.minInt(i32) or n > std.math.maxInt(i32)) return error.EINVAL;
            } else if (n < 0 or n > std.math.maxInt(u32)) return error.EINVAL;
            break :blk n;
        };
        cmd.present[key] = true;
        cmd.values[key] = number;
    }
    return cmd;
}

fn digit(byte: u8) Failure!u8 {
    return switch (byte) {
        'A'...'Z' => byte - 'A',
        'a'...'z' => byte - 'a' + 26,
        '0'...'9' => byte - '0' + 52,
        '+' => 62,
        '/' => 63,
        else => error.EINVAL,
    };
}

// Each Kitty packet is independently base64 aligned; padding is final-only.
pub fn decode(payload: []const u8, more: bool, out: []u8) Failure!usize {
    if (payload.len > max_payload) return error.ENOSPC;
    if (payload.len % 4 != 0) return error.EINVAL;
    var size: usize = 0;
    var index: usize = 0;
    while (index < payload.len) : (index += 4) {
        const block = payload[index..][0..4];
        const a = try digit(block[0]);
        const b = try digit(block[1]);
        const pad2 = block[2] == '=';
        const pad3 = block[3] == '=';
        if ((pad2 and !pad3) or ((pad2 or pad3) and (more or index + 4 != payload.len))) return error.EINVAL;
        const d2 = if (pad2) @as(u8, 0) else try digit(block[2]);
        const d3 = if (pad3) @as(u8, 0) else try digit(block[3]);
        if ((pad2 and b & 15 != 0) or (pad3 and !pad2 and d2 & 3 != 0)) return error.EINVAL;
        const count: usize = if (pad2) 1 else if (pad3) 2 else 3;
        if (size + count > out.len) return error.ENOSPC;
        out[size] = (a << 2) | (b >> 4);
        if (count > 1) out[size + 1] = (b << 4) | (d2 >> 2);
        if (count > 2) out[size + 2] = (d2 << 6) | d3;
        size += count;
    }
    return size;
}

test "graphics-command preserves presence and rejects overflow and malformed base64" {
    const cmd = try parse("a=T,f=32,s=360,v=423,o=z,m=1,i=4294967295,z=-2147483648");
    try std.testing.expectEqual(@as(u32, 4294967295), cmd.unsigned('i', 0));
    try std.testing.expect(!cmd.has('q'));
    try std.testing.expect((try parse("m=0,q=2")).continuation());
    try std.testing.expectError(error.EINVAL, parse("i=4294967296"));
    try std.testing.expectError(error.EINVAL, parse("z=-2147483649"));
    try std.testing.expectError(error.EINVAL, parse("m=1,m=0"));
    var buf: [6]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 4), try decode("AQIDBA==", false, &buf));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, buf[0..4]);
    try std.testing.expectError(error.EINVAL, decode("AQ==", true, &buf));
    try std.testing.expectError(error.EINVAL, decode("AB==", false, &buf));
}
