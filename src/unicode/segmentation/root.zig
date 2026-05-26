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

const east_asian_width = @import("../width/generated/east_asian_width.zig");
const unicode_data = @import("../generated/unicode_data.zig");

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
// UAX #29 Word boundary
// ============================================================================

const WordProp = WordBreakProperty;

inline fn isAHLetter(p: WordProp) bool {
    return p == .aletter or p == .hebrew_letter;
}

inline fn isMidNumLetQ(p: WordProp) bool {
    return p == .mid_num_let or p == .single_quote;
}

inline fn isWordIgnorable(p: WordProp) bool {
    // WB4: Extend, Format, ZWJ are "invisible" for rules WB5..WB999.
    return p == .extend or p == .format or p == .zwj;
}

inline fn isWordHardSep(p: WordProp) bool {
    return p == .newline or p == .cr or p == .lf;
}

/// Per-position state required to evaluate UAX #29 word boundary rules
/// incrementally. Construct via `WordStepState.init(code_points[0])` and feed
/// successive positions through `wordStep`.
pub const WordStepState = struct {
    /// Effective (post-WB4) property of the most recent non-ignorable codepoint.
    eff_prev: WordProp,
    /// Effective property of the codepoint before that, or null at start of text.
    eff_prev_prev: ?WordProp,
    /// Number of consecutive Regional_Indicator codepoints ending at the most
    /// recent non-ignorable position.
    ri_count: usize,
    /// Raw (literal, NOT WB4-skipped) property of the immediately previous
    /// codepoint. WB3/WB3a/WB3b/WB3c need the literal, not the effective.
    prev_lit: WordProp,

    pub fn init(first_code_point: CodePoint) WordStepState {
        const p = wordBreakProperty(first_code_point);
        return .{
            .eff_prev = p,
            .eff_prev_prev = null,
            .ri_count = if (p == .regional_indicator) 1 else 0,
            .prev_lit = p,
        };
    }
};

pub const WordStepDecision = struct {
    is_break: bool,
    new_state: WordStepState,
};

/// Walk forward from `start` over `code_points`, returning the property of
/// the first codepoint whose word break property is not Extend/Format/ZWJ,
/// or null if no such codepoint exists. Used for the bounded lookahead in
/// WB6, WB7b, and WB12.
fn nextEffectiveWordProp(code_points: []const CodePoint, start: usize) ?WordProp {
    var j = start;
    while (j < code_points.len) : (j += 1) {
        const p = wordBreakProperty(code_points[j]);
        if (!isWordIgnorable(p)) return p;
    }
    return null;
}

/// Decide whether there is a word boundary BEFORE `code_points[i]`, given
/// the algorithm state derived from positions 0..i-1. Returns the boundary
/// decision and the new state to use after consuming position `i`. The
/// caller must have invoked `WordStepState.init(code_points[0])` before
/// calling this for i == 1.
pub fn wordStep(state: WordStepState, code_points: []const CodePoint, i: usize) WordStepDecision {
    const curr = wordBreakProperty(code_points[i]);
    const prev_lit = state.prev_lit;

    // WB3: CR × LF — no break, eff state slides one over.
    if (prev_lit == .cr and curr == .lf) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = state.eff_prev,
                .ri_count = 0,
                .prev_lit = curr,
            },
        };
    }
    // WB3a: (Newline | CR | LF) ÷ — break, reset eff_prev_prev.
    if (isWordHardSep(prev_lit)) {
        return .{
            .is_break = true,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = null,
                .ri_count = if (curr == .regional_indicator) 1 else 0,
                .prev_lit = curr,
            },
        };
    }
    // WB3b: ÷ (Newline | CR | LF) — break before a hard separator.
    if (isWordHardSep(curr)) {
        return .{
            .is_break = true,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = null,
                .ri_count = 0,
                .prev_lit = curr,
            },
        };
    }
    // WB3c: ZWJ × Extended_Pictographic (literal previous; not WB4-skipped).
    if (prev_lit == .zwj and isExtendedPictographic(code_points[i])) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = state.eff_prev,
                .ri_count = if (curr == .regional_indicator) 1 else 0,
                .prev_lit = curr,
            },
        };
    }
    // WB3d: WSegSpace × WSegSpace.
    if (prev_lit == .wseg_space and curr == .wseg_space) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = state.eff_prev,
                .ri_count = 0,
                .prev_lit = curr,
            },
        };
    }
    // WB4: Any × (Extend | Format | ZWJ). The ignorable extends the cluster;
    // effective state is unchanged but prev_lit advances.
    if (isWordIgnorable(curr)) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = state.eff_prev,
                .eff_prev_prev = state.eff_prev_prev,
                .ri_count = state.ri_count,
                .prev_lit = curr,
            },
        };
    }

    // Beyond this point curr is a "visible" non-hardsep character.
    const prev = state.eff_prev;
    const prev_prev = state.eff_prev_prev;
    var no_break = false;

    // WB5
    if (isAHLetter(prev) and isAHLetter(curr)) no_break = true;
    // WB6: AHLetter × (MidLetter | MidNumLetQ) AHLetter.
    if (!no_break and isAHLetter(prev) and (curr == .mid_letter or isMidNumLetQ(curr))) {
        if (nextEffectiveWordProp(code_points, i + 1)) |after| {
            if (isAHLetter(after)) no_break = true;
        }
    }
    // WB7: AHLetter (MidLetter | MidNumLetQ) × AHLetter.
    if (!no_break and (prev == .mid_letter or isMidNumLetQ(prev)) and isAHLetter(curr)) {
        if (prev_prev) |pp| {
            if (isAHLetter(pp)) no_break = true;
        }
    }
    // WB7a
    if (!no_break and prev == .hebrew_letter and curr == .single_quote) no_break = true;
    // WB7b: Hebrew_Letter × Double_Quote Hebrew_Letter.
    if (!no_break and prev == .hebrew_letter and curr == .double_quote) {
        if (nextEffectiveWordProp(code_points, i + 1)) |after| {
            if (after == .hebrew_letter) no_break = true;
        }
    }
    // WB7c: Hebrew_Letter Double_Quote × Hebrew_Letter.
    if (!no_break and prev == .double_quote and curr == .hebrew_letter) {
        if (prev_prev) |pp| {
            if (pp == .hebrew_letter) no_break = true;
        }
    }
    // WB8
    if (!no_break and prev == .numeric and curr == .numeric) no_break = true;
    // WB9
    if (!no_break and isAHLetter(prev) and curr == .numeric) no_break = true;
    // WB10
    if (!no_break and prev == .numeric and isAHLetter(curr)) no_break = true;
    // WB11: Numeric (MidNum | MidNumLetQ) × Numeric.
    if (!no_break and (prev == .mid_num or isMidNumLetQ(prev)) and curr == .numeric) {
        if (prev_prev) |pp| {
            if (pp == .numeric) no_break = true;
        }
    }
    // WB12: Numeric × (MidNum | MidNumLetQ) Numeric.
    if (!no_break and prev == .numeric and (curr == .mid_num or isMidNumLetQ(curr))) {
        if (nextEffectiveWordProp(code_points, i + 1)) |after| {
            if (after == .numeric) no_break = true;
        }
    }
    // WB13
    if (!no_break and prev == .katakana and curr == .katakana) no_break = true;
    // WB13a
    if (!no_break and (isAHLetter(prev) or prev == .numeric or prev == .katakana or prev == .extend_num_let) and curr == .extend_num_let) no_break = true;
    // WB13b
    if (!no_break and prev == .extend_num_let and (isAHLetter(curr) or curr == .numeric or curr == .katakana)) no_break = true;
    // WB15/WB16: RI × RI when the count of unbroken RIs ending at prev is odd.
    if (!no_break and prev == .regional_indicator and curr == .regional_indicator) {
        if (state.ri_count % 2 == 1) no_break = true;
    }

    const next_ri_count: usize = if (curr == .regional_indicator)
        (if (no_break) state.ri_count + 1 else 1)
    else
        0;

    return .{
        .is_break = !no_break,
        .new_state = .{
            .eff_prev = curr,
            .eff_prev_prev = state.eff_prev,
            .ri_count = next_ri_count,
            .prev_lit = curr,
        },
    };
}

/// Compute word-boundary opportunities for a sequence of code points,
/// implementing the full UAX #29 word boundary algorithm (WB1..WB999).
/// `out[i]` is true iff there is a word boundary immediately BEFORE
/// `code_points[i]`. `out[0]` is sot, `out[n]` is eot; both are always true
/// per WB1/WB2 (and `out[0]` is true even when `n == 0` to represent the
/// degenerate empty input).
pub fn computeWordBoundaries(allocator: std.mem.Allocator, code_points: []const CodePoint) ![]bool {
    const n = code_points.len;
    const out = try allocator.alloc(bool, n + 1);
    errdefer allocator.free(out);
    out[0] = true; // WB1
    if (n == 0) return out;
    out[n] = true; // WB2
    if (n == 1) return out;

    var state = WordStepState.init(code_points[0]);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const decision = wordStep(state, code_points, i);
        out[i] = decision.is_break;
        state = decision.new_state;
    }
    return out;
}

/// Iterator over an explicit `[]const CodePoint` that yields slices of
/// codepoints belonging to the same word. Allocation-free.
pub const CodePointWordIterator = struct {
    code_points: []const CodePoint,
    pos: usize = 0,
    state: WordStepState = undefined,
    primed: bool = false,

    pub fn next(self: *CodePointWordIterator) ?[]const CodePoint {
        const n = self.code_points.len;
        if (self.pos >= n) return null;
        const start = self.pos;
        if (!self.primed) {
            self.state = WordStepState.init(self.code_points[0]);
            self.primed = true;
        }
        var i = self.pos + 1;
        while (i < n) : (i += 1) {
            const decision = wordStep(self.state, self.code_points, i);
            self.state = decision.new_state;
            if (decision.is_break) {
                self.pos = i;
                return self.code_points[start..i];
            }
        }
        self.pos = n;
        return self.code_points[start..n];
    }

    pub fn reset(self: *CodePointWordIterator) void {
        self.pos = 0;
        self.primed = false;
    }
};

