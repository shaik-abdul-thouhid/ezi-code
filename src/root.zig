const std = @import("std");

const utils = @import("utils");
pub const encoding = @import("encoding");
const ts = @import("transcoding");

pub const transcoding = ts.transcoding;

pub const utf8 = encoding.utf8;
pub const utf16 = encoding.utf16;
pub const utf32 = encoding.utf32;

pub const slices = utils.slices;

test {
    std.testing.refAllDecls(encoding);
    std.testing.refAllDecls(utils);
    std.testing.refAllDecls(ts);
}
