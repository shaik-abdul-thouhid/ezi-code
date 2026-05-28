const std = @import("std");

pub const helpers = @import("helpers.zig");
pub const slices = @import("slices.zig");
pub const search = @import("search.zig");

pub const isInRange = helpers.isInRange;
pub const every = helpers.every;
pub const some = helpers.some;

pub const bytesToU16Slice = slices.bytesToU16Slice;
pub const bytesToU16SliceComptime = slices.bytesToU16SliceComptime;
pub const bytesToU16SliceBuffer = slices.bytesToU16SliceBuffer;
pub const Endian = slices.Endian;

pub const binarySearch = search.binarySearch;
pub const binarySearchEntry = search.binarySearchEntry;
pub const searchRange = search.searchRange;
pub const containsInRange = search.containsInRange;

test {
    std.testing.refAllDecls(helpers);
    std.testing.refAllDecls(slices);
    std.testing.refAllDecls(search);
}