pub fn codePointWordIterator(code_points: []const CodePoint) CodePointWordIterator {
    return .{ .code_points = code_points };
}

/// Iterator over UTF-8 input that yields successive words as `[]const u8`
/// slices. Invalid UTF-8 is decoded lossily as U+FFFD. Allocation-free.
pub const WordIterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    state: WordStepState = undefined,
    primed: bool = false,

    pub fn next(self: *WordIterator) ?[]const u8 {
        const n = self.bytes.len;
        if (self.pos >= n) return null;
        const start = self.pos;
        // Decode the codepoint at the start of this segment. On the first ever
        // call we use it to seed the state; on subsequent calls, the state's
        // prev_lit is already set to this codepoint's WB property (the previous
        // break decision recorded it). Either way we skip past it so the loop
        // below tests boundaries against the NEXT codepoint.
        const first = utf8.validateAndDecodeCodePointBytesLossy(self.bytes, self.pos) catch unreachable;
        if (!self.primed) {
            self.state = WordStepState.init(first.code_point);
            self.primed = true;
        }
        var cursor = self.pos + first.len;
        while (cursor < n) {
            const decision = wordStepBytes(self.state, self.bytes, cursor);
            self.state = decision.new_state;
            if (decision.is_break) {
                self.pos = cursor;
                return self.bytes[start..cursor];
            }
            cursor += decision.consumed;
        }
        self.pos = n;
        return self.bytes[start..n];
    }

    pub fn reset(self: *WordIterator) void {
        self.pos = 0;
        self.primed = false;
    }
};

pub fn wordIterator(bytes: []const u8) WordIterator {
    return .{ .bytes = bytes };
}

/// Byte-stream variant of `wordStep`. Decodes the codepoint at `byte_pos`
/// (lossy on invalid UTF-8) and returns the boundary decision plus the byte
/// length consumed by that codepoint.
const WordByteDecision = struct {
    is_break: bool,
    new_state: WordStepState,
    consumed: usize,
};

fn wordStepBytes(state: WordStepState, bytes: []const u8, byte_pos: usize) WordByteDecision {
    const decoded = utf8.validateAndDecodeCodePointBytesLossy(bytes, byte_pos) catch unreachable;
    const curr_cp = decoded.code_point;
    const curr = wordBreakProperty(curr_cp);
    const prev_lit = state.prev_lit;

    // WB3..WB3d / WB4 — same as wordStep but without slice lookahead.
    if (prev_lit == .cr and curr == .lf) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = state.eff_prev,
                .ri_count = 0,
                .prev_lit = curr,
            },
            .consumed = decoded.len,
        };
    }
    if (isWordHardSep(prev_lit)) {
        return .{
            .is_break = true,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = null,
                .ri_count = if (curr == .regional_indicator) 1 else 0,
                .prev_lit = curr,
            },
            .consumed = decoded.len,
        };
    }
    if (isWordHardSep(curr)) {
        return .{
            .is_break = true,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = null,
                .ri_count = 0,
                .prev_lit = curr,
            },
            .consumed = decoded.len,
        };
    }
    if (prev_lit == .zwj and isExtendedPictographic(curr_cp)) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = state.eff_prev,
                .ri_count = if (curr == .regional_indicator) 1 else 0,
                .prev_lit = curr,
            },
            .consumed = decoded.len,
        };
    }
    if (prev_lit == .wseg_space and curr == .wseg_space) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = state.eff_prev,
                .ri_count = 0,
                .prev_lit = curr,
            },
            .consumed = decoded.len,
        };
    }
    if (isWordIgnorable(curr)) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = state.eff_prev,
                .eff_prev_prev = state.eff_prev_prev,
                .ri_count = state.ri_count,
                .prev_lit = curr,
            },
            .consumed = decoded.len,
        };
    }

    const prev = state.eff_prev;
    const prev_prev = state.eff_prev_prev;
    var no_break = false;

    if (isAHLetter(prev) and isAHLetter(curr)) no_break = true;
    if (!no_break and isAHLetter(prev) and (curr == .mid_letter or isMidNumLetQ(curr))) {
        if (nextEffectiveWordPropBytes(bytes, byte_pos + decoded.len)) |after| {
            if (isAHLetter(after)) no_break = true;
        }
    }
    if (!no_break and (prev == .mid_letter or isMidNumLetQ(prev)) and isAHLetter(curr)) {
        if (prev_prev) |pp| {
            if (isAHLetter(pp)) no_break = true;
        }
    }
    if (!no_break and prev == .hebrew_letter and curr == .single_quote) no_break = true;
    if (!no_break and prev == .hebrew_letter and curr == .double_quote) {
        if (nextEffectiveWordPropBytes(bytes, byte_pos + decoded.len)) |after| {
            if (after == .hebrew_letter) no_break = true;
        }
    }
    if (!no_break and prev == .double_quote and curr == .hebrew_letter) {
        if (prev_prev) |pp| {
            if (pp == .hebrew_letter) no_break = true;
        }
    }
    if (!no_break and prev == .numeric and curr == .numeric) no_break = true;
    if (!no_break and isAHLetter(prev) and curr == .numeric) no_break = true;
    if (!no_break and prev == .numeric and isAHLetter(curr)) no_break = true;
    if (!no_break and (prev == .mid_num or isMidNumLetQ(prev)) and curr == .numeric) {
        if (prev_prev) |pp| {
            if (pp == .numeric) no_break = true;
        }
    }
    if (!no_break and prev == .numeric and (curr == .mid_num or isMidNumLetQ(curr))) {
        if (nextEffectiveWordPropBytes(bytes, byte_pos + decoded.len)) |after| {
            if (after == .numeric) no_break = true;
        }
    }
    if (!no_break and prev == .katakana and curr == .katakana) no_break = true;
    if (!no_break and (isAHLetter(prev) or prev == .numeric or prev == .katakana or prev == .extend_num_let) and curr == .extend_num_let) no_break = true;
    if (!no_break and prev == .extend_num_let and (isAHLetter(curr) or curr == .numeric or curr == .katakana)) no_break = true;
    if (!no_break and prev == .regional_indicator and curr == .regional_indicator) {
        if (state.ri_count % 2 == 1) no_break = true;
    }

    const next_ri_count: usize = if (curr == .regional_indicator)
        (if (no_break) state.ri_count + 1 else 1)
    else
        0;

    return .{
        .is_break = !no_break,
        .new_state = .{
            .eff_prev = curr,
            .eff_prev_prev = state.eff_prev,
            .ri_count = next_ri_count,
            .prev_lit = curr,
        },
        .consumed = decoded.len,
    };
}

fn nextEffectiveWordPropBytes(bytes: []const u8, start_byte: usize) ?WordProp {
    var j = start_byte;
    while (j < bytes.len) {
        const decoded = utf8.validateAndDecodeCodePointBytesLossy(bytes, j) catch unreachable;
        const p = wordBreakProperty(decoded.code_point);
        if (!isWordIgnorable(p)) return p;
        j += decoded.len;
    }
    return null;
}

pub fn countWords(bytes: []const u8) usize {
    var it = wordIterator(bytes);
    var count: usize = 0;
    while (it.next() != null) count += 1;
    return count;
}

pub fn countWordsFromCodePoints(code_points: []const CodePoint) usize {
    var it = codePointWordIterator(code_points);
    var count: usize = 0;
    while (it.next() != null) count += 1;
    return count;
}

// ============================================================================
// UAX #29 Sentence boundary
// ============================================================================

const SBProp = SentenceBreakProperty;

inline fn isSATerm(p: SBProp) bool {
    return p == .sterm or p == .aterm;
}

inline fn isSBParaSep(p: SBProp) bool {
    return p == .sep or p == .cr or p == .lf;
}

inline fn isSBIgnorable(p: SBProp) bool {
    // SB5: Extend and Format are invisible to rules SB6..SB999.
    return p == .extend or p == .format;
}

/// Tracks whether we are sitting inside the `SATerm Close* Sp*` window that
/// SB8/SB8a/SB9/SB10/SB11 are sensitive to.
const SBContext = enum {
    none,
    /// SATerm was just seen, no Close/Sp yet.
    saterm,
    /// SATerm followed by one or more Close (no Sp yet).
    saterm_close,
    /// SATerm followed by Close* then one or more Sp.
    saterm_close_sp,
    /// SATerm Close* Sp* ParaSep (single ParaSep — SB11 still keeps the run
    /// open across the ParaSep before forcing a break after it).
    saterm_close_sp_parasep,
};

/// Per-position state for incremental UAX #29 sentence boundary evaluation.
pub const SentenceStepState = struct {
    eff_prev: SBProp,
    eff_prev_prev: ?SBProp,
    ctx: SBContext,
    ctx_is_aterm: bool,
    /// SB7 needs to remember whether the ATerm currently anchoring `ctx` was
    /// itself preceded by an Upper/Lower. Stored at the moment we open the
    /// ATerm context, so subsequent steps can consult it.
    aterm_after_ul: bool,
    /// Raw (literal) property of the previous codepoint, used by SB3/SB4.
    prev_lit: SBProp,

    pub fn init(first_code_point: CodePoint) SentenceStepState {
        const p = sentenceBreakProperty(first_code_point);
        var ctx: SBContext = .none;
        var ctx_is_aterm = false;
        switch (p) {
            .aterm => {
                ctx = .saterm;
                ctx_is_aterm = true;
            },
            .sterm => {
                ctx = .saterm;
            },
            else => {},
        }
        return .{
            .eff_prev = p,
            .eff_prev_prev = null,
            .ctx = ctx,
            .ctx_is_aterm = ctx_is_aterm,
            .aterm_after_ul = false,
            .prev_lit = p,
        };
    }
};

pub const SentenceStepDecision = struct {
    is_break: bool,
    new_state: SentenceStepState,
};

