//! Unicode case conversion and case-insensitive comparison.
//!
//! Provides simple (single-codepoint) and full (potentially multi-codepoint)
//! case mapping — upper, lower, and title — plus case folding and `equalFold`
//! comparison helpers operating on UTF-8 bytes or decoded codepoints.
//!
//! - Simple variants (`toUpperCase`, `caseFoldSimple`, …) map one codepoint to
//!   exactly one codepoint and never allocate or expand.
//! - Full variants (`toUpperCaseFull`, `caseFoldFull`, …) honor expansions
//!   such as U+00DF -> "ss" and return a `CaseMappingResult` whose capacity is
//!   sized at comptime from the relevant table — prefer these when correct
//!   Unicode case handling matters.
//! - Full case mapping is locale- and context-sensitive: pass the appropriate
//!   `SpecialCaseLocale` (e.g. `.tr` for Turkish) and `SpecialCaseCondition`
//!   (e.g. `.final_sigma`) to obtain conformant results.

const std = @import("std");
const encoding = @import("encoding");
const utils = @import("utils");
const types = @import("../types.zig");
const unicode_data = @import("../generated/unicode_data.zig");

/// Case-folding tables and lookup helpers (simple and full, default/Turkic).
pub const case_folding = @import("case_folding.zig");
/// Locale- and context-sensitive special-casing tables and lookup helpers.
pub const special_casing = @import("special_casing.zig");

const CodePoint = encoding.CodePoint;

/// Selects simple vs full case folding behavior.
pub const CaseFoldingMode = types.CaseFoldingMode;
/// Selects the case-folding locale: `.default` or `.turkic`.
pub const CaseFoldingLocale = types.CaseFoldingLocale;
/// Locale tag for special casing (`.none`, `.tr`, `.az`, `.lt`).
pub const SpecialCaseLocale = special_casing.Locale;
/// Contextual condition that gates a special-casing mapping (e.g. `.final_sigma`).
pub const SpecialCaseCondition = special_casing.Condition;
/// A special-casing table entry holding the lower/upper/title expansions.
pub const SpecialCaseMapping = special_casing.Mapping;

const CaseSlot = enum { lower, upper, title };

fn maxFoldLen(comptime entries: []const case_folding.FoldEntry) usize {
    return comptime blk: {
        @setEvalBranchQuota(200000);
        var m: usize = 1;
        for (entries) |e| {
            if (e.to.len > m) m = e.to.len;
        }
        break :blk m;
    };
}

fn maxSpecialLen(
    comptime selector: CaseSlot,
    comptime locale: special_casing.Locale,
    comptime condition: special_casing.Condition,
) usize {
    return comptime blk: {
        @setEvalBranchQuota(200000);
        var m: usize = 1;
        for (special_casing.mappings_table) |entry| {
            for (entry.mappings) |mapping| {
                if (mapping.locale != locale) continue;
                if (mapping.condition != condition) continue;
                const arr = switch (selector) {
                    .lower => mapping.lower,
                    .upper => mapping.upper,
                    .title => mapping.title,
                };
                if (arr.len > m) m = arr.len;
            }
        }
        break :blk m;
    };
}

/// Returns the worst-case codepoint count produced by full case folding for
/// `locale`. Use this to size a `CaseMappingResult` buffer at comptime.
///
/// @stable-since: v0.1.0
pub fn caseFoldFullCap(comptime locale: CaseFoldingLocale) usize {
    return switch (locale) {
        .default => maxFoldLen(&case_folding.common_full_table),
        .turkic => @max(maxFoldLen(&case_folding.turkic_full_table), maxFoldLen(&case_folding.common_full_table)),
    };
}

/// Returns the worst-case codepoint count produced by full case mapping for
/// the given `selector` (lower/upper/title), `locale`, and `condition`. Always
/// at least 1 (the simple-mapping fallback). Use it to size result buffers.
///
/// @stable-since: v0.1.0
pub fn fullCaseMapCap(
    comptime selector: CaseSlot,
    comptime locale: special_casing.Locale,
    comptime condition: special_casing.Condition,
) usize {
    const simple_minimum: usize = 1;
    return @max(simple_minimum, maxSpecialLen(selector, locale, condition));
}

/// Owned buffer holding a case-mapping result. `cap` is computed at comptime
/// from the largest entry in the source table, so the struct is exactly large
/// enough — no over-allocation, no fallback pointers.
pub fn CaseMappingResult(comptime cap: usize) type {
    return struct {
        const Self = @This();

        buf: [cap]CodePoint,
        len: u8,

        /// Returns the populated prefix of the buffer (`buf[0..len]`).
        /// @stable-since: v0.1.0
        pub fn slice(self: *const Self) []const CodePoint {
            return self.buf[0..self.len];
        }
    };
}

fn writeResult(comptime cap: usize, mapped: []const CodePoint) CaseMappingResult(cap) {
    var result: CaseMappingResult(cap) = .{ .buf = undefined, .len = @intCast(mapped.len) };
    for (mapped, 0..) |cp, i| result.buf[i] = cp;
    return result;
}

fn singletonResult(comptime cap: usize, code_point: CodePoint) CaseMappingResult(cap) {
    var result: CaseMappingResult(cap) = .{ .buf = undefined, .len = 1 };
    result.buf[0] = code_point;
    return result;
}

fn simpleCaseMap(table: []const unicode_data.CaseMappingRangeEntry, code_point: CodePoint) CodePoint {
    const range = utils.searchRange(
        unicode_data.CaseMappingRangeEntry,
        CodePoint,
        "start",
        "end",
        table,
        code_point,
    ) orelse return code_point;
    return @intCast(@as(i32, @intCast(code_point)) + range.delta);
}

/// Simple uppercase mapping: returns the single-codepoint uppercase form of
/// `code_point`, or `code_point` unchanged if it has no mapping. Does not
/// handle expansions (e.g. U+00DF stays U+00DF); use `toUpperCaseFull` for those.
///
/// @stable-since: v0.1.0
pub fn toUpperCase(code_point: CodePoint) CodePoint {
    return simpleCaseMap(&unicode_data.uppercase_range_mapping_table, code_point);
}

/// Simple lowercase mapping: returns the single-codepoint lowercase form of
/// `code_point`, or `code_point` unchanged if it has no mapping. For
/// context-sensitive or expanding mappings use `toLowerCaseFull`.
///
/// @stable-since: v0.1.0
pub fn toLowerCase(code_point: CodePoint) CodePoint {
    return simpleCaseMap(&unicode_data.lowercase_range_mapping_table, code_point);
}

/// Simple titlecase mapping: returns the single-codepoint titlecase form of
/// `code_point`, or `code_point` unchanged if it has no mapping. For expanding
/// mappings use `toTitleCaseFull`.
///
/// @stable-since: v0.1.0
pub fn toTitleCase(code_point: CodePoint) CodePoint {
    return simpleCaseMap(&unicode_data.titlecase_range_mapping_table, code_point);
}

/// Simple (single-codepoint) case folding for `code_point` under default rules.
/// Returns `code_point` unchanged when it has no folding. Prefer `caseFoldFull`
/// when expansions such as U+00DF -> "ss" must be honored.
///
/// @stable-since: v0.1.0
pub fn caseFoldSimple(code_point: CodePoint) CodePoint {
    return case_folding.lookup(.simple, .default, code_point) orelse code_point;
}

/// Simple case folding using Turkic rules (e.g. dotless-i handling).
/// Returns `code_point` unchanged when it has no folding.
///
/// @stable-since: v0.1.0
pub fn caseFoldSimpleTurkic(code_point: CodePoint) CodePoint {
    return case_folding.lookup(.simple, .turkic, code_point) orelse code_point;
}

/// Full case folding for `code_point` under default rules, expanding to multiple
/// codepoints where required (e.g. U+00DF -> "ss"). Returns a singleton result
/// holding `code_point` when it has no folding.
///
/// @stable-since: v0.1.0
pub fn caseFoldFull(code_point: CodePoint) CaseMappingResult(caseFoldFullCap(.default)) {
    const cap = comptime caseFoldFullCap(.default);
    if (case_folding.lookup(.full, .default, code_point)) |mapped| return writeResult(cap, mapped);
    return singletonResult(cap, code_point);
}

/// Full case folding for `code_point` using Turkic rules, expanding to multiple
/// codepoints where required. Returns a singleton result holding `code_point`
/// when it has no folding.
///
/// @stable-since: v0.1.0
pub fn caseFoldFullTurkic(code_point: CodePoint) CaseMappingResult(caseFoldFullCap(.turkic)) {
    const cap = comptime caseFoldFullCap(.turkic);
    if (case_folding.lookup(.full, .turkic, code_point)) |mapped| return writeResult(cap, mapped);
    return singletonResult(cap, code_point);
}

/// Looks up the special-casing mapping for `code_point` under the given
/// `locale` and contextual `condition`, returning `null` when no entry matches.
/// The returned mapping carries the lower/upper/title expansions; callers
/// typically prefer the `toXxxCaseFull` wrappers over calling this directly.
///
/// @stable-since: v0.1.0
pub fn specialCaseMapping(comptime locale: SpecialCaseLocale, comptime condition: SpecialCaseCondition, code_point: CodePoint) ?SpecialCaseMapping {
    return switch (locale) {
        .none => switch (condition) {
            .none => special_casing.lookup(.none, .none, code_point),
            .after_i => special_casing.lookup(.none, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.none, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.none, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.none, .more_above, code_point),
            .final_sigma => special_casing.lookup(.none, .final_sigma, code_point),
            else => null,
        },
        .tr => switch (condition) {
            .none => special_casing.lookup(.tr, .none, code_point),
            .after_i => special_casing.lookup(.tr, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.tr, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.tr, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.tr, .more_above, code_point),
            .final_sigma => special_casing.lookup(.tr, .final_sigma, code_point),
            else => null,
        },
        .az => switch (condition) {
            .none => special_casing.lookup(.az, .none, code_point),
            .after_i => special_casing.lookup(.az, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.az, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.az, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.az, .more_above, code_point),
            .final_sigma => special_casing.lookup(.az, .final_sigma, code_point),
            else => null,
        },
        .lt => switch (condition) {
            .none => special_casing.lookup(.lt, .none, code_point),
            .after_i => special_casing.lookup(.lt, .after_i, code_point),
            .not_before_dot => special_casing.lookup(.lt, .not_before_dot, code_point),
            .after_soft_dotted => special_casing.lookup(.lt, .after_soft_dotted, code_point),
            .more_above => special_casing.lookup(.lt, .more_above, code_point),
            .final_sigma => special_casing.lookup(.lt, .final_sigma, code_point),
            else => null,
        },
        else => null,
    };
}

/// Full lowercase mapping for `code_point` under `locale` and `condition`,
/// honoring multi-codepoint expansions and locale/context rules. Falls back to
/// the simple lowercase mapping when no special-casing entry applies. Prefer
/// this over `toLowerCase` when Unicode-conformant casing is required.
///
/// @stable-since: v0.1.0
pub fn toLowerCaseFull(
    code_point: CodePoint,
    comptime locale: SpecialCaseLocale,
    comptime condition: SpecialCaseCondition,
) CaseMappingResult(fullCaseMapCap(.lower, locale, condition)) {
    const cap = comptime fullCaseMapCap(.lower, locale, condition);
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.lower.len != 0) return writeResult(cap, mapping.lower);
    }
    return singletonResult(cap, toLowerCase(code_point));
}

