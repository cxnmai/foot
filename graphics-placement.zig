const std = @import("std");
const c = @import("graphics_abi");

pub const Placement = struct { image: usize, id: u32, geometry: c.struct_kg_placement };

pub fn put(list: *std.ArrayList(Placement), allocator: std.mem.Allocator, limit: usize, value: Placement) error{ENOSPC}!void {
    // Nonzero placement IDs are unique per image. Replacement must also work
    // at capacity; p=0 always creates a separate anonymous placement.
    if (value.id != 0) {
        for (list.items) |*old| {
            if (old.image == value.image and old.id == value.id) {
                old.* = value;
                return;
            }
        }
    }
    if (list.items.len >= limit) return error.ENOSPC;
    list.append(allocator, value) catch return error.ENOSPC;
}

test "named placements replace at capacity; anonymous and other images append" {
    const allocator = std.testing.allocator;
    var list: std.ArrayList(Placement) = .empty;
    defer list.deinit(allocator);
    var value: Placement = .{ .image = 0, .id = 1, .geometry = std.mem.zeroes(c.struct_kg_placement) };
    try put(&list, allocator, 3, value);
    value.id = 0;
    try put(&list, allocator, 3, value);
    try put(&list, allocator, 3, value);
    value.id = 1;
    for (0..10000) |i| {
        value.geometry.col = @intCast(i);
        try put(&list, allocator, 3, value);
    }
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(@as(c_int, 9999), list.items[0].geometry.col);
    value.image = 1;
    try std.testing.expectError(error.ENOSPC, put(&list, allocator, 3, value));
    try put(&list, allocator, 4, value);
    try std.testing.expectEqual(@as(usize, 4), list.items.len);
}
