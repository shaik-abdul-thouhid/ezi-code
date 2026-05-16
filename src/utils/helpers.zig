const std = @import("std");

pub fn isInRange(comptime T: type, range_start: T, range_end: T, value: T) bool {
    return value >= range_start and value <= range_end;
}

pub fn every(comptime T: type, elements: []const T, predicate: fn (T) bool) bool {
    for (elements) |element| {
        if (!predicate(element)) return false;
    }
    return true;
}

test "isInRange: inclusive unsigned bounds" {
    try std.testing.expect(isInRange(u8, 0, 255, 0));
    try std.testing.expect(isInRange(u8, 0, 255, 255));
    try std.testing.expect(isInRange(u8, 10, 20, 15));
    try std.testing.expect(!isInRange(u8, 10, 20, 9));
    try std.testing.expect(!isInRange(u8, 10, 20, 21));
}

test "isInRange: degenerate single-value range" {
    try std.testing.expect(isInRange(u32, 42, 42, 42));
    try std.testing.expect(!isInRange(u32, 42, 42, 41));
    try std.testing.expect(!isInRange(u32, 42, 42, 43));
}

test "isInRange: signed integers" {
    try std.testing.expect(isInRange(i32, -100, 100, -100));
    try std.testing.expect(isInRange(i32, -100, 100, 100));
    try std.testing.expect(isInRange(i32, -100, 100, 0));
    try std.testing.expect(!isInRange(i32, -100, 100, -101));
    try std.testing.expect(!isInRange(i32, -100, 100, 101));
}

test "isInRange: reversed range (start > end) yields false for typical interior values" {
    // Documented behavior: comparison is value >= start AND value <= end; if start > end, almost nothing matches.
    try std.testing.expect(!isInRange(u8, 20, 10, 15));
}

test "every: empty slice is vacuously true" {
    const is_even = struct {
        fn f(x: i32) bool {
            return @rem(x, 2) == 0;
        }
    }.f;
    try std.testing.expect(every(i32, &[_]i32{}, is_even));
}

test "every: all elements pass" {
    const is_positive = struct {
        fn f(x: i32) bool {
            return x > 0;
        }
    }.f;
    try std.testing.expect(every(i32, &[_]i32{ 1, 2, 3 }, is_positive));
}

test "every: first failure" {
    const under_ten = struct {
        fn f(x: u32) bool {
            return x < 10;
        }
    }.f;
    try std.testing.expect(!every(u32, &[_]u32{ 1, 2, 99, 3 }, under_ten));
}

test "every: single element" {
    const id = struct {
        fn f(b: bool) bool {
            return b;
        }
    }.f;
    try std.testing.expect(every(bool, &[_]bool{true}, id));
    try std.testing.expect(!every(bool, &[_]bool{false}, id));
}

test "every: all u8 non-zero" {
    const nz = struct {
        fn f(x: u8) bool {
            return x != 0;
        }
    }.f;
    try std.testing.expect(every(u8, &[_]u8{ 1, 2, 3 }, nz));
    try std.testing.expect(!every(u8, &[_]u8{ 1, 0, 3 }, nz));
}
