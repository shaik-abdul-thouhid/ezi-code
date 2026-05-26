const std = @import("std");
const encoding = @import("encoding");
const utf8 = encoding.utf8;

const CodePoint = encoding.CodePoint;

pub const generated = @import("generated/grapheme_break.zig");
pub const GraphemeBreakProperty = generated.GraphemeBreakProperty;
pub const graphemeBreakProperty = generated.graphemeBreakProperty;

pub const emoji_data = @import("generated/emoji_data.zig");
pub const word_break = @import("generated/word_break.zig");
pub const sentence_break = @import("generated/sentence_break.zig");
pub const line_break = @import("generated/line_break.zig");

pub const WordBreakProperty = word_break.WordBreakProperty;
pub const wordBreakProperty = word_break.wordBreakProperty;
pub const SentenceBreakProperty = sentence_break.SentenceBreakProperty;
pub const sentenceBreakProperty = sentence_break.sentenceBreakProperty;
pub const LineBreak = line_break.LineBreak;
pub const lineBreak = line_break.lineBreak;

pub const isEmoji = emoji_data.isEmoji;
pub const isEmojiPresentation = emoji_data.isEmojiPresentation;
pub const isEmojiModifier = emoji_data.isEmojiModifier;
pub const isEmojiModifierBase = emoji_data.isEmojiModifierBase;
pub const isEmojiComponent = emoji_data.isEmojiComponent;
pub const isExtendedPictographic = emoji_data.isExtendedPictographic;

const derived_core_properties = @import("../properties/generated/derived_core_properties.zig");
const DerivedProperty = derived_core_properties.Property;

/// Indic Conjunct Break property from DerivedCoreProperties.
/// Used to implement UAX #29 rule GB9c.
pub const InCB = enum { none, consonant, linker, extend };

pub inline fn inCB(cp: CodePoint) InCB {
    const mask = derived_core_properties.propertyMask(cp);
    if ((mask & @intFromEnum(DerivedProperty.in_cb_consonant)) != 0) return .consonant;
    if ((mask & @intFromEnum(DerivedProperty.in_cb_linker)) != 0) return .linker;
    if ((mask & @intFromEnum(DerivedProperty.in_cb_extend)) != 0) return .extend;
    return .none;
}

/// Per-cursor state required to evaluate UAX #29 boundary rules incrementally.
/// `prev == null` means the cursor sits at start-of-text (sot).
pub const BoundaryState = struct {
    prev: ?GraphemeBreakProperty = null,
    /// Number of consecutive Regional_Indicator codepoints ending at `prev`.
    ri_run: usize = 0,
    /// True while the active position is still inside an InCB conjunct
    /// sequence starting from an InCB=Consonant.
    in_consonant_run: bool = false,
    /// Within the active conjunct sequence, whether an InCB=Linker has been
    /// seen. GB9c requires at least one Linker between the two Consonants.
    in_linker_seen: bool = false,
    /// True while the active cluster contains an Extended_Pictographic
    /// followed only by Extend / ZWJ codepoints. Set by GB11 to bind the
    /// next Extended_Pictographic onto the same cluster across a ZWJ.
    ext_pict_active: bool = false,
};

pub const BoundaryDecision = struct {
    should_break: bool,
    new_state: BoundaryState,
};

