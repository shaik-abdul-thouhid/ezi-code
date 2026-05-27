const std = @import("std");

pub const Endian = enum {
    big,
    little,
};

pub const SliceConversionError = error{
    OddLengthBytes,
    InvalidLengthBytes,
    BufferTooSmall,
    InvalidValue,
    Overflow,
};

fn maxValueForBytes(comptime T: type, width: u4) T {
    const bits = @as(u16, width) * 8;
    if (bits >= @bitSizeOf(T)) {
        return std.math.maxInt(T);
    }

    const Shift = std.math.Log2Int(T);
    return (@as(T, 1) << @as(Shift, @intCast(bits))) - 1;
}

fn validateIntByteWidth(comptime T: type, value: T, width: u4) SliceConversionError!void {
    if (width == 0 or width > @sizeOf(T)) {
        return error.InvalidLengthBytes;
    }

    if (value > maxValueForBytes(T, width)) {
        return error.InvalidValue;
    }
}

fn writeIntBytes(comptime T: type, value: T, bytes: []u8, offset: usize, endian: Endian, width: u4) void {
    const Shift = std.math.Log2Int(T);
    var i: usize = 0;

    while (i < width) : (i += 1) {
        const byte_index = switch (endian) {
            .big => width - 1 - i,
            .little => i,
        };
        const shift = @as(Shift, @intCast(byte_index * 8));
        bytes[offset + i] = @as(u8, @truncate(value >> shift));
    }
}

pub fn intSliceToBytesLen(
    comptime T: type,
    input: []const T,
    comptime widthFor: fn (value: T, index: usize) anyerror!u4,
) !usize {
    var required: usize = 0;

    for (input, 0..) |value, index| {
        const width = try widthFor(value, index);
        try validateIntByteWidth(T, value, width);
        required = std.math.add(usize, required, width) catch return error.Overflow;
    }

    return required;
}

pub fn intSliceToBytesBuffer(
    comptime T: type,
    input: []const T,
    bytes: []u8,
    endian: Endian,
    comptime widthFor: fn (value: T, index: usize) anyerror!u4,
) !usize {
    const required = try intSliceToBytesLen(T, input, widthFor);

    if (bytes.len < required) {
        return error.BufferTooSmall;
    }

    var out_index: usize = 0;
    for (input, 0..) |value, index| {
        const width = try widthFor(value, index);
        writeIntBytes(T, value, bytes, out_index, endian, width);
        out_index = std.math.add(usize, out_index, width) catch return error.Overflow;
    }

    return required;
}

pub fn intSliceToBytes(
    allocator: std.mem.Allocator,
    comptime T: type,
    input: []const T,
    endian: Endian,
    comptime widthFor: fn (value: T, index: usize) anyerror!u4,
) ![]u8 {
    const required = try intSliceToBytesLen(T, input, widthFor);
    const out = try allocator.alloc(u8, required);
    errdefer allocator.free(out);

    _ = try intSliceToBytesBuffer(T, input, out, endian, widthFor);
    return out;
}

pub fn bytesToU16SliceBuffer(
    bytes: []const u8,
    buf: []u16,
    endian: Endian,
    comptime validator: ?fn (c16: u16, index: usize) anyerror!void,
) !usize {
    if (bytes.len % 2 != 0) {
        return error.OddLengthBytes;
    }

    const out_len = bytes.len / 2;

    if (buf.len < out_len) {
        return error.BufferTooSmall;
    }

    var i: usize = 0;
    var out_index: usize = 0;

    while (i < bytes.len) : ({
        i += 2;
        out_index += 1;
    }) {
        const value: u16 = switch (endian) {
            .big => (@as(u16, bytes[i]) << 8) |
                @as(u16, bytes[i + 1]),

            .little => (@as(u16, bytes[i + 1]) << 8) |
                @as(u16, bytes[i]),
        };

        if (validator) |v| {
            try v(value, out_index);
        }

        buf[out_index] = value;
    }

    return out_len;
}

pub fn u16SliceToBytesBuffer(buf: []const u16, bytes: []u8, endian: Endian) !usize {
    const required = std.math.mul(usize, buf.len, @sizeOf(u16)) catch return error.Overflow;

    if (bytes.len < required) {
        return error.BufferTooSmall;
    }

    var i: usize = 0;

    for (buf) |value| {
        switch (endian) {
            .big => {
                bytes[i] = @as(u8, @truncate(value >> 8));
                bytes[i + 1] = @as(u8, @truncate(value));
            },

            .little => {
                bytes[i] = @as(u8, @truncate(value));
                bytes[i + 1] = @as(u8, @truncate(value >> 8));
            },
        }

        i += 2;
    }

    return required;
}

