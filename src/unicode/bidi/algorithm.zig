//! The Unicode Bidirectional Algorithm (UAX #9).
//!
//! Given a paragraph of code points, this resolves the embedding level of every
//! character and produces the visual (left-to-right display) order of a line.
//! The implementation follows the rule numbering of the specification so the
//! code can be read next to it:
//!
//!   * P1–P3  — split into paragraphs and pick the paragraph embedding level.
//!   * X1–X8  — walk the explicit embeddings/overrides/isolates, assigning each
//!              character a level and applying overrides. (X9 is done by
//!              *retaining* the formatting characters and marking them BN, the
//!              alternative sanctioned by the spec's section 5.2.)
//!   * X10    — partition the text into isolating run sequences (BD13) and
//!              derive `sos`/`eos` for each.
//!   * W1–W7  — resolve weak types (numbers, separators, NSM).
//!   * N0–N2  — resolve paired brackets (BD16) and the remaining neutrals.
//!   * I1–I2  — fold the resolved types back into levels.
//!   * L1–L2  — reset trailing whitespace and reverse runs for display.
//!
//! The entry point is `resolveParagraph`, which returns a `Paragraph` owning the
//! per-character levels. Reordering is a separate, line-oriented step
//! (`Paragraph.reorderLine`) because line breaking happens above this layer and
//! L1/L2 are defined per visual line.
//!
//! Levels live in a `u8`: explicit nesting is capped at `max_depth` (125) and
//! I1/I2 can add at most two, so 127 is the ceiling.

const std = @import("std");
const encoding = @import("encoding");
const properties = @import("../properties/root.zig");
const generated_brackets = @import("generated/bidi_brackets.zig");
const generated_mirroring = @import("generated/bidi_mirroring.zig");

const CodePoint = encoding.CodePoint;
const BidiClass = properties.BidiClass;

/// An embedding level. Even levels are left-to-right, odd levels right-to-left.
pub const Level = u8;

/// The deepest explicit embedding/override/isolate nesting the algorithm
/// tracks (BD2). Anything deeper is counted as overflow and ignored.
pub const max_depth: Level = 125;

// The status stack never holds more than one entry per distinct level plus the
// base entry, so `max_depth + 2` is a safe upper bound.
const max_stack = max_depth + 2;

/// The base direction requested for a paragraph. `.auto` runs P2/P3 to detect
/// the direction from the first strong character (Unicode's HL1 / "first strong"
/// heuristic).
pub const BaseDirection = enum { ltr, rtl, auto };

// Short aliases for the bidi classes, matching the abbreviations used in the
// spec. Keeping them local avoids `properties.BidiClass.right_to_left` noise in
// every rule.
const L = BidiClass.left_to_right;
const R = BidiClass.right_to_left;
const AL = BidiClass.arabic_letter;
const EN = BidiClass.european_number;
const ES = BidiClass.european_separator;
const ET = BidiClass.european_terminator;
const AN = BidiClass.arabic_number;
const CS = BidiClass.common_separator;
const NSM = BidiClass.non_spacing_mark;
const BN = BidiClass.boundary_neutral;
const B = BidiClass.paragraph_separator;
const S = BidiClass.segment_separator;
const WS = BidiClass.whitespace;
const ON = BidiClass.other_neutral;
const LRE = BidiClass.left_to_right_embedding;
const LRO = BidiClass.left_to_right_override;
const RLE = BidiClass.right_to_left_embedding;
const RLO = BidiClass.right_to_left_override;
const PDF = BidiClass.pop_directional_format;
const LRI = BidiClass.left_to_right_isolate;
const RLI = BidiClass.right_to_left_isolate;
const FSI = BidiClass.first_strong_isolate;
const PDI = BidiClass.pop_directional_isolate;

// ============================================================================
// Class predicates (exported — useful on their own)
// ============================================================================

/// True for LRI, RLI, FSI — the three isolate initiators.
pub fn isIsolateInitiator(c: BidiClass) bool {
    return c == LRI or c == RLI or c == FSI;
}

/// True for the characters X9 removes from the algorithm: the embeddings,
/// overrides, the terminating PDF, and Boundary Neutral.
pub fn isRemovedByX9(c: BidiClass) bool {
    return c == RLE or c == LRE or c == RLO or c == LRO or c == PDF or c == BN;
}

/// True for the "NI" set in the spec: neutrals (B, S, WS, ON) plus the isolate
/// formatting characters (FSI, LRI, RLI, PDI). These are what N1/N2 resolve.
pub fn isNeutralOrIsolate(c: BidiClass) bool {
    return c == B or c == S or c == WS or c == ON or
        c == FSI or c == LRI or c == RLI or c == PDI;
}

/// True for the strong types L, R, AL.
pub fn isStrong(c: BidiClass) bool {
    return c == L or c == R or c == AL;
}

inline fn dirFromLevel(level: Level) BidiClass {
    return if (level & 1 == 1) R else L;
}

inline fn nextOddLevel(level: Level) Level {
    return (level + 1) | 1;
}

inline fn nextEvenLevel(level: Level) Level {
    return (level + 2) & ~@as(Level, 1);
}

/// L4: a character is shown mirrored exactly when its resolved level is odd and
/// it has a Bidi_Mirroring_Glyph. Returns the glyph to paint for `cp` at `level`
/// (the original code point when no mirroring applies).
///
/// @stable-since: v0.1.0
pub fn mirror(cp: CodePoint, level: Level) CodePoint {
    if (level & 1 == 1) return generated_mirroring.bidiMirroringGlyph(cp) orelse cp;
    return cp;
}

