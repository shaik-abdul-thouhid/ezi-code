const std = @import("std");

pub const helpers = @import("helpers.zig");
pub const slices = @import("slices.zig");

pub const isInRange = helpers.isInRange;
pub const every = helpers.every;

pub const bytesToU16Slice = slices.bytesToU16Slice;
pub const bytesToU16SliceComptime = slices.bytesToU16SliceComptime;
pub const bytesToU16SliceBuffer = slices.bytesToU16SliceBuffer;
pub const Endian = slices.Endian;

test {
    std.testing.refAllDecls(helpers);
    std.testing.refAllDecls(slices);
}