pub fn bytesToU32SliceBuffer(
    bytes: []const u8,
    buf: []u32,
    endian: Endian,
    comptime validator: ?fn (c32: u32, index: usize) anyerror!void,
) !usize {
    if (bytes.len % 4 != 0) {
        return error.InvalidLengthBytes;
    }

    const out_len = bytes.len / 4;

    if (buf.len < out_len) {
        return error.BufferTooSmall;
    }

    var i: usize = 0;
    var out_index: usize = 0;

    while (i < bytes.len) : ({
        i += 4;
        out_index += 1;
    }) {
        const value: u32 = switch (endian) {
            .big => (@as(u32, bytes[i]) << 24) |
                (@as(u32, bytes[i + 1]) << 16) |
                (@as(u32, bytes[i + 2]) << 8) |
                @as(u32, bytes[i + 3]),

            .little => (@as(u32, bytes[i + 3]) << 24) |
                (@as(u32, bytes[i + 2]) << 16) |
                (@as(u32, bytes[i + 1]) << 8) |
                @as(u32, bytes[i]),
        };

        if (validator) |v| {
            try v(value, out_index);
        }

        buf[out_index] = value;
    }

    return out_len;
}

pub fn u32SliceToBytesBuffer(buf: []const u32, bytes: []u8, endian: Endian) !usize {
    const required = std.math.mul(usize, buf.len, @sizeOf(u32)) catch return error.Overflow;

    if (bytes.len < required) {
        return error.BufferTooSmall;
    }

    var i: usize = 0;

    for (buf) |value| {
        switch (endian) {
            .big => {
                bytes[i] = @as(u8, @truncate(value >> 24));
                bytes[i + 1] = @as(u8, @truncate(value >> 16));
                bytes[i + 2] = @as(u8, @truncate(value >> 8));
                bytes[i + 3] = @as(u8, @truncate(value));
            },

            .little => {
                bytes[i] = @as(u8, @truncate(value));
                bytes[i + 1] = @as(u8, @truncate(value >> 8));
                bytes[i + 2] = @as(u8, @truncate(value >> 16));
                bytes[i + 3] = @as(u8, @truncate(value >> 24));
            },
        }

        i += 4;
    }

    return required;
}

pub fn bytesToU16SliceComptime(comptime bytes: []const u8, comptime endian: Endian) [
    if (bytes.len % 2 == 0)
        bytes.len / 2
    else
        @compileError("invalid u16 byte length")
]u16 {
    comptime {
        var out: [bytes.len / 2]u16 = undefined;

        _ = try bytesToU16SliceBuffer(bytes, &out, endian, null);

        return out;
    }
}

pub fn u16SliceToBytesComptime(comptime buf: []const u16, comptime endian: Endian) [buf.len * 2]u8 {
    comptime {
        var out: [buf.len * 2]u8 = undefined;

        _ = try u16SliceToBytesBuffer(buf, &out, endian);

        return out;
    }
}

pub fn bytesToU32SliceComptime(comptime bytes: []const u8, comptime endian: Endian) [
    if (bytes.len % 4 == 0)
        bytes.len / 4
    else
        @compileError("invalid u32 byte length")
]u32 {
    comptime {
        var out: [bytes.len / 4]u32 = undefined;

        _ = try bytesToU32SliceBuffer(bytes, &out, endian, null);

        return out;
    }
}

pub fn u32SliceToBytesComptime(comptime buf: []const u32, comptime endian: Endian) [buf.len * 4]u8 {
    comptime {
        var out: [buf.len * 4]u8 = undefined;

        _ = try u32SliceToBytesBuffer(buf, &out, endian);

        return out;
    }
}

pub fn bytesToU16Slice(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    endian: Endian,
    comptime validator: ?fn (c16: u16, index: usize) anyerror!void,
) ![]u16 {
    if (bytes.len % 2 != 0) {
        return error.OddLengthBytes;
    }

    const out = try allocator.alloc(u16, bytes.len / 2);
    errdefer allocator.free(out);

    _ = try bytesToU16SliceBuffer(bytes, out, endian, validator);

    return out;
}

