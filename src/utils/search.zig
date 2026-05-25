const std = @import("std");

/// Generic binary search over a sorted slice. `compareFn` returns the order of
/// the search context relative to the inspected item: `.lt` when the context
/// is "less than" the item (continue in the lower half), `.gt` when "greater
/// than" (continue in the upper half), `.eq` when the item matches the search.
/// Returns the matching index, or null if no item compares equal.
pub fn binarySearch(
    comptime T: type,
    items: []const T,
    context: anytype,
    comptime compareFn: fn (@TypeOf(context), T) std.math.Order,
) ?usize {
    var lo: usize = 0;
    var hi: usize = items.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        switch (compareFn(context, items[mid])) {
            .lt => hi = mid,
            .gt => lo = mid + 1,
            .eq => return mid,
        }
    }
    return null;
}

/// Convenience wrapper for `binarySearch` that returns the matching entry by
/// value, or null when no item matches.
pub fn binarySearchEntry(
    comptime T: type,
    items: []const T,
    context: anytype,
    comptime compareFn: fn (@TypeOf(context), T) std.math.Order,
) ?T {
    const idx = binarySearch(T, items, context, compareFn) orelse return null;
    return items[idx];
}

/// Binary search a sorted slice of inclusive `[start, end]` ranges keyed on
/// struct fields named by `start_field` and `end_field`. Returns the entry
/// whose range contains `key`, or null. The slice must be sorted ascending by
/// `start_field` and the ranges must not overlap.
pub fn searchRange(
    comptime T: type,
    comptime K: type,
    comptime start_field: []const u8,
    comptime end_field: []const u8,
    items: []const T,
    key: K,
) ?T {
    var lo: usize = 0;
    var hi: usize = items.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const entry = items[mid];
        if (key < @field(entry, start_field)) {
            hi = mid;
        } else if (key > @field(entry, end_field)) {
            lo = mid + 1;
        } else {
            return entry;
        }
    }
    return null;
}

/// Predicate variant of `searchRange` for callers that only need a hit/miss
/// answer (eg. set-membership predicates).
pub inline fn containsInRange(
    comptime T: type,
    comptime K: type,
    comptime start_field: []const u8,
    comptime end_field: []const u8,
    items: []const T,
    key: K,
) bool {
    return searchRange(T, K, start_field, end_field, items, key) != null;
}

test "binarySearch: empty slice returns null" {
    const cmp = struct {
        fn f(needle: i32, item: i32) std.math.Order {
            return std.math.order(needle, item);
        }
    }.f;
    try std.testing.expectEqual(@as(?usize, null), binarySearch(i32, &[_]i32{}, @as(i32, 5), cmp));
}

test "binarySearch: hit and miss on sorted ints" {
    const cmp = struct {
        fn f(needle: i32, item: i32) std.math.Order {
            return std.math.order(needle, item);
        }
    }.f;
    const items = [_]i32{ -10, 0, 1, 3, 7, 42, 100 };
    try std.testing.expectEqual(@as(?usize, 0), binarySearch(i32, &items, @as(i32, -10), cmp));
    try std.testing.expectEqual(@as(?usize, 3), binarySearch(i32, &items, @as(i32, 3), cmp));
    try std.testing.expectEqual(@as(?usize, 6), binarySearch(i32, &items, @as(i32, 100), cmp));
    try std.testing.expectEqual(@as(?usize, null), binarySearch(i32, &items, @as(i32, 2), cmp));
    try std.testing.expectEqual(@as(?usize, null), binarySearch(i32, &items, @as(i32, 1000), cmp));
}

test "binarySearchEntry: returns entry by value" {
    const Entry = struct { key: u32, payload: u8 };
    const items = [_]Entry{
        .{ .key = 1, .payload = 'a' },
        .{ .key = 5, .payload = 'b' },
        .{ .key = 9, .payload = 'c' },
    };
    const cmp = struct {
        fn f(needle: u32, item: Entry) std.math.Order {
            return std.math.order(needle, item.key);
        }
    }.f;
    const hit = binarySearchEntry(Entry, &items, @as(u32, 5), cmp).?;
    try std.testing.expectEqual(@as(u8, 'b'), hit.payload);
    try std.testing.expectEqual(@as(?Entry, null), binarySearchEntry(Entry, &items, @as(u32, 6), cmp));
}

test "searchRange: hit on first, mid, last and interior of a range" {
    const Range = struct { start: u32, end: u32, tag: u8 };
    const items = [_]Range{
        .{ .start = 0x10, .end = 0x20, .tag = 'a' },
        .{ .start = 0x30, .end = 0x30, .tag = 'b' },
        .{ .start = 0x40, .end = 0x4F, .tag = 'c' },
    };
    try std.testing.expectEqual(@as(u8, 'a'), searchRange(Range, u32, "start", "end", &items, 0x10).?.tag);
    try std.testing.expectEqual(@as(u8, 'a'), searchRange(Range, u32, "start", "end", &items, 0x18).?.tag);
    try std.testing.expectEqual(@as(u8, 'a'), searchRange(Range, u32, "start", "end", &items, 0x20).?.tag);
    try std.testing.expectEqual(@as(u8, 'b'), searchRange(Range, u32, "start", "end", &items, 0x30).?.tag);
    try std.testing.expectEqual(@as(u8, 'c'), searchRange(Range, u32, "start", "end", &items, 0x4F).?.tag);
}

test "searchRange: miss in gaps and beyond bounds" {
    const Range = struct { lo: u32, hi: u32 };
    const items = [_]Range{
        .{ .lo = 5, .hi = 10 },
        .{ .lo = 20, .hi = 25 },
    };
    try std.testing.expectEqual(@as(?Range, null), searchRange(Range, u32, "lo", "hi", &items, 0));
    try std.testing.expectEqual(@as(?Range, null), searchRange(Range, u32, "lo", "hi", &items, 15));
    try std.testing.expectEqual(@as(?Range, null), searchRange(Range, u32, "lo", "hi", &items, 30));
}

test "searchRange: empty slice always misses" {
    const Range = struct { start: u21, end: u21 };
    try std.testing.expectEqual(@as(?Range, null), searchRange(Range, u21, "start", "end", &[_]Range{}, 0));
}

test "containsInRange: predicate over disjoint ranges" {
    const Range = struct { start: u21, end: u21 };
    const items = [_]Range{
        .{ .start = 'A', .end = 'Z' },
        .{ .start = 'a', .end = 'z' },
    };
    try std.testing.expect(containsInRange(Range, u21, "start", "end", &items, 'M'));
    try std.testing.expect(containsInRange(Range, u21, "start", "end", &items, 'm'));
    try std.testing.expect(!containsInRange(Range, u21, "start", "end", &items, '['));
    try std.testing.expect(!containsInRange(Range, u21, "start", "end", &items, '0'));
}