/// SB8 lookahead over a code point slice. Starting at `start`, skip any
/// SB5-ignorable codepoint or codepoint whose property is NOT in
/// {OLetter, Upper, Lower, ParaSep, SATerm}, and return the first qualifying
/// property. Returns null at end-of-text.
fn sb8LookaheadCodePoints(code_points: []const CodePoint, start: usize) ?SBProp {
    var j = start;
    while (j < code_points.len) : (j += 1) {
        const p = sentenceBreakProperty(code_points[j]);
        if (isSBIgnorable(p)) continue;
        switch (p) {
            .oletter, .upper, .lower, .sep, .cr, .lf, .sterm, .aterm => return p,
            else => continue,
        }
    }
    return null;
}

/// SB8 lookahead over a byte stream — same as `sb8LookaheadCodePoints` but
/// decodes UTF-8 on the fly (lossy for invalid bytes).
fn sb8LookaheadBytes(bytes: []const u8, start_byte: usize) ?SBProp {
    var j = start_byte;
    while (j < bytes.len) {
        const decoded = utf8.validateAndDecodeCodePointBytesLossy(bytes, j) catch unreachable;
        const p = sentenceBreakProperty(decoded.code_point);
        j += decoded.len;
        if (isSBIgnorable(p)) continue;
        switch (p) {
            .oletter, .upper, .lower, .sep, .cr, .lf, .sterm, .aterm => return p,
            else => continue,
        }
    }
    return null;
}

/// Shared rule body for sentence stepping. The `lookahead` closure-equivalent
/// is passed as a `?SBProp` already resolved by the caller (codepoint-slice
/// and byte iterators differ only in how they look ahead).
fn sentenceStepInner(state: SentenceStepState, curr: SBProp, lookahead_for_sb8: ?SBProp) SentenceStepDecision {
    const prev_lit = state.prev_lit;

    // SB3: CR × LF — LF stays part of the ParaSep run, slide effective state.
    if (prev_lit == .cr and curr == .lf) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = state.eff_prev,
                .ctx = state.ctx,
                .ctx_is_aterm = state.ctx_is_aterm,
                .aterm_after_ul = state.aterm_after_ul,
                .prev_lit = curr,
            },
        };
    }
    // SB4: (Sep | CR | LF) ÷ — break AFTER a ParaSep, reset everything.
    if (isSBParaSep(prev_lit)) {
        var new_ctx: SBContext = .none;
        var new_ctx_is_aterm = false;
        switch (curr) {
            .aterm => {
                new_ctx = .saterm;
                new_ctx_is_aterm = true;
            },
            .sterm => {
                new_ctx = .saterm;
            },
            else => {},
        }
        return .{
            .is_break = true,
            .new_state = .{
                .eff_prev = curr,
                .eff_prev_prev = null,
                .ctx = new_ctx,
                .ctx_is_aterm = new_ctx_is_aterm,
                .aterm_after_ul = false,
                .prev_lit = curr,
            },
        };
    }
    // SB5: Any × (Extend | Format) — invisible to ctx, eff_prev, eff_prev_prev.
    if (isSBIgnorable(curr)) {
        return .{
            .is_break = false,
            .new_state = .{
                .eff_prev = state.eff_prev,
                .eff_prev_prev = state.eff_prev_prev,
                .ctx = state.ctx,
                .ctx_is_aterm = state.ctx_is_aterm,
                .aterm_after_ul = state.aterm_after_ul,
                .prev_lit = curr,
            },
        };
    }

    var no_break = false;

    if (state.ctx_is_aterm and (state.ctx == .saterm or state.ctx == .saterm_close or state.ctx == .saterm_close_sp)) {
        if (state.ctx == .saterm and curr == .numeric) no_break = true;
        if (state.ctx == .saterm and curr == .upper and state.aterm_after_ul) no_break = true;
        if (!no_break) {
            if (lookahead_for_sb8) |term| {
                if (term == .lower) no_break = true;
            }
        }
    }

    if (!no_break and (state.ctx == .saterm or state.ctx == .saterm_close or state.ctx == .saterm_close_sp)) {
        if (curr == .scontinue or isSATerm(curr)) no_break = true;
    }

    if (!no_break and (state.ctx == .saterm or state.ctx == .saterm_close)) {
        if (curr == .close or curr == .sp or isSBParaSep(curr)) no_break = true;
    }

    if (!no_break and (state.ctx == .saterm or state.ctx == .saterm_close or state.ctx == .saterm_close_sp)) {
        if (curr == .sp or isSBParaSep(curr)) no_break = true;
    }

    const in_saterm_ctx = state.ctx == .saterm or state.ctx == .saterm_close or state.ctx == .saterm_close_sp or state.ctx == .saterm_close_sp_parasep;
    const is_break = !no_break and in_saterm_ctx;

    // ctx / aterm_after_ul transition based on the (prev_ctx, curr) pair.
    var new_ctx = state.ctx;
    var new_ctx_is_aterm = state.ctx_is_aterm;
    var new_aterm_after_ul = state.aterm_after_ul;

    switch (state.ctx) {
        .none => {
            switch (curr) {
                .aterm => {
                    new_ctx = .saterm;
                    new_ctx_is_aterm = true;
                    new_aterm_after_ul = (state.eff_prev == .upper or state.eff_prev == .lower);
                },
                .sterm => {
                    new_ctx = .saterm;
                    new_ctx_is_aterm = false;
                },
                else => {},
            }
        },
        .saterm => {
            switch (curr) {
                .close => new_ctx = .saterm_close,
                .sp => new_ctx = .saterm_close_sp,
                .sep, .cr, .lf => new_ctx = .saterm_close_sp_parasep,
                .scontinue, .aterm, .sterm => {
                    if (curr == .aterm) {
                        new_ctx_is_aterm = true;
                        new_aterm_after_ul = (state.eff_prev == .upper or state.eff_prev == .lower);
                    } else if (curr == .sterm) {
                        new_ctx_is_aterm = false;
                    }
                    new_ctx = .saterm;
                },
                .numeric, .upper => new_ctx = .none,
                else => new_ctx = .none,
            }
        },
        .saterm_close => {
            switch (curr) {
                .close => {},
                .sp => new_ctx = .saterm_close_sp,
                .sep, .cr, .lf => new_ctx = .saterm_close_sp_parasep,
                .scontinue, .aterm, .sterm => {
                    if (curr == .aterm) {
                        new_ctx_is_aterm = true;
                        new_aterm_after_ul = false;
                    } else if (curr == .sterm) {
                        new_ctx_is_aterm = false;
                    }
                    new_ctx = .saterm;
                },
                else => new_ctx = .none,
            }
        },
        .saterm_close_sp => {
            switch (curr) {
                .sp => {},
                .sep, .cr, .lf => new_ctx = .saterm_close_sp_parasep,
                .scontinue, .aterm, .sterm => {
                    if (curr == .aterm) {
                        new_ctx_is_aterm = true;
                        new_aterm_after_ul = false;
                    } else if (curr == .sterm) {
                        new_ctx_is_aterm = false;
                    }
                    new_ctx = .saterm;
                },
                else => new_ctx = .none,
            }
        },
        .saterm_close_sp_parasep => {
            new_ctx = switch (curr) {
                .aterm => blk: {
                    new_ctx_is_aterm = true;
                    new_aterm_after_ul = false;
                    break :blk .saterm;
                },
                .sterm => blk: {
                    new_ctx_is_aterm = false;
                    break :blk .saterm;
                },
                else => .none,
            };
        },
    }

    return .{
        .is_break = is_break,
        .new_state = .{
            .eff_prev = curr,
            .eff_prev_prev = state.eff_prev,
            .ctx = new_ctx,
            .ctx_is_aterm = new_ctx_is_aterm,
            .aterm_after_ul = new_aterm_after_ul,
            .prev_lit = curr,
        },
    };
}

/// Decide whether there is a sentence boundary BEFORE `code_points[i]`,
/// given the algorithm state derived from positions 0..i-1.
pub fn sentenceStep(state: SentenceStepState, code_points: []const CodePoint, i: usize) SentenceStepDecision {
    const curr = sentenceBreakProperty(code_points[i]);
    // SB8's lookahead is only needed when we sit inside an ATerm window. We
    // conservatively resolve it always — it is O(distance) but the distance
    // is bounded by the rule itself.
    const lookahead = if (state.ctx_is_aterm and (state.ctx == .saterm or state.ctx == .saterm_close or state.ctx == .saterm_close_sp))
        sb8LookaheadCodePoints(code_points, i)
    else
        null;
    return sentenceStepInner(state, curr, lookahead);
}

/// Compute sentence-boundary opportunities for a sequence of code points,
/// implementing the full UAX #29 sentence boundary algorithm
/// (SB1..SB11 plus SB998/SB999). `out[i]` is true iff there is a sentence
/// boundary immediately BEFORE `code_points[i]`.
pub fn computeSentenceBoundaries(allocator: std.mem.Allocator, code_points: []const CodePoint) ![]bool {
    const n = code_points.len;
    const out = try allocator.alloc(bool, n + 1);
    errdefer allocator.free(out);
    out[0] = true; // SB1
    if (n == 0) return out;
    out[n] = true; // SB2
    if (n == 1) return out;

    var state = SentenceStepState.init(code_points[0]);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const decision = sentenceStep(state, code_points, i);
        out[i] = decision.is_break;
        state = decision.new_state;
    }
    return out;
}

/// Iterator over an explicit `[]const CodePoint` that yields successive
/// sentences as slices of codepoints. Allocation-free.
pub const CodePointSentenceIterator = struct {
    code_points: []const CodePoint,
    pos: usize = 0,
    state: SentenceStepState = undefined,
    primed: bool = false,

    pub fn next(self: *CodePointSentenceIterator) ?[]const CodePoint {
        const n = self.code_points.len;
        if (self.pos >= n) return null;
        const start = self.pos;
        if (!self.primed) {
            self.state = SentenceStepState.init(self.code_points[0]);
            self.primed = true;
        }
        var i = self.pos + 1;
        while (i < n) : (i += 1) {
            const decision = sentenceStep(self.state, self.code_points, i);
            self.state = decision.new_state;
            if (decision.is_break) {
                self.pos = i;
                return self.code_points[start..i];
            }
        }
        self.pos = n;
        return self.code_points[start..n];
    }

    pub fn reset(self: *CodePointSentenceIterator) void {
        self.pos = 0;
        self.primed = false;
    }
};