/// Full uppercase mapping for `code_point` under `locale` and `condition`,
/// honoring multi-codepoint expansions and locale/context rules. Falls back to
/// the simple uppercase mapping when no special-casing entry applies. Prefer
/// this over `toUpperCase` when Unicode-conformant casing is required.
///
/// @stable-since: v0.1.0
pub fn toUpperCaseFull(
    code_point: CodePoint,
    comptime locale: SpecialCaseLocale,
    comptime condition: SpecialCaseCondition,
) CaseMappingResult(fullCaseMapCap(.upper, locale, condition)) {
    const cap = comptime fullCaseMapCap(.upper, locale, condition);
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.upper.len != 0) return writeResult(cap, mapping.upper);
    }
    return singletonResult(cap, toUpperCase(code_point));
}

/// Full titlecase mapping for `code_point` under `locale` and `condition`,
/// honoring multi-codepoint expansions and locale/context rules. Falls back to
/// the simple titlecase mapping when no special-casing entry applies. Prefer
/// this over `toTitleCase` when Unicode-conformant casing is required.
///
/// @stable-since: v0.1.0
pub fn toTitleCaseFull(
    code_point: CodePoint,
    comptime locale: SpecialCaseLocale,
    comptime condition: SpecialCaseCondition,
) CaseMappingResult(fullCaseMapCap(.title, locale, condition)) {
    const cap = comptime fullCaseMapCap(.title, locale, condition);
    if (specialCaseMapping(locale, condition, code_point)) |mapping| {
        if (mapping.title.len != 0) return writeResult(cap, mapping.title);
    }
    return singletonResult(cap, toTitleCase(code_point));
}

/// Folding strategy for the `equalFold*` helpers: `.simple` compares one
/// codepoint to one codepoint; `.full` honors expanding folds (e.g. ß -> "ss").
pub const EqualFoldMode = enum { simple, full };

inline fn asciiFoldLower(byte: u8) u8 {
    return if ('A' <= byte and byte <= 'Z') byte + ('a' - 'A') else byte;
}

/// Compares two ASCII bytes case-insensitively (A-Z folded to a-z). Bytes
/// outside A-Z are compared as-is; non-ASCII bytes are not interpreted.
///
/// @stable-since: v0.1.0
pub inline fn asciiFoldEqual(a: u8, b: u8) bool {
    return asciiFoldLower(a) == asciiFoldLower(b);
}

/// Case-insensitively compares two UTF-8 byte strings via case folding.
/// `mode` selects simple or full folding. The inputs must be valid UTF-8:
/// invalid or truncated sequences surface as an error (e.g.
/// `error.InvalidByteSequence`, `error.IndexOutOfBounds`). Use
/// `equalFoldBytesLossy` to tolerate malformed input instead.
///
/// @stable-since: v0.1.0
pub fn equalFoldBytes(comptime mode: EqualFoldMode, s1: []const u8, s2: []const u8) !bool {
    if (mode == .simple) {
        var s1_i: usize = 0;
        var s2_i: usize = 0;

        while (s1_i < s1.len and s2_i < s2.len) {
            // ASCII fast path: both bytes are ASCII => one codepoint each on this step.
            if (encoding.isAscii(s1[s1_i]) and encoding.isAscii(s2[s2_i])) {
                if (!asciiFoldEqual(s1[s1_i], s2[s2_i])) return false;
                s1_i += 1;
                s2_i += 1;
                continue;
            }

            const s1_decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s1, s1_i);
            const s2_decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s2, s2_i);
            s1_i += s1_decoded.len;
            s2_i += s2_decoded.len;

            if (caseFoldSimple(s1_decoded.code_point) != caseFoldSimple(s2_decoded.code_point)) {
                return false;
            }
        }

        return s1_i == s1.len and s2_i == s2.len;
    }

    // Full mode: a single codepoint can fold to multiple codepoints (e.g. U+00DF -> "ss",
    // U+0149 -> U+02BC U+006E, U+0130 -> U+0069 U+0307). Compare the folded streams
    // codepoint-by-codepoint using a small refill buffer per side.
    const cap = comptime caseFoldFullCap(.default);

    var s1_i: usize = 0;
    var s2_i: usize = 0;
    var buf1: [cap]CodePoint = undefined;
    var buf2: [cap]CodePoint = undefined;
    var buf1_len: usize = 0;
    var buf2_len: usize = 0;
    var buf1_pos: usize = 0;
    var buf2_pos: usize = 0;

    while (true) {
        if (buf1_pos >= buf1_len) {
            if (s1_i >= s1.len) break;
            if (encoding.isAscii(s1[s1_i])) {
                buf1[0] = asciiFoldLower(s1[s1_i]);
                buf1_len = 1;
                s1_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s1, s1_i);
                s1_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf1[i] = cp;
                buf1_len = sl.len;
            }
            buf1_pos = 0;
        }

        if (buf2_pos >= buf2_len) {
            if (s2_i >= s2.len) break;
            if (encoding.isAscii(s2[s2_i])) {
                buf2[0] = asciiFoldLower(s2[s2_i]);
                buf2_len = 1;
                s2_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(s2, s2_i);
                s2_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf2[i] = cp;
                buf2_len = sl.len;
            }
            buf2_pos = 0;
        }

        if (buf1[buf1_pos] != buf2[buf2_pos]) return false;
        buf1_pos += 1;
        buf2_pos += 1;
    }

    return s1_i == s1.len and s2_i == s2.len and buf1_pos == buf1_len and buf2_pos == buf2_len;
}

/// Lossy variant of `equalFoldBytes`: invalid UTF-8 is replaced with U+FFFD
/// and comparison continues rather than erroring. Prefer this when comparing
/// untrusted or possibly malformed input; prefer `equalFoldBytes` when invalid
/// bytes should be treated as a hard error.
///
/// @stable-since: v0.1.0
pub fn equalFoldBytesLossy(comptime mode: EqualFoldMode, s1: []const u8, s2: []const u8) encoding.utf8.UTF8ValidationLossyError!bool {
    if (mode == .simple) {
        var s1_i: usize = 0;
        var s2_i: usize = 0;

        while (s1_i < s1.len and s2_i < s2.len) {
            if (encoding.isAscii(s1[s1_i]) and encoding.isAscii(s2[s2_i])) {
                if (!asciiFoldEqual(s1[s1_i], s2[s2_i])) return false;
                s1_i += 1;
                s2_i += 1;
                continue;
            }

            const s1_decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s1, s1_i);
            const s2_decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s2, s2_i);
            s1_i += s1_decoded.len;
            s2_i += s2_decoded.len;

            if (caseFoldSimple(s1_decoded.code_point) != caseFoldSimple(s2_decoded.code_point)) {
                return false;
            }
        }

        return s1_i == s1.len and s2_i == s2.len;
    }

    const cap = comptime caseFoldFullCap(.default);

    var s1_i: usize = 0;
    var s2_i: usize = 0;
    var buf1: [cap]CodePoint = undefined;
    var buf2: [cap]CodePoint = undefined;
    var buf1_len: usize = 0;
    var buf2_len: usize = 0;
    var buf1_pos: usize = 0;
    var buf2_pos: usize = 0;

    while (true) {
        if (buf1_pos >= buf1_len) {
            if (s1_i >= s1.len) break;
            if (encoding.isAscii(s1[s1_i])) {
                buf1[0] = asciiFoldLower(s1[s1_i]);
                buf1_len = 1;
                s1_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s1, s1_i);
                s1_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf1[i] = cp;
                buf1_len = sl.len;
            }
            buf1_pos = 0;
        }

        if (buf2_pos >= buf2_len) {
            if (s2_i >= s2.len) break;
            if (encoding.isAscii(s2[s2_i])) {
                buf2[0] = asciiFoldLower(s2[s2_i]);
                buf2_len = 1;
                s2_i += 1;
            } else {
                const decoded = try encoding.utf8.validateAndDecodeCodePointBytesLossy(s2, s2_i);
                s2_i += decoded.len;
                const folded = caseFoldFull(decoded.code_point);
                const sl = folded.slice();
                for (sl, 0..) |cp, i| buf2[i] = cp;
                buf2_len = sl.len;
            }
            buf2_pos = 0;
        }

        if (buf1[buf1_pos] != buf2[buf2_pos]) return false;
        buf1_pos += 1;
        buf2_pos += 1;
    }

    return s1_i == s1.len and s2_i == s2.len and buf1_pos == buf1_len and buf2_pos == buf2_len;
}

/// Case-insensitively compares two already-decoded codepoint slices via case
/// folding. `mode` selects simple or full folding. No validation is performed —
/// callers supply codepoints directly, so this cannot fail.
///
/// @stable-since: v0.1.0
pub fn equalFoldCodePoints(comptime mode: EqualFoldMode, s1: []const CodePoint, s2: []const CodePoint) bool {
    if (mode == .simple) {
        if (s1.len != s2.len) return false;
        for (s1, s2) |a, b| {
            if (caseFoldSimple(a) != caseFoldSimple(b)) return false;
        }
        return true;
    }

    const cap = comptime caseFoldFullCap(.default);

    var s1_i: usize = 0;
    var s2_i: usize = 0;
    var buf1: [cap]CodePoint = undefined;
    var buf2: [cap]CodePoint = undefined;
    var buf1_len: usize = 0;
    var buf2_len: usize = 0;
    var buf1_pos: usize = 0;
    var buf2_pos: usize = 0;

    while (true) {
        if (buf1_pos >= buf1_len) {
            if (s1_i >= s1.len) break;
            const folded = caseFoldFull(s1[s1_i]);
            s1_i += 1;
            const sl = folded.slice();
            for (sl, 0..) |cp, j| buf1[j] = cp;
            buf1_len = sl.len;
            buf1_pos = 0;
        }

        if (buf2_pos >= buf2_len) {
            if (s2_i >= s2.len) break;
            const folded = caseFoldFull(s2[s2_i]);
            s2_i += 1;
            const sl = folded.slice();
            for (sl, 0..) |cp, j| buf2[j] = cp;
            buf2_len = sl.len;
            buf2_pos = 0;
        }

        if (buf1[buf1_pos] != buf2[buf2_pos]) return false;
        buf1_pos += 1;
        buf2_pos += 1;
    }

    return s1_i == s1.len and s2_i == s2.len and buf1_pos == buf1_len and buf2_pos == buf2_len;
}

// ============================================================================
// String-level case mapping
//
// The functions above map a single codepoint. The helpers below apply a mapping
// across a whole string, in the project's variant families: `…Buffer` writes
// into caller memory, `…Alloc` returns an owned slice, `…Writer` streams UTF-8
// to a `*std.Io.Writer`, and `…Len` reports the exact output size.
//
// `…Simple` variants use the single-codepoint (1:1) mappings, so they never
// expand and never apply locale/contextual special-casing — fast and
// allocation-light, but not fully Unicode-conformant for cased text. `foldFull…`
// honors expanding folds (e.g. ß -> "ss"), making it the right primitive for
// caseless matching. For conformant cased output use the per-codepoint
// `toUpperCaseFull` / `toLowerCaseFull` / `toTitleCaseFull` with the appropriate
// locale and condition.
// ============================================================================