// ============================================================================
// Paragraph level (P2/P3)
// ============================================================================

// Scan `[start, end)` of `classes` for the first strong type, skipping anything
// between an isolate initiator and its matching PDI (P2). Returns 1 for R/AL, 0
// for L, and `default` if no strong type is found (P3).
fn firstStrongLevel(classes: []const BidiClass, start: usize, end: usize, default: Level) Level {
    var i = start;
    while (i < end) {
        const c = classes[i];
        if (isIsolateInitiator(c)) {
            var depth: usize = 1;
            i += 1;
            while (i < end and depth > 0) : (i += 1) {
                const cc = classes[i];
                if (isIsolateInitiator(cc)) {
                    depth += 1;
                } else if (cc == PDI) {
                    depth -= 1;
                }
            }
            continue;
        }
        switch (c) {
            R, AL => return 1,
            L => return 0,
            else => i += 1,
        }
    }
    return default;
}

/// The paragraph embedding level for `cps` under `base` (P2/P3). Does not
/// allocate — code points are classified on the fly.
///
/// @stable-since: v0.1.0
pub fn paragraphLevel(cps: []const CodePoint, base: BaseDirection) Level {
    switch (base) {
        .ltr => return 0,
        .rtl => return 1,
        .auto => {},
    }
    var i: usize = 0;
    while (i < cps.len) {
        const c = properties.bidiClass(cps[i]);
        if (isIsolateInitiator(c)) {
            var depth: usize = 1;
            i += 1;
            while (i < cps.len and depth > 0) : (i += 1) {
                const cc = properties.bidiClass(cps[i]);
                if (isIsolateInitiator(cc)) {
                    depth += 1;
                } else if (cc == PDI) {
                    depth -= 1;
                }
            }
            continue;
        }
        switch (c) {
            R, AL => return 1,
            L => return 0,
            else => i += 1,
        }
    }
    return 0;
}

// ============================================================================
// Resolved paragraph
// ============================================================================

/// The result of running the algorithm over one paragraph. Owns `levels` (the
/// resolved embedding level of every input character, after I1/I2) and
/// `original_classes` (kept because L1 and mirroring are defined on the
/// *original* types). Free it with `deinit`.
pub const Paragraph = struct {
    allocator: std.mem.Allocator,
    /// Paragraph embedding level (P3): 0 for LTR, 1 for RTL.
    level: Level,
    /// One resolved level per input code point.
    levels: []Level,
    /// The Bidi_Class of every input code point, before resolution.
    original_classes: []BidiClass,

    pub fn deinit(self: *Paragraph) void {
        self.allocator.free(self.levels);
        self.allocator.free(self.original_classes);
        self.* = undefined;
    }

    /// Resolved levels for the line `[start, end)` with L1 applied (trailing
    /// whitespace / separators reset to the paragraph level). The caller owns
    /// the returned slice.
    pub fn lineLevels(self: *const Paragraph, allocator: std.mem.Allocator, start: usize, end: usize) ![]Level {
        std.debug.assert(start <= end and end <= self.levels.len);
        const out = try allocator.dupe(Level, self.levels[start..end]);
        errdefer allocator.free(out);
        applyL1(out, self.original_classes[start..end], self.level);
        return out;
    }

    /// Visual order of the line `[start, end)`: a permutation of the absolute
    /// indices `start..end` giving left-to-right display order (L1 then L2).
    /// The caller owns the returned slice.
    pub fn reorderLine(self: *const Paragraph, allocator: std.mem.Allocator, start: usize, end: usize) ![]usize {
        const line = try self.lineLevels(allocator, start, end);
        defer allocator.free(line);
        const order = try reorderVisual(allocator, line);
        for (order) |*v| v.* += start;
        return order;
    }
};

/// L2: given the resolved `levels` of a single line, return the visual order as
/// a permutation of `0..levels.len`. The caller owns the returned slice.
///
/// @stable-since: v0.1.0
pub fn reorderVisual(allocator: std.mem.Allocator, levels: []const Level) ![]usize {
    const order = try allocator.alloc(usize, levels.len);
    errdefer allocator.free(order);
    for (order, 0..) |*v, i| v.* = i;
    if (levels.len == 0) return order;

    var highest: Level = 0;
    var lowest_odd: Level = std.math.maxInt(Level);
    for (levels) |lvl| {
        highest = @max(highest, lvl);
        if (lvl & 1 == 1) lowest_odd = @min(lowest_odd, lvl);
    }
    if (lowest_odd == std.math.maxInt(Level)) return order; // no odd levels: nothing to reverse

    var lvl = highest;
    while (lvl >= lowest_odd) : (lvl -= 1) {
        var i: usize = 0;
        while (i < order.len) {
            if (levels[order[i]] >= lvl) {
                var j = i + 1;
                while (j < order.len and levels[order[j]] >= lvl) j += 1;
                std.mem.reverse(usize, order[i..j]);
                i = j;
            } else {
                i += 1;
            }
        }
        if (lvl == 0) break; // unreachable (lowest_odd >= 1) but keeps the u8 honest
    }
    return order;
}

/// Convenience one-shot: resolve `cps` as a single paragraph and return the
/// visual (display) order of the whole text treated as one line (L1 then L2).
/// Equivalent to `resolveParagraph` followed by `Paragraph.reorderLine` over the
/// full range. The caller owns the returned slice.
///
/// @stable-since: v0.1.0
pub fn reorderParagraph(allocator: std.mem.Allocator, cps: []const CodePoint, base: BaseDirection) ![]usize {
    var p = try resolveParagraph(allocator, cps, base);
    defer p.deinit();
    return p.reorderLine(allocator, 0, p.levels.len);
}