pub fn codePointSentenceIterator(code_points: []const CodePoint) CodePointSentenceIterator {
    return .{ .code_points = code_points };
}

/// Iterator over UTF-8 input that yields successive sentences as
/// `[]const u8` slices. Invalid UTF-8 is decoded lossily as U+FFFD.
/// Allocation-free.
pub const SentenceIterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    state: SentenceStepState = undefined,
    primed: bool = false,

    pub fn next(self: *SentenceIterator) ?[]const u8 {
        const n = self.bytes.len;
        if (self.pos >= n) return null;
        const start = self.pos;
        // Same trick as WordIterator: decode the codepoint at the start of the
        // segment, prime state on the first ever call (otherwise the state was
        // updated by the previous break decision), then scan boundaries from
        // the byte AFTER this codepoint.
        const first = utf8.validateAndDecodeCodePointBytesLossy(self.bytes, self.pos) catch unreachable;
        if (!self.primed) {
            self.state = SentenceStepState.init(first.code_point);
            self.primed = true;
        }
        var cursor = self.pos + first.len;
        while (cursor < n) {
            const decoded = utf8.validateAndDecodeCodePointBytesLossy(self.bytes, cursor) catch unreachable;
            const curr = sentenceBreakProperty(decoded.code_point);
            const lookahead = if (self.state.ctx_is_aterm and
                (self.state.ctx == .saterm or self.state.ctx == .saterm_close or self.state.ctx == .saterm_close_sp))
                sb8LookaheadBytes(self.bytes, cursor)
            else
                null;
            const decision = sentenceStepInner(self.state, curr, lookahead);
            self.state = decision.new_state;
            if (decision.is_break) {
                self.pos = cursor;
                return self.bytes[start..cursor];
            }
            cursor += decoded.len;
        }
        self.pos = n;
        return self.bytes[start..n];
    }

    pub fn reset(self: *SentenceIterator) void {
        self.pos = 0;
        self.primed = false;
    }
};

pub fn sentenceIterator(bytes: []const u8) SentenceIterator {
    return .{ .bytes = bytes };
}

pub fn countSentences(bytes: []const u8) usize {
    var it = sentenceIterator(bytes);
    var count: usize = 0;
    while (it.next() != null) count += 1;
    return count;
}

pub fn countSentencesFromCodePoints(code_points: []const CodePoint) usize {
    var it = codePointSentenceIterator(code_points);
    var count: usize = 0;
    while (it.next() != null) count += 1;
    return count;
}

// ============================================================================
// UAX #14 Line break
// ============================================================================

const LBProp = LineBreak;

/// Three-way classification of every position returned by
/// `computeLineBoundaries`.
///
/// UAX #14 distinguishes three outcomes at each potential break, but the
/// boundary-test file in the UCD only marks ÷ vs ×, collapsing two of them.
/// Real consumers (text wrapping to a width, paragraph layout) must know which
/// "÷" was a forced newline from the source vs. a place the engine is allowed
/// to wrap, so we surface the distinction here instead of returning a bool.
pub const LineBreakKind = enum {
    /// No break is permitted before this position (UAX #14 "×").
    prohibited,
    /// A break is permitted before this position; the engine may take it to
    /// fit a line but is not required to (UAX #14 "÷" / "direct break").
    /// The vast majority of in-text break opportunities are this kind.
    opportunity,
    /// A break MUST occur before this position (UAX #14 "!"). Generated by
    /// LB4 (after BK), LB5 (after CR not followed by LF, after LF, after NL),
    /// and LB3 (at end of text). Layout engines must always honor these.
    mandatory,
};

/// Resolve UAX #14's "tailoring" requirement before the rule-pair scan: some
/// raw Line_Break property values must be mapped to a "fixed" value before
/// applying the rules (LB1). AI / SG / XX → AL ; CJ → NS ; SA → CM if the
/// codepoint's General_Category is Mn or Mc, else AL.
fn resolveLineBreakProp(p: LBProp, cp: CodePoint) LBProp {
    return switch (p) {
        .ai, .sg, .xx => .al,
        .sa => blk: {
            const gc = unicode_data.generalCategory(cp);
            break :blk if (gc == .non_spacing_mark or gc == .spacing_mark) .cm else .al;
        },
        .cj => .ns,
        else => p,
    };
}

/// True if the property is a space character per UAX #14: SP / ZW.
inline fn lbIsSpaceOrZW(p: LBProp) bool {
    return p == .sp or p == .zw;
}

/// U+25CC DOTTED CIRCLE — referenced verbatim by LB28a as a singleton
/// "AK-base" alongside the AK and AS line-break classes. Its own LB property
/// is AL, so the rule has to consult the raw codepoint.
const DOTTED_CIRCLE: CodePoint = 0x25CC;

inline fn isAKBase(class: LBProp, code_point: CodePoint) bool {
    return class == .ak or class == .as or code_point == DOTTED_CIRCLE;
}

/// Wide enough to count as East_Asian for UAX #14 (F | W | H). Inlined per
/// call site so the algorithm doesn't need to cache an EAW array up front.
inline fn isEastAsianWide(code_point: CodePoint) bool {
    const eaw = east_asian_width.eastAsianWidth(code_point);
    return eaw == .f or eaw == .w or eaw == .h;
}

inline fn isHangulSyllableClass(class: LBProp) bool {
    return switch (class) {
        .jl, .jv, .jt, .h2, .h3 => true,
        else => false,
    };
}

inline fn isHardLineBreaker(class: LBProp) bool {
    // The five classes that LB9 refuses to absorb a following CM/ZWJ into
    // (forcing LB10's "treat remaining CM/ZWJ as AL" instead). Augmented
    // with SP/ZW per LB9's wording: "X is not BK, CR, LF, NL, SP, or ZW".
    return switch (class) {
        .bk, .cr, .lf, .nl, .sp, .zw => true,
        else => false,
    };
}

/// LB25's back-suffix tracker.  `nu_chain` = "NU (SY|IS)*"; `nu_chain_close`
/// adds an optional trailing single CL or CP. Anything else breaks the
/// chain back to `none`. The chain replaces the unbounded tape walk that
/// the batch algorithm used to do.
const LineNumChain = enum { none, nu_chain, nu_chain_close };

inline fn nextLineNumChain(prev: LineNumChain, cur: LBProp) LineNumChain {
    return switch (cur) {
        .nu => .nu_chain,
        .sy, .is => if (prev == .nu_chain) .nu_chain else .none,
        .cl, .cp => if (prev == .nu_chain) .nu_chain_close else .none,
        else => .none,
    };
}

/// The "fresh" set in LB15a's `(sot | BK | CR | LF | NL | OP | QU | GL | SP | ZW)
/// Pi-QU SP* ×` rule.  Used to decide whether a Pi-class QU should arm
/// `lb15a_armed` when it lands on the effective tape.
inline fn isLB15aFreshClass(c: LBProp) bool {
    return switch (c) {
        .bk, .cr, .lf, .nl, .op, .qu, .gl, .sp, .zw => true,
        else => false,
    };
}

inline fn promoteLB10IfCmZwj(class: LBProp) LBProp {
    return if (class == .cm or class == .zwj) LBProp.al else class;
}

/// One element of the up-to-two effective lookaheads passed into
/// `lineStepRules`.  Stored post-LB9 attachment skipping, post-LB10
/// promotion — exactly the form the rule scan would see if it were
/// looking forward in the effective tape.
const LineLookaheadEntry = struct {
    cp: CodePoint,
    raw: LBProp,
    resolved: LBProp,
};

const LineLookaheadPair = struct {
    n1: ?LineLookaheadEntry = null,
    n2: ?LineLookaheadEntry = null,
};

/// Walk a codepoint slice forward starting at `start`, returning the next
/// up-to-two effective entries.  `initial_prev_resolved` is the resolved
/// class of the most recent non-attached entry just before `start`; it
/// seeds the LB9 attachment decision for the very first candidate.
fn lookaheadFromCodePoints(
    code_points: []const CodePoint,
    start: usize,
    initial_prev_resolved: LBProp,
) LineLookaheadPair {
    var prev_res = initial_prev_resolved;
    var result = LineLookaheadPair{};
    var j = start;
    while (j < code_points.len) : (j += 1) {
        const cp = code_points[j];
        const raw = lineBreak(cp);
        const res_pre10 = resolveLineBreakProp(raw, cp);
        const cm_or_zwj = (res_pre10 == .cm or res_pre10 == .zwj);
        if (cm_or_zwj and !isHardLineBreaker(prev_res)) continue;
        const res = promoteLB10IfCmZwj(res_pre10);
        if (result.n1 == null) {
            result.n1 = .{ .cp = cp, .raw = raw, .resolved = res };
            prev_res = res;
        } else {
            result.n2 = .{ .cp = cp, .raw = raw, .resolved = res };
            return result;
        }
    }
    return result;
}

/// Byte-stream variant of `lookaheadFromCodePoints`. Walks forward through
/// UTF-8 codepoints (lossy on invalid sequences) and returns the next
/// up-to-two effective entries.
fn lookaheadFromBytes(
    bytes: []const u8,
    start_byte: usize,
    initial_prev_resolved: LBProp,
) LineLookaheadPair {
    var prev_res = initial_prev_resolved;
    var result = LineLookaheadPair{};
    var j = start_byte;
    while (j < bytes.len) {
        const decoded = utf8.validateAndDecodeCodePointBytesLossy(bytes, j) catch unreachable;
        const cp = decoded.code_point;
        const raw = lineBreak(cp);
        const res_pre10 = resolveLineBreakProp(raw, cp);
        const cm_or_zwj = (res_pre10 == .cm or res_pre10 == .zwj);
        j += decoded.len;
        if (cm_or_zwj and !isHardLineBreaker(prev_res)) continue;
        const res = promoteLB10IfCmZwj(res_pre10);
        if (result.n1 == null) {
            result.n1 = .{ .cp = cp, .raw = raw, .resolved = res };
            prev_res = res;
        } else {
            result.n2 = .{ .cp = cp, .raw = raw, .resolved = res };
            return result;
        }
    }
    return result;
}