const SimpleMap = fn (CodePoint) CodePoint;

fn simpleMapCodePointsBuffer(comptime map: SimpleMap, code_points: []const CodePoint, out: []CodePoint) error{BufferTooSmall}!usize {
    if (out.len < code_points.len) return error.BufferTooSmall;
    for (code_points, 0..) |cp, i| out[i] = map(cp);
    return code_points.len;
}

fn simpleMapCodePointsAlloc(comptime map: SimpleMap, allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    const out = try allocator.alloc(CodePoint, code_points.len);
    errdefer allocator.free(out);
    for (code_points, 0..) |cp, i| out[i] = map(cp);
    return out;
}

/// Writes the simple uppercase mapping of each codepoint in `code_points` into
/// `out` (1:1, no expansion), returning the count written. Errors with
/// `error.BufferTooSmall` when `out` is shorter than `code_points`. Uses simple
/// mappings only — see `toUpperCaseFull` for conformant, expanding casing.
///
/// @stable-since: v0.2.0
pub fn upperSimpleBuffer(code_points: []const CodePoint, out: []CodePoint) error{BufferTooSmall}!usize {
    return simpleMapCodePointsBuffer(toUpperCase, code_points, out);
}

/// Allocates and returns the simple uppercase mapping of `code_points` (1:1).
/// The caller owns and must free the result.
///
/// @stable-since: v0.2.0
pub fn upperSimpleAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    return simpleMapCodePointsAlloc(toUpperCase, allocator, code_points);
}

/// Writes the simple lowercase mapping of each codepoint in `code_points` into
/// `out` (1:1, no expansion), returning the count written. Errors with
/// `error.BufferTooSmall` when `out` is too short. Uses simple mappings only —
/// see `toLowerCaseFull` for conformant, locale-aware casing.
///
/// @stable-since: v0.2.0
pub fn lowerSimpleBuffer(code_points: []const CodePoint, out: []CodePoint) error{BufferTooSmall}!usize {
    return simpleMapCodePointsBuffer(toLowerCase, code_points, out);
}

/// Allocates and returns the simple lowercase mapping of `code_points` (1:1).
/// The caller owns and must free the result.
///
/// @stable-since: v0.2.0
pub fn lowerSimpleAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    return simpleMapCodePointsAlloc(toLowerCase, allocator, code_points);
}

/// Writes the simple (1:1) default case folding of each codepoint in
/// `code_points` into `out`, returning the count written. Errors with
/// `error.BufferTooSmall` when `out` is too short. Use `foldFullBuffer` when
/// expanding folds (e.g. ß -> "ss") must be honored.
///
/// @stable-since: v0.2.0
pub fn foldSimpleBuffer(code_points: []const CodePoint, out: []CodePoint) error{BufferTooSmall}!usize {
    return simpleMapCodePointsBuffer(caseFoldSimple, code_points, out);
}

/// Allocates and returns the simple (1:1) default case folding of `code_points`.
/// The caller owns and must free the result.
///
/// @stable-since: v0.2.0
pub fn foldSimpleAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    return simpleMapCodePointsAlloc(caseFoldSimple, allocator, code_points);
}

/// Returns the number of codepoints produced by full default case folding of
/// `code_points`, accounting for expansions. Use it to size a `foldFullBuffer`
/// destination.
///
/// @stable-since: v0.2.0
pub fn foldFullLen(code_points: []const CodePoint) usize {
    var n: usize = 0;
    for (code_points) |cp| n += caseFoldFull(cp).len;
    return n;
}

/// Writes the full default case folding of `code_points` into `out`, returning
/// the count written. Expanding folds (e.g. ß -> "ss") are honored. Errors with
/// `error.BufferTooSmall` when `out` cannot hold the result; size it with
/// `foldFullLen`.
///
/// @stable-since: v0.2.0
pub fn foldFullBuffer(code_points: []const CodePoint, out: []CodePoint) error{BufferTooSmall}!usize {
    var o: usize = 0;
    for (code_points) |cp| {
        const folded = caseFoldFull(cp);
        const sl = folded.slice();
        if (o + sl.len > out.len) return error.BufferTooSmall;
        for (sl) |c| {
            out[o] = c;
            o += 1;
        }
    }
    return o;
}

/// Allocates and returns the full default case folding of `code_points`,
/// honoring expansions. The caller owns and must free the result.
///
/// @stable-since: v0.2.0
pub fn foldFullAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    const out = try allocator.alloc(CodePoint, foldFullLen(code_points));
    errdefer allocator.free(out);
    _ = foldFullBuffer(code_points, out) catch unreachable;
    return out;
}

/// Returns the number of codepoints produced by full uppercase mapping of
/// `code_points`, accounting for expansions (e.g. U+00DF -> "SS"). Use it to
/// size an `upperFullBuffer` destination. Uses the default (root) locale, so no
/// Turkic tailoring is applied.
///
/// @stable-since: v0.4.1
pub fn upperFullLen(code_points: []const CodePoint) usize {
    var n: usize = 0;
    for (code_points) |cp| n += toUpperCaseFull(cp, .none, .none).len;
    return n;
}

/// Writes the full uppercase mapping of `code_points` into `out`, returning the
/// count written. Expanding mappings (e.g. U+00DF -> "SS") are honored. Errors
/// with `error.BufferTooSmall` when `out` cannot hold the result; size it with
/// `upperFullLen`. Uses the default (root) locale, so no Turkic tailoring is
/// applied.
///
/// @stable-since: v0.4.1
pub fn upperFullBuffer(code_points: []const CodePoint, out: []CodePoint) error{BufferTooSmall}!usize {
    var o: usize = 0;
    for (code_points) |cp| {
        const mapped = toUpperCaseFull(cp, .none, .none);
        const sl = mapped.slice();
        if (o + sl.len > out.len) return error.BufferTooSmall;
        for (sl) |c| {
            out[o] = c;
            o += 1;
        }
    }
    return o;
}

/// Allocates and returns the full uppercase mapping of `code_points`, honoring
/// expansions. Uses the default (root) locale, so no Turkic tailoring is
/// applied. The caller owns and must free the result.
///
/// @stable-since: v0.4.1
pub fn upperFullAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    const out = try allocator.alloc(CodePoint, upperFullLen(code_points));
    errdefer allocator.free(out);
    _ = upperFullBuffer(code_points, out) catch unreachable;
    return out;
}

/// Returns the number of codepoints produced by full lowercase mapping of
/// `code_points`, accounting for expansions. Use it to size a `lowerFullBuffer`
/// destination. Applies the DEFAULT (context-free) lowercase mapping, so the
/// Greek Final_Sigma context is not applied (a trailing capital U+03A3
/// lowercases to medial U+03C3, not final U+03C2). For Final_Sigma use
/// `titlecaseAlloc` or the per-scalar `toLowerCaseFull` with `.final_sigma`.
///
/// @stable-since: v0.4.1
pub fn lowerFullLen(code_points: []const CodePoint) usize {
    var n: usize = 0;
    for (code_points) |cp| n += toLowerCaseFull(cp, .none, .none).len;
    return n;
}

/// Writes the full lowercase mapping of `code_points` into `out`, returning the
/// count written. Errors with `error.BufferTooSmall` when `out` cannot hold the
/// result; size it with `lowerFullLen`. Applies the DEFAULT (context-free)
/// lowercase mapping, so the Greek Final_Sigma context is not applied (a
/// trailing capital U+03A3 lowercases to medial U+03C3, not final U+03C2). For
/// Final_Sigma use `titlecaseAlloc` or the per-scalar `toLowerCaseFull` with
/// `.final_sigma`.
///
/// @stable-since: v0.4.1
pub fn lowerFullBuffer(code_points: []const CodePoint, out: []CodePoint) error{BufferTooSmall}!usize {
    var o: usize = 0;
    for (code_points) |cp| {
        const mapped = toLowerCaseFull(cp, .none, .none);
        const sl = mapped.slice();
        if (o + sl.len > out.len) return error.BufferTooSmall;
        for (sl) |c| {
            out[o] = c;
            o += 1;
        }
    }
    return o;
}

/// Allocates and returns the full lowercase mapping of `code_points`, honoring
/// expansions. Applies the DEFAULT (context-free) lowercase mapping, so the
/// Greek Final_Sigma context is not applied (a trailing capital U+03A3
/// lowercases to medial U+03C3, not final U+03C2). For Final_Sigma use
/// `titlecaseAlloc` or the per-scalar `toLowerCaseFull` with `.final_sigma`. The
/// caller owns and must free the result.
///
/// @stable-since: v0.4.1
pub fn lowerFullAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    const out = try allocator.alloc(CodePoint, lowerFullLen(code_points));
    errdefer allocator.free(out);
    _ = lowerFullBuffer(code_points, out) catch unreachable;
    return out;
}

const UTF8ValidationError = encoding.utf8.UTF8ValidationError;

fn simpleMapUtf8Len(comptime map: SimpleMap, bytes: []const u8) UTF8ValidationError!usize {
    var i: usize = 0;
    var n: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        n += encoding.utf8.utf8EncodeLen(map(decoded.code_point));
        i += decoded.len;
    }
    return n;
}

fn simpleMapUtf8Alloc(comptime map: SimpleMap, allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{OutOfMemory})![]u8 {
    const len = try simpleMapUtf8Len(map, bytes);
    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);

    var i: usize = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = encoding.utf8.validateAndDecodeCodePointBytes(bytes, i) catch unreachable;
        o += encoding.utf8.encodeCodePointUnchecked(map(decoded.code_point), out[o..]);
        i += decoded.len;
    }
    return out;
}

fn simpleMapUtf8Writer(comptime map: SimpleMap, bytes: []const u8, writer: *std.Io.Writer) (UTF8ValidationError || std.Io.Writer.Error)!usize {
    var i: usize = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        o += try encoding.utf8.encodeCodePointWriter(map(decoded.code_point), writer);
        i += decoded.len;
    }
    return o;
}

/// Allocates and returns the simple uppercase mapping of the UTF-8 `bytes` as a
/// new UTF-8 string (1:1 codepoint mapping). Malformed input surfaces a
/// `UTF8ValidationError`. The caller owns and must free the result.
///
/// @stable-since: v0.2.0
pub fn upperSimpleUtf8Alloc(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{OutOfMemory})![]u8 {
    return simpleMapUtf8Alloc(toUpperCase, allocator, bytes);
}

/// Allocates and returns the simple lowercase mapping of the UTF-8 `bytes` as a
/// new UTF-8 string (1:1 codepoint mapping). Malformed input surfaces a
/// `UTF8ValidationError`. The caller owns and must free the result.
///
/// @stable-since: v0.2.0
pub fn lowerSimpleUtf8Alloc(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{OutOfMemory})![]u8 {
    return simpleMapUtf8Alloc(toLowerCase, allocator, bytes);
}

/// Maps the UTF-8 `bytes` to simple uppercase and writes the result as UTF-8 to
/// `writer`, returning the number of bytes written. Surfaces a
/// `UTF8ValidationError` for malformed source or the writer's `error.WriteFailed`.
///
/// @stable-since: v0.2.0
pub fn upperSimpleUtf8Writer(bytes: []const u8, writer: *std.Io.Writer) (UTF8ValidationError || std.Io.Writer.Error)!usize {
    return simpleMapUtf8Writer(toUpperCase, bytes, writer);
}

