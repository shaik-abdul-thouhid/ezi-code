const std = @import("std");

pub const utf8 = @import("utf8.zig");
pub const utf16 = @import("utf16.zig");
pub const utf32 = @import("utf32.zig");

pub const CodePoint = u21;

pub const INVALID_CODE_POINT: CodePoint = 0xFFFD;

test {
    std.testing.refAllDecls(utf8);
    std.testing.refAllDecls(utf16);
    std.testing.refAllDecls(utf32);
}