/// Per-cursor state required to evaluate UAX #14 boundary rules
/// incrementally. Construct via `LineStepState.init(code_points[0])`, then
/// feed each subsequent codepoint through `lineStep` (codepoint slice) or
/// `lineStepBytes` (UTF-8 stream). Memory is O(1): the algorithm's
/// "effective tape" is collapsed into a few scalar fields plus targeted
/// flags for the SP-skipping and numeric-chain lookbacks.
pub const LineStepState = struct {
    /// Raw line-break class of the most recent source codepoint (literal,
    /// before LB10 promotion). LB8a needs the literal ZWJ; nothing else
    /// looks at this.
    raw_prev: ?LBProp = null,

    /// Effective class of the most recent non-attached codepoint
    /// (post-LB9 skip, post-LB10 promotion). null only at sot.
    eff_prev: ?LBProp = null,
    /// The codepoint that produced `eff_prev`. Used for EAW / general
    /// category / extended-pictographic re-queries by LB19a, LB30, LB30b.
    eff_prev_cp: CodePoint = 0,

    /// Effective class of the entry before `eff_prev`. null = sot or
    /// immediately after a break (tape reset). LB19a arm 4, LB20a, LB21a,
    /// and LB28a rule 3 read this slot.
    eff_prev_prev: ?LBProp = null,
    eff_prev_prev_cp: CodePoint = 0,

    /// Most recent non-attached non-SP effective class. Equals `eff_prev`
    /// unless `eff_prev` is SP, in which case it points further back to
    /// the entry the SPs trail. Drives LB8 (ZW SP* ÷), LB14 (OP SP* ×),
    /// LB16 ((CL|CP) SP* × NS), and LB17 (B2 SP* × B2). null = no non-SP
    /// effective entry in the current run yet.
    last_nonsp: ?LBProp = null,
    last_nonsp_cp: CodePoint = 0,

    /// LB15a fast path: true iff `last_nonsp` is a Pi-class QU AND what
    /// came before it (the literal eff_prev at the moment we installed
    /// the Pi-QU) was sot OR in `isLB15aFreshClass`. Set at the moment we
    /// open the Pi-QU window; trailing SPs leave it intact; the next
    /// non-SP entry clears or refreshes it. LB15a fires whenever this
    /// is true without any tape walk.
    lb15a_armed: bool = false,

    /// LB25 numeric chain back-suffix. See `LineNumChain`.
    num_chain: LineNumChain = .none,

    /// Parity of the unbroken RI run ending at `eff_prev`: 1 = odd
    /// (i.e. an unpaired RI), 0 = even.
    ri_parity: u1 = 0,

    /// Initialise state from the first codepoint of the input. LB2 marks
    /// the boundary BEFORE position 0 as `.prohibited`; callers should
    /// emit that themselves, then call `lineStep` for positions ≥ 1.
    pub fn init(first_cp: CodePoint) LineStepState {
        const raw = lineBreak(first_cp);
        const res_pre10 = resolveLineBreakProp(raw, first_cp);
        // An opening CM/ZWJ at sot has no base, so LB9 cannot attach it;
        // LB10 then promotes it to AL.
        const res = promoteLB10IfCmZwj(res_pre10);
        return .{
            .raw_prev = raw,
            .eff_prev = res,
            .eff_prev_cp = first_cp,
            .eff_prev_prev = null,
            .eff_prev_prev_cp = 0,
            .last_nonsp = if (res == .sp) null else res,
            .last_nonsp_cp = if (res == .sp) 0 else first_cp,
            .lb15a_armed = (res == .qu) and
                unicode_data.generalCategory(first_cp) == .initial_punctuation,
            .num_chain = if (res == .nu) .nu_chain else .none,
            .ri_parity = if (res == .ri) 1 else 0,
        };
    }
};

pub const LineStepDecision = struct {
    kind: LineBreakKind,
    new_state: LineStepState,
};

pub const LineStepByteDecision = struct {
    kind: LineBreakKind,
    new_state: LineStepState,
    /// Byte length of the codepoint that was just stepped over.
    consumed: usize,
};

/// Decide the UAX #14 boundary BEFORE `code_points[i]` given state derived
/// from positions 0..i-1, and return the state to use after consuming
/// position `i`. Caller must have invoked `LineStepState.init(code_points[0])`
/// before the first call (with i == 1).
pub fn lineStep(state: LineStepState, code_points: []const CodePoint, i: usize) LineStepDecision {
    const cur_cp = code_points[i];
    const cur_raw = lineBreak(cur_cp);
    const cur_res_pre10 = resolveLineBreakProp(cur_raw, cur_cp);

    // LB9 attachment: a CM or ZWJ absorbs into the preceding base unless
    // that base is a "hard breaker" (BK CR LF NL SP ZW). At sot there is
    // no base, so attachment is impossible.
    const cm_or_zwj = (cur_res_pre10 == .cm or cur_res_pre10 == .zwj);
    const attached = cm_or_zwj and if (state.eff_prev) |c| !isHardLineBreaker(c) else false;

    if (attached) {
        // LB9-attached marks are invisible: the boundary before them is
        // unconditionally no-break, and only `raw_prev` advances.
        var new_state = state;
        new_state.raw_prev = cur_raw;
        return .{ .kind = .prohibited, .new_state = new_state };
    }

    // LB10: any unattached CM/ZWJ is promoted to AL for the rule scan.
    const cur_res = promoteLB10IfCmZwj(cur_res_pre10);

    const lookahead = lookaheadFromCodePoints(code_points, i + 1, cur_res);
    return lineStepRules(state, cur_cp, cur_raw, cur_res, lookahead);
}

/// Byte-stream variant of `lineStep`. Decodes the codepoint at `byte_pos`
/// (lossy on invalid UTF-8) and returns the boundary decision plus the
/// byte length consumed by the stepped codepoint, so iterators can advance
/// without re-decoding.
pub fn lineStepBytes(state: LineStepState, bytes: []const u8, byte_pos: usize) LineStepByteDecision {
    const decoded = utf8.validateAndDecodeCodePointBytesLossy(bytes, byte_pos) catch unreachable;
    const cur_cp = decoded.code_point;
    const cur_raw = lineBreak(cur_cp);
    const cur_res_pre10 = resolveLineBreakProp(cur_raw, cur_cp);

    const cm_or_zwj = (cur_res_pre10 == .cm or cur_res_pre10 == .zwj);
    const attached = cm_or_zwj and if (state.eff_prev) |c| !isHardLineBreaker(c) else false;

    if (attached) {
        var new_state = state;
        new_state.raw_prev = cur_raw;
        return .{ .kind = .prohibited, .new_state = new_state, .consumed = decoded.len };
    }

    const cur_res = promoteLB10IfCmZwj(cur_res_pre10);
    const lookahead = lookaheadFromBytes(bytes, byte_pos + decoded.len, cur_res);
    const decision = lineStepRules(state, cur_cp, cur_raw, cur_res, lookahead);
    return .{ .kind = decision.kind, .new_state = decision.new_state, .consumed = decoded.len };
}

