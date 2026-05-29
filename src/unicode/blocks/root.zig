//! The Block property (UAX #44, Blocks.txt).
//!
//! `block(cp)` returns the Unicode block a codepoint belongs to. Blocks are a
//! coarse, allocation-oriented partition of the codespace into named contiguous
//! ranges; membership is purely positional and independent of whether `cp` is
//! actually assigned. Codepoints that fall in no block resolve to `.no_block`
//! (the file's `@missing` value). `blockName(b)` recovers the canonical
//! Unicode block name for display.
//!
//! Backed by a deduplicated 2-level page table over a `u16` block index in
//! `generated/blocks.zig`.

const std = @import("std");
const encoding = @import("encoding");

const CodePoint = encoding.CodePoint;

pub const generated = @import("generated/blocks.zig");

pub const Block = generated.Block;

/// The Block of `cp`. Codepoints in no block (and above U+10FFFF) are `.no_block`.
pub const block = generated.block;

/// The canonical Unicode block name for `b` (e.g. "Basic Latin", "No_Block").
pub const blockName = generated.blockName;

// ============================================================================
// Hostile / edge-case tests
// ============================================================================

const testing = std.testing;

test "block: representative codepoints across planes" {
    try testing.expectEqual(Block.basic_latin, block('A'));
    try testing.expectEqual(Block.basic_latin, block(0x00)); // NUL still has a block
    try testing.expectEqual(Block.basic_latin, block(0x7F)); // last of Basic Latin
    try testing.expectEqual(Block.cjk_unified_ideographs, block(0x4E00));
    try testing.expectEqual(Block.supplementary_private_use_area_b, block(0x10FFFF));
}

test "block: membership is positional, not assignment-based" {
    // U+0378 is unassigned but still inside the Greek and Coptic block.
    try testing.expect(block(0x0378) != .no_block);
    try testing.expectEqualStrings("Greek and Coptic", blockName(block(0x0378)));
    // Block boundaries: 0x0080 starts Latin-1 Supplement.
    try testing.expectEqualStrings("Latin-1 Supplement", blockName(block(0x0080)));
    try testing.expectEqualStrings("Basic Latin", blockName(block(0x007F)));
}

test "block: gaps between blocks resolve to no_block" {
    // Plane 14: Tags is E0000..E007F, Variation Selectors Supplement is
    // E0100..E01EF — the range in between belongs to no block.
    try testing.expectEqual(Block.no_block, block(0xE0080));
    try testing.expectEqual(Block.no_block, block(0xE00FF));
    try testing.expectEqualStrings("No_Block", blockName(block(0xE0080)));
}

test "block: out-of-range never traps and is no_block" {
    try testing.expectEqual(Block.no_block, block(0x110000));
    try testing.expectEqual(Block.no_block, block(0x1FFFFF));
}

test "block: every codepoint maps to a valid enum variant, never traps" {
    const field_count = @typeInfo(Block).@"enum".fields.len;
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        const b = block(cp);
        try testing.expect(@intFromEnum(b) < field_count);
    }
}

test "blockName: round-trips through every enum variant and is non-empty" {
    inline for (@typeInfo(Block).@"enum".fields) |f| {
        const b: Block = @enumFromInt(f.value);
        try testing.expect(blockName(b).len > 0);
    }
    try testing.expectEqualStrings("No_Block", blockName(.no_block));
    try testing.expectEqualStrings("CJK Unified Ideographs", blockName(.cjk_unified_ideographs));
}

test {
    testing.refAllDecls(@This());
}