// L1: reset to the paragraph level every segment/paragraph separator, and every
// run of whitespace / isolate-formatting (and X9-removed) characters that ends
// at a separator or at the end of the line. Uses the *original* types.
fn applyL1(levels: []Level, original: []const BidiClass, para_level: Level) void {
    var run_start: ?usize = null;
    for (original, 0..) |c, i| {
        if (c == WS or isIsolateInitiator(c) or c == PDI or isRemovedByX9(c)) {
            if (run_start == null) run_start = i;
        } else if (c == S or c == B) {
            if (run_start) |s| {
                for (levels[s..i]) |*lv| lv.* = para_level;
            }
            levels[i] = para_level;
            run_start = null;
        } else {
            run_start = null;
        }
    }
    if (run_start) |s| {
        for (levels[s..]) |*lv| lv.* = para_level;
    }
}

// ============================================================================
// Main entry point
// ============================================================================

/// Run the full algorithm over a single paragraph and return the resolved
/// levels. The input is one paragraph's worth of code points (split on type-B
/// separators with `paragraphs` if you have multiple). The caller owns the
/// returned `Paragraph` and must `deinit` it. Split multi-paragraph text on
/// type-B separators before calling if you need per-paragraph base directions.
///
/// @stable-since: v0.1.0
pub fn resolveParagraph(allocator: std.mem.Allocator, cps: []const CodePoint, base: BaseDirection) !Paragraph {
    const n = cps.len;

    const original = try allocator.alloc(BidiClass, n);
    errdefer allocator.free(original);
    const levels = try allocator.alloc(Level, n);
    errdefer allocator.free(levels);

    for (cps, 0..) |cp, i| original[i] = properties.bidiClass(cp);

    const para_level = switch (base) {
        .ltr => @as(Level, 0),
        .rtl => @as(Level, 1),
        .auto => firstStrongLevel(original, 0, n, 0),
    };

    if (n == 0) {
        return .{ .allocator = allocator, .level = para_level, .levels = levels, .original_classes = original };
    }

    // Everything below is scratch; an arena keeps the bookkeeping simple.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Working classes — mutated by X (overrides), W, N. `original` is preserved.
    const classes = try a.dupe(BidiClass, original);

    // BD9 matching: matching_pdi[i] is the index of the PDI that matches the
    // isolate initiator at i (or n if none); matching_isolate[j] is the matching
    // initiator for the PDI at j (or n).
    const matching_pdi = try a.alloc(usize, n);
    const matching_isolate = try a.alloc(usize, n);
    @memset(matching_pdi, n);
    @memset(matching_isolate, n);
    {
        var stack = try a.alloc(usize, n);
        var sp: usize = 0;
        for (original, 0..) |c, i| {
            if (isIsolateInitiator(c)) {
                stack[sp] = i;
                sp += 1;
            } else if (c == PDI and sp > 0) {
                sp -= 1;
                matching_pdi[stack[sp]] = i;
                matching_isolate[i] = stack[sp];
            }
        }
    }

    computeExplicitLevels(original, classes, levels, matching_pdi, para_level);

    // X10 — isolating run sequences, then W/N/I per sequence.
    const seqs = try isolatingRunSequences(a, original, levels, matching_pdi, matching_isolate, para_level);
    for (seqs) |seq| {
        resolveWeak(seq, classes);
        resolveNeutral(a, seq, cps, original, classes);
        resolveImplicit(seq, classes, levels);
    }

    return .{ .allocator = allocator, .level = para_level, .levels = levels, .original_classes = original };
}

// ============================================================================
// X1–X8: explicit levels and directions
// ============================================================================

const Override = enum { neutral, ltr, rtl };
const StatusEntry = struct { level: Level, override: Override, isolate: bool };