/// Shared rule body. Caller has already decided that the current codepoint
/// is NOT LB9-attached and has applied LB10 to produce `cur_res`. The
/// `lookahead` pair gives the next up-to-two effective entries forward.
fn lineStepRules(
    state: LineStepState,
    cur_cp: CodePoint,
    cur_raw: LBProp,
    cur_res: LBProp,
    lookahead: LineLookaheadPair,
) LineStepDecision {
    // After `lineStepInit`, every subsequent step has a non-null eff_prev.
    const prev = state.eff_prev.?;
    const prev_cp = state.eff_prev_cp;

    // ----- Hard-break / early-exit rules. -----

    // LB4: BK !
    if (prev == .bk) {
        return .{ .kind = .mandatory, .new_state = stateAfterBreak(cur_cp, cur_raw, cur_res) };
    }
    // LB5: CR × LF.
    if (prev == .cr and cur_res == .lf) {
        return .{ .kind = .prohibited, .new_state = stateAfterContinue(state, cur_cp, cur_raw, cur_res) };
    }
    // LB5: lone CR / LF / NL !
    if (prev == .cr or prev == .lf or prev == .nl) {
        return .{ .kind = .mandatory, .new_state = stateAfterBreak(cur_cp, cur_raw, cur_res) };
    }
    // LB6: × (BK | CR | LF | NL).
    if (cur_res == .bk or cur_res == .cr or cur_res == .lf or cur_res == .nl) {
        return .{ .kind = .prohibited, .new_state = stateAfterContinue(state, cur_cp, cur_raw, cur_res) };
    }
    // LB7: × SP ; × ZW.
    if (cur_res == .sp or cur_res == .zw) {
        return .{ .kind = .prohibited, .new_state = stateAfterContinue(state, cur_cp, cur_raw, cur_res) };
    }

    // LB8: ZW SP* ÷ — break after the most recent non-SP effective entry
    // if it is ZW.
    if (state.last_nonsp) |ns| {
        if (ns == .zw) {
            return .{ .kind = .opportunity, .new_state = stateAfterBreak(cur_cp, cur_raw, cur_res) };
        }
    }

    // LB8a: literal ZWJ ×.
    if (state.raw_prev) |rp| {
        if (rp == .zwj) {
            return .{ .kind = .prohibited, .new_state = stateAfterContinue(state, cur_cp, cur_raw, cur_res) };
        }
    }

    // ----- LB11..LB31 (default-break unless a × rule suppresses). -----

    var allow_break = true;

    // LB11
    if (cur_res == .wj or prev == .wj) allow_break = false;

    // LB12
    if (allow_break and prev == .gl) allow_break = false;

    // LB12a: [^SP BA HY HH] × GL.
    if (allow_break and cur_res == .gl) {
        switch (prev) {
            .sp, .ba, .hy, .hh => {},
            else => allow_break = false,
        }
    }

    // LB13: × CL ; × CP ; × EX ; × SY (IS removed in Unicode 17).
    if (allow_break and (cur_res == .cl or cur_res == .cp or cur_res == .ex or cur_res == .sy)) {
        allow_break = false;
    }

    // LB14: OP SP* × — most recent non-SP is OP.
    if (allow_break) {
        if (state.last_nonsp) |ns| {
            if (ns == .op) allow_break = false;
        }
    }

    // LB15a: armed Pi-QU window (set at the moment the Pi-QU became
    // last_nonsp). Trailing SPs preserve the flag.
    if (allow_break and state.lb15a_armed) allow_break = false;

    // LB15b: × Pf-QU (SP | GL | WJ | CL | QU | CP | EX | IS | SY | BK |
    //                 CR | LF | NL | ZW | eot).
    if (allow_break and cur_res == .qu and unicode_data.generalCategory(cur_cp) == .final_punctuation) {
        const next_in_set = if (lookahead.n1) |n| switch (n.resolved) {
            .sp, .gl, .wj, .cl, .qu, .cp, .ex, .is, .sy, .bk, .cr, .lf, .nl, .zw => true,
            else => false,
        } else true; // eot
        if (next_in_set) allow_break = false;
    }

    // LB15c (Unicode 17): SP ÷ IS NU — forced opportunity break, but only
    // if no earlier × rule suppressed it.
    if (allow_break and prev == .sp and cur_res == .is) {
        if (lookahead.n1) |n| {
            if (n.resolved == .nu) {
                return .{ .kind = .opportunity, .new_state = stateAfterBreak(cur_cp, cur_raw, cur_res) };
            }
        }
    }

    // LB15d: × IS.
    if (allow_break and cur_res == .is) allow_break = false;

    // LB16: (CL | CP) SP* × NS.
    if (allow_break and cur_res == .ns) {
        if (state.last_nonsp) |ns| {
            if (ns == .cl or ns == .cp) allow_break = false;
        }
    }

    // LB17: B2 SP* × B2.
    if (allow_break and cur_res == .b2) {
        if (state.last_nonsp) |ns| {
            if (ns == .b2) allow_break = false;
        }
    }

    // LB18: SP ÷ — break after a space unless an earlier × rule fired.
    if (prev == .sp) {
        if (allow_break) {
            return .{ .kind = .opportunity, .new_state = stateAfterBreak(cur_cp, cur_raw, cur_res) };
        } else {
            return .{ .kind = .prohibited, .new_state = stateAfterContinue(state, cur_cp, cur_raw, cur_res) };
        }
    }

    // LB19: × [QU - Pi] ; [QU - Pf] ×.
    if (allow_break and cur_res == .qu and unicode_data.generalCategory(cur_cp) != .initial_punctuation) {
        allow_break = false;
    }
    if (allow_break and prev == .qu and unicode_data.generalCategory(prev_cp) != .final_punctuation) {
        allow_break = false;
    }

    // LB19a (Unicode 17): EAW-conditioned QU rules.
    //   1. [^EastAsian] × QU
    //   2. × QU ([^EastAsian] | eot)
    //   3. QU × [^EastAsian]
    //   4. (sot | [^EastAsian]) QU ×
    if (allow_break and cur_res == .qu) {
        if (!isEastAsianWide(prev_cp)) allow_break = false; // arm 1
        if (allow_break) {
            const next_non_ea_or_eot = if (lookahead.n1) |n|
                !isEastAsianWide(n.cp)
            else
                true; // eot
            if (next_non_ea_or_eot) allow_break = false; // arm 2
        }
    }
    if (allow_break and prev == .qu) {
        if (!isEastAsianWide(cur_cp)) allow_break = false; // arm 3
        if (allow_break) {
            // arm 4: the character BEFORE the previous QU. sot or non-EA
            // suppresses the break.
            const before_qu_is_ea = if (state.eff_prev_prev != null)
                isEastAsianWide(state.eff_prev_prev_cp)
            else
                false; // sot counts as non-EA
            if (!before_qu_is_ea) allow_break = false;
        }
    }

    // LB20: ÷ CB ; CB ÷.
    if (allow_break and (cur_res == .cb or prev == .cb)) {
        return .{ .kind = .opportunity, .new_state = stateAfterBreak(cur_cp, cur_raw, cur_res) };
    }

    // LB20a (Unicode 17): (sot | BK | CR | LF | NL | SP | ZW | CB | GL)
    //                     (HY | HH) × (AL | HL).
    if (allow_break and (cur_res == .al or cur_res == .hl) and (prev == .hy or prev == .hh)) {
        const fresh = if (state.eff_prev_prev) |c| switch (c) {
            .bk, .cr, .lf, .nl, .sp, .zw, .cb, .gl => true,
            else => false,
        } else true; // sot
        if (fresh) allow_break = false;
    }

    // LB21: × BA ; × HH ; × HY ; × NS ; BB ×.
    if (allow_break and (cur_res == .ba or cur_res == .hh or cur_res == .hy or
        cur_res == .ns or prev == .bb))
    {
        allow_break = false;
    }

    // LB21a: HL (HY | HH) × [^HL].
    if (allow_break and cur_res != .hl) {
        if (state.eff_prev_prev) |back2| {
            if (back2 == .hl and (prev == .hy or prev == .hh)) allow_break = false;
        }
    }

    // LB21b: SY × HL.
    if (allow_break and prev == .sy and cur_res == .hl) allow_break = false;

    // LB22: × IN.
    if (allow_break and cur_res == .in) allow_break = false;

    // LB23: (AL | HL) × NU ; NU × (AL | HL).
    if (allow_break) {
        const al_hl_to_nu = (prev == .al or prev == .hl) and cur_res == .nu;
        const nu_to_al_hl = prev == .nu and (cur_res == .al or cur_res == .hl);
        if (al_hl_to_nu or nu_to_al_hl) allow_break = false;
    }

    // LB23a: PR × (ID | EB | EM) ; (ID | EB | EM) × PO.
    if (allow_break) {
        const pr_to_ideo = prev == .pr and (cur_res == .id or cur_res == .eb or cur_res == .em);
        const ideo_to_po = (prev == .id or prev == .eb or prev == .em) and cur_res == .po;
        if (pr_to_ideo or ideo_to_po) allow_break = false;
    }

    // LB24: (PR | PO) × (AL | HL) ; (AL | HL) × (PR | PO).
    if (allow_break) {
        const prpo_to_alhl = (prev == .pr or prev == .po) and (cur_res == .al or cur_res == .hl);
        const alhl_to_prpo = (prev == .al or prev == .hl) and (cur_res == .pr or cur_res == .po);
        if (prpo_to_alhl or alhl_to_prpo) allow_break = false;
    }

    // LB25: closed-form via num_chain plus immediate prev / two-step
    // lookahead. See `lb25MatchesStream` for the case map.
    if (allow_break and lb25MatchesStream(state.num_chain, prev, cur_res, lookahead)) {
        allow_break = false;
    }

    // LB26 — Hangul syllable interior.
    if (allow_break) {
        if (prev == .jl and (cur_res == .jl or cur_res == .jv or
            cur_res == .h2 or cur_res == .h3))
        {
            allow_break = false;
        } else if ((prev == .jv or prev == .h2) and (cur_res == .jv or cur_res == .jt)) {
            allow_break = false;
        } else if ((prev == .jt or prev == .h3) and cur_res == .jt) {
            allow_break = false;
        }
    }

    // LB27: (JL | JV | JT | H2 | H3) × PO ; PR × (JL | JV | JT | H2 | H3).
    if (allow_break) {
        if (isHangulSyllableClass(prev) and cur_res == .po) allow_break = false;
        if (prev == .pr and isHangulSyllableClass(cur_res)) allow_break = false;
    }

    // LB28: (AL | HL) × (AL | HL).
    if (allow_break and (prev == .al or prev == .hl) and (cur_res == .al or cur_res == .hl)) {
        allow_break = false;
    }

    // LB28a — Brahmic letter pairs.
    if (allow_break and lb28aMatchesStream(
        prev,
        cur_res,
        prev_cp,
        cur_cp,
        state.eff_prev_prev,
        state.eff_prev_prev_cp,
        lookahead,
    )) {
        allow_break = false;
    }

    // LB29: IS × (AL | HL).
    if (allow_break and prev == .is and (cur_res == .al or cur_res == .hl)) {
        allow_break = false;
    }

    // LB30: (AL | HL | NU) × [OP - EastAsian] ;
    //       [CP - EastAsian] × (AL | HL | NU).
    if (allow_break) {
        const left_to_op = (prev == .al or prev == .hl or prev == .nu) and
            cur_res == .op and !isEastAsianWide(cur_cp);
        const cp_to_right = prev == .cp and
            (cur_res == .al or cur_res == .hl or cur_res == .nu) and
            !isEastAsianWide(prev_cp);
        if (left_to_op or cp_to_right) allow_break = false;
    }

    // LB30a — RI parity.
    if (allow_break and prev == .ri and cur_res == .ri and state.ri_parity == 1) {
        allow_break = false;
    }

    // LB30b: EB × EM ; [Extended_Pictographic & gc=Cn] × EM.
    if (allow_break and cur_res == .em) {
        if (prev == .eb) {
            allow_break = false;
        } else if (isExtendedPictographic(prev_cp) and
            unicode_data.generalCategory(prev_cp) == .unassigned)
        {
            allow_break = false;
        }
    }

    // Commit.
    if (allow_break) {
        return .{ .kind = .opportunity, .new_state = stateAfterBreak(cur_cp, cur_raw, cur_res) };
    } else {
        return .{ .kind = .prohibited, .new_state = stateAfterContinue(state, cur_cp, cur_raw, cur_res) };
    }
}