/// Maps the UTF-8 `bytes` to simple lowercase and writes the result as UTF-8 to
/// `writer`, returning the number of bytes written. Surfaces a
/// `UTF8ValidationError` for malformed source or the writer's `error.WriteFailed`.
///
/// @stable-since: v0.2.0
pub fn lowerSimpleUtf8Writer(bytes: []const u8, writer: *std.Io.Writer) (UTF8ValidationError || std.Io.Writer.Error)!usize {
    return simpleMapUtf8Writer(toLowerCase, bytes, writer);
}

/// Allocates and returns the full default case folding of the UTF-8 `bytes` as a
/// new UTF-8 string, honoring expanding folds (e.g. ß -> "ss"). This is the
/// primitive for caseless matching of UTF-8 text. Malformed input surfaces a
/// `UTF8ValidationError`. The caller owns and must free the result.
///
/// @stable-since: v0.2.0
pub fn foldFullUtf8Alloc(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{OutOfMemory})![]u8 {
    // Size pass: account for fold expansions and the encoded byte length.
    var i: usize = 0;
    var len: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        const folded = caseFoldFull(decoded.code_point);
        for (folded.slice()) |c| len += encoding.utf8.utf8EncodeLen(c);
        i += decoded.len;
    }

    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);

    i = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = encoding.utf8.validateAndDecodeCodePointBytes(bytes, i) catch unreachable;
        const folded = caseFoldFull(decoded.code_point);
        for (folded.slice()) |c| o += encoding.utf8.encodeCodePointUnchecked(c, out[o..]);
        i += decoded.len;
    }
    return out;
}

/// Folds the UTF-8 `bytes` with full default case folding and writes the result
/// as UTF-8 to `writer`, returning the number of bytes written. Expanding folds
/// are honored. Surfaces a `UTF8ValidationError` for malformed source or the
/// writer's `error.WriteFailed`.
///
/// @stable-since: v0.2.0
pub fn foldFullUtf8Writer(bytes: []const u8, writer: *std.Io.Writer) (UTF8ValidationError || std.Io.Writer.Error)!usize {
    var i: usize = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        const folded = caseFoldFull(decoded.code_point);
        for (folded.slice()) |c| o += try encoding.utf8.encodeCodePointWriter(c, writer);
        i += decoded.len;
    }
    return o;
}

/// Allocates and returns the full uppercase mapping of the UTF-8 `bytes` as a
/// new UTF-8 string, honoring expanding mappings (e.g. ß -> "SS"). Unlike
/// `upperSimpleUtf8Alloc`, this is fully Unicode-conformant for cased text.
/// Uses the default (root) locale, so no Turkic tailoring is applied. Malformed
/// input surfaces a `UTF8ValidationError`. The caller owns and must free the
/// result.
///
/// @stable-since: v0.4.1
pub fn upperFullUtf8Alloc(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{OutOfMemory})![]u8 {
    // Size pass: account for mapping expansions and the encoded byte length.
    var i: usize = 0;
    var len: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        const mapped = toUpperCaseFull(decoded.code_point, .none, .none);
        for (mapped.slice()) |c| len += encoding.utf8.utf8EncodeLen(c);
        i += decoded.len;
    }

    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);

    i = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = encoding.utf8.validateAndDecodeCodePointBytes(bytes, i) catch unreachable;
        const mapped = toUpperCaseFull(decoded.code_point, .none, .none);
        for (mapped.slice()) |c| o += encoding.utf8.encodeCodePointUnchecked(c, out[o..]);
        i += decoded.len;
    }
    return out;
}

/// Maps the UTF-8 `bytes` to full uppercase and writes the result as UTF-8 to
/// `writer`, returning the number of bytes written. Expanding mappings (e.g.
/// ß -> "SS") are honored. Uses the default (root) locale, so no Turkic
/// tailoring is applied. Surfaces a `UTF8ValidationError` for malformed source
/// or the writer's `error.WriteFailed`.
///
/// @stable-since: v0.4.1
pub fn upperFullUtf8Writer(bytes: []const u8, writer: *std.Io.Writer) (UTF8ValidationError || std.Io.Writer.Error)!usize {
    var i: usize = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        const mapped = toUpperCaseFull(decoded.code_point, .none, .none);
        for (mapped.slice()) |c| o += try encoding.utf8.encodeCodePointWriter(c, writer);
        i += decoded.len;
    }
    return o;
}

/// Allocates and returns the full lowercase mapping of the UTF-8 `bytes` as a
/// new UTF-8 string, honoring expanding mappings. Unlike `lowerSimpleUtf8Alloc`,
/// this honors expansions, but it applies the DEFAULT (context-free) lowercase
/// mapping, so the Greek Final_Sigma context is not applied (a trailing capital
/// Σ lowercases to medial σ, not final ς). Direct users needing Final_Sigma
/// should use `titlecaseUtf8Alloc` or the per-scalar `toLowerCaseFull` with
/// `.final_sigma`. Malformed input surfaces a `UTF8ValidationError`. The caller
/// owns and must free the result.
///
/// @stable-since: v0.4.1
pub fn lowerFullUtf8Alloc(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{OutOfMemory})![]u8 {
    // Size pass: account for mapping expansions and the encoded byte length.
    var i: usize = 0;
    var len: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        const mapped = toLowerCaseFull(decoded.code_point, .none, .none);
        for (mapped.slice()) |c| len += encoding.utf8.utf8EncodeLen(c);
        i += decoded.len;
    }

    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);

    i = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = encoding.utf8.validateAndDecodeCodePointBytes(bytes, i) catch unreachable;
        const mapped = toLowerCaseFull(decoded.code_point, .none, .none);
        for (mapped.slice()) |c| o += encoding.utf8.encodeCodePointUnchecked(c, out[o..]);
        i += decoded.len;
    }
    return out;
}

/// Maps the UTF-8 `bytes` to full lowercase and writes the result as UTF-8 to
/// `writer`, returning the number of bytes written. Expanding mappings are
/// honored, but this applies the DEFAULT (context-free) lowercase mapping, so
/// the Greek Final_Sigma context is not applied (a trailing capital Σ lowercases
/// to medial σ, not final ς). Direct users needing Final_Sigma should use
/// `titlecaseUtf8Alloc` or the per-scalar `toLowerCaseFull` with `.final_sigma`.
/// Surfaces a `UTF8ValidationError` for malformed source or the writer's
/// `error.WriteFailed`.
///
/// @stable-since: v0.4.1
pub fn lowerFullUtf8Writer(bytes: []const u8, writer: *std.Io.Writer) (UTF8ValidationError || std.Io.Writer.Error)!usize {
    var i: usize = 0;
    var o: usize = 0;
    while (i < bytes.len) {
        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(bytes, i);
        const mapped = toLowerCaseFull(decoded.code_point, .none, .none);
        for (mapped.slice()) |c| o += try encoding.utf8.encodeCodePointWriter(c, writer);
        i += decoded.len;
    }
    return o;
}

/// Lazily yields the case-folded codepoint stream of a UTF-8 string, one
/// folded scalar at a time, without allocating: expanding folds (ß -> "ss")
/// are buffered in a fixed `caseFoldFullCap`-sized window. The streaming
/// primitive behind `indexOfFold`; the same shape `equalFoldBytes` uses
/// inline.
fn FoldedUtf8Stream(comptime mode: EqualFoldMode) type {
    const cap = switch (mode) {
        .simple => 1,
        .full => caseFoldFullCap(.default),
    };

    return struct {
        bytes: []const u8,
        i: usize = 0,
        buf: [cap]CodePoint = undefined,
        buf_len: usize = 0,
        buf_pos: usize = 0,

        const Self = @This();

        /// True when no fold expansion is half-consumed, i.e. the stream sits
        /// exactly on a scalar boundary of the underlying bytes.
        fn atBoundary(self: *const Self) bool {
            return self.buf_pos >= self.buf_len;
        }

        fn next(self: *Self) UTF8ValidationError!?CodePoint {
            if (self.buf_pos >= self.buf_len) {
                if (self.i >= self.bytes.len) return null;

                if (encoding.isAscii(self.bytes[self.i])) {
                    self.buf[0] = asciiFoldLower(self.bytes[self.i]);
                    self.buf_len = 1;
                    self.i += 1;
                } else {
                    const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(self.bytes, self.i);
                    self.i += decoded.len;
                    switch (mode) {
                        .simple => {
                            self.buf[0] = caseFoldSimple(decoded.code_point);
                            self.buf_len = 1;
                        },
                        .full => {
                            const folded = caseFoldFull(decoded.code_point);
                            const sl = folded.slice();
                            for (sl, 0..) |cp, k| self.buf[k] = cp;
                            self.buf_len = sl.len;
                        },
                    }
                }
                self.buf_pos = 0;
            }

            const cp = self.buf[self.buf_pos];
            self.buf_pos += 1;
            return cp;
        }
    };
}

/// Codepoint-slice twin of `FoldedUtf8Stream`: no decoding, no errors.
fn FoldedCodePointStream(comptime mode: EqualFoldMode) type {
    const cap = switch (mode) {
        .simple => 1,
        .full => caseFoldFullCap(.default),
    };

    return struct {
        code_points: []const CodePoint,
        i: usize = 0,
        buf: [cap]CodePoint = undefined,
        buf_len: usize = 0,
        buf_pos: usize = 0,

        const Self = @This();

        fn atBoundary(self: *const Self) bool {
            return self.buf_pos >= self.buf_len;
        }

        fn next(self: *Self) ?CodePoint {
            if (self.buf_pos >= self.buf_len) {
                if (self.i >= self.code_points.len) return null;

                const code_point = self.code_points[self.i];
                self.i += 1;
                switch (mode) {
                    .simple => {
                        self.buf[0] = caseFoldSimple(code_point);
                        self.buf_len = 1;
                    },
                    .full => {
                        const folded = caseFoldFull(code_point);
                        const sl = folded.slice();
                        for (sl, 0..) |cp, k| self.buf[k] = cp;
                        self.buf_len = sl.len;
                    },
                }
                self.buf_pos = 0;
            }

            const cp = self.buf[self.buf_pos];
            self.buf_pos += 1;
            return cp;
        }
    };
}

/// Returns the byte offset of the first caseless occurrence of `needle` in
/// `haystack`, or `null`. Comparison folds both sides on the fly (`mode`
/// selects simple or full folding) without allocating, so `"STRASSE"` is
/// found in `"…straße…"` under `.full`. An occurrence always covers whole
/// haystack scalars: a needle that ends midway through one scalar's fold
/// expansion (e.g. needle `"s"` against haystack `"ß"`) does not match.
///
/// An empty needle matches at offset 0. Both inputs must be valid UTF-8;
/// malformed bytes surface a `UTF8ValidationError`. Worst-case cost is
/// `O(haystack scalars × needle scalars)`.
///
/// @stable-since: v0.4.0
pub fn indexOfFold(comptime mode: EqualFoldMode, haystack: []const u8, needle: []const u8) UTF8ValidationError!?usize {
    if (needle.len == 0) return 0;

    var start: usize = 0;
    while (start < haystack.len) {
        var h = FoldedUtf8Stream(mode){ .bytes = haystack[start..] };
        var n = FoldedUtf8Stream(mode){ .bytes = needle };

        const matched = blk: {
            while (try n.next()) |ncp| {
                const hcp = (try h.next()) orelse break :blk false;
                if (hcp != ncp) break :blk false;
            }
            // The needle is exhausted; a real occurrence must also end on a
            // haystack scalar boundary.
            break :blk h.atBoundary();
        };
        if (matched) return start;

        const decoded = try encoding.utf8.validateAndDecodeCodePointBytes(haystack, start);
        start += decoded.len;
    }

    return null;
}