fn computeExplicitLevels(
    original: []const BidiClass,
    classes: []BidiClass,
    levels: []Level,
    matching_pdi: []const usize,
    para_level: Level,
) void {
    const n = original.len;

    var stack: [max_stack]StatusEntry = undefined;
    var sp: usize = 0;
    stack[0] = .{ .level = para_level, .override = .neutral, .isolate = false };
    sp = 1;

    var overflow_isolate: usize = 0;
    var overflow_embedding: usize = 0;
    var valid_isolate: usize = 0;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const c = original[i];
        const top = &stack[sp - 1];
        switch (c) {
            RLE, LRE, RLO, LRO => {
                // X2–X5. The formatting character itself is removed (X9): keep
                // it at the current level and mark it BN.
                levels[i] = top.level;
                classes[i] = BN;
                const is_rtl = (c == RLE or c == RLO);
                const new_level = if (is_rtl) nextOddLevel(top.level) else nextEvenLevel(top.level);
                if (new_level <= max_depth and overflow_isolate == 0 and overflow_embedding == 0) {
                    const ovr: Override = switch (c) {
                        RLO => .rtl,
                        LRO => .ltr,
                        else => .neutral,
                    };
                    stack[sp] = .{ .level = new_level, .override = ovr, .isolate = false };
                    sp += 1;
                } else if (overflow_isolate == 0) {
                    overflow_embedding += 1;
                }
            },
            RLI, LRI, FSI => {
                // X5a/X5b/X5c. The isolate initiator takes the current level
                // (and current override) before pushing.
                levels[i] = top.level;
                if (top.override != .neutral) {
                    classes[i] = if (top.override == .ltr) L else R;
                }
                const is_rtl = switch (c) {
                    RLI => true,
                    LRI => false,
                    else => firstStrongLevel(original, i + 1, matching_pdi[i], 0) == 1, // FSI: X5c
                };
                const new_level = if (is_rtl) nextOddLevel(top.level) else nextEvenLevel(top.level);
                if (new_level <= max_depth and overflow_isolate == 0 and overflow_embedding == 0) {
                    valid_isolate += 1;
                    stack[sp] = .{ .level = new_level, .override = .neutral, .isolate = true };
                    sp += 1;
                } else {
                    overflow_isolate += 1;
                }
            },
            PDI => {
                // X6a.
                if (overflow_isolate > 0) {
                    overflow_isolate -= 1;
                } else if (valid_isolate != 0) {
                    overflow_embedding = 0;
                    while (!stack[sp - 1].isolate) sp -= 1;
                    sp -= 1;
                    valid_isolate -= 1;
                }
                const new_top = &stack[sp - 1];
                levels[i] = new_top.level;
                if (new_top.override != .neutral) {
                    classes[i] = if (new_top.override == .ltr) L else R;
                }
            },
            PDF => {
                // X7. Removed by X9.
                levels[i] = top.level;
                classes[i] = BN;
                if (overflow_isolate > 0) {
                    // do nothing
                } else if (overflow_embedding > 0) {
                    overflow_embedding -= 1;
                } else if (!top.isolate and sp >= 2) {
                    sp -= 1;
                }
            },
            B => {
                // X8. A paragraph separator terminates all embeddings; it takes
                // the paragraph level. Reset the stack so any trailing text is
                // back at the base.
                levels[i] = para_level;
                sp = 1;
                stack[0] = .{ .level = para_level, .override = .neutral, .isolate = false };
                overflow_isolate = 0;
                overflow_embedding = 0;
                valid_isolate = 0;
            },
            BN => {
                // Already removed; keep its level for completeness.
                levels[i] = top.level;
            },
            else => {
                // X6: ordinary characters.
                levels[i] = top.level;
                if (top.override == .ltr) {
                    classes[i] = L;
                } else if (top.override == .rtl) {
                    classes[i] = R;
                }
            },
        }
    }
}

// ============================================================================
// X10 / BD13: isolating run sequences
// ============================================================================

const Sequence = struct {
    indices: []const usize,
    sos: BidiClass,
    eos: BidiClass,
    level: Level,
};

fn isolatingRunSequences(
    a: std.mem.Allocator,
    original: []const BidiClass,
    levels: []const Level,
    matching_pdi: []const usize,
    matching_isolate: []const usize,
    para_level: Level,
) ![]Sequence {
    const n = original.len;

    // The stream of indices not removed by X9, in logical order.
    var stream = try std.ArrayList(usize).initCapacity(a, n);
    for (original, 0..) |c, i| {
        if (!isRemovedByX9(c)) stream.appendAssumeCapacity(i);
    }

    // Level runs (BD7): maximal stream slices of equal level. Record, for each
    // run, the stream position of its first/last entry, and a map from the
    // original index of a run's first character to the run id.
    const RunRange = struct { begin: usize, end: usize }; // [begin, end) into stream
    var runs = std.ArrayList(RunRange).empty;
    const run_at_first = try a.alloc(usize, n); // original index -> run id, else n
    @memset(run_at_first, n);
    {
        var begin: usize = 0;
        while (begin < stream.items.len) {
            const lvl = levels[stream.items[begin]];
            var end = begin + 1;
            while (end < stream.items.len and levels[stream.items[end]] == lvl) end += 1;
            run_at_first[stream.items[begin]] = runs.items.len;
            try runs.append(a, .{ .begin = begin, .end = end });
            begin = end;
        }
    }

    // stream position of each original index (for sos/eos neighbours).
    const stream_pos = try a.alloc(usize, n);
    @memset(stream_pos, n);
    for (stream.items, 0..) |orig_i, pos| stream_pos[orig_i] = pos;

    var sequences = std.ArrayList(Sequence).empty;

    for (runs.items) |run| {
        const first_orig = stream.items[run.begin];
        // BD13: a run starts a sequence unless its first character is a PDI that
        // matches an isolate initiator (i.e. it continues a previous run).
        const continues = (original[first_orig] == PDI and matching_isolate[first_orig] != n);
        if (continues) continue;

        var indices = std.ArrayList(usize).empty;
        var cur = run;
        while (true) {
            for (stream.items[cur.begin..cur.end]) |orig_i| try indices.append(a, orig_i);
            const last_orig = stream.items[cur.end - 1];
            if (isIsolateInitiator(original[last_orig]) and matching_pdi[last_orig] != n) {
                const next_run_id = run_at_first[matching_pdi[last_orig]];
                if (next_run_id != n) {
                    cur = runs.items[next_run_id];
                    continue;
                }
            }
            break;
        }

        const seq_level = levels[indices.items[0]];

        // sos: compare the sequence level with the previous non-removed
        // character's level (or the paragraph level at the boundary).
        const first_pos = stream_pos[indices.items[0]];
        const prev_level: Level = if (first_pos == 0) para_level else levels[stream.items[first_pos - 1]];
        const sos: BidiClass = if (@max(seq_level, prev_level) & 1 == 1) R else L;

        // eos: if the sequence ends with an unmatched isolate initiator the
        // boundary is the paragraph level; otherwise the next non-removed char.
        const last = indices.items[indices.items.len - 1];
        var succ_level: Level = undefined;
        if (isIsolateInitiator(original[last]) and matching_pdi[last] == n) {
            succ_level = para_level;
        } else {
            const last_pos = stream_pos[last];
            succ_level = if (last_pos + 1 >= stream.items.len) para_level else levels[stream.items[last_pos + 1]];
        }
        const eos: BidiClass = if (@max(seq_level, succ_level) & 1 == 1) R else L;

        try sequences.append(a, .{
            .indices = indices.items,
            .sos = sos,
            .eos = eos,
            .level = seq_level,
        });
    }

    return sequences.items;
}

