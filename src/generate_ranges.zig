//! Standalone generator for sorted code-point RANGE tables.
//!
//! Why this exists (and is separate from `generate.zig`):
//! ------------------------------------------------------
//! The main `generate.zig` downloads the UCD and emits the 2-level page tables
//! used for O(1) per-code-point property lookups. Those tables answer "what is
//! the property of THIS code point?" cheaply, but they cannot be *enumerated*
//! into ranges without walking all 1.1M code points — which is fine at runtime
//! but infeasible at a *consumer's* comptime (it would blow the eval branch
//! quota). Consumers such as a regex engine need to resolve `\p{...}`, `\d`,
//! `\w`, `\s`, scripts, etc. into sorted code-point ranges at comptime.
//!
//! So this generator does the 1.1M-code-point walk ONCE, here, on the
//! developer's machine, reusing the already-validated page-table lookups as the
//! source of truth, and commits the coalesced range tables as plain `pub const`
//! arrays. A consumer then iterates a few-thousand-entry array (cheap, comptime
//! or runtime) instead of the whole code space.
//!
//! Run with `zig build generate-ranges` from the repo root. No network access;
//! it depends only on the committed page tables.

const std = @import("std");
const ezi_code = @import("ezi_code");

const properties = ezi_code.unicode.properties;
const scripts = ezi_code.unicode.scripts;
const emoji = ezi_code.unicode.emoji;
const GeneralCategory = properties.GeneralCategory;
const ScriptType = scripts.ScriptType;

const MAX_CP: u32 = 0x10FFFF;

const header =
    \\//! This file is auto-generated. Do not edit directly.
    \\//! To regenerate run `zig build generate-ranges` in same level
    \\//! as `build.zig` file.
    \\
    \\
;

fn openWriter(io: std.Io, path: []const u8, buf: []u8) !struct { file: std.Io.File, fw: std.Io.File.Writer } {
    var dir: std.Io.Dir = .cwd();
    const file = try dir.createFile(io, path, .{ .truncate = true, .permissions = .default_file });
    return .{ .file = file, .fw = file.writer(io, buf) };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const clock: std.Io.Clock = .real;
    const start = clock.now(io);

    try genCategoryRuns(io);
    try genDerivedRuns(io);
    try genPropListRanges(io);
    try genScriptRuns(io);
    try genEmojiRanges(io);

    const end = clock.now(io);
    std.debug.print("generate-ranges done in {}ms\n", .{end.toMilliseconds() - start.toMilliseconds()});
}