pub fn u16SliceToBytes(
    allocator: std.mem.Allocator,
    buf: []const u16,
    endian: Endian,
) ![]u8 {
    const byte_len = std.math.mul(usize, buf.len, @sizeOf(u16)) catch return error.Overflow;
    const out = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(out);

    _ = try u16SliceToBytesBuffer(buf, out, endian);

    return out;
}

pub fn bytesToU32Slice(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    endian: Endian,
    comptime validator: ?fn (c32: u32, index: usize) anyerror!void,
) ![]u32 {
    if (bytes.len % 4 != 0) {
        return error.InvalidLengthBytes;
    }

    const out = try allocator.alloc(u32, bytes.len / 4);
    errdefer allocator.free(out);

    _ = try bytesToU32SliceBuffer(bytes, out, endian, validator);

    return out;
}

pub fn u32SliceToBytes(
    allocator: std.mem.Allocator,
    buf: []const u32,
    endian: Endian,
) ![]u8 {
    const byte_len = std.math.mul(usize, buf.len, @sizeOf(u32)) catch return error.Overflow;
    const out = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(out);

    _ = try u32SliceToBytesBuffer(buf, out, endian);

    return out;
}

pub fn u16SliceToU32SliceBuffer(input: []const u16, output: []u32) !usize {
    if (output.len < input.len) {
        return error.BufferTooSmall;
    }

    for (input, 0..) |value, i| {
        output[i] = value;
    }

    return input.len;
}

pub fn u32SliceToU16SliceBuffer(input: []const u32, output: []u16) !usize {
    if (output.len < input.len) {
        return error.BufferTooSmall;
    }

    for (input, 0..) |value, i| {
        if (value > std.math.maxInt(u16)) {
            return error.InvalidValue;
        }

        output[i] = @truncate(value);
    }

    return input.len;
}

pub fn u8SliceToU32SliceBuffer(input: []const u8, output: []u32) !usize {
    if (output.len < input.len) {
        return error.BufferTooSmall;
    }

    for (input, 0..) |value, i| {
        output[i] = value;
    }

    return input.len;
}

pub fn u32SliceToU8SliceBuffer(input: []const u32, output: []u8) !usize {
    if (output.len < input.len) {
        return error.BufferTooSmall;
    }

    for (input, 0..) |value, i| {
        if (value > std.math.maxInt(u8)) {
            return error.InvalidValue;
        }

        output[i] = @truncate(value);
    }

    return input.len;
}

pub fn u8SliceToU16SliceBuffer(input: []const u8, output: []u16) !usize {
    if (output.len < input.len) {
        return error.BufferTooSmall;
    }

    for (input, 0..) |value, i| {
        output[i] = value;
    }

    return input.len;
}

pub fn u16SliceToU8SliceBuffer(input: []const u16, output: []u8) !usize {
    if (output.len < input.len) {
        return error.BufferTooSmall;
    }

    for (input, 0..) |value, i| {
        if (value > std.math.maxInt(u8)) {
            return error.InvalidValue;
        }

        output[i] = @truncate(value);
    }

    return input.len;
}

pub fn u16SliceToU32SliceComptime(comptime input: []const u16) [input.len]u32 {
    comptime {
        var out: [input.len]u32 = undefined;

        _ = try u16SliceToU32SliceBuffer(input, &out);

        return out;
    }
}

pub fn u32SliceToU16SliceComptime(comptime input: []const u32) [input.len]u16 {
    comptime {
        var out: [input.len]u16 = undefined;

        _ = try u32SliceToU16SliceBuffer(input, &out);

        return out;
    }
}

pub fn u8SliceToU32SliceComptime(comptime input: []const u8) [input.len]u32 {
    comptime {
        var out: [input.len]u32 = undefined;

        _ = try u8SliceToU32SliceBuffer(input, &out);

        return out;
    }
}

pub fn u32SliceToU8SliceComptime(comptime input: []const u32) [input.len]u8 {
    comptime {
        var out: [input.len]u8 = undefined;

        _ = try u32SliceToU8SliceBuffer(input, &out);

        return out;
    }
}

pub fn u8SliceToU16SliceComptime(comptime input: []const u8) [input.len]u16 {
    comptime {
        var out: [input.len]u16 = undefined;

        _ = try u8SliceToU16SliceBuffer(input, &out);

        return out;
    }
}