/// Decide whether there is a grapheme-cluster boundary BEFORE `cur`, given
/// the prior cursor state. Returns the decision and the state to use after
/// `cur` is consumed. Implements the full UAX #29 extended grapheme cluster
/// algorithm (GB1–GB9c, GB11, GB12/13, GB999).
pub fn checkBoundary(state: BoundaryState, cur: CodePoint) BoundaryDecision {
    const cur_prop = graphemeBreakProperty(cur);
    const cur_incb = inCB(cur);
    const cur_is_ext_pict = isExtendedPictographic(cur);

    const should_break = decide: {
        // GB1: sot ÷ Any
        const prev = state.prev orelse break :decide true;

        // GB3: CR × LF — checked before the broad GB4/GB5 control rules.
        if (prev == .cr and cur_prop == .lf) break :decide false;
        // GB4: (Control | CR | LF) ÷
        if (prev == .control or prev == .cr or prev == .lf) break :decide true;
        // GB5: ÷ (Control | CR | LF)
        if (cur_prop == .control or cur_prop == .cr or cur_prop == .lf) break :decide true;
        // GB6: L × (L | V | LV | LVT)
        if (prev == .l) switch (cur_prop) {
            .l, .v, .lv, .lvt => break :decide false,
            else => {},
        };
        // GB7: (LV | V) × (V | T)
        if (prev == .lv or prev == .v) switch (cur_prop) {
            .v, .t => break :decide false,
            else => {},
        };
        // GB8: (LVT | T) × T
        if ((prev == .lvt or prev == .t) and cur_prop == .t) break :decide false;
        // GB9: × (Extend | ZWJ)
        if (cur_prop == .extend or cur_prop == .zwj) break :decide false;
        // GB9a: × SpacingMark
        if (cur_prop == .spacing_mark) break :decide false;
        // GB9b: Prepend ×
        if (prev == .prepend) break :decide false;
        // GB9c: \p{InCB=Consonant} [\p{InCB=Extend}\p{InCB=Linker}]* \p{InCB=Linker}
        //       [\p{InCB=Extend}\p{InCB=Linker}]* × \p{InCB=Consonant}
        if (cur_incb == .consonant and state.in_consonant_run and state.in_linker_seen) break :decide false;
        // GB11: \p{Extended_Pictographic} Extend* ZWJ × \p{Extended_Pictographic}
        if (prev == .zwj and state.ext_pict_active and cur_is_ext_pict) break :decide false;
        // GB12/GB13: RI × RI when the prior RI run length is odd. Odd means
        // `prev` is the start of a fresh pair, so the new RI joins it.
        if (prev == .regional_indicator and cur_prop == .regional_indicator and (state.ri_run % 2 == 1)) break :decide false;

        // GB999: Any ÷ Any
        break :decide true;
    };

    var new_state = state;

    if (cur_prop == .regional_indicator) {
        new_state.ri_run = if (should_break) 1 else state.ri_run + 1;
    } else {
        new_state.ri_run = 0;
    }

    // A break ends the active conjunct and pictographic contexts before we
    // start tracking from the codepoint we just decided to break before.
    if (should_break) {
        new_state.in_consonant_run = false;
        new_state.in_linker_seen = false;
        new_state.ext_pict_active = false;
    }

    if (cur_incb == .consonant) {
        new_state.in_consonant_run = true;
        new_state.in_linker_seen = false;
    } else if (new_state.in_consonant_run) {
        switch (cur_incb) {
            .linker => new_state.in_linker_seen = true,
            .extend => {},
            else => {
                new_state.in_consonant_run = false;
                new_state.in_linker_seen = false;
            },
        }
    }

    // Track GB11's `Extended_Pictographic Extend* ZWJ` prefix. Extended_Pict
    // arms it; Extend/ZWJ keep it armed; anything else disarms it.
    if (cur_is_ext_pict) {
        new_state.ext_pict_active = true;
    } else if (new_state.ext_pict_active) {
        if (cur_prop != .extend and cur_prop != .zwj) {
            new_state.ext_pict_active = false;
        }
    }

    new_state.prev = cur_prop;

    return .{ .should_break = should_break, .new_state = new_state };
}

/// Iterator that yields successive grapheme clusters as `[]const u8` slices
/// of the original UTF-8 buffer. Invalid UTF-8 is decoded lossily as U+FFFD.
pub const GraphemeIterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    state: BoundaryState = .{},

    pub fn next(self: *GraphemeIterator) ?[]const u8 {
        if (self.pos >= self.bytes.len) return null;
        const start = self.pos;
        var consumed_first = false;

        while (self.pos < self.bytes.len) {
            const decoded = utf8.validateAndDecodeCodePointBytesLossy(self.bytes, self.pos) catch unreachable;
            const decision = checkBoundary(self.state, decoded.code_point);
            if (decision.should_break and consumed_first) break;
            self.state = decision.new_state;
            self.pos += decoded.len;
            consumed_first = true;
        }
        return self.bytes[start..self.pos];
    }

    pub fn reset(self: *GraphemeIterator) void {
        self.pos = 0;
        self.state = .{};
    }

    pub fn peek(self: *const GraphemeIterator) ?[]const u8 {
        var copy = self.*;
        return copy.next();
    }
};