/// Returns `true` when `needle` occurs caselessly anywhere in `haystack`.
/// Convenience wrapper over `indexOfFold`; same folding, boundary, and
/// validity rules.
///
/// @stable-since: v0.4.0
pub fn containsFold(comptime mode: EqualFoldMode, haystack: []const u8, needle: []const u8) UTF8ValidationError!bool {
    return (try indexOfFold(mode, haystack, needle)) != null;
}

/// Codepoint-slice twin of `indexOfFold`: returns the scalar index of the
/// first caseless occurrence of `needle` in `haystack`, or `null`. Since the
/// input is already decoded, no decoding or validation is paid and the
/// function cannot fail (`CodePoint` contract). Same whole-scalar boundary
/// rule as `indexOfFold`.
///
/// @stable-since: v0.4.0
pub fn indexOfFoldCodePoints(comptime mode: EqualFoldMode, haystack: []const CodePoint, needle: []const CodePoint) ?usize {
    if (needle.len == 0) return 0;

    var start: usize = 0;
    while (start < haystack.len) : (start += 1) {
        var h = FoldedCodePointStream(mode){ .code_points = haystack[start..] };
        var n = FoldedCodePointStream(mode){ .code_points = needle };

        const matched = blk: {
            while (n.next()) |ncp| {
                const hcp = h.next() orelse break :blk false;
                if (hcp != ncp) break :blk false;
            }
            break :blk h.atBoundary();
        };
        if (matched) return start;
    }

    return null;
}

/// Returns `true` when `needle` occurs caselessly anywhere in `haystack`.
/// Codepoint-slice twin of `containsFold`; cannot fail.
///
/// @stable-since: v0.4.0
pub fn containsFoldCodePoints(comptime mode: EqualFoldMode, haystack: []const CodePoint, needle: []const CodePoint) bool {
    return indexOfFoldCodePoints(mode, haystack, needle) != null;
}

const segmentation = @import("../segmentation/root.zig");

/// True when `code_points[i]` sits in Final_Sigma context (Unicode Table
/// 3-17): preceded by a cased scalar (skipping case-ignorables), and not
/// followed by one (skipping case-ignorables). Only meaningful for U+03A3.
fn isFinalSigmaContext(code_points: []const CodePoint, i: usize) bool {
    var has_cased_before = false;
    var j = i;
    while (j > 0) {
        j -= 1;
        if (properties.isCaseIgnorable(code_points[j])) continue;
        has_cased_before = properties.isCased(code_points[j]);
        break;
    }
    if (!has_cased_before) return false;

    var k = i + 1;
    while (k < code_points.len) : (k += 1) {
        if (properties.isCaseIgnorable(code_points[k])) continue;
        return !properties.isCased(code_points[k]);
    }
    return true;
}

/// Shared walk for the titlecase APIs: when `out` is null only counts the
/// mapped length, otherwise writes into it (sized by the counting pass).
fn titlecaseEmit(code_points: []const CodePoint, out: ?[]CodePoint) usize {
    var o: usize = 0;
    var words = segmentation.codePointWordIterator(code_points);

    while (words.next()) |word| {
        const word_base = (@intFromPtr(word.ptr) - @intFromPtr(code_points.ptr)) / @sizeOf(CodePoint);
        var seen_cased = false;

        for (word, 0..) |code_point, wi| {
            if (!seen_cased) {
                if (properties.isCased(code_point)) {
                    seen_cased = true;
                    const mapped = toTitleCaseFull(code_point, .none, .none);
                    for (mapped.slice()) |cp| {
                        if (out) |buf| buf[o] = cp;
                        o += 1;
                    }
                } else {
                    // Before the word's first cased scalar: unchanged (R3).
                    if (out) |buf| buf[o] = code_point;
                    o += 1;
                }
                continue;
            }

            // U+03A3 is the only scalar whose default lowercase mapping is
            // context-sensitive (Final_Sigma -> U+03C2).
            if (code_point == 0x03A3 and isFinalSigmaContext(code_points, word_base + wi)) {
                const mapped = toLowerCaseFull(code_point, .none, .final_sigma);
                for (mapped.slice()) |cp| {
                    if (out) |buf| buf[o] = cp;
                    o += 1;
                }
            } else {
                const mapped = toLowerCaseFull(code_point, .none, .none);
                for (mapped.slice()) |cp| {
                    if (out) |buf| buf[o] = cp;
                    o += 1;
                }
            }
        }
    }

    return o;
}

/// Titlecases `code_points` as a string per the Unicode default algorithm
/// (R3): words are found with UAX #29 word segmentation, the first cased
/// scalar of each word maps through the full titlecase mapping, every scalar
/// after it through the full lowercase mapping (with Final_Sigma context for
/// U+03A3), and scalars before the first cased one pass through unchanged.
/// Default (root-locale) mappings; no Turkic/Lithuanian tailoring.
///
/// Returns a freshly-allocated, exactly-sized slice the caller owns. Since
/// the input is already decoded, no decoding or validation is paid
/// (`CodePoint` contract).
///
/// @stable-since: v0.4.0
pub fn titlecaseAlloc(allocator: std.mem.Allocator, code_points: []const CodePoint) error{OutOfMemory}![]CodePoint {
    const len = titlecaseEmit(code_points, null);
    const out = try allocator.alloc(CodePoint, len);
    errdefer allocator.free(out);

    _ = titlecaseEmit(code_points, out);
    return out;
}

/// UTF-8 convenience over `titlecaseAlloc`: decodes `bytes` strictly,
/// titlecases, and re-encodes into a freshly-allocated UTF-8 string the
/// caller owns. Malformed input surfaces a `UTF8ValidationError`.
///
/// @stable-since: v0.4.0
pub fn titlecaseUtf8Alloc(allocator: std.mem.Allocator, bytes: []const u8) (UTF8ValidationError || error{ BufferTooSmall, OutOfMemory })![]u8 {
    const code_points = try encoding.utf8.bytesToUTF8String(allocator, bytes);
    defer allocator.free(code_points);

    const titled = try titlecaseAlloc(allocator, code_points);
    defer allocator.free(titled);

    return encoding.utf8.encodeCodePointsAlloc(allocator, titled);
}

// ============================================================================
// Tests (relocated from unicode/root.zig during the slim-facade refactor)
// ============================================================================

const properties = @import("../properties/root.zig");
const testing = std.testing;

test "unicode api: derived properties, case folding, and full special casing are not decorative wrappers" {
    try testing.expect(properties.isAlphabetic('A'));
    try testing.expect(properties.isUpperCase('A'));
    try testing.expect(properties.isLowerCase('a'));
    try testing.expect(properties.isMath('+'));
    try testing.expect(properties.isIdStart('A'));
    try testing.expect(!properties.isIdStart('_'));
    try testing.expect(properties.isIdentifierStart('_'));
    try testing.expect(properties.isXidContinue(0x0301));

    try testing.expectEqual(@as(CodePoint, 'a'), caseFoldSimple('A'));
    try testing.expectEqual(@as(CodePoint, 0x0131), caseFoldSimpleTurkic('I'));
    try testing.expectEqual(@as(CodePoint, 'a'), caseFoldSimpleTurkic('A'));

    {
        const r = caseFoldFull(0x00DF);
        try testing.expectEqualSlices(CodePoint, &.{ 's', 's' }, r.slice());
    }
    {
        const r = caseFoldFull(0x10FFFF);
        try testing.expectEqualSlices(CodePoint, &.{0x10FFFF}, r.slice());
    }

    {
        const r = toLowerCaseFull(0x0130, .none, .none);
        try testing.expectEqualSlices(CodePoint, &.{ 0x69, 0x307 }, r.slice());
    }
    {
        const r = toLowerCaseFull(0x0130, .tr, .none);
        try testing.expectEqualSlices(CodePoint, &.{0x69}, r.slice());
    }
    {
        const r = toLowerCaseFull(0x03A3, .none, .final_sigma);
        try testing.expectEqualSlices(CodePoint, &.{0x03C2}, r.slice());
    }
}

test "toUpperCase: ASCII lowercase to uppercase" {
    for ('a'..'z' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp - ('a' - 'A'), upper);
    }
}

test "toUpperCase: ASCII uppercase unchanged" {
    for ('A'..'Z' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, upper);
    }
}

test "toUpperCase: ASCII non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        const upper = toUpperCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, upper);
    }
}

test "toUpperCase: extended Latin" {
    const cases = [_]struct { lower: CodePoint, upper: CodePoint }{
        .{ .lower = 0xE0, .upper = 0xC0 },
        .{ .lower = 0xE9, .upper = 0xC9 },
        .{ .lower = 0xF1, .upper = 0xD1 },
    };
    for (cases) |tc| try testing.expectEqual(tc.upper, toUpperCase(tc.lower));
}

test "toUpperCase: already uppercase unchanged" {
    for ([_]CodePoint{ 0xC0, 0xC9, 0xD1 }) |cp| try testing.expectEqual(cp, toUpperCase(cp));
}

test "toLowerCase: ASCII uppercase to lowercase" {
    for ('A'..'Z' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp + ('a' - 'A'), lower);
    }
}

test "toLowerCase: ASCII lowercase unchanged" {
    for ('a'..'z' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, lower);
    }
}

test "toLowerCase: ASCII non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        const lower = toLowerCase(@as(CodePoint, @intCast(cp)));
        try testing.expectEqual(cp, lower);
    }
}

test "toLowerCase: extended Latin" {
    const cases = [_]struct { upper: CodePoint, lower: CodePoint }{
        .{ .upper = 0xC0, .lower = 0xE0 },
        .{ .upper = 0xC9, .lower = 0xE9 },
        .{ .upper = 0xD1, .lower = 0xF1 },
    };
    for (cases) |tc| try testing.expectEqual(tc.lower, toLowerCase(tc.upper));
}

test "toLowerCase: already lowercase unchanged" {
    for ([_]CodePoint{ 0xE0, 0xE9, 0xF1 }) |cp| try testing.expectEqual(cp, toLowerCase(cp));
}

test "toTitleCase: ASCII uppercase and lowercase" {
    for ('a'..'z' + 1) |cp| {
        try testing.expectEqual(cp - ('a' - 'A'), toTitleCase(@as(CodePoint, @intCast(cp))));
    }
    for ('A'..'Z' + 1) |cp| {
        try testing.expectEqual(cp, toTitleCase(@as(CodePoint, @intCast(cp))));
    }
}

test "toTitleCase: non-letters unchanged" {
    for ('0'..'9' + 1) |cp| {
        try testing.expectEqual(cp, toTitleCase(@as(CodePoint, @intCast(cp))));
    }
}