/// State immediately after a break (opportunity or mandatory). The new
/// "effective tape" starts fresh at `cur`, so every back-pointer becomes
/// either `cur` or null. Note: LB7 routes SP and ZW to `stateAfterContinue`,
/// so by the time this is reached `cur_res` is never SP.
inline fn stateAfterBreak(cur_cp: CodePoint, cur_raw: LBProp, cur_res: LBProp) LineStepState {
    return .{
        .raw_prev = cur_raw,
        .eff_prev = cur_res,
        .eff_prev_cp = cur_cp,
        .eff_prev_prev = null,
        .eff_prev_prev_cp = 0,
        .last_nonsp = if (cur_res == .sp) null else cur_res,
        .last_nonsp_cp = if (cur_res == .sp) 0 else cur_cp,
        // A Pi-QU starting a fresh run satisfies LB15a's "before fresh"
        // clause via sot.
        .lb15a_armed = (cur_res == .qu) and
            unicode_data.generalCategory(cur_cp) == .initial_punctuation,
        .num_chain = if (cur_res == .nu) .nu_chain else .none,
        .ri_parity = if (cur_res == .ri) 1 else 0,
    };
}

/// State after a non-break boundary (`.prohibited`). The current codepoint
/// joins the effective tape; SP entries preserve `last_nonsp` and
/// `lb15a_armed` so an arbitrarily long SP run keeps the X-SP* lookbacks
/// intact, while non-SP entries refresh both.
inline fn stateAfterContinue(
    state: LineStepState,
    cur_cp: CodePoint,
    cur_raw: LBProp,
    cur_res: LBProp,
) LineStepState {
    var new = LineStepState{};
    new.raw_prev = cur_raw;
    new.eff_prev = cur_res;
    new.eff_prev_cp = cur_cp;
    new.eff_prev_prev = state.eff_prev;
    new.eff_prev_prev_cp = state.eff_prev_cp;

    if (cur_res == .sp) {
        new.last_nonsp = state.last_nonsp;
        new.last_nonsp_cp = state.last_nonsp_cp;
        new.lb15a_armed = state.lb15a_armed;
    } else {
        new.last_nonsp = cur_res;
        new.last_nonsp_cp = cur_cp;
        const is_pi_qu = (cur_res == .qu) and
            unicode_data.generalCategory(cur_cp) == .initial_punctuation;
        const before_fresh = if (state.eff_prev) |c| isLB15aFreshClass(c) else true;
        new.lb15a_armed = is_pi_qu and before_fresh;
    }

    new.num_chain = nextLineNumChain(state.num_chain, cur_res);

    if (cur_res == .ri) {
        // RI run accounting: if the run ending at the previous step was
        // odd (parity == 1) and we did not break (only the case if LB30a
        // fired), this RI pairs up — parity flips to even. Otherwise we
        // start a fresh single RI.
        const prev_is_ri = if (state.eff_prev) |c| c == .ri else false;
        if (prev_is_ri and state.ri_parity == 1) {
            new.ri_parity = 0;
        } else {
            new.ri_parity = 1;
        }
    } else {
        new.ri_parity = 0;
    }

    return new;
}

/// Streaming LB25 check. The fifteen UAX #14 numeric sub-rules collapse
/// into: (1) immediate-previous tests for prev × NU; (2) `num_chain` for
/// "NU (SY|IS)* (CL|CP)? × (PO|PR)" and "NU (SY|IS)* × NU"; (3) up to
/// two-step lookahead for "(PO|PR) × OP (NU | IS NU)".
fn lb25MatchesStream(
    chain: LineNumChain,
    prev: LBProp,
    cur: LBProp,
    lookahead: LineLookaheadPair,
) bool {
    // Rules 9 / 12 / 13 / 14 / 15: × NU.
    if (cur == .nu) {
        switch (prev) {
            .po, .pr, .hy, .is => return true,
            else => {},
        }
        if (chain == .nu_chain) return true; // rule 15
    }

    // Rules 7 / 8 / 10 / 11: (PO | PR) × OP (NU | IS NU).
    if ((prev == .po or prev == .pr) and cur == .op) {
        if (lookahead.n1) |n1| {
            if (n1.resolved == .nu) return true;
            if (n1.resolved == .is) {
                if (lookahead.n2) |n2| {
                    if (n2.resolved == .nu) return true;
                }
            }
        }
    }

    // Rules 1..6: NU (SY | IS)* (CL | CP)? × (PO | PR).
    if (cur == .po or cur == .pr) {
        if (chain == .nu_chain or chain == .nu_chain_close) return true;
    }

    return false;
}

/// Streaming LB28a check (Brahmic letter pairs). Sub-rules 1-3 read back
/// at most two effective entries, all available from state. Sub-rule 4
/// uses one effective lookahead.
fn lb28aMatchesStream(
    prev: LBProp,
    cur: LBProp,
    prev_cp: CodePoint,
    cur_cp: CodePoint,
    back2: ?LBProp,
    back2_cp: CodePoint,
    lookahead: LineLookaheadPair,
) bool {
    const prev_is_ak_base = isAKBase(prev, prev_cp);
    const cur_is_ak_base = isAKBase(cur, cur_cp);

    // Rule 1: AP × (AK | DC | AS).
    if (prev == .ap and cur_is_ak_base) return true;

    // Rule 2: (AK | DC | AS) × (VF | VI).
    if (prev_is_ak_base and (cur == .vf or cur == .vi)) return true;

    // Rule 3: (AK | DC | AS) VI × (AK | DC).
    if (prev == .vi and (cur == .ak or cur_cp == DOTTED_CIRCLE)) {
        if (back2) |b2_class| {
            if (isAKBase(b2_class, back2_cp)) return true;
        }
    }

    // Rule 4: (AK | DC | AS) × (AK | DC | AS) VF — one effective lookahead.
    if (prev_is_ak_base and cur_is_ak_base) {
        if (lookahead.n1) |n1| {
            if (n1.resolved == .vf) return true;
        }
    }

    return false;
}

/// Compute line-break classification for a sequence of code points,
/// implementing the full UAX #14 line-break algorithm (Unicode 17.0,
/// rev 55). `out[i]` describes the boundary BEFORE `code_points[i]`:
/// `.prohibited` (× rules), `.opportunity` (÷ rules), or `.mandatory`
/// (LB4/LB5 forced breaks, and LB3 at end-of-text).
///
///   - `out[0]` is `.prohibited` — LB2 ("never break at start of text");
///     for n == 0 the returned slice is a single `.prohibited`.
///   - `out[n]` is `.mandatory` — LB3 ("always break at end of text").
///
/// The three-way classification is the meaningful return type: layout
/// engines must always honor a mandatory break (a literal newline) while
/// opportunities are merely candidate wrap points. Collapsing the two
/// onto a single boolean loses that distinction.
///
/// Internally this is a thin wrapper around the streaming `lineStep`
/// state machine: the only allocation is the returned boundary array
/// itself; the algorithm's prior workspace (raw/resolved class arrays,
/// LB9 attachment table, effective tape) has been replaced with O(1)
/// state inside `LineStepState`.
pub fn computeLineBoundaries(allocator: std.mem.Allocator, code_points: []const CodePoint) ![]LineBreakKind {
    const total = code_points.len;
    const boundaries = try allocator.alloc(LineBreakKind, total + 1);
    errdefer allocator.free(boundaries);

    // LB2: × sot.
    boundaries[0] = .prohibited;
    if (total == 0) return boundaries;
    // LB3: ! eot.
    boundaries[total] = .mandatory;
    if (total == 1) return boundaries;

    var state = LineStepState.init(code_points[0]);
    var i: usize = 1;
    while (i < total) : (i += 1) {
        const decision = lineStep(state, code_points, i);
        boundaries[i] = decision.kind;
        state = decision.new_state;
    }
    return boundaries;
}

/// One segment yielded by `LineBreakIterator` / `CodePointLineBoundaryIterator`:
/// the bytes (or codepoints) up to the boundary, plus the kind of break that
/// terminated the segment. Layout engines must honor `.mandatory` and may
/// take `.opportunity` to fit a line; for the final segment of the input the
/// kind is `.mandatory` (LB3).
pub fn LineSegment(comptime Element: type) type {
    return struct {
        slice: []const Element,
        kind: LineBreakKind,
    };
}

/// Iterator over an explicit `[]const CodePoint` that yields successive
/// line-break segments. Each item carries the codepoints from the previous
/// boundary up to the position just before the next break, paired with the
/// `LineBreakKind` (mandatory vs opportunity) that terminates it.
/// Allocation-free: state is computed lazily via `lineStep`.
pub const CodePointLineBoundaryIterator = struct {
    code_points: []const CodePoint,
    pos: usize = 0,
    state: LineStepState = undefined,
    primed: bool = false,

    pub fn next(self: *CodePointLineBoundaryIterator) ?LineSegment(CodePoint) {
        const n = self.code_points.len;
        if (self.pos >= n) return null;
        const start = self.pos;
        if (!self.primed) {
            self.state = LineStepState.init(self.code_points[0]);
            self.primed = true;
        }
        var i = self.pos + 1;
        while (i < n) : (i += 1) {
            const decision = lineStep(self.state, self.code_points, i);
            self.state = decision.new_state;
            if (decision.kind != .prohibited) {
                self.pos = i;
                return .{ .slice = self.code_points[start..i], .kind = decision.kind };
            }
        }
        self.pos = n;
        // LB3: eot is always mandatory.
        return .{ .slice = self.code_points[start..n], .kind = .mandatory };
    }

    pub fn reset(self: *CodePointLineBoundaryIterator) void {
        self.pos = 0;
        self.primed = false;
    }
};

pub fn codePointLineBoundaryIterator(code_points: []const CodePoint) CodePointLineBoundaryIterator {
    return .{ .code_points = code_points };
}