pub fn iterator(bytes: []const u8) GraphemeIterator {
    return .{ .bytes = bytes };
}

/// Iterator over an explicit `[]const CodePoint` that yields slices of
/// codepoints belonging to the same grapheme cluster. Operates without any
/// UTF-8 decoding, so it is the primitive used by the UCD conformance test.
pub const CodePointGraphemeIterator = struct {
    code_points: []const CodePoint,
    pos: usize = 0,
    state: BoundaryState = .{},

    pub fn next(self: *CodePointGraphemeIterator) ?[]const CodePoint {
        if (self.pos >= self.code_points.len) return null;
        const start = self.pos;
        var consumed_first = false;

        while (self.pos < self.code_points.len) {
            const decision = checkBoundary(self.state, self.code_points[self.pos]);
            if (decision.should_break and consumed_first) break;
            self.state = decision.new_state;
            self.pos += 1;
            consumed_first = true;
        }
        return self.code_points[start..self.pos];
    }

    pub fn reset(self: *CodePointGraphemeIterator) void {
        self.pos = 0;
        self.state = .{};
    }
};

pub fn codePointIterator(code_points: []const CodePoint) CodePointGraphemeIterator {
    return .{ .code_points = code_points };
}

pub fn countGraphemes(bytes: []const u8) usize {
    var it = iterator(bytes);
    var count: usize = 0;
    while (it.next() != null) count += 1;
    return count;
}

pub fn countGraphemesFromCodePoints(code_points: []const CodePoint) usize {
    var it = codePointIterator(code_points);
    var count: usize = 0;
    while (it.next() != null) count += 1;
    return count;
}

// ============================================================================
// Hostile / edge-case unit tests
// ============================================================================

const testing = std.testing;

test "grapheme prop: known assignments at well-known codepoints" {
    try testing.expectEqual(GraphemeBreakProperty.cr, graphemeBreakProperty(0x000D));
    try testing.expectEqual(GraphemeBreakProperty.lf, graphemeBreakProperty(0x000A));
    try testing.expectEqual(GraphemeBreakProperty.control, graphemeBreakProperty(0x0000));
    try testing.expectEqual(GraphemeBreakProperty.control, graphemeBreakProperty(0x0007));
    try testing.expectEqual(GraphemeBreakProperty.control, graphemeBreakProperty(0x001B));
    try testing.expectEqual(GraphemeBreakProperty.none, graphemeBreakProperty(0x0020));
    try testing.expectEqual(GraphemeBreakProperty.none, graphemeBreakProperty('a'));
    try testing.expectEqual(GraphemeBreakProperty.none, graphemeBreakProperty('A'));
    try testing.expectEqual(GraphemeBreakProperty.extend, graphemeBreakProperty(0x0308));
    try testing.expectEqual(GraphemeBreakProperty.zwj, graphemeBreakProperty(0x200D));
    try testing.expectEqual(GraphemeBreakProperty.l, graphemeBreakProperty(0x1100));
    try testing.expectEqual(GraphemeBreakProperty.v, graphemeBreakProperty(0x1161));
    try testing.expectEqual(GraphemeBreakProperty.t, graphemeBreakProperty(0x11A8));
    try testing.expectEqual(GraphemeBreakProperty.lv, graphemeBreakProperty(0xAC00));
    try testing.expectEqual(GraphemeBreakProperty.lvt, graphemeBreakProperty(0xAC01));
    try testing.expectEqual(GraphemeBreakProperty.regional_indicator, graphemeBreakProperty(0x1F1E6));
    try testing.expectEqual(GraphemeBreakProperty.regional_indicator, graphemeBreakProperty(0x1F1FF));
    try testing.expectEqual(GraphemeBreakProperty.prepend, graphemeBreakProperty(0x0600));
    try testing.expectEqual(GraphemeBreakProperty.spacing_mark, graphemeBreakProperty(0x0903));
    // Out-of-range guards must return .none, never trap.
    try testing.expectEqual(GraphemeBreakProperty.none, graphemeBreakProperty(0x110000));
    try testing.expectEqual(GraphemeBreakProperty.none, graphemeBreakProperty(0x1FFFFF));
}