// ============================================================================
// W1–W7: weak types
// ============================================================================

fn resolveWeak(seq: Sequence, classes: []BidiClass) void {
    const idx = seq.indices;

    // W1: NSM takes the type of the previous character; ON after an isolate
    // initiator or PDI; sos at the start.
    {
        var prev = seq.sos;
        for (idx) |i| {
            if (classes[i] == NSM) {
                classes[i] = if (isIsolateInitiator(prev) or prev == PDI) ON else prev;
            }
            prev = classes[i];
        }
    }

    // W2: EN after an AL (looking back to the last strong) becomes AN.
    {
        var strong = seq.sos;
        for (idx) |i| {
            switch (classes[i]) {
                R, L, AL => strong = classes[i],
                EN => if (strong == AL) {
                    classes[i] = AN;
                },
                else => {},
            }
        }
    }

    // W3: AL -> R.
    for (idx) |i| {
        if (classes[i] == AL) classes[i] = R;
    }

    // W4: a single ES between two EN -> EN; a single CS between two same-type
    // numbers -> that type.
    if (idx.len >= 3) {
        var k: usize = 1;
        while (k + 1 < idx.len) : (k += 1) {
            const c = classes[idx[k]];
            const p = classes[idx[k - 1]];
            const nx = classes[idx[k + 1]];
            if (c == ES and p == EN and nx == EN) {
                classes[idx[k]] = EN;
            } else if (c == CS and ((p == EN and nx == EN) or (p == AN and nx == AN))) {
                classes[idx[k]] = p;
            }
        }
    }

    // W5: a run of ET adjacent to EN -> EN.
    {
        var k: usize = 0;
        while (k < idx.len) {
            if (classes[idx[k]] == ET) {
                var j = k;
                while (j < idx.len and classes[idx[j]] == ET) j += 1;
                const before = k > 0 and classes[idx[k - 1]] == EN;
                const after = j < idx.len and classes[idx[j]] == EN;
                if (before or after) {
                    for (idx[k..j]) |i| classes[i] = EN;
                }
                k = j;
            } else {
                k += 1;
            }
        }
    }

    // W6: any remaining ES/ET/CS -> ON.
    for (idx) |i| {
        switch (classes[i]) {
            ES, ET, CS => classes[i] = ON,
            else => {},
        }
    }

    // W7: EN after an L (looking back to the last strong) becomes L.
    {
        var strong = seq.sos;
        for (idx) |i| {
            switch (classes[i]) {
                L, R => strong = classes[i],
                EN => if (strong == L) {
                    classes[i] = L;
                },
                else => {},
            }
        }
    }
}

// ============================================================================
// N0–N2: neutral and isolate formatting types
// ============================================================================

// Strong direction for N rules: L stays L; R, EN, AN count as R.
fn neutralStrongDir(c: BidiClass) ?BidiClass {
    return switch (c) {
        L => L,
        R, EN, AN => R,
        else => null,
    };
}

fn canonicalBracket(cp: CodePoint) CodePoint {
    return switch (cp) {
        0x3008 => 0x2329,
        0x3009 => 0x232A,
        else => cp,
    };
}

fn resolveNeutral(
    a: std.mem.Allocator,
    seq: Sequence,
    cps: []const CodePoint,
    original: []const BidiClass,
    classes: []BidiClass,
) void {
    const idx = seq.indices;
    const e = dirFromLevel(seq.level); // embedding direction

    resolveBrackets(a, seq, cps, original, classes) catch {
        // BD16 bounds its own work (63-deep stack); allocation failure for the
        // tiny pair list is the only error path and simply skips N0, which is a
        // safe (if slightly less accurate) fallback.
    };

    // N1: a run of NIs bounded by the same strong direction takes it. sos/eos
    // stand in at the sequence boundaries; EN/AN count as R.
    {
        var k: usize = 0;
        while (k < idx.len) {
            if (isNeutralOrIsolate(classes[idx[k]])) {
                var j = k;
                while (j < idx.len and isNeutralOrIsolate(classes[idx[j]])) j += 1;
                const left: BidiClass = if (k == 0) seq.sos else (neutralStrongDir(classes[idx[k - 1]]) orelse seq.sos);
                const right: BidiClass = if (j == idx.len) seq.eos else (neutralStrongDir(classes[idx[j]]) orelse seq.eos);
                if (left == right) {
                    for (idx[k..j]) |i| classes[i] = left;
                }
                k = j;
            } else {
                k += 1;
            }
        }
    }

    // N2: anything still neutral takes the embedding direction.
    for (idx) |i| {
        if (isNeutralOrIsolate(classes[i])) classes[i] = e;
    }
}

const BracketPair = struct { open: usize, close: usize }; // positions within seq.indices