// ── General_Category runs (covers \p{Lu}, \p{L}, \d=Nd, Mark, Pc, ...) ─────────
// A complete partition of 0..=0x10FFFF: every code point, including unassigned
// (`.unassigned`) and surrogates (`.surrogate`), belongs to exactly one run so
// that \p{C}/\p{Cn} resolve correctly.
fn genCategoryRuns(io: std.Io) !void {
    var buf: [1 << 16]u8 = undefined;
    var h = try openWriter(io, "src/unicode/properties/generated/category_ranges.zig", &buf);
    defer h.file.close(io);
    const w = &h.fw.interface;
    defer w.flush() catch {};

    try w.writeAll(header);
    try w.writeAll(
        \\const CodePoint = @import("encoding").CodePoint;
        \\const GeneralCategory = @import("../../generated/unicode_data.zig").GeneralCategory;
        \\
        \\pub const CategoryRun = struct { start: CodePoint, end: CodePoint, category: GeneralCategory };
        \\
        \\/// Every code point in 0..=0x10FFFF, partitioned into maximal runs of equal
        \\/// General_Category and sorted by `start`. Unassigned code points appear as
        \\/// `.unassigned` runs so that \p{C}/\p{Cn} can be resolved from this table.
        \\pub const category_runs = [_]CategoryRun{
        \\
    );

    var run_start: u32 = 0;
    var cur = properties.generalCategory(0);
    var count: usize = 0;
    var cp: u32 = 1;
    while (cp <= MAX_CP) : (cp += 1) {
        const v = properties.generalCategory(@intCast(cp));
        if (v != cur) {
            try emitCatRun(w, run_start, cp - 1, cur);
            count += 1;
            run_start = cp;
            cur = v;
        }
    }
    try emitCatRun(w, run_start, MAX_CP, cur);
    count += 1;
    try w.writeAll("};\n");
    std.debug.print("category_runs: {} runs\n", .{count});
}

fn emitCatRun(w: *std.Io.Writer, lo: u32, hi: u32, cat: GeneralCategory) !void {
    try w.print("    .{{ .start = 0x{X}, .end = 0x{X}, .category = .{s} }},\n", .{ lo, hi, @tagName(cat) });
}

// ── DerivedCoreProperties runs (covers \p{Alphabetic}, \p{ID_Start}, ...) ──────
// Coalesced by equal property bitmask; runs with an empty mask are omitted.
fn genDerivedRuns(io: std.Io) !void {
    var buf: [1 << 16]u8 = undefined;
    var h = try openWriter(io, "src/unicode/properties/generated/derived_ranges.zig", &buf);
    defer h.file.close(io);
    const w = &h.fw.interface;
    defer w.flush() catch {};

    try w.writeAll(header);
    try w.writeAll(
        \\const CodePoint = @import("encoding").CodePoint;
        \\
        \\/// `mask` is the same DerivedCoreProperties bitmask returned by
        \\/// `properties.derivedPropertyMask`; test a property with
        \\/// `(mask & @intFromEnum(DerivedProperty.<x>)) != 0`.
        \\pub const DerivedRun = struct { start: CodePoint, end: CodePoint, mask: u32 };
        \\
        \\/// Maximal runs of equal DerivedCoreProperties mask, sorted by `start`.
        \\/// Code points with no derived property (mask == 0) are omitted.
        \\pub const derived_runs = [_]DerivedRun{
        \\
    );

    var run_start: u32 = 0;
    var cur = properties.derivedPropertyMask(0);
    var count: usize = 0;
    var cp: u32 = 1;
    while (cp <= MAX_CP) : (cp += 1) {
        const v = properties.derivedPropertyMask(@intCast(cp));
        if (v != cur) {
            if (cur != 0) {
                try w.print("    .{{ .start = 0x{X}, .end = 0x{X}, .mask = 0x{X} }},\n", .{ run_start, cp - 1, cur });
                count += 1;
            }
            run_start = cp;
            cur = v;
        }
    }
    if (cur != 0) {
        try w.print("    .{{ .start = 0x{X}, .end = 0x{X}, .mask = 0x{X} }},\n", .{ run_start, MAX_CP, cur });
        count += 1;
    }
    try w.writeAll("};\n");
    std.debug.print("derived_runs: {} runs\n", .{count});
}

// ── PropList ranges needed by Perl classes (\s = White_Space, \w needs both) ───
fn genPropListRanges(io: std.Io) !void {
    var buf: [1 << 16]u8 = undefined;
    var h = try openWriter(io, "src/unicode/properties/generated/prop_list_ranges.zig", &buf);
    defer h.file.close(io);
    const w = &h.fw.interface;
    defer w.flush() catch {};

    try w.writeAll(header);
    try w.writeAll(
        \\const CodePoint = @import("encoding").CodePoint;
        \\
        \\pub const Range = struct { start: CodePoint, end: CodePoint };
        \\
        \\/// PropList White_Space ranges (the Unicode basis for the `\s` shorthand).
        \\
    );
    try emitBoolRanges(w, "white_space_ranges", properties.isWhitespace);
    try w.writeAll("\n/// PropList Join_Control ranges (part of the `\\w` shorthand definition).\n");
    try emitBoolRanges(w, "join_control_ranges", properties.isJoinControl);
}

fn emitBoolRanges(w: *std.Io.Writer, name: []const u8, comptime pred: fn (ezi_code.encoding.CodePoint) bool) !void {
    try w.print("pub const {s} = [_]Range{{\n", .{name});
    var in_run = false;
    var run_start: u32 = 0;
    var count: usize = 0;
    var cp: u32 = 0;
    while (cp <= MAX_CP) : (cp += 1) {
        const v = pred(@intCast(cp));
        if (v and !in_run) {
            in_run = true;
            run_start = cp;
        } else if (!v and in_run) {
            try w.print("    .{{ .start = 0x{X}, .end = 0x{X} }},\n", .{ run_start, cp - 1 });
            count += 1;
            in_run = false;
        }
    }
    if (in_run) {
        try w.print("    .{{ .start = 0x{X}, .end = 0x{X} }},\n", .{ run_start, MAX_CP });
        count += 1;
    }
    try w.writeAll("};\n");
    std.debug.print("{s}: {} ranges\n", .{ name, count });
}

// ── Script runs (covers \p{Script=Latin} etc.) ────────────────────────────────
// Coalesced by equal ScriptType; `.unknown` (unassigned/no script) runs are
// omitted — \p{Script=Unknown} is not resolvable from this table.
fn genScriptRuns(io: std.Io) !void {
    var buf: [1 << 16]u8 = undefined;
    var h = try openWriter(io, "src/unicode/scripts/generated/script_ranges.zig", &buf);
    defer h.file.close(io);
    const w = &h.fw.interface;
    defer w.flush() catch {};

    try w.writeAll(header);
    try w.writeAll(
        \\const CodePoint = @import("encoding").CodePoint;
        \\const ScriptType = @import("scripts.zig").ScriptType;
        \\
        \\pub const ScriptRun = struct { start: CodePoint, end: CodePoint, script: ScriptType };
        \\
        \\/// Maximal runs of equal Script property, sorted by `start`. Code points
        \\/// with no assigned script (`.unknown`) are omitted.
        \\pub const script_runs = [_]ScriptRun{
        \\
    );

    var run_start: u32 = 0;
    var cur = scripts.scriptType(0);
    var count: usize = 0;
    var cp: u32 = 1;
    while (cp <= MAX_CP) : (cp += 1) {
        const v = scripts.scriptType(@intCast(cp));
        if (v != cur) {
            if (cur != .unknown) {
                try w.print("    .{{ .start = 0x{X}, .end = 0x{X}, .script = .{s} }},\n", .{ run_start, cp - 1, @tagName(cur) });
                count += 1;
            }
            run_start = cp;
            cur = v;
        }
    }
    if (cur != .unknown) {
        try w.print("    .{{ .start = 0x{X}, .end = 0x{X}, .script = .{s} }},\n", .{ run_start, MAX_CP, @tagName(cur) });
        count += 1;
    }
    try w.writeAll("};\n");
    std.debug.print("script_runs: {} runs\n", .{count});
}

// The emoji `is*` lookups are `inline fn`, which cannot coerce to the ordinary
// `fn(CodePoint) bool` that `emitBoolRanges` expects. Wrap each in a plain
// (non-inline) function so it passes as a concrete function value.
const CP = ezi_code.encoding.CodePoint;
fn isEmoji(cp: CP) bool {
    return emoji.isEmoji(cp);
}
fn isEmojiPresentation(cp: CP) bool {
    return emoji.isEmojiPresentation(cp);
}
fn isEmojiModifier(cp: CP) bool {
    return emoji.isEmojiModifier(cp);
}
fn isEmojiModifierBase(cp: CP) bool {
    return emoji.isEmojiModifierBase(cp);
}
fn isEmojiComponent(cp: CP) bool {
    return emoji.isEmojiComponent(cp);
}
fn isExtendedPictographic(cp: CP) bool {
    return emoji.isExtendedPictographic(cp);
}

// ── Emoji ranges (covers \p{Emoji}, \p{Emoji_Presentation}, ...) ───────────────
// One sorted range list per UTS #51 boolean property, coalesced from the
// committed page/range predicates. Mirrors the `prop_list` range layout (a plain
// `Range{ start, end }`), so a consumer enumerates a few-hundred-entry array
// instead of walking the whole code space to resolve `\p{Emoji}` etc.
fn genEmojiRanges(io: std.Io) !void {
    var buf: [1 << 16]u8 = undefined;
    var h = try openWriter(io, "src/unicode/emoji/generated/emoji_ranges.zig", &buf);
    defer h.file.close(io);
    const w = &h.fw.interface;
    defer w.flush() catch {};

    try w.writeAll(header);
    try w.writeAll(
        \\const CodePoint = @import("encoding").CodePoint;
        \\
        \\pub const Range = struct { start: CodePoint, end: CodePoint };
        \\
        \\/// UTS #51 Emoji ranges (the basis for resolving `\p{Emoji}`).
        \\
    );
    try emitBoolRanges(w, "emoji_ranges", isEmoji);
    try w.writeAll("\n/// UTS #51 Emoji_Presentation ranges.\n");
    try emitBoolRanges(w, "emoji_presentation_ranges", isEmojiPresentation);
    try w.writeAll("\n/// UTS #51 Emoji_Modifier ranges.\n");
    try emitBoolRanges(w, "emoji_modifier_ranges", isEmojiModifier);
    try w.writeAll("\n/// UTS #51 Emoji_Modifier_Base ranges.\n");
    try emitBoolRanges(w, "emoji_modifier_base_ranges", isEmojiModifierBase);
    try w.writeAll("\n/// UTS #51 Emoji_Component ranges.\n");
    try emitBoolRanges(w, "emoji_component_ranges", isEmojiComponent);
    try w.writeAll("\n/// UTS #51 Extended_Pictographic ranges (the UAX #29 GB11 basis).\n");
    try emitBoolRanges(w, "extended_pictographic_ranges", isExtendedPictographic);
}