test "case conversion roundtrip: uppercase->lowercase->uppercase" {
    for ([_]CodePoint{ 'A', 'B', 'Z', 0xC0, 0xC9 }) |cp| {
        const lower = toLowerCase(cp);
        const upper = toUpperCase(lower);
        if (cp <= 'Z') try testing.expectEqual(cp, upper);
    }
}

test "case conversion roundtrip: lowercase->uppercase->lowercase" {
    for ([_]CodePoint{ 'a', 'b', 'z', 0xE0, 0xE9 }) |cp| {
        const upper = toUpperCase(cp);
        const lower = toLowerCase(upper);
        if (cp <= 'z') try testing.expectEqual(cp, lower);
    }
}

test "edge case: null code point maps to itself under every casing operation" {
    try testing.expectEqual(@as(CodePoint, 0), toUpperCase(0));
    try testing.expectEqual(@as(CodePoint, 0), toLowerCase(0));
    try testing.expectEqual(@as(CodePoint, 0), toTitleCase(0));
}

test "case mapping with unusual inputs never produces invalid code points" {
    for (0x0000..0x10FFFF) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        if (cp >= 0xD800 and cp <= 0xDFFF) continue; // skip surrogates
        try testing.expect(toUpperCase(cp) <= 0x10FFFF);
        try testing.expect(toLowerCase(cp) <= 0x10FFFF);
        try testing.expect(toTitleCase(cp) <= 0x10FFFF);
    }
}

test "binary search: case mapping correctness in ranges" {
    for (0xC2..0xDF) |cp_usize| {
        const cp: CodePoint = @intCast(cp_usize);
        _ = toUpperCase(cp);
        _ = toLowerCase(cp);
    }
}

// ============================================================================
// equalFoldBytes tests
// ============================================================================

test "equalFoldBytes simple: empty strings are equal" {
    try testing.expect(try equalFoldBytes(.simple, "", ""));
}

test "equalFoldBytes simple: empty vs non-empty" {
    try testing.expect(!try equalFoldBytes(.simple, "", "a"));
    try testing.expect(!try equalFoldBytes(.simple, "a", ""));
    try testing.expect(!try equalFoldBytes(.simple, "", "abc"));
    try testing.expect(!try equalFoldBytes(.simple, "abc", ""));
}

test "equalFoldBytes simple: identical ASCII" {
    try testing.expect(try equalFoldBytes(.simple, "hello", "hello"));
    try testing.expect(try equalFoldBytes(.simple, "Hello, World!", "Hello, World!"));
    try testing.expect(try equalFoldBytes(.simple, "a", "a"));
}

test "equalFoldBytes simple: ASCII case-insensitive" {
    try testing.expect(try equalFoldBytes(.simple, "hello", "HELLO"));
    try testing.expect(try equalFoldBytes(.simple, "Hello", "hELLO"));
    try testing.expect(try equalFoldBytes(.simple, "hElLo", "HeLlO"));
    try testing.expect(try equalFoldBytes(.simple, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"));
}

test "equalFoldBytes simple: ASCII full alphabet roundtrip" {
    for ('A'..'Z' + 1) |c| {
        const upper = [_]u8{@intCast(c)};
        const lower = [_]u8{@intCast(c + ('a' - 'A'))};
        try testing.expect(try equalFoldBytes(.simple, &upper, &lower));
        try testing.expect(try equalFoldBytes(.simple, &lower, &upper));
    }
}

test "equalFoldBytes simple: ASCII digits and punctuation not folded" {
    try testing.expect(try equalFoldBytes(.simple, "123", "123"));
    try testing.expect(try equalFoldBytes(.simple, "!@#$%", "!@#$%"));
    try testing.expect(!try equalFoldBytes(.simple, "1", "2"));
    try testing.expect(!try equalFoldBytes(.simple, "!", "?"));
}

test "equalFoldBytes simple: ASCII non-letter byte close to A-Z is not folded" {
    // '@' (0x40) is just below 'A' (0x41); '[' (0x5B) is just above 'Z' (0x5A).
    // These must not be confused with case-folding neighbours.
    try testing.expect(!try equalFoldBytes(.simple, "@", "`"));
    try testing.expect(!try equalFoldBytes(.simple, "[", "{"));
    try testing.expect(!try equalFoldBytes(.simple, "A", "@"));
    try testing.expect(!try equalFoldBytes(.simple, "Z", "["));
}

test "equalFoldBytes simple: different ASCII lengths" {
    try testing.expect(!try equalFoldBytes(.simple, "hello", "hellos"));
    try testing.expect(!try equalFoldBytes(.simple, "hellos", "hello"));
    try testing.expect(!try equalFoldBytes(.simple, "a", "ab"));
}

test "equalFoldBytes simple: non-ASCII identity" {
    // U+00E9 (é) == U+00E9
    try testing.expect(try equalFoldBytes(.simple, "café", "café"));
    // U+1F600 (😀) == U+1F600
    try testing.expect(try equalFoldBytes(.simple, "\u{1F600}", "\u{1F600}"));
}

test "equalFoldBytes simple: Latin-1 case fold" {
    // U+00C9 (É) folds to U+00E9 (é)
    try testing.expect(try equalFoldBytes(.simple, "café", "CAFÉ"));
    // U+00DC (Ü) <-> U+00FC (ü)
    try testing.expect(try equalFoldBytes(.simple, "Ü", "ü"));
    // U+00D1 (Ñ) <-> U+00F1 (ñ)
    try testing.expect(try equalFoldBytes(.simple, "ÑOÑO", "ñoño"));
}

test "equalFoldBytes simple: Greek case fold" {
    // U+0391 (Α) <-> U+03B1 (α)
    try testing.expect(try equalFoldBytes(.simple, "Α", "α"));
    // U+0395 (Ε) <-> U+03B5 (ε)
    try testing.expect(try equalFoldBytes(.simple, "Ε", "ε"));
}

test "equalFoldBytes simple: Cyrillic case fold" {
    // U+0410 (А Cyrillic) <-> U+0430 (а Cyrillic)
    try testing.expect(try equalFoldBytes(.simple, "ПРИВЕТ", "привет"));
}

test "equalFoldBytes simple: KELVIN SIGN folds to k" {
    // U+212A (KELVIN SIGN) folds to U+006B (k)
    try testing.expect(try equalFoldBytes(.simple, "\u{212A}", "k"));
    try testing.expect(try equalFoldBytes(.simple, "k", "\u{212A}"));
    try testing.expect(try equalFoldBytes(.simple, "\u{212A}", "K"));
}

test "equalFoldBytes simple: ß does NOT fold to ss in simple mode" {
    // In simple mode, U+00DF stays as U+00DF (no expansion). "ss" != "ß".
    try testing.expect(!try equalFoldBytes(.simple, "ß", "ss"));
    try testing.expect(!try equalFoldBytes(.simple, "ss", "ß"));
    // But "ß" == "ß" trivially.
    try testing.expect(try equalFoldBytes(.simple, "ß", "ß"));
}

test "equalFoldBytes simple: latin mixed with non-ASCII" {
    try testing.expect(try equalFoldBytes(.simple, "Hello Café", "hello café"));
    try testing.expect(try equalFoldBytes(.simple, "Hello Café", "HELLO CAFÉ"));
    try testing.expect(!try equalFoldBytes(.simple, "Hello Café", "Hello Cafe"));
}

test "equalFoldBytes simple: differing non-ASCII codepoints" {
    try testing.expect(!try equalFoldBytes(.simple, "é", "è"));
    try testing.expect(!try equalFoldBytes(.simple, "α", "β"));
}

test "equalFoldBytes simple: mismatched lengths with non-ASCII" {
    try testing.expect(!try equalFoldBytes(.simple, "café", "caféé"));
    try testing.expect(!try equalFoldBytes(.simple, "café", "caf"));
}

test "equalFoldBytes simple: invalid UTF-8 surfaces as error" {
    // 0xC0 0x80 is overlong NUL, 0xFF is invalid.
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.simple, "\xFF", "?"));
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.simple, "a", "\xFF"));
    // truncated 2-byte sequence
    try testing.expectError(error.IndexOutOfBounds, equalFoldBytes(.simple, "\xC3", "a"));
}

test "equalFoldBytes full: empty strings are equal" {
    try testing.expect(try equalFoldBytes(.full, "", ""));
}

test "equalFoldBytes full: empty vs non-empty" {
    try testing.expect(!try equalFoldBytes(.full, "", "a"));
    try testing.expect(!try equalFoldBytes(.full, "a", ""));
}

test "equalFoldBytes full: identical ASCII" {
    try testing.expect(try equalFoldBytes(.full, "hello", "hello"));
    try testing.expect(try equalFoldBytes(.full, "Hello, World!", "Hello, World!"));
}