fn resolveBrackets(
    a: std.mem.Allocator,
    seq: Sequence,
    cps: []const CodePoint,
    original: []const BidiClass,
    classes: []BidiClass,
) !void {
    const idx = seq.indices;
    const e = dirFromLevel(seq.level);
    const o = if (e == L) R else L;

    // BD16: pair up brackets with a 63-deep stack.
    const StackEntry = struct { expected_close: CodePoint, pos: usize };
    var bracket_stack: [63]StackEntry = undefined;
    var bsp: usize = 0;

    var pairs = std.ArrayList(BracketPair).empty;

    for (idx, 0..) |orig_i, k| {
        if (classes[orig_i] != ON) continue;
        const cp = cps[orig_i];
        switch (generated_brackets.bidiPairedBracketType(cp)) {
            .open => {
                if (bsp == 63) break; // BD16: stack overflow stops the algorithm
                const close = generated_brackets.bidiPairedBracket(cp) orelse continue;
                bracket_stack[bsp] = .{ .expected_close = canonicalBracket(close), .pos = k };
                bsp += 1;
            },
            .close => {
                const cc = canonicalBracket(cp);
                var s = bsp;
                while (s > 0) {
                    s -= 1;
                    if (bracket_stack[s].expected_close == cc) {
                        try pairs.append(a, .{ .open = bracket_stack[s].pos, .close = k });
                        bsp = s; // pop the match and everything above it
                        break;
                    }
                }
            },
            .none => {},
        }
    }

    // Pairs are produced in closing order; N0 wants opening (logical) order.
    std.mem.sort(BracketPair, pairs.items, {}, struct {
        fn lt(_: void, x: BracketPair, y: BracketPair) bool {
            return x.open < y.open;
        }
    }.lt);

    // N0: resolve each pair.
    for (pairs.items) |pair| {
        var found_e = false;
        var found_o = false;
        var k = pair.open + 1;
        while (k < pair.close) : (k += 1) {
            if (neutralStrongDir(classes[idx[k]])) |d| {
                if (d == e) {
                    found_e = true;
                    break;
                }
                found_o = true;
            }
        }

        var resolved: ?BidiClass = null;
        if (found_e) {
            resolved = e;
        } else if (found_o) {
            // Look at the strong context preceding the opening bracket.
            var ctx: BidiClass = seq.sos;
            var m = pair.open;
            while (m > 0) {
                m -= 1;
                if (neutralStrongDir(classes[idx[m]])) |d| {
                    ctx = d;
                    break;
                }
            }
            resolved = if (ctx == o) o else e;
        }

        if (resolved) |dir| {
            setBracket(idx, original, classes, pair.open, dir);
            setBracket(idx, original, classes, pair.close, dir);
        }
    }
}

// Set a resolved bracket to `dir`, and carry that into any character whose
// original type was NSM that immediately follows it (N0's note about combining
// marks on brackets — tested against the original, pre-W1 classes).
fn setBracket(idx: []const usize, original: []const BidiClass, classes: []BidiClass, pos: usize, dir: BidiClass) void {
    classes[idx[pos]] = dir;
    var k = pos + 1;
    while (k < idx.len and original[idx[k]] == NSM) : (k += 1) {
        classes[idx[k]] = dir;
    }
}

// ============================================================================
// I1–I2: implicit levels
// ============================================================================

fn resolveImplicit(seq: Sequence, classes: []const BidiClass, levels: []Level) void {
    for (seq.indices) |i| {
        const c = classes[i];
        if (levels[i] & 1 == 0) {
            // I1 (even level)
            switch (c) {
                R => levels[i] += 1,
                AN, EN => levels[i] += 2,
                else => {},
            }
        } else {
            // I2 (odd level)
            switch (c) {
                L, EN, AN => levels[i] += 1,
                else => {},
            }
        }
    }
}

// ============================================================================
// Tests
// ============================================================================
//
// Code points used below:
//   L   : 'a','b','c'      R  : U+05D0..U+05D2 (Hebrew)   AL : U+0627 (Arabic)
//   EN  : '0'..'9'         AN : U+0660 (Arabic-Indic digit)
//   NSM : U+0301 (combining acute)
//   ON  : '(' ')' '&'
//   Formatting: LRE U+202A, RLE U+202B, PDF U+202C, LRO U+202D, RLO U+202E,
//               LRI U+2066, RLI U+2067, FSI U+2068, PDI U+2069

const testing = std.testing;

const hebrew_alef: CodePoint = 0x05D0;
const hebrew_bet: CodePoint = 0x05D1;
const hebrew_gimel: CodePoint = 0x05D2;
const arabic_alef: CodePoint = 0x0627;
const arabic_digit: CodePoint = 0x0660;
const nsm_acute: CodePoint = 0x0301;
const cp_lre: CodePoint = 0x202A;
const cp_rle: CodePoint = 0x202B;
const cp_pdf: CodePoint = 0x202C;
const cp_rlo: CodePoint = 0x202E;
const cp_lri: CodePoint = 0x2066;
const cp_pdi: CodePoint = 0x2069;

test "paragraphLevel: explicit base directions and first-strong detection" {
    try testing.expectEqual(@as(Level, 0), paragraphLevel(&.{ 'a', 'b' }, .ltr));
    try testing.expectEqual(@as(Level, 1), paragraphLevel(&.{ 'a', 'b' }, .rtl));
    try testing.expectEqual(@as(Level, 0), paragraphLevel(&.{ 'a', hebrew_alef }, .auto));
    try testing.expectEqual(@as(Level, 1), paragraphLevel(&.{ hebrew_alef, 'a' }, .auto));
    try testing.expectEqual(@as(Level, 1), paragraphLevel(&.{ arabic_alef, 'a' }, .auto)); // AL counts as RTL
    // No strong characters -> default LTR (P3).
    try testing.expectEqual(@as(Level, 0), paragraphLevel(&.{ '1', '2', ' ' }, .auto));
    try testing.expectEqual(@as(Level, 0), paragraphLevel(&[_]CodePoint{}, .auto));
}

