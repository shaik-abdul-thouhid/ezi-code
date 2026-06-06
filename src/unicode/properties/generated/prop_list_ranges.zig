//! This file is auto-generated. Do not edit directly.
//! To regenerate run `zig build generate-ranges` in same level
//! as `build.zig` file.

const CodePoint = @import("encoding").CodePoint;

pub const Range = struct { start: CodePoint, end: CodePoint };

/// PropList White_Space ranges (the Unicode basis for the `\s` shorthand).
pub const white_space_ranges = [_]Range{
    .{ .start = 0x9, .end = 0xD },
    .{ .start = 0x20, .end = 0x20 },
    .{ .start = 0x85, .end = 0x85 },
    .{ .start = 0xA0, .end = 0xA0 },
    .{ .start = 0x1680, .end = 0x1680 },
    .{ .start = 0x2000, .end = 0x200A },
    .{ .start = 0x2028, .end = 0x2029 },
    .{ .start = 0x202F, .end = 0x202F },
    .{ .start = 0x205F, .end = 0x205F },
    .{ .start = 0x3000, .end = 0x3000 },
};

/// PropList Join_Control ranges (part of the `\w` shorthand definition).
pub const join_control_ranges = [_]Range{
    .{ .start = 0x200C, .end = 0x200D },
};