test "equalFoldBytes full: ASCII case-insensitive" {
    try testing.expect(try equalFoldBytes(.full, "hello", "HELLO"));
    try testing.expect(try equalFoldBytes(.full, "Hello, World!", "hELLO, wORLD!"));
    try testing.expect(try equalFoldBytes(.full, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz"));
}

test "equalFoldBytes full: ß folds to ss" {
    // The canonical full-mode test: U+00DF expands to "ss" in case folding.
    try testing.expect(try equalFoldBytes(.full, "ß", "ss"));
    try testing.expect(try equalFoldBytes(.full, "ss", "ß"));
    try testing.expect(try equalFoldBytes(.full, "ß", "SS"));
    try testing.expect(try equalFoldBytes(.full, "SS", "ß"));
    try testing.expect(try equalFoldBytes(.full, "ß", "Ss"));
    try testing.expect(try equalFoldBytes(.full, "ß", "sS"));
}

test "equalFoldBytes full: ß in the middle of a word" {
    try testing.expect(try equalFoldBytes(.full, "Straße", "strasse"));
    try testing.expect(try equalFoldBytes(.full, "Straße", "STRASSE"));
    try testing.expect(try equalFoldBytes(.full, "Maßstab", "massstab"));
}

test "equalFoldBytes full: ß does not match a single s" {
    try testing.expect(!try equalFoldBytes(.full, "ß", "s"));
    try testing.expect(!try equalFoldBytes(.full, "s", "ß"));
}

test "equalFoldBytes full: ligature ff folds to ff" {
    // U+FB00 (ﬀ) folds to "ff" under full mode.
    try testing.expect(try equalFoldBytes(.full, "\u{FB00}", "ff"));
    try testing.expect(try equalFoldBytes(.full, "\u{FB00}", "FF"));
    try testing.expect(try equalFoldBytes(.full, "a\u{FB00}b", "affb"));
}

test "equalFoldBytes full: ligature fi folds to fi" {
    // U+FB01 (ﬁ) folds to "fi" under full mode.
    try testing.expect(try equalFoldBytes(.full, "\u{FB01}", "fi"));
    try testing.expect(try equalFoldBytes(.full, "\u{FB01}", "FI"));
}

test "equalFoldBytes full: ŉ folds to two codepoints" {
    // U+0149 (ŉ) folds to U+02BC U+006E.
    try testing.expect(try equalFoldBytes(.full, "\u{0149}", "\u{02BC}n"));
    try testing.expect(try equalFoldBytes(.full, "\u{02BC}n", "\u{0149}"));
}

test "equalFoldBytes full: İ folds to i + combining dot" {
    // U+0130 (İ) folds to U+0069 U+0307 under full default folding.
    try testing.expect(try equalFoldBytes(.full, "\u{0130}", "i\u{0307}"));
    try testing.expect(try equalFoldBytes(.full, "i\u{0307}", "\u{0130}"));
}

test "equalFoldBytes full: KELVIN SIGN folds to k" {
    try testing.expect(try equalFoldBytes(.full, "\u{212A}", "k"));
    try testing.expect(try equalFoldBytes(.full, "K\u{212A}lvin", "KKlvin"));
}

test "equalFoldBytes full: expansion + suffix mismatch" {
    // s1 expands to more codepoints than s2 has -> not equal.
    try testing.expect(!try equalFoldBytes(.full, "ß", "s"));
    try testing.expect(!try equalFoldBytes(.full, "ßx", "ssy"));
    try testing.expect(!try equalFoldBytes(.full, "ßx", "ss"));
    try testing.expect(!try equalFoldBytes(.full, "ss", "ßx"));
}

test "equalFoldBytes full: multiple expansions in a row" {
    try testing.expect(try equalFoldBytes(.full, "ßß", "ssss"));
    try testing.expect(try equalFoldBytes(.full, "ßß", "SSSS"));
    try testing.expect(try equalFoldBytes(.full, "ssss", "ßß"));
    try testing.expect(!try equalFoldBytes(.full, "ßß", "sss"));
    try testing.expect(!try equalFoldBytes(.full, "ßß", "sssss"));
}

test "equalFoldBytes full: expansion at boundary between strings" {
    // ß at end of s1 must consume two s's at end of s2.
    try testing.expect(try equalFoldBytes(.full, "aß", "ass"));
    try testing.expect(try equalFoldBytes(.full, "ass", "aß"));
    // ß at start.
    try testing.expect(try equalFoldBytes(.full, "ßa", "ssa"));
    try testing.expect(try equalFoldBytes(.full, "ssa", "ßa"));
}

test "equalFoldBytes full: differing non-ASCII codepoints" {
    try testing.expect(!try equalFoldBytes(.full, "é", "è"));
    try testing.expect(!try equalFoldBytes(.full, "α", "β"));
}

test "equalFoldBytes full: Greek and Cyrillic case fold" {
    try testing.expect(try equalFoldBytes(.full, "ΑΒΓ", "αβγ"));
    try testing.expect(try equalFoldBytes(.full, "ПРИВЕТ", "привет"));
}

test "equalFoldBytes full: invalid UTF-8 surfaces as error" {
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.full, "\xFF", "?"));
    try testing.expectError(error.InvalidByteSequence, equalFoldBytes(.full, "a", "\xFF"));
    try testing.expectError(error.IndexOutOfBounds, equalFoldBytes(.full, "\xC3", "a"));
}

test "equalFoldBytes full: identity for high-plane codepoints" {
    try testing.expect(try equalFoldBytes(.full, "\u{1F600}", "\u{1F600}"));
    try testing.expect(!try equalFoldBytes(.full, "\u{1F600}", "\u{1F601}"));
}

// ============================================================================
// equalFoldBytesLossy tests
// ============================================================================

test "equalFoldBytesLossy simple: matches strict on valid input" {
    try testing.expect(try equalFoldBytesLossy(.simple, "", ""));
    try testing.expect(try equalFoldBytesLossy(.simple, "hello", "HELLO"));
    try testing.expect(try equalFoldBytesLossy(.simple, "café", "CAFÉ"));
    try testing.expect(!try equalFoldBytesLossy(.simple, "hello", "world"));
    try testing.expect(!try equalFoldBytesLossy(.simple, "ß", "ss"));
}

test "equalFoldBytesLossy full: matches strict on valid input" {
    try testing.expect(try equalFoldBytesLossy(.full, "ß", "ss"));
    try testing.expect(try equalFoldBytesLossy(.full, "Straße", "STRASSE"));
    try testing.expect(try equalFoldBytesLossy(.full, "\u{FB00}", "ff"));
    try testing.expect(!try equalFoldBytesLossy(.full, "ß", "s"));
}

test "equalFoldBytesLossy: invalid bytes do not surface as errors" {
    // Strict would error here; lossy replaces with U+FFFD and continues.
    try testing.expect(try equalFoldBytesLossy(.simple, "\xFF", "\xFF"));
    try testing.expect(try equalFoldBytesLossy(.full, "\xFF", "\xFF"));
}

test "equalFoldBytesLossy: invalid byte vs valid byte not equal" {
    // Invalid byte folds to U+FFFD; not equal to '?'.
    try testing.expect(!try equalFoldBytesLossy(.simple, "\xFF", "?"));
    try testing.expect(!try equalFoldBytesLossy(.full, "\xFF", "?"));
}

test "equalFoldBytesLossy: replacement char matches replacement char" {
    // Both sides produce U+FFFD: explicit replacement vs invalid byte.
    try testing.expect(try equalFoldBytesLossy(.simple, "\u{FFFD}", "\xFF"));
    try testing.expect(try equalFoldBytesLossy(.full, "\u{FFFD}", "\xFF"));
}

test "equalFoldBytesLossy: invalid bytes embedded in valid text" {
    try testing.expect(try equalFoldBytesLossy(.simple, "a\xFFb", "A\xFFB"));
    try testing.expect(try equalFoldBytesLossy(.full, "a\xFFß", "A\xFFss"));
}

// ============================================================================
// equalFoldCodePoints tests
// ============================================================================

test "equalFoldCodePoints simple: empty inputs" {
    try testing.expect(equalFoldCodePoints(.simple, &.{}, &.{}));
    try testing.expect(!equalFoldCodePoints(.simple, &.{}, &.{'a'}));
    try testing.expect(!equalFoldCodePoints(.simple, &.{'a'}, &.{}));
}

test "equalFoldCodePoints simple: ASCII case-insensitive" {
    try testing.expect(equalFoldCodePoints(.simple, &.{ 'H', 'I' }, &.{ 'h', 'i' }));
    try testing.expect(equalFoldCodePoints(.simple, &.{ 'a', 'B', 'c' }, &.{ 'A', 'b', 'C' }));
    try testing.expect(!equalFoldCodePoints(.simple, &.{ 'a', 'b' }, &.{ 'a', 'c' }));
}

test "equalFoldCodePoints simple: length mismatch" {
    try testing.expect(!equalFoldCodePoints(.simple, &.{ 'a', 'b', 'c' }, &.{ 'a', 'b' }));
    try testing.expect(!equalFoldCodePoints(.simple, &.{ 'a', 'b' }, &.{ 'a', 'b', 'c' }));
}

test "equalFoldCodePoints simple: non-ASCII case fold" {
    // É (U+00C9) == é (U+00E9) under simple fold.
    try testing.expect(equalFoldCodePoints(.simple, &.{0x00C9}, &.{0x00E9}));
    // KELVIN SIGN (U+212A) == k (U+006B)
    try testing.expect(equalFoldCodePoints(.simple, &.{0x212A}, &.{'k'}));
    // Greek Α (U+0391) == α (U+03B1)
    try testing.expect(equalFoldCodePoints(.simple, &.{0x0391}, &.{0x03B1}));
}

test "equalFoldCodePoints simple: ß does NOT fold to ss in simple mode" {
    try testing.expect(!equalFoldCodePoints(.simple, &.{0x00DF}, &.{ 's', 's' }));
}

test "equalFoldCodePoints full: ß folds to ss" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x00DF}, &.{ 's', 's' }));
    try testing.expect(equalFoldCodePoints(.full, &.{ 's', 's' }, &.{0x00DF}));
    try testing.expect(equalFoldCodePoints(.full, &.{0x00DF}, &.{ 'S', 'S' }));
}

test "equalFoldCodePoints full: ligatures" {
    // U+FB00 (ﬀ) -> "ff"
    try testing.expect(equalFoldCodePoints(.full, &.{0xFB00}, &.{ 'f', 'f' }));
    // U+FB01 (ﬁ) -> "fi"
    try testing.expect(equalFoldCodePoints(.full, &.{0xFB01}, &.{ 'F', 'I' }));
}

test "equalFoldCodePoints full: İ folds to i + combining dot" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x0130}, &.{ 0x0069, 0x0307 }));
}

test "equalFoldCodePoints full: ŉ folds to two codepoints" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x0149}, &.{ 0x02BC, 0x006E }));
}

test "equalFoldCodePoints full: expansion at boundaries" {
    try testing.expect(equalFoldCodePoints(.full, &.{ 'a', 0x00DF }, &.{ 'A', 's', 's' }));
    try testing.expect(equalFoldCodePoints(.full, &.{ 0x00DF, 'a' }, &.{ 's', 's', 'A' }));
    try testing.expect(!equalFoldCodePoints(.full, &.{ 0x00DF, 'a' }, &.{ 's', 's' }));
    try testing.expect(!equalFoldCodePoints(.full, &.{ 0x00DF, 'a' }, &.{ 's', 's', 's' }));
}

test "equalFoldCodePoints full: multiple expansions" {
    try testing.expect(equalFoldCodePoints(.full, &.{ 0x00DF, 0x00DF }, &.{ 's', 's', 's', 's' }));
    try testing.expect(!equalFoldCodePoints(.full, &.{ 0x00DF, 0x00DF }, &.{ 's', 's', 's' }));
}

test "equalFoldCodePoints full: high-plane identity" {
    try testing.expect(equalFoldCodePoints(.full, &.{0x1F600}, &.{0x1F600}));
    try testing.expect(!equalFoldCodePoints(.full, &.{0x1F600}, &.{0x1F601}));
}

// ============================================================================
// String-level case mapping tests
// ============================================================================

test "upper/lower/foldSimple over codepoints: Buffer and Alloc" {
    const mixed = [_]CodePoint{ 'H', 'e', 'L', 'l', 'O' };

    var buf: [5]CodePoint = undefined;
    try testing.expectEqual(@as(usize, 5), try upperSimpleBuffer(&mixed, &buf));
    try testing.expectEqualSlices(CodePoint, &.{ 'H', 'E', 'L', 'L', 'O' }, buf[0..5]);
    try testing.expectEqual(@as(usize, 5), try lowerSimpleBuffer(&mixed, &buf));
    try testing.expectEqualSlices(CodePoint, &.{ 'h', 'e', 'l', 'l', 'o' }, buf[0..5]);
    try testing.expectEqual(@as(usize, 5), try foldSimpleBuffer(&mixed, &buf));
    try testing.expectEqualSlices(CodePoint, &.{ 'h', 'e', 'l', 'l', 'o' }, buf[0..5]);

    var tiny: [1]CodePoint = undefined;
    try testing.expectError(error.BufferTooSmall, upperSimpleBuffer(&mixed, &tiny));

    const up = try upperSimpleAlloc(testing.allocator, &mixed);
    defer testing.allocator.free(up);
    try testing.expectEqualSlices(CodePoint, &.{ 'H', 'E', 'L', 'L', 'O' }, up);
    const lo = try lowerSimpleAlloc(testing.allocator, &mixed);
    defer testing.allocator.free(lo);
    try testing.expectEqualSlices(CodePoint, &.{ 'h', 'e', 'l', 'l', 'o' }, lo);
    const fs = try foldSimpleAlloc(testing.allocator, &mixed);
    defer testing.allocator.free(fs);
    try testing.expectEqualSlices(CodePoint, &.{ 'h', 'e', 'l', 'l', 'o' }, fs);
}