test "paragraphLevel: P2 skips over isolated spans" {
    // The RTL inside the isolate must not set the paragraph direction; the first
    // strong outside is the LTR 'a'.
    try testing.expectEqual(@as(Level, 0), paragraphLevel(&.{ cp_lri, hebrew_alef, cp_pdi, 'a' }, .auto));
    // Same text without the isolate is detected as RTL.
    try testing.expectEqual(@as(Level, 1), paragraphLevel(&.{ hebrew_alef, 'a' }, .auto));
}

test "resolveParagraph: pure LTR" {
    var p = try resolveParagraph(testing.allocator, &.{ 'a', 'b', 'c' }, .auto);
    defer p.deinit();
    try testing.expectEqual(@as(Level, 0), p.level);
    try testing.expectEqualSlices(Level, &.{ 0, 0, 0 }, p.levels);
}

test "resolveParagraph: pure RTL" {
    var p = try resolveParagraph(testing.allocator, &.{ hebrew_alef, hebrew_bet, hebrew_gimel }, .auto);
    defer p.deinit();
    try testing.expectEqual(@as(Level, 1), p.level);
    try testing.expectEqualSlices(Level, &.{ 1, 1, 1 }, p.levels);
}

test "resolveParagraph + reorderVisual: LTR paragraph with a trailing RTL run" {
    const cps = &.{ 'a', 'b', 'c', ' ', hebrew_alef, hebrew_bet, hebrew_gimel };
    var p = try resolveParagraph(testing.allocator, cps, .ltr);
    defer p.deinit();
    try testing.expectEqualSlices(Level, &.{ 0, 0, 0, 0, 1, 1, 1 }, p.levels);

    const order = try reorderVisual(testing.allocator, p.levels);
    defer testing.allocator.free(order);
    try testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3, 6, 5, 4 }, order);
}

test "resolveParagraph + reorderLine: RTL paragraph with an embedded LTR word" {
    const cps = &.{ hebrew_alef, ' ', 'a', 'b' };
    var p = try resolveParagraph(testing.allocator, cps, .auto);
    defer p.deinit();
    try testing.expectEqual(@as(Level, 1), p.level);
    try testing.expectEqualSlices(Level, &.{ 1, 1, 2, 2 }, p.levels);

    const order = try p.reorderLine(testing.allocator, 0, p.levels.len);
    defer testing.allocator.free(order);
    try testing.expectEqualSlices(usize, &.{ 2, 3, 1, 0 }, order);
}

test "weak rules: W7 turns EN after L into L" {
    var p = try resolveParagraph(testing.allocator, &.{ 'a', '1' }, .ltr);
    defer p.deinit();
    try testing.expectEqualSlices(Level, &.{ 0, 0 }, p.levels);
}

test "weak rules: W2/W3 — EN after AL becomes AN" {
    // AL then EN; AL detects RTL paragraph, W2 changes EN->AN, W3 changes AL->R.
    var p = try resolveParagraph(testing.allocator, &.{ arabic_alef, '1' }, .auto);
    defer p.deinit();
    try testing.expectEqual(@as(Level, 1), p.level);
    try testing.expectEqualSlices(Level, &.{ 1, 2 }, p.levels); // R at 1, AN at 2
}

test "neutral rules: N1 — neutral between equal strong takes that direction" {
    var p = try resolveParagraph(testing.allocator, &.{ 'a', '&', 'b' }, .ltr);
    defer p.deinit();
    try testing.expectEqualSlices(Level, &.{ 0, 0, 0 }, p.levels);
}

test "neutral rules: N0 — brackets enclosing matching strong take it" {
    // ( ) around a Hebrew letter inside an RTL paragraph: embedding direction R.
    var p = try resolveParagraph(testing.allocator, &.{ hebrew_alef, '(', hebrew_bet, ')' }, .auto);
    defer p.deinit();
    try testing.expectEqualSlices(Level, &.{ 1, 1, 1, 1 }, p.levels);
}

test "neutral rules: N0 — brackets around opposite strong fall back to context" {
    // RTL paragraph, brackets around an LTR letter. The strong inside is opposite
    // the embedding direction, and the context before the bracket is R, so the
    // brackets resolve to the embedding direction R.
    var p = try resolveParagraph(testing.allocator, &.{ hebrew_alef, '(', 'a', ')' }, .auto);
    defer p.deinit();
    try testing.expectEqualSlices(Level, &.{ 1, 1, 2, 1 }, p.levels);
}

test "explicit overrides: RLO forces L letters to R" {
    const cps = &.{ cp_rlo, 'a', 'b', cp_pdf };
    var p = try resolveParagraph(testing.allocator, cps, .ltr);
    defer p.deinit();
    try testing.expectEqualSlices(Level, &.{ 0, 1, 1, 1 }, p.levels);
}

test "reorderVisual: nested level reversal" {
    {
        const order = try reorderVisual(testing.allocator, &.{ 0, 1, 1, 0 });
        defer testing.allocator.free(order);
        try testing.expectEqualSlices(usize, &.{ 0, 2, 1, 3 }, order);
    }
    {
        const order = try reorderVisual(testing.allocator, &.{ 2, 1, 2 });
        defer testing.allocator.free(order);
        try testing.expectEqualSlices(usize, &.{ 2, 1, 0 }, order);
    }
    {
        // No odd levels: identity.
        const order = try reorderVisual(testing.allocator, &.{ 0, 0, 2, 0 });
        defer testing.allocator.free(order);
        try testing.expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, order);
    }
}

