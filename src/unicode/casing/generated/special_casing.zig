//! This file is auto-generated. Do not edit directly.
//! To regenerate run `zig build generate` in same level
//! as `build.zig` file.

const CodePoint = @import("encoding").CodePoint;

pub const Mapping = struct {
    lower: []const CodePoint,
    upper: []const CodePoint,
    title: []const CodePoint,
    locale: Locale,
    condition: Condition,
};

pub const CaseMapEntry = struct {
    code_point: CodePoint,
    mappings: []const Mapping,
};

pub const Condition = enum(u8) {
    none,
    after_i,
    not_before_dot,
    after_soft_dotted,
    more_above,
    final_sigma,

    /// panic if any other condition
    /// is used
    _,
};

pub const Locale = enum(u8) {
    none,
    az,
    tr,
    lt,

    /// panic if any other locale
    /// is used
    _,
};

// zig fmt: off
pub const mappings_table = [_]CaseMapEntry{
    .{
        .code_point = 0x49,
        .mappings = &.{
            .{ .lower = &.{ 0x69, 0x307, }, .upper = &.{ 0x49, }, .title = &.{ 0x49, }, .locale = .lt, .condition = .more_above },
            .{ .lower = &.{ 0x131, }, .upper = &.{ 0x49, }, .title = &.{ 0x49, }, .locale = .tr, .condition = .not_before_dot },
            .{ .lower = &.{ 0x131, }, .upper = &.{ 0x49, }, .title = &.{ 0x49, }, .locale = .az, .condition = .not_before_dot },
        }
    },
    .{
        .code_point = 0x4A,
        .mappings = &.{
            .{ .lower = &.{ 0x6A, 0x307, }, .upper = &.{ 0x4A, }, .title = &.{ 0x4A, }, .locale = .lt, .condition = .more_above },
        }
    },
    .{
        .code_point = 0x69,
        .mappings = &.{
            .{ .lower = &.{ 0x69, }, .upper = &.{ 0x130, }, .title = &.{ 0x130, }, .locale = .tr, .condition = .none },
            .{ .lower = &.{ 0x69, }, .upper = &.{ 0x130, }, .title = &.{ 0x130, }, .locale = .az, .condition = .none },
        }
    },
    .{
        .code_point = 0xCC,
        .mappings = &.{
            .{ .lower = &.{ 0x69, 0x307, 0x300, }, .upper = &.{ 0xCC, }, .title = &.{ 0xCC, }, .locale = .lt, .condition = .none },
        }
    },
    .{
        .code_point = 0xCD,
        .mappings = &.{
            .{ .lower = &.{ 0x69, 0x307, 0x301, }, .upper = &.{ 0xCD, }, .title = &.{ 0xCD, }, .locale = .lt, .condition = .none },
        }
    },
    .{
        .code_point = 0xDF,
        .mappings = &.{
            .{ .lower = &.{ 0xDF, }, .upper = &.{ 0x53, 0x53, }, .title = &.{ 0x53, 0x73, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x128,
        .mappings = &.{
            .{ .lower = &.{ 0x69, 0x307, 0x303, }, .upper = &.{ 0x128, }, .title = &.{ 0x128, }, .locale = .lt, .condition = .none },
        }
    },
    .{
        .code_point = 0x12E,
        .mappings = &.{
            .{ .lower = &.{ 0x12F, 0x307, }, .upper = &.{ 0x12E, }, .title = &.{ 0x12E, }, .locale = .lt, .condition = .more_above },
        }
    },
    .{
        .code_point = 0x130,
        .mappings = &.{
            .{ .lower = &.{ 0x69, 0x307, }, .upper = &.{ 0x130, }, .title = &.{ 0x130, }, .locale = .none, .condition = .none },
            .{ .lower = &.{ 0x69, }, .upper = &.{ 0x130, }, .title = &.{ 0x130, }, .locale = .tr, .condition = .none },
            .{ .lower = &.{ 0x69, }, .upper = &.{ 0x130, }, .title = &.{ 0x130, }, .locale = .az, .condition = .none },
        }
    },
    .{
        .code_point = 0x149,
        .mappings = &.{
            .{ .lower = &.{ 0x149, }, .upper = &.{ 0x2BC, 0x4E, }, .title = &.{ 0x2BC, 0x4E, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F0,
        .mappings = &.{
            .{ .lower = &.{ 0x1F0, }, .upper = &.{ 0x4A, 0x30C, }, .title = &.{ 0x4A, 0x30C, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x307,
        .mappings = &.{
            .{ .lower = &.{ 0x307, }, .upper = &.{}, .title = &.{}, .locale = .lt, .condition = .after_soft_dotted },
            .{ .lower = &.{}, .upper = &.{ 0x307, }, .title = &.{ 0x307, }, .locale = .tr, .condition = .after_i },
            .{ .lower = &.{}, .upper = &.{ 0x307, }, .title = &.{ 0x307, }, .locale = .az, .condition = .after_i },
        }
    },
    .{
        .code_point = 0x390,
        .mappings = &.{
            .{ .lower = &.{ 0x390, }, .upper = &.{ 0x399, 0x308, 0x301, }, .title = &.{ 0x399, 0x308, 0x301, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x3A3,
        .mappings = &.{
            .{ .lower = &.{ 0x3C2, }, .upper = &.{ 0x3A3, }, .title = &.{ 0x3A3, }, .locale = .none, .condition = .final_sigma },
        }
    },
    .{
        .code_point = 0x3B0,
        .mappings = &.{
            .{ .lower = &.{ 0x3B0, }, .upper = &.{ 0x3A5, 0x308, 0x301, }, .title = &.{ 0x3A5, 0x308, 0x301, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x587,
        .mappings = &.{
            .{ .lower = &.{ 0x587, }, .upper = &.{ 0x535, 0x552, }, .title = &.{ 0x535, 0x582, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1E96,
        .mappings = &.{
            .{ .lower = &.{ 0x1E96, }, .upper = &.{ 0x48, 0x331, }, .title = &.{ 0x48, 0x331, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1E97,
        .mappings = &.{
            .{ .lower = &.{ 0x1E97, }, .upper = &.{ 0x54, 0x308, }, .title = &.{ 0x54, 0x308, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1E98,
        .mappings = &.{
            .{ .lower = &.{ 0x1E98, }, .upper = &.{ 0x57, 0x30A, }, .title = &.{ 0x57, 0x30A, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1E99,
        .mappings = &.{
            .{ .lower = &.{ 0x1E99, }, .upper = &.{ 0x59, 0x30A, }, .title = &.{ 0x59, 0x30A, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1E9A,
        .mappings = &.{
            .{ .lower = &.{ 0x1E9A, }, .upper = &.{ 0x41, 0x2BE, }, .title = &.{ 0x41, 0x2BE, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F50,
        .mappings = &.{
            .{ .lower = &.{ 0x1F50, }, .upper = &.{ 0x3A5, 0x313, }, .title = &.{ 0x3A5, 0x313, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F52,
        .mappings = &.{
            .{ .lower = &.{ 0x1F52, }, .upper = &.{ 0x3A5, 0x313, 0x300, }, .title = &.{ 0x3A5, 0x313, 0x300, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F54,
        .mappings = &.{
            .{ .lower = &.{ 0x1F54, }, .upper = &.{ 0x3A5, 0x313, 0x301, }, .title = &.{ 0x3A5, 0x313, 0x301, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F56,
        .mappings = &.{
            .{ .lower = &.{ 0x1F56, }, .upper = &.{ 0x3A5, 0x313, 0x342, }, .title = &.{ 0x3A5, 0x313, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F80,
        .mappings = &.{
            .{ .lower = &.{ 0x1F80, }, .upper = &.{ 0x1F08, 0x399, }, .title = &.{ 0x1F88, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F81,
        .mappings = &.{
            .{ .lower = &.{ 0x1F81, }, .upper = &.{ 0x1F09, 0x399, }, .title = &.{ 0x1F89, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F82,
        .mappings = &.{
            .{ .lower = &.{ 0x1F82, }, .upper = &.{ 0x1F0A, 0x399, }, .title = &.{ 0x1F8A, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F83,
        .mappings = &.{
            .{ .lower = &.{ 0x1F83, }, .upper = &.{ 0x1F0B, 0x399, }, .title = &.{ 0x1F8B, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F84,
        .mappings = &.{
            .{ .lower = &.{ 0x1F84, }, .upper = &.{ 0x1F0C, 0x399, }, .title = &.{ 0x1F8C, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F85,
        .mappings = &.{
            .{ .lower = &.{ 0x1F85, }, .upper = &.{ 0x1F0D, 0x399, }, .title = &.{ 0x1F8D, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F86,
        .mappings = &.{
            .{ .lower = &.{ 0x1F86, }, .upper = &.{ 0x1F0E, 0x399, }, .title = &.{ 0x1F8E, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F87,
        .mappings = &.{
            .{ .lower = &.{ 0x1F87, }, .upper = &.{ 0x1F0F, 0x399, }, .title = &.{ 0x1F8F, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F88,
        .mappings = &.{
            .{ .lower = &.{ 0x1F80, }, .upper = &.{ 0x1F08, 0x399, }, .title = &.{ 0x1F88, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F89,
        .mappings = &.{
            .{ .lower = &.{ 0x1F81, }, .upper = &.{ 0x1F09, 0x399, }, .title = &.{ 0x1F89, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F8A,
        .mappings = &.{
            .{ .lower = &.{ 0x1F82, }, .upper = &.{ 0x1F0A, 0x399, }, .title = &.{ 0x1F8A, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F8B,
        .mappings = &.{
            .{ .lower = &.{ 0x1F83, }, .upper = &.{ 0x1F0B, 0x399, }, .title = &.{ 0x1F8B, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F8C,
        .mappings = &.{
            .{ .lower = &.{ 0x1F84, }, .upper = &.{ 0x1F0C, 0x399, }, .title = &.{ 0x1F8C, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F8D,
        .mappings = &.{
            .{ .lower = &.{ 0x1F85, }, .upper = &.{ 0x1F0D, 0x399, }, .title = &.{ 0x1F8D, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F8E,
        .mappings = &.{
            .{ .lower = &.{ 0x1F86, }, .upper = &.{ 0x1F0E, 0x399, }, .title = &.{ 0x1F8E, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F8F,
        .mappings = &.{
            .{ .lower = &.{ 0x1F87, }, .upper = &.{ 0x1F0F, 0x399, }, .title = &.{ 0x1F8F, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F90,
        .mappings = &.{
            .{ .lower = &.{ 0x1F90, }, .upper = &.{ 0x1F28, 0x399, }, .title = &.{ 0x1F98, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F91,
        .mappings = &.{
            .{ .lower = &.{ 0x1F91, }, .upper = &.{ 0x1F29, 0x399, }, .title = &.{ 0x1F99, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F92,
        .mappings = &.{
            .{ .lower = &.{ 0x1F92, }, .upper = &.{ 0x1F2A, 0x399, }, .title = &.{ 0x1F9A, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F93,
        .mappings = &.{
            .{ .lower = &.{ 0x1F93, }, .upper = &.{ 0x1F2B, 0x399, }, .title = &.{ 0x1F9B, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F94,
        .mappings = &.{
            .{ .lower = &.{ 0x1F94, }, .upper = &.{ 0x1F2C, 0x399, }, .title = &.{ 0x1F9C, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F95,
        .mappings = &.{
            .{ .lower = &.{ 0x1F95, }, .upper = &.{ 0x1F2D, 0x399, }, .title = &.{ 0x1F9D, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F96,
        .mappings = &.{
            .{ .lower = &.{ 0x1F96, }, .upper = &.{ 0x1F2E, 0x399, }, .title = &.{ 0x1F9E, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F97,
        .mappings = &.{
            .{ .lower = &.{ 0x1F97, }, .upper = &.{ 0x1F2F, 0x399, }, .title = &.{ 0x1F9F, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F98,
        .mappings = &.{
            .{ .lower = &.{ 0x1F90, }, .upper = &.{ 0x1F28, 0x399, }, .title = &.{ 0x1F98, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F99,
        .mappings = &.{
            .{ .lower = &.{ 0x1F91, }, .upper = &.{ 0x1F29, 0x399, }, .title = &.{ 0x1F99, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F9A,
        .mappings = &.{
            .{ .lower = &.{ 0x1F92, }, .upper = &.{ 0x1F2A, 0x399, }, .title = &.{ 0x1F9A, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F9B,
        .mappings = &.{
            .{ .lower = &.{ 0x1F93, }, .upper = &.{ 0x1F2B, 0x399, }, .title = &.{ 0x1F9B, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F9C,
        .mappings = &.{
            .{ .lower = &.{ 0x1F94, }, .upper = &.{ 0x1F2C, 0x399, }, .title = &.{ 0x1F9C, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F9D,
        .mappings = &.{
            .{ .lower = &.{ 0x1F95, }, .upper = &.{ 0x1F2D, 0x399, }, .title = &.{ 0x1F9D, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F9E,
        .mappings = &.{
            .{ .lower = &.{ 0x1F96, }, .upper = &.{ 0x1F2E, 0x399, }, .title = &.{ 0x1F9E, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1F9F,
        .mappings = &.{
            .{ .lower = &.{ 0x1F97, }, .upper = &.{ 0x1F2F, 0x399, }, .title = &.{ 0x1F9F, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA0,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA0, }, .upper = &.{ 0x1F68, 0x399, }, .title = &.{ 0x1FA8, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA1,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA1, }, .upper = &.{ 0x1F69, 0x399, }, .title = &.{ 0x1FA9, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA2,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA2, }, .upper = &.{ 0x1F6A, 0x399, }, .title = &.{ 0x1FAA, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA3,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA3, }, .upper = &.{ 0x1F6B, 0x399, }, .title = &.{ 0x1FAB, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA4,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA4, }, .upper = &.{ 0x1F6C, 0x399, }, .title = &.{ 0x1FAC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA5,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA5, }, .upper = &.{ 0x1F6D, 0x399, }, .title = &.{ 0x1FAD, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA6,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA6, }, .upper = &.{ 0x1F6E, 0x399, }, .title = &.{ 0x1FAE, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA7,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA7, }, .upper = &.{ 0x1F6F, 0x399, }, .title = &.{ 0x1FAF, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA8,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA0, }, .upper = &.{ 0x1F68, 0x399, }, .title = &.{ 0x1FA8, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FA9,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA1, }, .upper = &.{ 0x1F69, 0x399, }, .title = &.{ 0x1FA9, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FAA,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA2, }, .upper = &.{ 0x1F6A, 0x399, }, .title = &.{ 0x1FAA, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FAB,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA3, }, .upper = &.{ 0x1F6B, 0x399, }, .title = &.{ 0x1FAB, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FAC,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA4, }, .upper = &.{ 0x1F6C, 0x399, }, .title = &.{ 0x1FAC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FAD,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA5, }, .upper = &.{ 0x1F6D, 0x399, }, .title = &.{ 0x1FAD, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FAE,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA6, }, .upper = &.{ 0x1F6E, 0x399, }, .title = &.{ 0x1FAE, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FAF,
        .mappings = &.{
            .{ .lower = &.{ 0x1FA7, }, .upper = &.{ 0x1F6F, 0x399, }, .title = &.{ 0x1FAF, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FB2,
        .mappings = &.{
            .{ .lower = &.{ 0x1FB2, }, .upper = &.{ 0x1FBA, 0x399, }, .title = &.{ 0x1FBA, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FB3,
        .mappings = &.{
            .{ .lower = &.{ 0x1FB3, }, .upper = &.{ 0x391, 0x399, }, .title = &.{ 0x1FBC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FB4,
        .mappings = &.{
            .{ .lower = &.{ 0x1FB4, }, .upper = &.{ 0x386, 0x399, }, .title = &.{ 0x386, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FB6,
        .mappings = &.{
            .{ .lower = &.{ 0x1FB6, }, .upper = &.{ 0x391, 0x342, }, .title = &.{ 0x391, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FB7,
        .mappings = &.{
            .{ .lower = &.{ 0x1FB7, }, .upper = &.{ 0x391, 0x342, 0x399, }, .title = &.{ 0x391, 0x342, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FBC,
        .mappings = &.{
            .{ .lower = &.{ 0x1FB3, }, .upper = &.{ 0x391, 0x399, }, .title = &.{ 0x1FBC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FC2,
        .mappings = &.{
            .{ .lower = &.{ 0x1FC2, }, .upper = &.{ 0x1FCA, 0x399, }, .title = &.{ 0x1FCA, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FC3,
        .mappings = &.{
            .{ .lower = &.{ 0x1FC3, }, .upper = &.{ 0x397, 0x399, }, .title = &.{ 0x1FCC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FC4,
        .mappings = &.{
            .{ .lower = &.{ 0x1FC4, }, .upper = &.{ 0x389, 0x399, }, .title = &.{ 0x389, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FC6,
        .mappings = &.{
            .{ .lower = &.{ 0x1FC6, }, .upper = &.{ 0x397, 0x342, }, .title = &.{ 0x397, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FC7,
        .mappings = &.{
            .{ .lower = &.{ 0x1FC7, }, .upper = &.{ 0x397, 0x342, 0x399, }, .title = &.{ 0x397, 0x342, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FCC,
        .mappings = &.{
            .{ .lower = &.{ 0x1FC3, }, .upper = &.{ 0x397, 0x399, }, .title = &.{ 0x1FCC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FD2,
        .mappings = &.{
            .{ .lower = &.{ 0x1FD2, }, .upper = &.{ 0x399, 0x308, 0x300, }, .title = &.{ 0x399, 0x308, 0x300, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FD3,
        .mappings = &.{
            .{ .lower = &.{ 0x1FD3, }, .upper = &.{ 0x399, 0x308, 0x301, }, .title = &.{ 0x399, 0x308, 0x301, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FD6,
        .mappings = &.{
            .{ .lower = &.{ 0x1FD6, }, .upper = &.{ 0x399, 0x342, }, .title = &.{ 0x399, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FD7,
        .mappings = &.{
            .{ .lower = &.{ 0x1FD7, }, .upper = &.{ 0x399, 0x308, 0x342, }, .title = &.{ 0x399, 0x308, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FE2,
        .mappings = &.{
            .{ .lower = &.{ 0x1FE2, }, .upper = &.{ 0x3A5, 0x308, 0x300, }, .title = &.{ 0x3A5, 0x308, 0x300, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FE3,
        .mappings = &.{
            .{ .lower = &.{ 0x1FE3, }, .upper = &.{ 0x3A5, 0x308, 0x301, }, .title = &.{ 0x3A5, 0x308, 0x301, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FE4,
        .mappings = &.{
            .{ .lower = &.{ 0x1FE4, }, .upper = &.{ 0x3A1, 0x313, }, .title = &.{ 0x3A1, 0x313, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FE6,
        .mappings = &.{
            .{ .lower = &.{ 0x1FE6, }, .upper = &.{ 0x3A5, 0x342, }, .title = &.{ 0x3A5, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FE7,
        .mappings = &.{
            .{ .lower = &.{ 0x1FE7, }, .upper = &.{ 0x3A5, 0x308, 0x342, }, .title = &.{ 0x3A5, 0x308, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FF2,
        .mappings = &.{
            .{ .lower = &.{ 0x1FF2, }, .upper = &.{ 0x1FFA, 0x399, }, .title = &.{ 0x1FFA, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FF3,
        .mappings = &.{
            .{ .lower = &.{ 0x1FF3, }, .upper = &.{ 0x3A9, 0x399, }, .title = &.{ 0x1FFC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FF4,
        .mappings = &.{
            .{ .lower = &.{ 0x1FF4, }, .upper = &.{ 0x38F, 0x399, }, .title = &.{ 0x38F, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FF6,
        .mappings = &.{
            .{ .lower = &.{ 0x1FF6, }, .upper = &.{ 0x3A9, 0x342, }, .title = &.{ 0x3A9, 0x342, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FF7,
        .mappings = &.{
            .{ .lower = &.{ 0x1FF7, }, .upper = &.{ 0x3A9, 0x342, 0x399, }, .title = &.{ 0x3A9, 0x342, 0x345, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0x1FFC,
        .mappings = &.{
            .{ .lower = &.{ 0x1FF3, }, .upper = &.{ 0x3A9, 0x399, }, .title = &.{ 0x1FFC, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB00,
        .mappings = &.{
            .{ .lower = &.{ 0xFB00, }, .upper = &.{ 0x46, 0x46, }, .title = &.{ 0x46, 0x66, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB01,
        .mappings = &.{
            .{ .lower = &.{ 0xFB01, }, .upper = &.{ 0x46, 0x49, }, .title = &.{ 0x46, 0x69, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB02,
        .mappings = &.{
            .{ .lower = &.{ 0xFB02, }, .upper = &.{ 0x46, 0x4C, }, .title = &.{ 0x46, 0x6C, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB03,
        .mappings = &.{
            .{ .lower = &.{ 0xFB03, }, .upper = &.{ 0x46, 0x46, 0x49, }, .title = &.{ 0x46, 0x66, 0x69, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB04,
        .mappings = &.{
            .{ .lower = &.{ 0xFB04, }, .upper = &.{ 0x46, 0x46, 0x4C, }, .title = &.{ 0x46, 0x66, 0x6C, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB05,
        .mappings = &.{
            .{ .lower = &.{ 0xFB05, }, .upper = &.{ 0x53, 0x54, }, .title = &.{ 0x53, 0x74, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB06,
        .mappings = &.{
            .{ .lower = &.{ 0xFB06, }, .upper = &.{ 0x53, 0x54, }, .title = &.{ 0x53, 0x74, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB13,
        .mappings = &.{
            .{ .lower = &.{ 0xFB13, }, .upper = &.{ 0x544, 0x546, }, .title = &.{ 0x544, 0x576, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB14,
        .mappings = &.{
            .{ .lower = &.{ 0xFB14, }, .upper = &.{ 0x544, 0x535, }, .title = &.{ 0x544, 0x565, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB15,
        .mappings = &.{
            .{ .lower = &.{ 0xFB15, }, .upper = &.{ 0x544, 0x53B, }, .title = &.{ 0x544, 0x56B, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB16,
        .mappings = &.{
            .{ .lower = &.{ 0xFB16, }, .upper = &.{ 0x54E, 0x546, }, .title = &.{ 0x54E, 0x576, }, .locale = .none, .condition = .none },
        }
    },
    .{
        .code_point = 0xFB17,
        .mappings = &.{
            .{ .lower = &.{ 0xFB17, }, .upper = &.{ 0x544, 0x53D, }, .title = &.{ 0x544, 0x56D, }, .locale = .none, .condition = .none },
        }
    },
};
// zig fmt: on

fn findEntry(code_point: CodePoint) ?CaseMapEntry {
    var left: usize = 0;
    var right: usize = mappings_table.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const entry = mappings_table[mid];

        if (code_point < entry.code_point) {
            right = mid;
        } else if (code_point > entry.code_point) {
            left = mid + 1;
        } else return entry;
    }

    return null;
}

pub fn lookup(comptime locale: Locale, comptime condition: Condition, code_point: CodePoint) ?Mapping {
    const entry = findEntry(code_point) orelse return null;

    for (entry.mappings) |mapping| {
        if (mapping.locale == locale and mapping.condition == condition) return mapping;
    }

    if (comptime locale != .none and condition != .none) {
        for (entry.mappings) |mapping| {
            if (mapping.locale == locale and mapping.condition == .none) return mapping;
        }
    }

    if (comptime condition != .none) {
        for (entry.mappings) |mapping| {
            if (mapping.locale == .none and mapping.condition == condition) return mapping;
        }
    }

    for (entry.mappings) |mapping| {
        if (mapping.locale == .none and mapping.condition == .none) return mapping;
    }

    return null;
}

pub inline fn lookupDefault(code_point: CodePoint) ?Mapping {
    return lookup(.none, .none, code_point);
}

pub inline fn lookupTurkish(code_point: CodePoint) ?Mapping {
    return lookup(.tr, .none, code_point);
}

pub inline fn lookupAzeri(code_point: CodePoint) ?Mapping {
    return lookup(.az, .none, code_point);
}

pub inline fn lookupLithuanian(code_point: CodePoint) ?Mapping {
    return lookup(.lt, .none, code_point);
}

pub inline fn lookupFinalSigma(code_point: CodePoint) ?Mapping {
    return lookup(.none, .final_sigma, code_point);
}