pub fn u16SliceToU8SliceComptime(comptime input: []const u16) [input.len]u8 {
    comptime {
        var out: [input.len]u8 = undefined;

        _ = try u16SliceToU8SliceBuffer(input, &out);

        return out;
    }
}

fn rejectMaxU16(value: u16, _: usize) !void {
    if (value == std.math.maxInt(u16)) {
        return error.InvalidValue;
    }
}

fn rejectMaxU32(value: u32, _: usize) !void {
    if (value == std.math.maxInt(u32)) {
        return error.InvalidValue;
    }
}

test "u16: zero length input" {
    var out: [0]u16 = .{};

    const n = try bytesToU16SliceBuffer(&.{}, &out, .big, null);

    try std.testing.expectEqual(@as(usize, 0), n);
}

test "u32: zero length input" {
    var out: [0]u32 = .{};

    const n = try bytesToU32SliceBuffer(&.{}, &out, .little, null);

    try std.testing.expectEqual(@as(usize, 0), n);
}

test "u16: buffer too small decode" {
    const bytes = [_]u8{ 0x12, 0x34, 0x56, 0x78 };

    var out: [1]u16 = undefined;

    try std.testing.expectError(
        error.BufferTooSmall,
        bytesToU16SliceBuffer(&bytes, &out, .big, null),
    );
}

test "u32: buffer too small decode" {
    const bytes = [_]u8{ 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0 };

    var out: [1]u32 = undefined;

    try std.testing.expectError(
        error.BufferTooSmall,
        bytesToU32SliceBuffer(&bytes, &out, .big, null),
    );
}

test "u16: buffer too small encode" {
    const input = [_]u16{ 0x1234, 0x5678 };

    var out: [3]u8 = undefined;

    try std.testing.expectError(
        error.BufferTooSmall,
        u16SliceToBytesBuffer(&input, &out, .big),
    );
}

test "u32: buffer too small encode" {
    const input = [_]u32{0x12345678};

    var out: [3]u8 = undefined;

    try std.testing.expectError(
        error.BufferTooSmall,
        u32SliceToBytesBuffer(&input, &out, .big),
    );
}

test "u16: endian inversion check" {
    const value = [_]u16{0x1234};

    var big: [2]u8 = undefined;
    var little: [2]u8 = undefined;

    _ = try u16SliceToBytesBuffer(&value, &big, .big);
    _ = try u16SliceToBytesBuffer(&value, &little, .little);

    try std.testing.expect(big[0] == little[1]);
    try std.testing.expect(big[1] == little[0]);
}

test "u32: endian inversion check" {
    const value = [_]u32{0x12345678};

    var big: [4]u8 = undefined;

    var little: [4]u8 = undefined;

    _ = try u32SliceToBytesBuffer(&value, &big, .big);

    _ = try u32SliceToBytesBuffer(&value, &little, .little);

    try std.testing.expect(big[0] == little[3]);
    try std.testing.expect(big[1] == little[2]);
    try std.testing.expect(big[2] == little[1]);
    try std.testing.expect(big[3] == little[0]);
}

test "u16: alternating bit patterns" {
    const values = [_]u16{ 0xAAAA, 0x5555, 0xF0F0, 0x0F0F };

    var bytes: [8]u8 = undefined;
    var decoded: [4]u16 = undefined;

    _ = try u16SliceToBytesBuffer(&values, &bytes, .big);
    _ = try bytesToU16SliceBuffer(&bytes, &decoded, .big, null);

    try std.testing.expectEqualSlices(u16, &values, &decoded);
}

test "u32: alternating bit patterns" {
    const values = [_]u32{ 0xAAAAAAAA, 0x55555555, 0xF0F0F0F0, 0x0F0F0F0F };

    var bytes: [16]u8 = undefined;
    var decoded: [4]u32 = undefined;

    _ = try u32SliceToBytesBuffer(&values, &bytes, .little);
    _ = try bytesToU32SliceBuffer(&bytes, &decoded, .little, null);

    try std.testing.expectEqualSlices(u32, &values, &decoded);
}