test "L1: trailing whitespace inside an embedding resets to the paragraph level" {
    // 'a' RLE <hebrew> ' ' PDF — the space sits at level 1 after resolution, but
    // L1 must pull the trailing whitespace (and the removed PDF) back to level 0.
    const cps = &.{ 'a', cp_rle, hebrew_alef, ' ', cp_pdf };
    var p = try resolveParagraph(testing.allocator, cps, .ltr);
    defer p.deinit();
    try testing.expectEqual(@as(Level, 1), p.levels[3]); // space resolved to the embedding

    const line = try p.lineLevels(testing.allocator, 0, p.levels.len);
    defer testing.allocator.free(line);
    try testing.expectEqual(@as(Level, 0), line[3]); // ...and reset by L1
}

test "L4 mirror: glyph chosen by resolved level" {
    try testing.expectEqual(@as(CodePoint, ')'), mirror('(', 1));
    try testing.expectEqual(@as(CodePoint, '('), mirror('(', 0));
    try testing.expectEqual(@as(CodePoint, '('), mirror(')', 1));
    try testing.expectEqual(@as(CodePoint, 'a'), mirror('a', 1));
}

test "predicates: class groupings" {
    try testing.expect(isIsolateInitiator(.left_to_right_isolate));
    try testing.expect(isIsolateInitiator(.first_strong_isolate));
    try testing.expect(!isIsolateInitiator(.pop_directional_isolate));
    try testing.expect(isRemovedByX9(.boundary_neutral));
    try testing.expect(isRemovedByX9(.right_to_left_embedding));
    try testing.expect(!isRemovedByX9(.left_to_right));
    try testing.expect(isNeutralOrIsolate(.whitespace));
    try testing.expect(isNeutralOrIsolate(.pop_directional_isolate));
    try testing.expect(!isNeutralOrIsolate(.left_to_right));
    try testing.expect(isStrong(.arabic_letter));
    try testing.expect(!isStrong(.european_number));
}

test "edge: NSM at sequence start resolves to sos" {
    {
        var p = try resolveParagraph(testing.allocator, &.{ nsm_acute, 'a' }, .ltr);
        defer p.deinit();
        try testing.expectEqualSlices(Level, &.{ 0, 0 }, p.levels);
    }
    {
        var p = try resolveParagraph(testing.allocator, &.{ nsm_acute, 'a' }, .rtl);
        defer p.deinit();
        try testing.expectEqualSlices(Level, &.{ 1, 2 }, p.levels); // NSM->R at 1, L at 2
    }
}

test "edge: empty paragraph" {
    var p = try resolveParagraph(testing.allocator, &[_]CodePoint{}, .auto);
    defer p.deinit();
    try testing.expectEqual(@as(usize, 0), p.levels.len);
    try testing.expectEqual(@as(Level, 0), p.level);

    const order = try reorderVisual(testing.allocator, p.levels);
    defer testing.allocator.free(order);
    try testing.expectEqual(@as(usize, 0), order.len);
}

test "edge: all-neutral text takes the embedding direction" {
    {
        var p = try resolveParagraph(testing.allocator, &.{ ' ', '&', ' ' }, .ltr);
        defer p.deinit();
        try testing.expectEqualSlices(Level, &.{ 0, 0, 0 }, p.levels);
    }
    {
        var p = try resolveParagraph(testing.allocator, &.{ ' ', '&', ' ' }, .rtl);
        defer p.deinit();
        try testing.expectEqualSlices(Level, &.{ 1, 1, 1 }, p.levels);
    }
}

test "unmatched PDI and unmatched isolate initiator are harmless" {
    const cps = &.{ cp_pdi, 'a', cp_lri, hebrew_alef };
    var p = try resolveParagraph(testing.allocator, cps, .auto);
    defer p.deinit();
    try testing.expectEqual(cps.len, p.levels.len);
    for (p.levels) |lv| try testing.expect(lv <= max_depth + 2);
}

test "embedding nesting past max_depth overflows without trapping" {
    var cps: [401]CodePoint = undefined;
    for (0..200) |i| cps[i] = cp_rle;
    cps[200] = 'a';
    for (201..401) |i| cps[i] = cp_pdf;

    var p = try resolveParagraph(testing.allocator, &cps, .ltr);
    defer p.deinit();
    // Only 63 RLE pushes are valid before the level would exceed 125; the 'a'
    // ends up at level 125 (odd), and I2 lifts the L to 126.
    try testing.expectEqual(@as(Level, 126), p.levels[200]);
    for (p.levels) |lv| try testing.expect(lv <= max_depth + 2);
}

test "bracket stack overflow (>63 nested) does not trap" {
    var cps: [128]CodePoint = undefined;
    for (0..64) |i| cps[i] = '(';
    for (64..128) |i| cps[i] = ')';

    var p = try resolveParagraph(testing.allocator, &cps, .ltr);
    defer p.deinit();
    try testing.expectEqual(@as(usize, 128), p.levels.len);
    for (p.levels) |lv| try testing.expect(lv <= max_depth + 2);
}

test "deeply alternating isolates round-trip" {
    var cps: [200]CodePoint = undefined;
    var i: usize = 0;
    while (i < 100) : (i += 1) cps[i] = cp_lri;
    while (i < 200) : (i += 1) cps[i] = cp_pdi;

    var p = try resolveParagraph(testing.allocator, &cps, .auto);
    defer p.deinit();
    try testing.expectEqual(@as(usize, 200), p.levels.len);
    for (p.levels) |lv| try testing.expect(lv <= max_depth + 2);
}

test "reorderParagraph: one-shot visual order of an RTL paragraph" {
    const cps = &.{ hebrew_alef, ' ', 'a', 'b' };
    const order = try reorderParagraph(testing.allocator, cps, .auto);
    defer testing.allocator.free(order);
    try testing.expectEqualSlices(usize, &.{ 2, 3, 1, 0 }, order);
}

test {
    testing.refAllDecls(@This());
}