test "grapheme prop: every codepoint maps to a defined enum value" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        // Calling the function for every scalar must not crash, and the result
        // must be exhaustively switchable.
        switch (graphemeBreakProperty(cp)) {
            .none, .control, .cr, .extend, .l, .lf, .lv, .lvt, .prepend, .regional_indicator, .spacing_mark, .t, .v, .zwj => {},
        }
    }
}

test "grapheme inCB: cores of Devanagari conjuncts and ZWJ" {
    try testing.expectEqual(InCB.consonant, inCB(0x0915)); // DEVANAGARI LETTER KA
    try testing.expectEqual(InCB.consonant, inCB(0x0924)); // DEVANAGARI LETTER TA
    try testing.expectEqual(InCB.linker, inCB(0x094D)); // DEVANAGARI SIGN VIRAMA
    try testing.expectEqual(InCB.extend, inCB(0x200D)); // ZWJ
    try testing.expectEqual(InCB.none, inCB('a'));
    try testing.expectEqual(InCB.none, inCB('A'));
}

test "grapheme: empty input yields no clusters" {
    var it = iterator("");
    try testing.expectEqual(@as(?[]const u8, null), it.next());
}

test "grapheme: single ASCII codepoint forms one cluster" {
    var it = iterator("a");
    try testing.expectEqualStrings("a", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB3 binds CR LF together but lone CR or LF stays separate" {
    {
        var it = iterator("\r\n");
        try testing.expectEqualStrings("\r\n", it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        var it = iterator("\n\r");
        try testing.expectEqualStrings("\n", it.next().?);
        try testing.expectEqualStrings("\r", it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        var it = iterator("a\r\nb");
        try testing.expectEqualStrings("a", it.next().?);
        try testing.expectEqualStrings("\r\n", it.next().?);
        try testing.expectEqualStrings("b", it.next().?);
        try testing.expect(it.next() == null);
    }
}

test "grapheme: GB4 / GB5 isolate every Control / CR / LF" {
    var it = iterator("a\x07b");
    try testing.expectEqualStrings("a", it.next().?);
    try testing.expectEqualStrings("\x07", it.next().?);
    try testing.expectEqualStrings("b", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB6 / GB7 / GB8 keep Hangul syllables together" {
    {
        const data = "\u{1100}\u{1161}";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        const data = "\u{1100}\u{1161}\u{11A8}";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        const data = "\u{AC00}\u{11A8}";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        // L × L is allowed.
        const data = "\u{1100}\u{1100}";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        // T × L is a break — GB8 only allows T × T.
        const data = "\u{11A8}\u{1100}";
        var it = iterator(data);
        try testing.expectEqualStrings("\u{11A8}", it.next().?);
        try testing.expectEqualStrings("\u{1100}", it.next().?);
        try testing.expect(it.next() == null);
    }
}

test "grapheme: GB9 chains of Extend stick to the base codepoint" {
    const data = "a\u{0308}\u{0300}";
    var it = iterator(data);
    try testing.expectEqualStrings(data, it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB9 ZWJ binds back to a non-pictographic base, and the next non-pictographic still breaks" {
    // 'a' is not Extended_Pictographic; ext_pict_active stays false, so GB11
    // does not fire and the next 'b' starts a new cluster.
    const data = "a\u{200D}b";
    var it = iterator(data);
    try testing.expectEqualStrings("a\u{200D}", it.next().?);
    try testing.expectEqualStrings("b", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB11 ZWJ emoji sequences fuse into one cluster" {
    // 👨‍👩‍👧 — man + ZWJ + woman + ZWJ + girl (a family ZWJ sequence)
    {
        const data = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
    // ExtPict + Extend* + ZWJ + ExtPict — e.g., baby + Fitzpatrick + ZWJ + octagonal sign.
    {
        const data = "\u{1F476}\u{1F3FF}\u{200D}\u{1F6D1}";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
}

test "grapheme: GB11 does NOT bridge across a non-pictographic codepoint" {
    // 👨ABC👩 — ExtPict, then a run of letters, then ExtPict.
    const data = "\u{1F468}ABC\u{1F469}";
    var it = iterator(data);
    try testing.expectEqualStrings("\u{1F468}", it.next().?);
    try testing.expectEqualStrings("A", it.next().?);
    try testing.expectEqualStrings("B", it.next().?);
    try testing.expectEqualStrings("C", it.next().?);
    try testing.expectEqualStrings("\u{1F469}", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB11 does NOT fire when ZWJ comes without a preceding pictographic" {
    // 'a' is not ExtPict, so 'a' + ZWJ + 👩 should break before the woman.
    const data = "a\u{200D}\u{1F469}";
    var it = iterator(data);
    try testing.expectEqualStrings("a\u{200D}", it.next().?);
    try testing.expectEqualStrings("\u{1F469}", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB9a SpacingMark binds back" {
    const data = "\u{0915}\u{0903}";
    var it = iterator(data);
    try testing.expectEqualStrings(data, it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB9b Prepend binds forward, and a lone Prepend at eot is still one cluster" {
    {
        const data = "\u{0600}1";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        const tail = "\u{0600}";
        var it = iterator(tail);
        try testing.expectEqualStrings(tail, it.next().?);
        try testing.expect(it.next() == null);
    }
}

test "grapheme: GB9c Devanagari Consonant Linker Consonant stays one cluster" {
    const data = "\u{0915}\u{094D}\u{0924}";
    var it = iterator(data);
    try testing.expectEqualStrings(data, it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB9c with ZWJ between Linker and Consonant is still one cluster" {
    const data = "\u{0915}\u{094D}\u{200D}\u{0924}";
    var it = iterator(data);
    try testing.expectEqualStrings(data, it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB9c does NOT apply when there is no Linker between Consonants" {
    // C + ZWJ + C — no Linker → break before the second C.
    const data = "\u{0915}\u{200D}\u{0924}";
    var it = iterator(data);
    try testing.expectEqualStrings("\u{0915}\u{200D}", it.next().?);
    try testing.expectEqualStrings("\u{0924}", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: GB12 / GB13 Regional Indicator pairing" {
    {
        const data = "\u{1F1FA}\u{1F1F8}";
        var it = iterator(data);
        try testing.expectEqualStrings(data, it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        const data = "\u{1F1FA}\u{1F1F8}\u{1F1EB}";
        var it = iterator(data);
        try testing.expectEqualStrings("\u{1F1FA}\u{1F1F8}", it.next().?);
        try testing.expectEqualStrings("\u{1F1EB}", it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        const data = "\u{1F1FA}\u{1F1F8}\u{1F1EB}\u{1F1F7}";
        var it = iterator(data);
        try testing.expectEqualStrings("\u{1F1FA}\u{1F1F8}", it.next().?);
        try testing.expectEqualStrings("\u{1F1EB}\u{1F1F7}", it.next().?);
        try testing.expect(it.next() == null);
    }
    {
        // A non-RI between two RI pairs resets the count.
        const data = "a\u{1F1FA}\u{1F1F8}";
        var it = iterator(data);
        try testing.expectEqualStrings("a", it.next().?);
        try testing.expectEqualStrings("\u{1F1FA}\u{1F1F8}", it.next().?);
        try testing.expect(it.next() == null);
    }
}

test "grapheme: codepoint iterator yields the same boundary structure as the byte iterator" {
    const cps = [_]CodePoint{ 'a', 0x0308, 0x0300, 'b', '\r', '\n', 'c' };
    const expected_lengths = [_]usize{ 3, 1, 2, 1 };
    var it = codePointIterator(&cps);
    for (expected_lengths) |want_len| {
        const cluster = it.next() orelse return error.TestExpectedCluster;
        try testing.expectEqual(want_len, cluster.len);
    }
    try testing.expect(it.next() == null);
}

test "grapheme: countGraphemes covers a broad spread of cases" {
    const cases = [_]struct { data: []const u8, count: usize }{
        .{ .data = "", .count = 0 },
        .{ .data = "a", .count = 1 },
        .{ .data = "abc", .count = 3 },
        .{ .data = "\r\n\r\n", .count = 2 },
        .{ .data = "a\u{0308}b", .count = 2 },
        .{ .data = "\u{0915}\u{094D}\u{0924}", .count = 1 },
        .{ .data = "\u{1F1FA}\u{1F1F8}\u{1F1EB}\u{1F1F7}", .count = 2 },
        .{ .data = "\u{1F1FA}\u{1F1F8}\u{1F1EB}", .count = 2 },
        .{ .data = "\u{0600}1", .count = 1 },
        .{ .data = "\u{0915}\u{0903}", .count = 1 },
    };
    for (cases) |c| {
        try testing.expectEqual(c.count, countGraphemes(c.data));
    }
}

test "grapheme: reset rewinds the iterator and clears RI / conjunct state" {
    var it = iterator("\u{1F1FA}\u{1F1F8}\u{1F1EB}");
    try testing.expectEqualStrings("\u{1F1FA}\u{1F1F8}", it.next().?);
    try testing.expectEqualStrings("\u{1F1EB}", it.next().?);
    it.reset();
    try testing.expectEqualStrings("\u{1F1FA}\u{1F1F8}", it.next().?);
    try testing.expectEqualStrings("\u{1F1EB}", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: peek does not advance the iterator" {
    var it = iterator("ab");
    try testing.expectEqualStrings("a", it.peek().?);
    try testing.expectEqualStrings("a", it.peek().?);
    try testing.expectEqualStrings("a", it.next().?);
    try testing.expectEqualStrings("b", it.peek().?);
    try testing.expectEqualStrings("b", it.next().?);
    try testing.expect(it.peek() == null);
}

test "grapheme: invalid UTF-8 leader is treated as one cluster of one byte" {
    var it = iterator("a\xFFb");
    try testing.expectEqualStrings("a", it.next().?);
    try testing.expectEqualStrings("\xFF", it.next().?);
    try testing.expectEqualStrings("b", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: hostile interleaved Hangul, marks, RIs, and controls" {
    const data = "\u{AC00}\u{0301}\r\n\u{1F1FA}\u{1F1F8}b";
    try testing.expectEqual(@as(usize, 4), countGraphemes(data));
    var it = iterator(data);
    try testing.expectEqualStrings("\u{AC00}\u{0301}", it.next().?);
    try testing.expectEqualStrings("\r\n", it.next().?);
    try testing.expectEqualStrings("\u{1F1FA}\u{1F1F8}", it.next().?);
    try testing.expectEqualStrings("b", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: checkBoundary at sot always reports a break and primes prev" {
    const decision = checkBoundary(.{}, 'a');
    try testing.expect(decision.should_break);
    try testing.expectEqual(@as(?GraphemeBreakProperty, .none), decision.new_state.prev);
    try testing.expectEqual(@as(usize, 0), decision.new_state.ri_run);
    try testing.expect(!decision.new_state.in_consonant_run);
    try testing.expect(!decision.new_state.in_linker_seen);
    try testing.expect(!decision.new_state.ext_pict_active);
}

test "grapheme: RI parity flips correctly across many indicators" {
    // 8 RIs → 4 clusters of 2.
    const data = "\u{1F1FA}\u{1F1F8}\u{1F1FA}\u{1F1F8}\u{1F1FA}\u{1F1F8}\u{1F1FA}\u{1F1F8}";
    try testing.expectEqual(@as(usize, 4), countGraphemes(data));
    // 9 RIs → 4 pairs + 1 trailing solo.
    const data2 = "\u{1F1FA}\u{1F1F8}\u{1F1FA}\u{1F1F8}\u{1F1FA}\u{1F1F8}\u{1F1FA}\u{1F1F8}\u{1F1FA}";
    try testing.expectEqual(@as(usize, 5), countGraphemes(data2));
}

test "grapheme: Prepend followed by CR breaks because GB5 wins over GB9b" {
    // Per UAX #29 rule precedence, GB5 (÷ CR) breaks before GB9b can bind.
    const data = "\u{0600}\r";
    var it = iterator(data);
    try testing.expectEqualStrings("\u{0600}", it.next().?);
    try testing.expectEqualStrings("\r", it.next().?);
    try testing.expect(it.next() == null);
}

test "grapheme: Extend chain on a control codepoint still breaks before the Extend (GB4)" {
    // \r is CR; GB4 forces a break after CR before anything else (except LF).
    const data = "\r\u{0308}";
    var it = iterator(data);
    try testing.expectEqualStrings("\r", it.next().?);
    try testing.expectEqualStrings("\u{0308}", it.next().?);
    try testing.expect(it.next() == null);
}

// ============================================================================
// Hostile / edge-case tests for the newly generated tables
// ============================================================================

test "wordBreakProperty: known assignments" {
    try testing.expectEqual(WordBreakProperty.aletter, wordBreakProperty('a'));
    try testing.expectEqual(WordBreakProperty.aletter, wordBreakProperty('Z'));
    try testing.expectEqual(WordBreakProperty.numeric, wordBreakProperty('0'));
    try testing.expectEqual(WordBreakProperty.numeric, wordBreakProperty('9'));
    try testing.expectEqual(WordBreakProperty.cr, wordBreakProperty(0x000D));
    try testing.expectEqual(WordBreakProperty.lf, wordBreakProperty(0x000A));
    try testing.expectEqual(WordBreakProperty.newline, wordBreakProperty(0x000B));
    try testing.expectEqual(WordBreakProperty.zwj, wordBreakProperty(0x200D));
    try testing.expectEqual(WordBreakProperty.regional_indicator, wordBreakProperty(0x1F1E6));
    try testing.expectEqual(WordBreakProperty.double_quote, wordBreakProperty(0x0022));
    try testing.expectEqual(WordBreakProperty.single_quote, wordBreakProperty(0x0027));
    try testing.expectEqual(WordBreakProperty.hebrew_letter, wordBreakProperty(0x05D0)); // ALEF
    try testing.expectEqual(WordBreakProperty.katakana, wordBreakProperty(0x30A2)); // KATAKANA LETTER A
    try testing.expectEqual(WordBreakProperty.extend, wordBreakProperty(0x0308));
    // SPACE is Word_Break=WSegSpace, not Other.
    try testing.expectEqual(WordBreakProperty.wseg_space, wordBreakProperty(' '));
    // Default for unassigned / out-of-range scalars.
    try testing.expectEqual(WordBreakProperty.other, wordBreakProperty(0x110000));
}

test "wordBreakProperty: exhaustive switch coverage across every codepoint" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        switch (wordBreakProperty(cp)) {
            .other, .aletter, .cr, .double_quote, .extend, .extend_num_let, .format, .hebrew_letter, .katakana, .lf, .mid_letter, .mid_num, .mid_num_let, .newline, .numeric, .regional_indicator, .single_quote, .wseg_space, .zwj => {},
        }
    }
}

test "sentenceBreakProperty: known assignments" {
    try testing.expectEqual(SentenceBreakProperty.upper, sentenceBreakProperty('A'));
    try testing.expectEqual(SentenceBreakProperty.lower, sentenceBreakProperty('a'));
    try testing.expectEqual(SentenceBreakProperty.numeric, sentenceBreakProperty('0'));
    try testing.expectEqual(SentenceBreakProperty.aterm, sentenceBreakProperty('.'));
    try testing.expectEqual(SentenceBreakProperty.sterm, sentenceBreakProperty('?'));
    try testing.expectEqual(SentenceBreakProperty.sterm, sentenceBreakProperty('!'));
    try testing.expectEqual(SentenceBreakProperty.cr, sentenceBreakProperty(0x000D));
    try testing.expectEqual(SentenceBreakProperty.lf, sentenceBreakProperty(0x000A));
    try testing.expectEqual(SentenceBreakProperty.sp, sentenceBreakProperty(' '));
    // Default
    try testing.expectEqual(SentenceBreakProperty.other, sentenceBreakProperty(0x110000));
}

test "sentenceBreakProperty: exhaustive switch coverage" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        switch (sentenceBreakProperty(cp)) {
            .other, .aterm, .close, .cr, .extend, .format, .lf, .lower, .numeric, .oletter, .scontinue, .sep, .sp, .sterm, .upper => {},
        }
    }
}

test "lineBreak: known assignments and digit-preserving normalization" {
    try testing.expectEqual(LineBreak.al, lineBreak('a'));
    try testing.expectEqual(LineBreak.nu, lineBreak('0'));
    try testing.expectEqual(LineBreak.cr, lineBreak(0x000D));
    try testing.expectEqual(LineBreak.lf, lineBreak(0x000A));
    try testing.expectEqual(LineBreak.bk, lineBreak(0x000C)); // FORM FEED
    try testing.expectEqual(LineBreak.sp, lineBreak(' '));
    try testing.expectEqual(LineBreak.gl, lineBreak(0x00A0)); // NBSP
    try testing.expectEqual(LineBreak.zw, lineBreak(0x200B)); // ZERO WIDTH SPACE
    try testing.expectEqual(LineBreak.zwj, lineBreak(0x200D)); // ZWJ
    // Hangul syllable types — these are the digit-preserving cases.
    try testing.expectEqual(LineBreak.jl, lineBreak(0x1100));
    try testing.expectEqual(LineBreak.jv, lineBreak(0x1161));
    try testing.expectEqual(LineBreak.jt, lineBreak(0x11A8));
    try testing.expectEqual(LineBreak.h2, lineBreak(0xAC00)); // LV syllable
    try testing.expectEqual(LineBreak.h3, lineBreak(0xAC01)); // LVT syllable
    // Default
    try testing.expectEqual(LineBreak.xx, lineBreak(0x110000));
}

test "lineBreak: exhaustive switch coverage" {
    var cp: CodePoint = 0;
    while (cp <= 0x10FFFF) : (cp += 1) {
        switch (lineBreak(cp)) {
            .xx, .ai, .ak, .al, .ap, .as, .b2, .ba, .bb, .bk, .cb, .cj, .cl, .cm, .cp, .cr, .eb, .em, .ex, .gl, .h2, .h3, .hh, .hl, .hy, .id, .in, .is, .jl, .jt, .jv, .lf, .nl, .ns, .nu, .op, .po, .pr, .qu, .ri, .sa, .sg, .sp, .sy, .vf, .vi, .wj, .zw, .zwj => {},
        }
    }
}

test "emoji-data: each predicate matches known examples and rejects unrelated codepoints" {
    // Emoji presentation defaults — base emoji like the keycap pieces.
    try testing.expect(isEmoji(0x231A)); // WATCH
    try testing.expect(isEmojiPresentation(0x231A));

    // Skin-tone modifiers.
    try testing.expect(isEmojiModifier(0x1F3FB));
    try testing.expect(isEmojiModifier(0x1F3FF));
    try testing.expect(!isEmojiModifier('a'));

    // Modifier bases: people emoji that accept skin tone.
    try testing.expect(isEmojiModifierBase(0x1F476)); // BABY

    // Component (regional indicator letters are emoji components).
    try testing.expect(isEmojiComponent(0x1F1E6));
    try testing.expect(isEmojiComponent(0x1F1FF));

    // Extended_Pictographic includes codepoints that aren't Emoji proper.
    try testing.expect(isExtendedPictographic(0x00A9)); // COPYRIGHT SIGN
    try testing.expect(isExtendedPictographic(0x1F468)); // MAN
    try testing.expect(isExtendedPictographic(0x1F469)); // WOMAN

    // Plain letters are none of the emoji properties. (Digits 0-9 and '#'/'*'
    // ARE Emoji and Emoji_Component per the file, so don't test those here.)
    for ("aZxYbW") |c| {
        const cp: CodePoint = @intCast(c);
        try testing.expect(!isEmoji(cp));
        try testing.expect(!isEmojiPresentation(cp));
        try testing.expect(!isEmojiModifier(cp));
        try testing.expect(!isEmojiModifierBase(cp));
        try testing.expect(!isEmojiComponent(cp));
        try testing.expect(!isExtendedPictographic(cp));
    }

    // Digits ARE Emoji + Emoji_Component (used for keycap sequences) but NOT
    // Extended_Pictographic. This pins down the actual semantic distinction.
    try testing.expect(isEmoji('0'));
    try testing.expect(isEmojiComponent('0'));
    try testing.expect(!isExtendedPictographic('0'));

    // Out-of-range guard.
    try testing.expect(!isEmoji(0x110000));
    try testing.expect(!isExtendedPictographic(0x110000));
}