test "u16: validator receives correct index" {
    const bytes = [_]u8{ 0x00, 0x01, 0x00, 0x02, 0x00, 0x03 };

    const Validator = struct {
        fn validate(value: u16, index: usize) !void {
            switch (index) {
                0 => try std.testing.expectEqual(@as(u16, 1), value),
                1 => try std.testing.expectEqual(@as(u16, 2), value),
                2 => try std.testing.expectEqual(@as(u16, 3), value),
                else => return error.BadIndex,
            }
        }
    };

    var out: [3]u16 = undefined;

    _ = try bytesToU16SliceBuffer(&bytes, &out, .big, Validator.validate);
}

test "u32: validator receives correct index" {
    const bytes = [_]u8{ 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02 };

    const Validator = struct {
        fn validate(value: u32, index: usize) !void {
            switch (index) {
                0 => try std.testing.expectEqual(@as(u32, 1), value),
                1 => try std.testing.expectEqual(@as(u32, 2), value),
                else => return error.BadIndex,
            }
        }
    };

    var out: [2]u32 = undefined;

    _ = try bytesToU32SliceBuffer(&bytes, &out, .big, Validator.validate);
}

test "u16: large sweep roundtrip" {
    var values: [1024]u16 = undefined;

    for (&values, 0..) |*v, i| {
        v.* = @truncate(i * 37);
    }

    var bytes: [2048]u8 = undefined;
    var decoded: [1024]u16 = undefined;

    _ = try u16SliceToBytesBuffer(&values, &bytes, .little);
    _ = try bytesToU16SliceBuffer(&bytes, &decoded, .little, null);

    try std.testing.expectEqualSlices(u16, &values, &decoded);
}

test "u32: large sweep roundtrip" {
    var values: [512]u32 = undefined;

    for (&values, 0..) |*v, i| {
        v.* = @truncate(i * 7919);
    }

    var bytes: [2048]u8 = undefined;
    var decoded: [512]u32 = undefined;

    _ = try u32SliceToBytesBuffer(&values, &bytes, .big);
    _ = try bytesToU32SliceBuffer(&bytes, &decoded, .big, null);

    try std.testing.expectEqualSlices(u32, &values, &decoded);
}

test "u16: exact bytes written" {
    const input = [_]u16{ 0xAAAA, 0xBBBB };

    var out: [4]u8 = undefined;

    const n = try u16SliceToBytesBuffer(&input, &out, .big);

    try std.testing.expectEqual(@as(usize, 4), n);
}

test "u32: exact bytes written" {
    const input = [_]u32{0xAAAAAAAA};

    var out: [4]u8 = undefined;

    const n = try u32SliceToBytesBuffer(&input, &out, .little);

    try std.testing.expectEqual(@as(usize, 4), n);
}

test "generic intSliceToBytesBuffer: u32 variable width big endian" {
    const input = [_]u32{ 0x7F, 0x1234, 0xABCDEF, 0x12345678 };

    const Width = struct {
        fn minimal(value: u32, _: usize) !u4 {
            if (value <= 0xFF) return 1;
            if (value <= 0xFFFF) return 2;
            if (value <= 0xFFFFFF) return 3;
            return 4;
        }
    };

    var out: [10]u8 = undefined;
    const n = try intSliceToBytesBuffer(u32, &input, &out, .big, Width.minimal);

    try std.testing.expectEqual(@as(usize, 10), n);
    try std.testing.expectEqualSlices(u8, &.{
        0x7F,
        0x12,
        0x34,
        0xAB,
        0xCD,
        0xEF,
        0x12,
        0x34,
        0x56,
        0x78,
    }, out[0..n]);
}

test "generic intSliceToBytesBuffer: u32 variable width little endian" {
    const input = [_]u32{ 0x7F, 0x1234, 0xABCDEF, 0x12345678 };

    const Width = struct {
        fn minimal(value: u32, _: usize) !u4 {
            if (value <= 0xFF) return 1;
            if (value <= 0xFFFF) return 2;
            if (value <= 0xFFFFFF) return 3;
            return 4;
        }
    };

    var out: [10]u8 = undefined;
    const n = try intSliceToBytesBuffer(u32, &input, &out, .little, Width.minimal);

    try std.testing.expectEqual(@as(usize, 10), n);
    try std.testing.expectEqualSlices(u8, &.{
        0x7F,
        0x34,
        0x12,
        0xEF,
        0xCD,
        0xAB,
        0x78,
        0x56,
        0x34,
        0x12,
    }, out[0..n]);
}