test "foldFull over codepoints: Len, Buffer, Alloc honor expansion" {
    // 'ma' + ß + 'e' -> "masse" (ß expands to ss).
    const input = [_]CodePoint{ 'm', 'a', 0x00DF, 'e' };
    try testing.expectEqual(@as(usize, 5), foldFullLen(&input));

    var buf: [5]CodePoint = undefined;
    try testing.expectEqual(@as(usize, 5), try foldFullBuffer(&input, &buf));
    try testing.expectEqualSlices(CodePoint, &.{ 'm', 'a', 's', 's', 'e' }, buf[0..5]);

    var tiny: [4]CodePoint = undefined;
    try testing.expectError(error.BufferTooSmall, foldFullBuffer(&input, &tiny));

    const ff = try foldFullAlloc(testing.allocator, &input);
    defer testing.allocator.free(ff);
    try testing.expectEqualSlices(CodePoint, &.{ 'm', 'a', 's', 's', 'e' }, ff);
}

test "simple case mapping over UTF-8: Alloc and Writer" {
    const up = try upperSimpleUtf8Alloc(testing.allocator, "café");
    defer testing.allocator.free(up);
    try testing.expectEqualStrings("CAFÉ", up);

    const lo = try lowerSimpleUtf8Alloc(testing.allocator, "HÉLLO");
    defer testing.allocator.free(lo);
    try testing.expectEqualStrings("héllo", lo);

    var backing: [16]u8 = undefined;
    var w = std.Io.Writer.fixed(&backing);
    const n = try upperSimpleUtf8Writer("café", &w);
    try testing.expectEqualStrings("CAFÉ", w.buffered());
    try testing.expectEqual(w.buffered().len, n);

    try testing.expectError(error.InvalidByteSequence, upperSimpleUtf8Alloc(testing.allocator, "\xFF"));
}

test "full case folding over UTF-8: Alloc and Writer expand ß" {
    const ff = try foldFullUtf8Alloc(testing.allocator, "Straße");
    defer testing.allocator.free(ff);
    try testing.expectEqualStrings("strasse", ff);

    var backing: [32]u8 = undefined;
    var w = std.Io.Writer.fixed(&backing);
    const n = try foldFullUtf8Writer("Straße", &w);
    try testing.expectEqualStrings("strasse", w.buffered());
    try testing.expectEqual(w.buffered().len, n);

    // Result is caseless-equal to the original per equalFoldBytes.
    try testing.expect(try equalFoldBytes(.full, "Straße", ff));
}

test "full uppercase over UTF-8: Alloc expands ß where simple does not" {
    // The full driver expands ß -> "SS" (audit finding C2); the simple driver
    // leaves ß intact. Assert both to document the contrast.
    const full = try upperFullUtf8Alloc(testing.allocator, "straße");
    defer testing.allocator.free(full);
    try testing.expectEqualStrings("STRASSE", full);

    const simple = try upperSimpleUtf8Alloc(testing.allocator, "straße");
    defer testing.allocator.free(simple);
    try testing.expectEqualStrings("STRAßE", simple);

    // U+FB00 LATIN SMALL LIGATURE FF uppercases (full) to "FF".
    const lig = try upperFullUtf8Alloc(testing.allocator, "\u{FB00}");
    defer testing.allocator.free(lig);
    try testing.expectEqualStrings("FF", lig);
}

test "full lowercase over UTF-8: Alloc and mixed round-trip" {
    const lo = try lowerFullUtf8Alloc(testing.allocator, "HELLO");
    defer testing.allocator.free(lo);
    try testing.expectEqualStrings("hello", lo);

    // Mixed string round-trips: lowercasing an already-lowercase string is a
    // no-op, and re-uppercasing recovers the all-caps form.
    const mixed = "HeLLo WoRLD";
    const down = try lowerFullUtf8Alloc(testing.allocator, mixed);
    defer testing.allocator.free(down);
    try testing.expectEqualStrings("hello world", down);

    const down_again = try lowerFullUtf8Alloc(testing.allocator, down);
    defer testing.allocator.free(down_again);
    try testing.expectEqualStrings(down, down_again);

    const up = try upperFullUtf8Alloc(testing.allocator, down);
    defer testing.allocator.free(up);
    try testing.expectEqualStrings("HELLO WORLD", up);
}

test "full uppercase: codepoint variant agrees with the UTF-8 variant" {
    const cps = try encoding.utf8.bytesToUTF8String(testing.allocator, "straße");
    defer testing.allocator.free(cps);

    const upper_cps = try upperFullAlloc(testing.allocator, cps);
    defer testing.allocator.free(upper_cps);
    const from_cps = try encoding.utf8.encodeCodePointsAlloc(testing.allocator, upper_cps);
    defer testing.allocator.free(from_cps);

    const from_bytes = try upperFullUtf8Alloc(testing.allocator, "straße");
    defer testing.allocator.free(from_bytes);

    try testing.expectEqualStrings(from_bytes, from_cps);
    try testing.expectEqualStrings("STRASSE", from_cps);
}

test "upperFullLen and upperFullBuffer honor expansion and report shortfall" {
    // ß -> "SS" is the canonical 1->2 expansion.
    try testing.expectEqual(@as(usize, 2), upperFullLen(&.{0x00DF}));
    // Empty input produces no codepoints.
    try testing.expectEqual(@as(usize, 0), upperFullLen(&.{}));

    // A length-1 buffer cannot hold the 2-codepoint expansion of ß.
    var tiny: [1]CodePoint = undefined;
    try testing.expectError(error.BufferTooSmall, upperFullBuffer(&.{0x00DF}, &tiny));

    // A length-2 buffer holds it exactly.
    var buf: [2]CodePoint = undefined;
    try testing.expectEqual(@as(usize, 2), try upperFullBuffer(&.{0x00DF}, &buf));
    try testing.expectEqualSlices(CodePoint, &.{ 'S', 'S' }, buf[0..2]);
}

test "full uppercase over UTF-8: Writer expands ß" {
    var backing: [32]u8 = undefined;
    var w = std.Io.Writer.fixed(&backing);
    const n = try upperFullUtf8Writer("straße", &w);
    try testing.expectEqualStrings("STRASSE", w.buffered());
    try testing.expectEqual(w.buffered().len, n);
}

test {
    std.testing.refAllDecls(@This());
}

test "indexOfFold: caseless search with expanding folds and boundary rule" {
    // Plain ASCII, both modes.
    inline for ([_]EqualFoldMode{ .simple, .full }) |mode| {
        try testing.expectEqual(@as(?usize, 6), try indexOfFold(mode, "Hello WORLD", "world"));
        try testing.expectEqual(@as(?usize, 0), try indexOfFold(mode, "abc", ""));
        try testing.expectEqual(@as(?usize, null), try indexOfFold(mode, "abc", "zzz"));
        try testing.expectEqual(@as(?usize, null), try indexOfFold(mode, "", "a"));
    }

    // Full folding: ß <-> ss in either direction.
    try testing.expectEqual(@as(?usize, 4), try indexOfFold(.full, "die Straße hier", "STRASSE"));
    try testing.expectEqual(@as(?usize, 4), try indexOfFold(.full, "die STRASSE hier", "straße"));
    // Simple folding does not expand ß, so no match.
    try testing.expectEqual(@as(?usize, null), try indexOfFold(.simple, "die Straße hier", "STRASSE"));

    // Boundary rule: a needle ending inside one scalar's expansion is not a hit.
    try testing.expectEqual(@as(?usize, null), try indexOfFold(.full, "ß", "s"));
    try testing.expectEqual(@as(?usize, 0), try indexOfFold(.full, "ß", "ss"));

    // Greek: final sigma folds together with capital sigma.
    try testing.expectEqual(@as(?usize, 0), try indexOfFold(.full, "ΣΟΦΟΣ", "σοφος"));

    // Invalid UTF-8 surfaces an error.
    try testing.expectError(
        error.InvalidByteSequence,
        indexOfFold(.full, "ab" ++ [_]u8{0xC0} ++ "cd", "zz"),
    );

    try testing.expect(try containsFold(.full, "die Straße hier", "STRASSE"));
    try testing.expect(!try containsFold(.full, "die Straße hier", "autobahn"));
}

test "indexOfFoldCodePoints: scalar-index twin agrees with the byte search" {
    const haystack = [_]CodePoint{ 'd', 'i', 'e', ' ', 'S', 't', 'r', 'a', 0x00DF, 'e' };
    const needle = [_]CodePoint{ 'S', 'T', 'R', 'A', 'S', 'S', 'E' };

    try testing.expectEqual(@as(?usize, 4), indexOfFoldCodePoints(.full, &haystack, &needle));
    try testing.expectEqual(@as(?usize, null), indexOfFoldCodePoints(.simple, &haystack, &needle));
    try testing.expectEqual(@as(?usize, 0), indexOfFoldCodePoints(.full, &haystack, &.{}));
    try testing.expect(containsFoldCodePoints(.full, &haystack, &needle));

    // Boundary rule holds for slices too.
    const eszett = [_]CodePoint{0x00DF};
    try testing.expectEqual(@as(?usize, null), indexOfFoldCodePoints(.full, &eszett, &.{'s'}));
}

test "titlecaseUtf8Alloc: word-segmented titlecase with full mappings" {
    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "hello world", .expected = "Hello World" },
        .{ .input = "STRASSE pizza", .expected = "Strasse Pizza" },
        // MidLetter apostrophe keeps the word together (no "Don'T").
        .{ .input = "don't stop", .expected = "Don't Stop" },
        // ß titlecases to "Ss" per SpecialCasing.
        .{ .input = "ßorn free", .expected = "Ssorn Free" },
        // Greek: trailing capital sigma lowercases to final sigma.
        .{ .input = "ΜΕΓΑΣ ΣΟΦΟΣ", .expected = "Μεγας Σοφος" },
        // Uncased leading characters pass through; the first cased character
        // of each word gets the title map — hence "42Nd", which is the
        // R3-conformant result ('4' and '2' are not cased).
        .{ .input = "'tis 42nd street", .expected = "'Tis 42Nd Street" },
        .{ .input = "", .expected = "" },
        .{ .input = "123 456", .expected = "123 456" },
    };

    for (cases) |case| {
        const got = try titlecaseUtf8Alloc(testing.allocator, case.input);
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(case.expected, got);
    }
}

test "titlecaseAlloc: codepoint-slice variant agrees with the byte variant" {
    const input = "ΜΕΓΑΣ don't ßtraße";

    const cps = try encoding.utf8.bytesToUTF8String(testing.allocator, input);
    defer testing.allocator.free(cps);

    const titled_cps = try titlecaseAlloc(testing.allocator, cps);
    defer testing.allocator.free(titled_cps);
    const from_cps = try encoding.utf8.encodeCodePointsAlloc(testing.allocator, titled_cps);
    defer testing.allocator.free(from_cps);

    const from_bytes = try titlecaseUtf8Alloc(testing.allocator, input);
    defer testing.allocator.free(from_bytes);

    try testing.expectEqualStrings(from_bytes, from_cps);
}
