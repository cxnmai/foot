const std = @import("std");

// Bound work even for hostile titles and arbitrarily long combining sequences.
pub const byte_limit = 16384;
pub const Values = struct {
    index: []const u8 = "",
    title: []const u8 = "",
    activity: bool = false,
    bell: bool = false,
};

pub fn boundedString(ptr: [*c]const u8) []const u8 {
    if (ptr == null) return "";
    var len: usize = 0;
    while (len < byte_limit and ptr[len] != 0) : (len += 1) {}
    return ptr[0..len];
}

pub const Iterator = struct {
    format: []const u8,
    values: Values,
    value: []const u8 = "",
    budget: usize = byte_limit,
    expand: bool = true,

    pub fn init(format: []const u8, values: Values) Iterator {
        return .{ .format = format[0..@min(format.len, byte_limit)], .values = values };
    }

    pub fn literal(text: []const u8) Iterator {
        var it = init(text, .{});
        it.expand = false;
        return it;
    }

    pub fn next(self: *Iterator) ?u21 {
        while (self.budget > 0) {
            if (self.value.len == 0 and self.expand) {
                const fields = [_][]const u8{ "{index}", "{title}", "{activity}", "{bell}" };
                const values = [_][]const u8{
                    self.values.index,                 self.values.title,
                    if (self.values.activity) "•" else "",
                    if (self.values.bell) "*" else "",
                };
                var matched = false;
                for (fields, values) |field, value| {
                    if (std.mem.startsWith(u8, self.format, field)) {
                        self.format = self.format[field.len..];
                        self.value = value[0..@min(value.len, byte_limit)];
                        self.budget -= 1;
                        matched = true;
                        break;
                    }
                }
                if (matched) continue;
            }
            const source = if (self.value.len > 0) &self.value else &self.format;
            if (source.len == 0) return null;
            const len = std.unicode.utf8ByteSequenceLength(source.*[0]) catch 0;
            var consumed: usize = 1;
            const cp: u21 = if (len > 0 and len <= source.len) decoded: {
                const decoded = std.unicode.utf8Decode(source.*[0..len]) catch break :decoded 0xfffd;
                consumed = len;
                break :decoded decoded;
            } else 0xfffd;
            source.* = source.*[consumed..];
            self.budget -= 1;
            if (cp < 0x20 or (cp >= 0x7f and cp < 0xa0)) continue;
            return cp;
        }
        return null;
    }
};

pub const Character = struct { codepoint: u21, column: i32, width: i32 };

// Measurement and painting use this same scanner; leading combining marks vanish.
pub const Scanner = struct {
    iterator: Iterator,
    limit: i32,
    columns: i32 = 0,
    previous_width: i32 = 0,

    pub fn next(self: *Scanner, widthFn: anytype) ?Character {
        while (self.iterator.next()) |cp| {
            const width = widthFn(@as(u32, cp));
            if (width < 0 or (width == 0 and self.previous_width == 0)) continue;
            if (width > self.limit - self.columns) return null;
            const column = self.columns - (if (width == 0) self.previous_width else 0);
            self.columns += width;
            if (width > 0) self.previous_width = width;
            return .{ .codepoint = cp, .column = column, .width = width };
        }
        return null;
    }
};

pub fn measure(iterator: Iterator, limit: i32, widthFn: anytype) i32 {
    var scanner = Scanner{ .iterator = iterator, .limit = limit };
    while (scanner.next(widthFn) != null) {}
    return scanner.columns;
}

fn testWidth(cp: u32) i32 {
    return switch (cp) {
        0x301 => 0,
        0x754c => 2,
        else => 1,
    };
}

fn expectText(expected: []const u8, source: Iterator) !void {
    var it = source;
    var result: [256]u8 = undefined;
    var len: usize = 0;
    while (it.next()) |cp| {
        len += try std.unicode.utf8Encode(cp, result[len..]);
    }
    try std.testing.expectEqualStrings(expected, result[0..len]);
}

test "tab-label expands known fields once and preserves unknown fields literally" {
    try expectText("2: {bell}•*{unknown}", Iterator.init("{index}: {title}{activity}{bell}{unknown}", .{
        .index = "2",
        .title = "{bell}",
        .activity = true,
        .bell = true,
    }));
    try expectText("", Iterator.init("{title}{activity}{bell}", .{}));
    try expectText("{title}", Iterator.literal("{title}"));
}

test "tab-label sanitizes invalid UTF8 and controls without damaging replacement characters" {
    try expectText("a��b�c", Iterator.literal("a\xff\xc2b�\x1bc\x00\x7f\xc2\x80"));
    try expectText("�", Iterator.literal("\xe2"));
    try expectText("�(�", Iterator.literal("\xe2(\xa1"));
}

test "tab-label column bounds preserve wide and combining character alignment" {
    try std.testing.expectEqual(@as(i32, 3), measure(Iterator.literal("\u{301}a\u{301}界x"), 3, testWidth));
    try std.testing.expectEqual(@as(i32, 1), measure(Iterator.literal("a界"), 2, testWidth));
    var scanner = Scanner{ .iterator = Iterator.literal("界\u{301}x"), .limit = 3 };
    const wide = scanner.next(testWidth).?;
    const combining = scanner.next(testWidth).?;
    const final = scanner.next(testWidth).?;
    try std.testing.expectEqual(@as(i32, 2), wide.width);
    try std.testing.expectEqual(@as(i32, 0), combining.column);
    try std.testing.expectEqual(@as(i32, 2), final.column);
    try std.testing.expect(scanner.next(testWidth) == null);
}

test "tab-label bounds hostile input and repeated empty substitutions" {
    const huge: [byte_limit + 1]u8 = @splat('x');
    try std.testing.expectEqual(@as(i32, byte_limit), measure(Iterator.literal(&huge), 20000, testWidth));
    var empty: [7 * 2000]u8 = undefined;
    for (&empty, 0..) |*byte, i| byte.* = "{title}"[i % 7];
    try std.testing.expectEqual(@as(i32, 0), measure(Iterator.init(&empty, .{}), 1024, testWidth));
    try std.testing.expectEqual(@as(usize, 0), boundedString(null).len);
}