test "generic intSliceToBytesBuffer: width validation rejects impossible u32 narrowing" {
    const input = [_]u32{0x100};

    const Width = struct {
        fn one(_: u32, _: usize) !u4 {
            return 1;
        }
    };

    var out: [4]u8 = undefined;
    try std.testing.expectError(
        error.InvalidValue,
        intSliceToBytesBuffer(u32, &input, &out, .big, Width.one),
    );
}

test "generic intSliceToBytesBuffer: u16 variable width" {
    const input = [_]u16{ 0x7F, 0x1234 };

    const Width = struct {
        fn minimal(value: u16, _: usize) !u4 {
            return if (value <= 0xFF) 1 else 2;
        }
    };

    var out: [3]u8 = undefined;
    const n = try intSliceToBytesBuffer(u16, &input, &out, .big, Width.minimal);

    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(u8, &.{ 0x7F, 0x12, 0x34 }, out[0..n]);
}

test "fixed-width byte encoders reject length multiplication overflow before reading input" {
    const huge_u16_ptr: [*]const u16 = @ptrFromInt(0x1000);
    const huge_u32_ptr: [*]const u32 = @ptrFromInt(0x1000);
    var huge_u16_len: usize = std.math.maxInt(usize) / @sizeOf(u16) + 1;
    var huge_u32_len: usize = std.math.maxInt(usize) / @sizeOf(u32) + 1;
    huge_u16_len += 0;
    huge_u32_len += 0;
    const huge_u16 = huge_u16_ptr[0..huge_u16_len];
    const huge_u32 = huge_u32_ptr[0..huge_u32_len];

    var empty: [0]u8 = .{};
    try std.testing.expectError(error.Overflow, u16SliceToBytesBuffer(huge_u16, &empty, .big));
    try std.testing.expectError(error.Overflow, u32SliceToBytesBuffer(huge_u32, &empty, .little));
}

test "allocator u16 OutOfMemory" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );

    try std.testing.expectError(
        error.OutOfMemory,
        bytesToU16Slice(failing.allocator(), &[_]u8{ 0x12, 0x34 }, .big, null),
    );
}

test "allocator u32 OutOfMemory" {
    var failing = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 0 },
    );

    try std.testing.expectError(
        error.OutOfMemory,
        bytesToU32Slice(failing.allocator(), &[_]u8{ 0x12, 0x34, 0x56, 0x78 }, .big, null),
    );
}

test "u16 comptime hostile patterns" {
    const decoded = comptime bytesToU16SliceComptime(&[_]u8{ 0xFF, 0xFF, 0x00, 0x00, 0xAA, 0x55 }, .big);

    try comptime std.testing.expect(decoded[0] == 0xFFFF);
    try comptime std.testing.expect(decoded[1] == 0x0000);
    try comptime std.testing.expect(decoded[2] == 0xAA55);
}

test "u32 comptime hostile patterns" {
    const decoded = comptime bytesToU32SliceComptime(&[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00 }, .big);

    try comptime std.testing.expect(decoded[0] == 0xFFFFFFFF);
    try comptime std.testing.expect(decoded[1] == 0x00000000);
}

test "u16 -> u32 conversion" {
    const input = [_]u16{ 0x0000, 0x1234, 0xFFFF };

    var out: [3]u32 = undefined;

    const n = try u16SliceToU32SliceBuffer(&input, &out);

    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0x0000, 0x1234, 0xFFFF }, &out);
}

test "u32 -> u16 conversion" {
    const input = [_]u32{ 0x0000, 0x1234, 0xFFFF };

    var out: [3]u16 = undefined;

    const n = try u32SliceToU16SliceBuffer(&input, &out);

    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualSlices(u16, &[_]u16{ 0x0000, 0x1234, 0xFFFF }, &out);
}

test "u32 -> u16 overflow rejection" {
    const input = [_]u32{0x10000};

    var out: [1]u16 = undefined;

    try std.testing.expectError(
        error.InvalidValue,
        u32SliceToU16SliceBuffer(&input, &out),
    );
}

test "u8 -> u16 conversion" {
    const input = [_]u8{ 0x00, 0x7F, 0xFF };

    var out: [3]u16 = undefined;

    _ = try u8SliceToU16SliceBuffer(&input, &out);

    try std.testing.expectEqualSlices(u16, &[_]u16{ 0x00, 0x7F, 0xFF }, &out);
}