/// Iterator over UTF-8 input that yields successive line-break segments as
/// byte slices paired with the `LineBreakKind` terminating each segment.
/// Allocation-free: boundary classification is computed lazily via
/// `lineStepBytes`.
pub const LineBreakIterator = struct {
    bytes: []const u8,
    pos: usize = 0,
    state: LineStepState = undefined,
    primed: bool = false,

    pub fn next(self: *LineBreakIterator) ?LineSegment(u8) {
        const n = self.bytes.len;
        if (self.pos >= n) return null;
        const start = self.pos;
        // Decode the codepoint that opens the new segment. On the very
        // first call we use it to seed the state; on subsequent calls the
        // state was already updated by the previous break decision, so we
        // just skip past it.
        const first = utf8.validateAndDecodeCodePointBytesLossy(self.bytes, self.pos) catch unreachable;
        if (!self.primed) {
            self.state = LineStepState.init(first.code_point);
            self.primed = true;
        }
        var cursor = self.pos + first.len;
        while (cursor < n) {
            const decision = lineStepBytes(self.state, self.bytes, cursor);
            self.state = decision.new_state;
            if (decision.kind != .prohibited) {
                self.pos = cursor;
                return .{ .slice = self.bytes[start..cursor], .kind = decision.kind };
            }
            cursor += decision.consumed;
        }
        self.pos = n;
        // LB3: eot is always mandatory.
        return .{ .slice = self.bytes[start..n], .kind = .mandatory };
    }

    pub fn reset(self: *LineBreakIterator) void {
        self.pos = 0;
        self.primed = false;
    }
};

pub fn lineBreakIterator(bytes: []const u8) LineBreakIterator {
    return .{ .bytes = bytes };
}

/// Count the number of line-break segments in `bytes`. Allocation-free.
pub fn countLineSegments(bytes: []const u8) usize {
    var it = lineBreakIterator(bytes);
    var count: usize = 0;
    while (it.next() != null) count += 1;
    return count;
}

pub fn countLineSegmentsFromCodePoints(code_points: []const CodePoint) usize {
    var it = codePointLineBoundaryIterator(code_points);
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

// ============================================================================
// Line-break kind, iterators, and count helpers
// ============================================================================

test "line break: LB3 marks end-of-text as mandatory and LB2 sot as prohibited" {
    const cps = [_]CodePoint{ 'a', 'b' };
    const got = try computeLineBoundaries(testing.allocator, &cps);
    defer testing.allocator.free(got);
    try testing.expectEqual(@as(usize, 3), got.len);
    try testing.expectEqual(LineBreakKind.prohibited, got[0]);
    try testing.expectEqual(LineBreakKind.prohibited, got[1]); // LB28: AL × AL
    try testing.expectEqual(LineBreakKind.mandatory, got[2]); // LB3
}

test "line break: mandatory vs opportunity is distinguished where conformance hides it" {
    // "a b\nc" — boundary before 'b' is a regular opportunity (SP ÷ via LB18),
    // boundary before 'c' is a MANDATORY break (LB5 after LF). Conformance
    // returns ÷ for both; the enum must not.
    const cps = [_]CodePoint{ 'a', ' ', 'b', '\n', 'c' };
    const got = try computeLineBoundaries(testing.allocator, &cps);
    defer testing.allocator.free(got);
    try testing.expectEqual(LineBreakKind.prohibited, got[0]); // sot
    try testing.expectEqual(LineBreakKind.prohibited, got[1]); // × SP (LB7)
    try testing.expectEqual(LineBreakKind.opportunity, got[2]); // SP ÷ b (LB18)
    try testing.expectEqual(LineBreakKind.prohibited, got[3]); // × LF (LB6)
    try testing.expectEqual(LineBreakKind.mandatory, got[4]); // LF ! c (LB5)
    try testing.expectEqual(LineBreakKind.mandatory, got[5]); // eot (LB3)
}

test "line break: CR LF stays together; lone CR is still mandatory" {
    {
        const cps = [_]CodePoint{ 'a', '\r', '\n', 'b' };
        const got = try computeLineBoundaries(testing.allocator, &cps);
        defer testing.allocator.free(got);
        try testing.expectEqual(LineBreakKind.prohibited, got[2]); // CR × LF
        try testing.expectEqual(LineBreakKind.mandatory, got[3]); // after LF
    }
    {
        const cps = [_]CodePoint{ 'a', '\r', 'b' };
        const got = try computeLineBoundaries(testing.allocator, &cps);
        defer testing.allocator.free(got);
        try testing.expectEqual(LineBreakKind.mandatory, got[2]); // lone CR is LB5 mandatory
    }
}

test "line break: BK forces mandatory break (LB4)" {
    // FORM FEED U+000C is class BK.
    const cps = [_]CodePoint{ 'a', 0x000C, 'b' };
    const got = try computeLineBoundaries(testing.allocator, &cps);
    defer testing.allocator.free(got);
    try testing.expectEqual(LineBreakKind.prohibited, got[1]); // × BK (LB6)
    try testing.expectEqual(LineBreakKind.mandatory, got[2]); // BK ! b (LB4)
}

test "word iterator: codepoint slice yields word-level segments matching the compute primitive" {
    const cps = [_]CodePoint{ 'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd' };
    var it = codePointWordIterator(&cps);
    const w1 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqual(@as(usize, 5), w1.len); // "hello"
    const w2 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqual(@as(usize, 1), w2.len); // " "
    const w3 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqual(@as(usize, 5), w3.len); // "world"
    try testing.expect(it.next() == null);
}

test "word iterator: byte stream matches grapheme-style ergonomics over UTF-8" {
    var it = wordIterator("hello world");
    try testing.expectEqualStrings("hello", it.next().?);
    try testing.expectEqualStrings(" ", it.next().?);
    try testing.expectEqualStrings("world", it.next().?);
    try testing.expect(it.next() == null);
}

test "word iterator: empty input yields no words" {
    var it = wordIterator("");
    try testing.expect(it.next() == null);
    var cp_it = codePointWordIterator(&[_]CodePoint{});
    try testing.expect(cp_it.next() == null);
}

test "word iterator: reset re-emits the same sequence" {
    var it = wordIterator("foo bar");
    try testing.expectEqualStrings("foo", it.next().?);
    try testing.expectEqualStrings(" ", it.next().?);
    it.reset();
    try testing.expectEqualStrings("foo", it.next().?);
}

test "word iterator: agrees with computeWordBoundaries on a hostile case" {
    // Numeric expressions, ZWJ emoji, and CR LF in one sample.
    const cps = [_]CodePoint{ '1', '2', '.', '5', ' ', 'A', '\r', '\n', 0x1F468, 0x200D, 0x1F469 };
    const want = try computeWordBoundaries(testing.allocator, &cps);
    defer testing.allocator.free(want);

    var it = codePointWordIterator(&cps);
    var i: usize = 0;
    while (it.next()) |word| {
        // Boundary before the start of every word must be true in `want`.
        try testing.expect(want[i]);
        i += word.len;
    }
    try testing.expectEqual(cps.len, i);
    try testing.expect(want[cps.len]); // WB2
}

test "sentence iterator: byte stream splits a multi-sentence paragraph" {
    var it = sentenceIterator("Hello. How are you? I am fine.");
    try testing.expectEqualStrings("Hello. ", it.next().?);
    try testing.expectEqualStrings("How are you? ", it.next().?);
    try testing.expectEqualStrings("I am fine.", it.next().?);
    try testing.expect(it.next() == null);
}

test "sentence iterator: agrees with computeSentenceBoundaries" {
    const cps = [_]CodePoint{ 'H', 'i', '.', ' ', 'B', 'y', 'e', '.' };
    const want = try computeSentenceBoundaries(testing.allocator, &cps);
    defer testing.allocator.free(want);

    var it = codePointSentenceIterator(&cps);
    var i: usize = 0;
    while (it.next()) |seg| {
        try testing.expect(want[i]);
        i += seg.len;
    }
    try testing.expectEqual(cps.len, i);
    try testing.expect(want[cps.len]);
}

test "line break iterator: yields opportunities and final mandatory" {
    var it = lineBreakIterator("hello world");
    const s1 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqualStrings("hello ", s1.slice);
    try testing.expectEqual(LineBreakKind.opportunity, s1.kind);
    const s2 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqualStrings("world", s2.slice);
    try testing.expectEqual(LineBreakKind.mandatory, s2.kind);
    try testing.expect(it.next() == null);
}

test "line break iterator: distinguishes mandatory from opportunity over a newline" {
    var it = lineBreakIterator("foo bar\nbaz");
    const s1 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqualStrings("foo ", s1.slice);
    try testing.expectEqual(LineBreakKind.opportunity, s1.kind);
    const s2 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqualStrings("bar\n", s2.slice);
    try testing.expectEqual(LineBreakKind.mandatory, s2.kind); // LF ! baz
    const s3 = it.next() orelse return error.TestExpectedSegment;
    try testing.expectEqualStrings("baz", s3.slice);
    try testing.expectEqual(LineBreakKind.mandatory, s3.kind); // eot LB3
    try testing.expect(it.next() == null);
}

test "line break iterator: empty input yields no segments" {
    var it = lineBreakIterator("");
    try testing.expect(it.next() == null);
}

test "line break iterator: codepoint variant agrees with byte variant" {
    const text = "ab cd\nef";
    var byte_it = lineBreakIterator(text);
    const cps = [_]CodePoint{ 'a', 'b', ' ', 'c', 'd', '\n', 'e', 'f' };
    var cp_it = codePointLineBoundaryIterator(&cps);
    while (true) {
        const a = byte_it.next();
        const b = cp_it.next();
        if (a == null and b == null) break;
        try testing.expect(a != null and b != null);
        try testing.expectEqual(a.?.slice.len, b.?.slice.len);
        try testing.expectEqual(a.?.kind, b.?.kind);
    }
}

test "count helpers: counts match iterator output" {
    try testing.expectEqual(@as(usize, 3), countWords("foo bar"));
    try testing.expectEqual(@as(usize, 0), countWords(""));
    try testing.expectEqual(@as(usize, 2), countSentences("One. Two."));
    try testing.expectEqual(@as(usize, 2), countLineSegments("hi there"));
    try testing.expectEqual(@as(usize, 3), countLineSegments("a b\nc"));
}