test "u16 -> u8 conversion" {
    const input = [_]u16{ 0x00, 0x7F, 0xFF };

    var out: [3]u8 = undefined;

    _ = try u16SliceToU8SliceBuffer(&input, &out);

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x7F, 0xFF }, &out);
}

test "u16 -> u8 overflow rejection" {
    const input = [_]u16{0x0100};

    var out: [1]u8 = undefined;

    try std.testing.expectError(
        error.InvalidValue,
        u16SliceToU8SliceBuffer(&input, &out),
    );
}

test "u8 -> u32 conversion" {
    const input = [_]u8{ 0x00, 0x7F, 0xFF };

    var out: [3]u32 = undefined;

    _ = try u8SliceToU32SliceBuffer(&input, &out);

    try std.testing.expectEqualSlices(u32, &[_]u32{ 0x00, 0x7F, 0xFF }, &out);
}

test "u32 -> u8 conversion" {
    const input = [_]u32{ 0x00, 0x7F, 0xFF };

    var out: [3]u8 = undefined;

    _ = try u32SliceToU8SliceBuffer(&input, &out);

    try std.testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0x7F, 0xFF }, &out);
}

test "u32 -> u8 overflow rejection" {
    const input = [_]u32{256};

    var out: [1]u8 = undefined;

    try std.testing.expectError(
        error.InvalidValue,
        u32SliceToU8SliceBuffer(&input, &out),
    );
}

test "interconversion roundtrip u8 <-> u16" {
    const original = [_]u8{ 1, 2, 3, 200, 255 };

    var widened: [5]u16 = undefined;
    var narrowed: [5]u8 = undefined;

    _ = try u8SliceToU16SliceBuffer(&original, &widened);
    _ = try u16SliceToU8SliceBuffer(&widened, &narrowed);

    try std.testing.expectEqualSlices(u8, &original, &narrowed);
}

test "interconversion roundtrip u8 <-> u32" {
    const original = [_]u8{ 1, 2, 3, 200, 255 };

    var widened: [5]u32 = undefined;
    var narrowed: [5]u8 = undefined;

    _ = try u8SliceToU32SliceBuffer(&original, &widened);
    _ = try u32SliceToU8SliceBuffer(&widened, &narrowed);

    try std.testing.expectEqualSlices(u8, &original, &narrowed);
}

test "interconversion roundtrip u16 <-> u32" {
    const original = [_]u16{ 0x0000, 0x1234, 0xFFFF };

    var widened: [3]u32 = undefined;
    var narrowed: [3]u16 = undefined;

    _ = try u16SliceToU32SliceBuffer(&original, &widened);
    _ = try u32SliceToU16SliceBuffer(&widened, &narrowed);

    try std.testing.expectEqualSlices(u16, &original, &narrowed);
}

test "comptime interconversion variants" {
    const a = comptime u8SliceToU16SliceComptime(&[_]u8{ 1, 2, 255 });
    try comptime std.testing.expect(a[0] == 1);
    try comptime std.testing.expect(a[2] == 255);

    const b = comptime u16SliceToU32SliceComptime(&[_]u16{ 0x1234, 0xFFFF });
    try comptime std.testing.expect(b[0] == 0x1234);
    try comptime std.testing.expect(b[1] == 0xFFFF);

    const c = comptime u32SliceToU16SliceComptime(&[_]u32{ 0x1234, 0xFFFF });
    try comptime std.testing.expect(c[0] == 0x1234);
    try comptime std.testing.expect(c[1] == 0xFFFF);

    const d = comptime u32SliceToU8SliceComptime(&[_]u32{ 1, 2, 255 });
    try comptime std.testing.expect(d[0] == 1);
    try comptime std.testing.expect(d[2] == 255);
}

test "interconversion hostile large sweep" {
    var values: [1024]u8 = undefined;

    for (&values, 0..) |*v, i| {
        v.* = @truncate(i % 256);
    }

    var u16s: [1024]u16 = undefined;
    var u32s: [1024]u32 = undefined;
    var final: [1024]u8 = undefined;

    _ = try u8SliceToU16SliceBuffer(&values, &u16s);
    _ = try u16SliceToU32SliceBuffer(&u16s, &u32s);
    _ = try u32SliceToU8SliceBuffer(&u32s, &final);

    try std.testing.expectEqualSlices(u8, &values, &final);
}
