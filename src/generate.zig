const std = @import("std");

const utils = @import("utils/root.zig");
const every = utils.every;
const some = @import("utils/helpers.zig").some;

const unicode_types = @import("unicode/types.zig");
const CanonicalCombiningClass = unicode_types.CanonicalCombiningClass;

// ============================================================================
// HTTP / file IO
// ============================================================================

const ucd_folder = "ucd";

fn downloadFileToPath(allocator: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer, url: []const u8) !void {
    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();
    const uri: std.Uri = try .parse(url);
    _ = try client.fetch(.{ .location = .{ .uri = uri }, .response_writer = writer });
}

fn extractFileNameFromPath(path: []const u8) struct { dir_path: []const u8, file_name: []const u8 } {
    if (path.len == 0) return .{ .dir_path = "", .file_name = "" };
    var split_iter = std.mem.splitScalar(u8, path, '/');
    var i: usize = 0;
    while (split_iter.next()) |path_section| {
        if (split_iter.peek() == null) return .{ .dir_path = path[0..i], .file_name = path[i..] };
        i += path_section.len + 1;
    }
    return .{ .dir_path = "", .file_name = "" };
}

fn saveUCDFile(arena: std.mem.Allocator, io: std.Io, dir: *std.Io.Dir, data: []const u8, url: []const u8, buf: []u8) !void {
    const ucd_file_name = extractFileNameFromPath(url);
    const ucd_file = try dir.createFile(io, try std.fmt.allocPrint(arena, "ucd/{s}", .{ucd_file_name.file_name}), .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer ucd_file.close(io);
    var ucd_file_writer = ucd_file.writer(io, buf);
    const ucd_writer = &ucd_file_writer.interface;
    defer ucd_writer.flush() catch {};
    try ucd_writer.writeAll(data);
}

// ============================================================================
// Identifier normalization
// ============================================================================

fn normalizeKey(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var slice: std.ArrayList(u8) = .empty;
    defer slice.deinit(allocator);
    try slice.ensureTotalCapacity(allocator, input.len);

    for (input, 0..) |c, idx| {
        switch (c) {
            'A'...'Z' => {
                if (idx != 0) {
                    const prev = switch (input[idx - 1]) {
                        'A'...'Z' => true,
                        else => false,
                    };
                    if (!prev and idx - 1 != 0) try slice.append(allocator, '_');
                }
                try slice.append(allocator, c + 32);
            },
            'a'...'z' => try slice.append(allocator, c),
            // Preserve digits so labels like LineBreak's "H2"/"H3"/"B2"
            // produce distinct enum variants.
            '0'...'9' => try slice.append(allocator, c),
            else => {},
        }
    }

    return slice.toOwnedSlice(allocator);
}

fn normalizeFnName(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var slice: std.ArrayList(u8) = .empty;
    defer slice.deinit(allocator);
    try slice.ensureTotalCapacity(allocator, input.len);

    var word_start = true;
    var output_started = false;

    for (input) |c| {
        switch (c) {
            'A'...'Z', 'a'...'z' => {
                const lower: u8 = if (c >= 'A' and c <= 'Z') c + 32 else c;
                const upper: u8 = if (c >= 'a' and c <= 'z') c - 32 else c;

                if (!output_started) {
                    try slice.append(allocator, lower);
                    output_started = true;
                    word_start = false;
                } else if (word_start) {
                    try slice.append(allocator, upper);
                    word_start = false;
                } else {
                    try slice.append(allocator, lower);
                }
            },
            '0'...'9' => {
                try slice.append(allocator, c);
                output_started = true;
                word_start = true;
            },
            else => if (output_started) {
                word_start = true;
            },
        }
    }

    return slice.toOwnedSlice(allocator);
}

// ============================================================================
// Parsed range data
// ============================================================================

const RangeType = struct { start: u21, end: u21 };

const ParsedLabel = struct {
    normalized_key: []const u8,
    ranges: std.ArrayList(RangeType) = .empty,
};

const EnumProperty = struct { key: []const u8, ranges: []RangeType };

/// Parse a UCD file shaped like `<range> ; <Label> # <comment>` into a map
/// from raw label string to its normalized snake_case key and accumulated
/// ranges. Used by every enum + 2-level page table generator.
fn parseSemicolonRangeFile(arena: std.mem.Allocator, data: []const u8) !std.StringHashMapUnmanaged(ParsedLabel) {
    var labels: std.StringHashMapUnmanaged(ParsedLabel) = .empty;
    var lines = std.mem.splitScalar(u8, data, '\n');
    line_loop: while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue :line_loop;
        var split_comments = std.mem.splitScalar(u8, line, '#');
        const tokens_raw = split_comments.next() orelse continue :line_loop;
        var tokens_iter = std.mem.splitScalar(u8, tokens_raw, ';');
        const cp_raw = tokens_iter.next() orelse continue :line_loop;
        const label_raw = tokens_iter.next() orelse continue :line_loop;
        const entry = try labels.getOrPut(arena, label_raw);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .normalized_key = try normalizeKey(arena, label_raw) };
        }
        var cp_iter = std.mem.splitSequence(u8, std.mem.trim(u8, cp_raw, " \t"), "..");
        const start_raw = cp_iter.next() orelse continue :line_loop;
        const start = try std.fmt.parseInt(u21, std.mem.trim(u8, start_raw, " \t"), 16);
        const end = if (cp_iter.next()) |end_raw|
            try std.fmt.parseInt(u21, std.mem.trim(u8, end_raw, " \t"), 16)
        else
            start;
        try entry.value_ptr.ranges.append(arena, .{ .start = start, .end = end });
    }
    return labels;
}

fn labelMapToProperties(arena: std.mem.Allocator, labels: *std.StringHashMapUnmanaged(ParsedLabel)) ![]EnumProperty {
    const arr = try arena.alloc(EnumProperty, labels.count());
    var i: usize = 0;
    var it = labels.valueIterator();
    while (it.next()) |v| : (i += 1) {
        arr[i] = .{ .key = v.normalized_key, .ranges = v.ranges.items };
    }
    return arr;
}

/// Parse a space-separated list of hex codepoints into an owned slice.
/// Returns null when input is empty.
fn parseCodePointSequence(arena: std.mem.Allocator, raw: []const u8) !?[]u21 {
    if (raw.len == 0) return null;
    var split_tokens = std.mem.splitScalar(u8, raw, ' ');
    var new_slice: std.ArrayList(u21) = .empty;
    while (split_tokens.next()) |token| {
        const cp_trim = std.mem.trim(u8, token, " \t");
        if (cp_trim.len == 0) continue;
        try new_slice.append(arena, try std.fmt.parseInt(u21, cp_trim, 16));
    }
    return try new_slice.toOwnedSlice(arena);
}

// ============================================================================
// Two-level page table builder & emission helpers
// ============================================================================

const PAGE_BITS = 8;
const PAGE_SIZE = 1 << PAGE_BITS;

fn PageTable(comptime T: type) type {
    return struct {
        unique_pages: []const []const T,
        level1: []const usize,
    };
}

/// Build a deduplicated 2-level page table over `values`. Hashes each
/// 256-element page and reuses identical pages across the codepoint space.
fn buildPageTable(comptime T: type, arena: std.mem.Allocator, values: []const T, default_value: T) !PageTable(T) {
    var unique_pages = std.ArrayList([]const T).empty;
    var level1 = std.ArrayList(usize).empty;
    var page_map: std.AutoHashMapUnmanaged(u64, usize) = .empty;

    const page_buf = try arena.alloc(T, PAGE_SIZE);

    var total: usize = 0;
    while (total < values.len) : (total += PAGE_SIZE) {
        const page_start = total;
        const page_end = @min(page_start + PAGE_SIZE, values.len);

        for (page_buf, 0..) |*slot, j| {
            const idx = page_start + j;
            slot.* = if (idx < page_end) values[idx] else default_value;
        }

        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.sliceAsBytes(page_buf));
        const page_hash = hasher.final();

        var existing_idx: ?usize = null;
        if (page_map.get(page_hash)) |idx| {
            if (std.mem.eql(T, unique_pages.items[idx], page_buf)) existing_idx = idx;
        }

        const final_idx = existing_idx orelse blk: {
            const new_page = try arena.alloc(T, PAGE_SIZE);
            @memcpy(new_page, page_buf);
            const new_idx = unique_pages.items.len;
            try unique_pages.append(arena, new_page);
            try page_map.put(arena, page_hash, new_idx);
            break :blk new_idx;
        };

        try level1.append(arena, final_idx);
    }

    return .{ .unique_pages = unique_pages.items, .level1 = level1.items };
}

/// Emit `const {prefix}_level1 = [_]u16 { ... };` wrapped in zig fmt: off.
fn emitLevel1(writer: *std.Io.Writer, prefix: []const u8, items: []const usize) !void {
    try writer.print("//zig fmt: off\nconst {s}_level1 = [_]u16 {{", .{prefix});
    for (items, 0..) |idx, n| {
        if (n % 12 == 0) try writer.writeAll("\n    ");
        try writer.print("{},", .{idx});
        if (n + 1 != items.len) try writer.writeAll(" ");
    }
    try writer.writeAll("\n};\n//zig fmt: on\n\n");
}

/// Separator after the j-th page element: 12 per row, space between in-row,
/// nothing after the last element.
inline fn writePageItemSep(writer: *std.Io.Writer, j: usize, page_len: usize) !void {
    if ((j + 1) % 12 == 0 and (j + 1) != page_len) {
        try writer.writeAll("\n        ");
    } else if (j + 1 != page_len) {
        try writer.writeAll(" ");
    }
}

// ============================================================================
// Enum + page table emitter (shared by all simple `<range> ; <label>` files)
// ============================================================================

/// Emit a `pub const {enum_name} = enum(u8) { ... }` + two-level page table
/// + lookup function. `default_variant` is declared first and gets enum
/// value 0. If an input label normalizes to the same key as the default,
/// it's folded into the default (no duplicate variant emitted).
fn emitEnumPageTable(
    arena: std.mem.Allocator,
    writer: *std.Io.Writer,
    properties_in: []EnumProperty,
    enum_name: []const u8,
    table_prefix: []const u8,
    default_variant: []const u8,
    lookup_fn_name: []const u8,
) !void {
    std.mem.sort(EnumProperty, properties_in, {}, struct {
        fn lessThan(_: void, a: EnumProperty, b: EnumProperty) bool {
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lessThan);

    var default_idx: ?usize = null;
    for (properties_in, 0..) |prop, i| {
        if (std.mem.eql(u8, prop.key, default_variant)) {
            default_idx = i;
            break;
        }
    }

    const values = try arena.alloc(u8, 0x110000);
    @memset(values, 0);

    for (properties_in, 0..) |prop, i| {
        const enum_val: u8 = if (default_idx != null and i == default_idx.?) 0 else @intCast(i + 1);
        for (prop.ranges) |range| {
            var cp = range.start;
            while (cp <= range.end) : (cp += 1) values[cp] = enum_val;
        }
    }

    const pt = try buildPageTable(u8, arena, values, 0);

    try writer.print("pub const {s} = enum(u8) {{\n    {s},\n", .{ enum_name, default_variant });
    for (properties_in) |prop| {
        if (std.mem.eql(u8, prop.key, default_variant)) continue;
        try writer.print("    {s},\n", .{prop.key});
    }
    try writer.writeAll("};\n\n");

    try emitLevel1(writer, table_prefix, pt.level1);

    try writer.print("//zig fmt: off\nconst {s}_level2 = [_][256]{s} {{\n", .{ table_prefix, enum_name });
    for (pt.unique_pages) |page| {
        try writer.writeAll("    .{\n        ");
        for (page, 0..) |val, j| {
            const name = if (val == 0) default_variant else properties_in[val - 1].key;
            try writer.print(".{s},", .{name});
            try writePageItemSep(writer, j, page.len);
        }
        try writer.writeAll("\n    },\n");
    }
    try writer.writeAll("};\n//zig fmt: on\n\n");

    try writer.print(
        \\pub inline fn {s}(cp: CodePoint) {s} {{
        \\    if (cp > 0x10FFFF) return .{s};
        \\    const page = {s}_level1[cp >> 8];
        \\    return {s}_level2[page][cp & 0xFF];
        \\}}
        \\
        \\
    , .{ lookup_fn_name, enum_name, default_variant, table_prefix, table_prefix });
}

const generated_file_header =
    \\//! This file is auto-generated. Do not edit directly.
    \\//! To regenerate run `zig build generate` in same level
    \\//! as `build.zig` file.
    \\
    \\const CodePoint = @import("encoding").CodePoint;
    \\
    \\
;

// ============================================================================
// UnicodeData.txt helpers
// ============================================================================

/// Run-length tracker for the lowercase / uppercase / titlecase mapping
/// tables in UnicodeData.txt. Codepoints that map by a constant delta and
/// are contiguous get merged into a single CaseMappingRangeEntry.
const CaseMappingTracker = struct {
    range_start: ?u21 = null,
    range_end: ?u21 = null,
    current_difference: i32 = 0,
    buffer: std.ArrayList(u8) = .empty,

    fn add(self: *CaseMappingTracker, arena: std.mem.Allocator, cp: u21, mapping_str: []const u8) !void {
        if (mapping_str.len == 0) return;
        const cp_to = try std.fmt.parseInt(u21, mapping_str, 16);
        const difference = @as(i32, @intCast(cp_to)) - @as(i32, @intCast(cp));

        if (self.range_start == null or self.range_end == null or self.current_difference == 0) {
            self.range_start = cp;
            self.range_end = cp;
            self.current_difference = difference;
        } else if (self.current_difference == difference and cp == self.range_end.? + 1) {
            self.range_end = cp;
        } else {
            try self.flushPending(arena);
            self.range_start = cp;
            self.range_end = cp;
            self.current_difference = difference;
        }
    }

    fn flushPending(self: *CaseMappingTracker, arena: std.mem.Allocator) !void {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
            .{ self.range_start.?, self.range_end.?, self.current_difference },
        );
        try self.buffer.appendSlice(arena, p);
    }

    fn finalize(self: *CaseMappingTracker, arena: std.mem.Allocator) !void {
        if (self.range_start != null) try self.flushPending(arena);
    }
};

/// Emit a 2-level page table where each slot is a `CanonicalCombiningClass`
/// enum variant. Pages store the raw u8 value (`@enumFromInt` at lookup time)
/// — significantly smaller in source than emitting variant names, and lets
/// the optimizer fold the whole lookup into two array indexes.
fn emitCombiningClassPageTable(
    writer: *std.Io.Writer,
    pt: PageTable(u8),
) !void {
    try emitLevel1(writer, "combining_class", pt.level1);
    try writer.writeAll("//zig fmt: off\nconst combining_class_level_2 = [_][256]u8 {\n");
    for (pt.unique_pages) |page| {
        try writer.writeAll("    .{\n        ");
        for (page, 0..) |val, j| {
            try writer.print("{d},", .{val});
            if ((j + 1) % 16 == 0 and (j + 1) != page.len) try writer.writeAll("\n        ");
        }
        try writer.writeAll("\n    },\n");
    }
    try writer.writeAll("};\n//zig fmt: on\n\n");
}

const CategoryEntry = struct { short: []const u8, name: []const u8 };

/// Maps UnicodeData.txt's 2-letter general-category codes (Lu, Ll, ...) to
/// the snake_case enum variant names. Sentinel `short = ""` at the tail is
/// the fallback ("unassigned") returned when no short code matches.
const general_category_table = [_]CategoryEntry{
    .{ .short = "Lu", .name = "uppercase_letter" },
    .{ .short = "Ll", .name = "lowercase_letter" },
    .{ .short = "Lt", .name = "titlecase_letter" },
    .{ .short = "Lm", .name = "modifier_letter" },
    .{ .short = "Lo", .name = "other_letter" },
    .{ .short = "Mn", .name = "non_spacing_mark" },
    .{ .short = "Mc", .name = "spacing_mark" },
    .{ .short = "Me", .name = "enclosing_mark" },
    .{ .short = "Nd", .name = "decimal_number" },
    .{ .short = "Nl", .name = "letter_number" },
    .{ .short = "No", .name = "other_number" },
    .{ .short = "Pc", .name = "connector_punctuation" },
    .{ .short = "Pd", .name = "dash_punctuation" },
    .{ .short = "Ps", .name = "open_punctuation" },
    .{ .short = "Pe", .name = "close_punctuation" },
    .{ .short = "Pi", .name = "initial_punctuation" },
    .{ .short = "Pf", .name = "final_punctuation" },
    .{ .short = "Po", .name = "other_punctuation" },
    .{ .short = "Sm", .name = "math_symbol" },
    .{ .short = "Sc", .name = "currency_symbol" },
    .{ .short = "Sk", .name = "modifier_symbol" },
    .{ .short = "So", .name = "other_symbol" },
    .{ .short = "Zs", .name = "space_separator" },
    .{ .short = "Zl", .name = "line_separator" },
    .{ .short = "Zp", .name = "paragraph_separator" },
    .{ .short = "Cc", .name = "control" },
    .{ .short = "Cf", .name = "format" },
    .{ .short = "Cs", .name = "surrogate" },
    .{ .short = "Co", .name = "private_use" },
    .{ .short = "", .name = "unassigned" },
};
const general_category_default: u8 = general_category_table.len - 1;

/// `short = ""` at the tail mirrors the original generator's fallback: any
/// unrecognized Bidi_Class string fell through to "pop_directional_isolate".
/// Distinct from the gap-fill default (which is "left_to_right", index 0).
const bidi_class_table = [_]CategoryEntry{
    .{ .short = "L", .name = "left_to_right" },
    .{ .short = "R", .name = "right_to_left" },
    .{ .short = "AL", .name = "arabic_letter" },
    .{ .short = "EN", .name = "european_number" },
    .{ .short = "ES", .name = "european_separator" },
    .{ .short = "ET", .name = "european_terminator" },
    .{ .short = "AN", .name = "arabic_number" },
    .{ .short = "CS", .name = "common_separator" },
    .{ .short = "NSM", .name = "non_spacing_mark" },
    .{ .short = "BN", .name = "boundary_neutral" },
    .{ .short = "B", .name = "paragraph_separator" },
    .{ .short = "S", .name = "segment_separator" },
    .{ .short = "WS", .name = "whitespace" },
    .{ .short = "ON", .name = "other_neutral" },
    .{ .short = "LRE", .name = "left_to_right_embedding" },
    .{ .short = "LRO", .name = "left_to_right_override" },
    .{ .short = "RLE", .name = "right_to_left_embedding" },
    .{ .short = "RLO", .name = "right_to_left_override" },
    .{ .short = "PDF", .name = "pop_directional_format" },
    .{ .short = "LRI", .name = "left_to_right_isolate" },
    .{ .short = "RLI", .name = "right_to_left_isolate" },
    .{ .short = "FSI", .name = "first_strong_isolate" },
    .{ .short = "", .name = "pop_directional_isolate" },
};
const bidi_class_gap_fill: u8 = 0; // "left_to_right"
const bidi_class_unknown: u8 = bidi_class_table.len - 1;

fn lookupCategory(table: []const CategoryEntry, fallback_idx: u8, code: []const u8) u8 {
    for (table, 0..) |entry, i| {
        if (entry.short.len == 0) continue;
        if (std.mem.eql(u8, code, entry.short)) return @intCast(i);
    }
    return fallback_idx;
}

fn emitNamedEnum(writer: *std.Io.Writer, name: []const u8, table: []const CategoryEntry) !void {
    try writer.print("pub const {s} = enum(u8) {{\n", .{name});
    for (table) |entry| try writer.print("    {s},\n", .{entry.name});
    try writer.writeAll("};\n\n");
}

/// Emit a 2-level page table where each element is a named enum variant
/// (the variant name is looked up in `table` by the page slot's index).
fn emitNamedEnumPageTable(
    writer: *std.Io.Writer,
    table_prefix: []const u8,
    level2_name_suffix: []const u8,
    element_type: []const u8,
    table: []const CategoryEntry,
    pt: PageTable(u8),
) !void {
    try emitLevel1(writer, table_prefix, pt.level1);

    try writer.print("//zig fmt: off\nconst {s}{s} = [_][256]{s} {{\n", .{ table_prefix, level2_name_suffix, element_type });
    for (pt.unique_pages) |page| {
        try writer.writeAll("    .{\n        ");
        for (page, 0..) |idx, j| {
            try writer.print(".{s},", .{table[idx].name});
            if ((j + 1) % 12 == 0 and (j + 1) != page.len) try writer.writeAll("\n        ");
        }
        try writer.writeAll("\n    },\n");
    }
    try writer.writeAll("};\n//zig fmt: on\n\n");
}

// ============================================================================
// Generators
// ============================================================================

fn generateUnicodeData(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();
    var file = try dir.createFile(io, file_name, .{ .truncate = true, .permissions = .default_file });
    defer file.close(io);
    const buf = try arena.alloc(u8, 1024 * 4);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    var lowercase = CaseMappingTracker{};
    var uppercase = CaseMappingTracker{};
    var titlecase = CaseMappingTracker{};

    var category_values = std.ArrayList(u8).empty;
    var bidi_values = std.ArrayList(u8).empty;
    var combining_values = std.ArrayList(u8).empty;

    var pending_range_start: ?u21 = null;
    var pending_range_category: u8 = general_category_default;
    var pending_range_bidi: u8 = bidi_class_gap_fill;
    var pending_range_combining: u8 = 0;

    var next_cp: u21 = 0;
    var next_bidi_cp: u21 = 0;
    var next_combining_cp: u21 = 0;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var field_iter = std.mem.splitScalar(u8, line, ';');

        const code_point = field_iter.next() orelse continue;
        const range_hint = field_iter.next() orelse continue;
        const category = field_iter.next() orelse continue;
        const combining_class = field_iter.next() orelse continue;
        const bidi_class = field_iter.next() orelse continue;

        // skip Decomposition_Mapping, Decimal_Digit_Value, Digit_Value,
        // Numeric_Value, Bidi_Mirrored, Unicode_1_Name, ISO_Comment.
        inline for (0..7) |_| _ = field_iter.next();

        const uppercase_mapping = field_iter.next() orelse "";
        const lowercase_mapping = field_iter.next() orelse "";
        const titlecase_mapping = field_iter.next() orelse "";

        const cp = try std.fmt.parseInt(u21, code_point, 16);
        const cat_idx = lookupCategory(&general_category_table, general_category_default, category);
        const bidi_idx = lookupCategory(&bidi_class_table, bidi_class_unknown, bidi_class);

        const ccc_byte: u8 = std.fmt.parseInt(u8, combining_class, 10) catch 0;

        if (std.mem.endsWith(u8, range_hint, ", First>")) {
            pending_range_start = cp;
            pending_range_category = cat_idx;
            pending_range_bidi = bidi_idx;
            pending_range_combining = ccc_byte;
            continue;
        }

        if (std.mem.endsWith(u8, range_hint, ", Last>")) {
            const start_cp = pending_range_start orelse return error.InvalidUnicodeRange;
            while (next_cp < start_cp) : (next_cp += 1) try category_values.append(arena, general_category_default);
            while (next_bidi_cp < start_cp) : (next_bidi_cp += 1) try bidi_values.append(arena, bidi_class_gap_fill);
            while (next_combining_cp < start_cp) : (next_combining_cp += 1) try combining_values.append(arena, 0);
            var range_cp = start_cp;
            while (range_cp <= cp) : (range_cp += 1) {
                try category_values.append(arena, pending_range_category);
                try bidi_values.append(arena, pending_range_bidi);
                try combining_values.append(arena, pending_range_combining);
            }
            next_cp = cp + 1;
            next_bidi_cp = cp + 1;
            next_combining_cp = cp + 1;
            pending_range_start = null;
            continue;
        }

        while (next_cp < cp) : (next_cp += 1) try category_values.append(arena, general_category_default);
        try category_values.append(arena, cat_idx);
        next_cp = cp + 1;

        while (next_combining_cp < cp) : (next_combining_cp += 1) try combining_values.append(arena, 0);
        try combining_values.append(arena, ccc_byte);
        next_combining_cp = cp + 1;

        while (next_bidi_cp < cp) : (next_bidi_cp += 1) try bidi_values.append(arena, bidi_class_gap_fill);
        try bidi_values.append(arena, bidi_idx);
        next_bidi_cp = cp + 1;

        try uppercase.add(arena, cp, uppercase_mapping);
        try lowercase.add(arena, cp, lowercase_mapping);
        try titlecase.add(arena, cp, titlecase_mapping);
    }

    while (next_cp <= 0x10FFFF) : (next_cp += 1) try category_values.append(arena, general_category_default);
    while (next_bidi_cp <= 0x10FFFF) : (next_bidi_cp += 1) try bidi_values.append(arena, bidi_class_gap_fill);
    while (next_combining_cp <= 0x10FFFF) : (next_combining_cp += 1) try combining_values.append(arena, 0);

    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
        \\
        \\const CodePoint = @import("encoding").CodePoint;
        \\const unicode_types = @import("../types.zig");
        \\
        \\const CanonicalCombiningClass = unicode_types.CanonicalCombiningClass;
        \\
        \\
    );

    try emitNamedEnum(writer, "GeneralCategory", &general_category_table);
    try emitNamedEnum(writer, "BidiClass", &bidi_class_table);

    try writer.writeAll(
        \\pub const BidiEntry = struct {
        \\    range_start: CodePoint,
        \\    range_end: CodePoint,
        \\    bidi_class: BidiClass,
        \\};
        \\
        \\pub const CaseMappingRangeEntry = struct { start: CodePoint, end: CodePoint, delta: i32 };
        \\
        \\
    );

    const cat_pt = try buildPageTable(u8, arena, category_values.items, general_category_default);
    try emitNamedEnumPageTable(writer, "category", "_level_2", "GeneralCategory", &general_category_table, cat_pt);

    try writer.writeAll(
        \\pub inline fn generalCategory(cp: CodePoint) GeneralCategory {
        \\    if (cp > 0x10FFFF) return .unassigned;
        \\    const page = category_level1[cp >> 8];
        \\    return category_level_2[page][cp & 0xFF];
        \\}
        \\
        \\
    );

    const combining_pt = try buildPageTable(u8, arena, combining_values.items, 0);
    try emitCombiningClassPageTable(writer, combining_pt);

    try writer.writeAll(
        \\pub inline fn canonicalCombiningClass(cp: CodePoint) CanonicalCombiningClass {
        \\    if (cp > 0x10FFFF) return .not_reordered;
        \\    const page = combining_class_level1[cp >> 8];
        \\    return @enumFromInt(combining_class_level_2[page][cp & 0xFF]);
        \\}
        \\
        \\
    );

    const bidi_pt = try buildPageTable(u8, arena, bidi_values.items, bidi_class_gap_fill);
    try emitNamedEnumPageTable(writer, "bidi", "_level_2", "BidiClass", &bidi_class_table, bidi_pt);

    try writer.writeAll(
        \\pub inline fn bidiClass(cp: CodePoint) BidiClass {
        \\    const page = bidi_level1[cp >> 8];
        \\    return bidi_level_2[page][cp & 0xFF];
        \\}
        \\
        \\
    );

    try lowercase.finalize(arena);
    try uppercase.finalize(arena);
    try titlecase.finalize(arena);

    try writer.writeAll("pub const lowercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(lowercase.buffer.items);
    try writer.writeAll("};\n\npub const uppercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(uppercase.buffer.items);
    try writer.writeAll("};\n\npub const titlecase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(titlecase.buffer.items);
    try writer.writeAll("};\n");

    try file_writer.flush();
    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn generateDerivedCoreProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();
    var file = try dir.createFile(io, file_name, .{ .truncate = true, .permissions = .default_file });
    defer file.close(io);
    const buf = try arena.alloc(u8, 1024 * 4);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    var total_keys: u8 = 0;
    var derived_label_hash: std.StringHashMapUnmanaged(struct {
        index: u8,
        normalized_key: []u8,
        items: std.ArrayList(RangeType) = .empty,
    }) = .empty;

    var lines = std.mem.splitScalar(u8, data, '\n');
    loop: while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue :loop;

        var semicolon_delimited_tokens = std.mem.splitSequence(u8, line, " ; ");
        const code_points_raw = semicolon_delimited_tokens.next() orelse continue :loop;
        const code_points = std.mem.trim(u8, code_points_raw, " ");

        var split_comments = std.mem.splitScalar(u8, semicolon_delimited_tokens.next() orelse continue :loop, '#');
        const label_raw = split_comments.next() orelse continue :loop;
        const label = std.mem.trim(u8, label_raw, " ");

        var entry = try derived_label_hash.getOrPut(arena, label);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .index = total_keys,
                .normalized_key = try normalizeKey(arena, label),
            };
            try entry.value_ptr.items.ensureTotalCapacity(arena, 128);
            total_keys += 1;
        }

        var code_point_split_range = std.mem.splitSequence(u8, code_points, "..");
        const start_raw = code_point_split_range.next() orelse continue :loop;
        const start = try std.fmt.parseInt(u21, start_raw, 16);
        const end = if (code_point_split_range.next()) |val| try std.fmt.parseInt(u21, val, 16) else start;

        try entry.value_ptr.items.append(arena, .{ .start = start, .end = end });
    }

    const map_count = derived_label_hash.size;
    var sorted_normalize_keys = try arena.alloc([]const u8, map_count);
    const sorted_property_ranges = try arena.alloc([]RangeType, map_count);
    const items_indices = try arena.alloc(usize, map_count);
    @memset(items_indices, 0);

    var iter = derived_label_hash.valueIterator();
    while (iter.next()) |val| {
        sorted_normalize_keys[val.index] = val.normalized_key;
        sorted_property_ranges[val.index] = val.items.items;
    }

    std.debug.assert(map_count < 32);

    var final_result_table: std.ArrayList(struct { start: u21, end: u21, bitmask: u32 }) = .empty;
    try final_result_table.ensureTotalCapacity(arena, 2048);

    const predicate = struct {
        pub fn predicate(ranges: []const []RangeType, val: usize, index: usize) bool {
            return val < ranges[index].len;
        }
    }.predicate;

    var previous_bit_mask: u32 = 0;
    var min: u21 = sorted_property_ranges[0][0].start;
    var max: u21 = sorted_property_ranges[0][sorted_property_ranges[0].len - 1].end;

    for (sorted_property_ranges[1..]) |ranges| {
        if (ranges[0].start < min) min = ranges[0].start;
        if (ranges[ranges.len - 1].end > max) max = ranges[ranges.len - 1].end;
    }

    var code_point: u21 = min;
    while (some(usize, sorted_property_ranges, items_indices, predicate) and code_point <= max) : (code_point += 1) {
        var i: usize = 0;
        var current_mask: u32 = 0;

        inner_loop: while (i < sorted_property_ranges.len) {
            var idx = items_indices[i];
            const ranges = sorted_property_ranges[i];

            while (idx < ranges.len and code_point > ranges[idx].end) idx += 1;
            items_indices[i] = idx;

            if (idx >= ranges.len) {
                i += 1;
                continue :inner_loop;
            }

            const range = ranges[idx];
            if (code_point >= range.start and code_point <= range.end) {
                current_mask |= @as(u32, 1) << @intCast(i + 1);
            }

            i += 1;
        }

        if (final_result_table.items.len == 0) {
            if (current_mask != 0) {
                try final_result_table.append(arena, .{ .start = code_point, .end = code_point, .bitmask = current_mask });
            }
        } else if (previous_bit_mask == current_mask and current_mask != 0) {
            final_result_table.items[final_result_table.items.len - 1].end = code_point;
        } else if (current_mask != 0) {
            try final_result_table.append(arena, .{ .start = code_point, .end = code_point, .bitmask = current_mask });
        }

        previous_bit_mask = current_mask;
    }

    var property_values = try arena.alloc(u32, 0x110000);
    @memset(property_values, 0);

    for (final_result_table.items) |entry| {
        var cp = entry.start;
        while (cp <= entry.end) : (cp += 1) property_values[cp] = entry.bitmask;
    }

    const pt = try buildPageTable(u32, arena, property_values, 0);

    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
        \\
        \\const CodePoint = @import("encoding").CodePoint;
        \\
        \\pub const Property = enum(u32) {
        \\
    );
    for (sorted_normalize_keys, 0..) |key, idx| try writer.print("    {s} = 1 << {},\n", .{ key, idx + 1 });
    try writer.writeAll("};\n");

    try emitLevel1(writer, "property", pt.level1);

    try writer.writeAll("//zig fmt: off\nconst property_level2 = [_][256]u32 {\n");
    for (pt.unique_pages) |page| {
        try writer.writeAll("    .{\n        ");
        for (page, 0..) |val, j| {
            try writer.print("0x{X},", .{val});
            try writePageItemSep(writer, j, page.len);
        }
        try writer.writeAll("\n    },\n");
    }
    try writer.writeAll("};\n//zig fmt: on\n\n");

    try writer.writeAll(
        \\pub inline fn propertyMask(code_point: CodePoint) u32 {
        \\    if (code_point > 0x10FFFF) return 0;
        \\    const page = property_level1[code_point >> 8];
        \\    return property_level2[page][code_point & 0xFF];
        \\}
        \\
        \\pub inline fn codePointProperty(code_point: CodePoint, property: Property) bool {
        \\    return (propertyMask(code_point) & @intFromEnum(property)) != 0;
        \\}
        \\
    );

    try file_writer.flush();
    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn generateCaseFolding(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();
    var file = try dir.createFile(io, file_name, .{ .truncate = true, .permissions = .default_file });
    defer file.close(io);
    const buf = try arena.alloc(u8, 4096);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    const FoldEntry = struct {
        from: u21,
        to: []const u21,
    };

    var common_simple = std.ArrayList(FoldEntry).empty;
    var common_full = std.ArrayList(FoldEntry).empty;
    var turkic_simple = std.ArrayList(FoldEntry).empty;
    var turkic_full = std.ArrayList(FoldEntry).empty;

    var split_lines = std.mem.splitScalar(u8, data, '\n');
    line_loop: while (split_lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue :line_loop;

        var semi = std.mem.splitScalar(u8, trimmed, ';');
        const src_raw = semi.next() orelse continue :line_loop;
        const status_raw = semi.next() orelse continue :line_loop;
        const mapping_raw = semi.next() orelse continue :line_loop;

        const from = try std.fmt.parseInt(u21, std.mem.trim(u8, src_raw, " \t"), 16);
        const status = std.mem.trim(u8, status_raw, " \t");
        const mapping_str = std.mem.trim(u8, mapping_raw, " \t");

        var mapping_buf = std.ArrayList(u21).empty;
        var mapping_split = std.mem.splitScalar(u8, mapping_str, ' ');
        while (mapping_split.next()) |cpstr| {
            const cp_trim = std.mem.trim(u8, cpstr, " \t");
            if (cp_trim.len == 0) continue;
            try mapping_buf.append(arena, try std.fmt.parseInt(u21, cp_trim, 16));
        }
        const to = try arena.dupe(u21, mapping_buf.items);

        if (std.mem.eql(u8, status, "C")) {
            try common_simple.append(arena, .{ .from = from, .to = to });
            try common_full.append(arena, .{ .from = from, .to = to });
        } else if (std.mem.eql(u8, status, "S")) {
            try common_simple.append(arena, .{ .from = from, .to = to });
        } else if (std.mem.eql(u8, status, "F")) {
            try common_full.append(arena, .{ .from = from, .to = to });
        } else if (std.mem.eql(u8, status, "T")) {
            try turkic_simple.append(arena, .{ .from = from, .to = to });
            try turkic_full.append(arena, .{ .from = from, .to = to });
        }
    }

    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
        \\
        \\const std = @import("std");
        \\const CodePoint = @import("encoding").CodePoint;
        \\const utils = @import("utils");
        \\
        \\const unicode_types = @import("../../types.zig");
        \\const CaseFoldingMode = unicode_types.CaseFoldingMode;
        \\const CaseFoldingLocale = unicode_types.CaseFoldingLocale;
        \\const FoldResult = unicode_types.FoldResult;
        \\
        \\pub const FoldEntry = struct {
        \\    from: CodePoint,
        \\    to: []const CodePoint,
        \\};
        \\
        \\fn compareFoldEntry(needle: CodePoint, item: FoldEntry) std.math.Order {
        \\    return std.math.order(needle, item.from);
        \\}
        \\
        \\
    );

    const emitTable = struct {
        fn emitTable(w: *std.Io.Writer, table_name: []const u8, entries: []const FoldEntry) !void {
            try w.writeAll("// zig fmt: off\npub const ");
            try w.writeAll(table_name);
            try w.writeAll(" = [_]FoldEntry{\n");
            var i: usize = 0;
            for (entries) |entry| {
                try w.writeAll("    .{ .from = 0x");
                try w.print("{X}", .{entry.from});
                try w.writeAll(", .to = &.{");
                for (entry.to, 0..) |cp, idx| {
                    if (idx > 0) try w.writeAll(", ");
                    try w.print("0x{X}", .{cp});
                }
                try w.writeAll("} },");
                if (i >= 2) {
                    try w.writeAll("\n");
                    i = 0;
                } else i += 1;
            }
            try w.writeAll("\n};\n// zig fmt: off\n\n");
        }
    }.emitTable;

    try emitTable(writer, "common_simple_table", common_simple.items);
    try emitTable(writer, "common_full_table", common_full.items);
    try emitTable(writer, "turkic_simple_table", turkic_simple.items);
    try emitTable(writer, "turkic_full_table", turkic_full.items);

    try writer.writeAll(
        \\fn lookupTable(comptime mode: CaseFoldingMode, comptime table: []const FoldEntry, code_point: CodePoint) ?FoldResult(mode) {
        \\    const entry = utils.binarySearchEntry(FoldEntry, table, code_point, compareFoldEntry) orelse return null;
        \\    return if (comptime FoldResult(mode) == CodePoint) entry.to[0] else entry.to;
        \\}
        \\
        \\pub fn lookup(comptime mode: CaseFoldingMode, comptime locale: CaseFoldingLocale, code_point: CodePoint) ?FoldResult(mode) {
        \\    if (locale == .turkic) {
        \\        const turkic_table = switch (mode) {
        \\            .simple => &turkic_simple_table,
        \\            .full => &turkic_full_table,
        \\        };
        \\        if (lookupTable(mode, turkic_table, code_point)) |mapped| return mapped;
        \\    }
        \\
        \\    const common_table = switch (mode) {
        \\        .simple => &common_simple_table,
        \\        .full => &common_full_table,
        \\    };
        \\    return lookupTable(mode, common_table, code_point);
        \\}
        \\
    );

    try file_writer.flush();
    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn emitOptionalCpArray(writer: *std.Io.Writer, maybe_arr: ?[]const u21) !void {
    if (maybe_arr) |v| {
        try writer.writeAll("&.{");
        for (v) |cp| try writer.print(" 0x{X},", .{cp});
        try writer.writeAll(" }");
    } else try writer.writeAll("&.{}");
}

fn generateSpecialCasing(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();
    var file = try dir.createFile(io, file_name, .{ .truncate = true, .permissions = .default_file });
    defer file.close(io);
    const buf = try arena.alloc(u8, 4096);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    const SpecialMapping = struct {
        lower: ?[]u21 = null,
        upper: ?[]u21 = null,
        title: ?[]u21 = null,
        locale: ?[]const u8 = null,
        condition: ?[]const u8 = null,
    };

    var special_folding_map: std.AutoHashMapUnmanaged(u21, std.ArrayList(SpecialMapping)) = .empty;
    var unique_locale: std.StringHashMapUnmanaged(void) = .empty;
    var unique_conditions: std.StringHashMapUnmanaged(void) = .empty;

    var split_lines = std.mem.splitScalar(u8, data, '\n');
    line_loop: while (split_lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue :line_loop;

        var split_comments = std.mem.splitScalar(u8, line, '#');
        var tokens = std.mem.splitScalar(u8, split_comments.next() orelse continue :line_loop, ';');

        const code_point_raw = std.mem.trim(u8, tokens.next() orelse @panic("code point not found"), " ");
        const lower_raw = std.mem.trim(u8, tokens.next() orelse "", " ");
        const title_raw = std.mem.trim(u8, tokens.next() orelse "", " ");
        const upper_raw = std.mem.trim(u8, tokens.next() orelse "", " ");
        const condition_raw = std.mem.trim(u8, tokens.next() orelse "", " ");

        const code_point = try std.fmt.parseInt(u21, code_point_raw, 16);
        const lower_point = try parseCodePointSequence(arena, lower_raw);
        const title_point = try parseCodePointSequence(arena, title_raw);
        const upper_point = try parseCodePointSequence(arena, upper_raw);

        var locale: ?[]const u8 = null;
        var condition: ?[]const u8 = null;

        var conditional_tokens = std.mem.splitScalar(u8, condition_raw, ' ');
        while (conditional_tokens.next()) |token| {
            // 2-character lowercase tokens are locale codes; longer tokens
            // are conditions (e.g. "Final_Sigma").
            if (token.len == 2 and every(u8, {}, token, struct {
                fn predicate(_: void, ch: u8, _: usize) bool {
                    return ch >= 'a' and ch <= 'z';
                }
            }.predicate)) {
                locale = token;
                try unique_locale.put(arena, token, {});
            } else if (token.len > 1) {
                const normalized = try normalizeKey(arena, token);
                condition = normalized;
                try unique_conditions.put(arena, normalized, {});
            }
        }

        const entry = try special_folding_map.getOrPut(arena, code_point);
        if (!entry.found_existing) entry.value_ptr.* = .empty;

        try entry.value_ptr.append(arena, .{
            .lower = lower_point,
            .upper = upper_point,
            .title = title_point,
            .locale = locale,
            .condition = condition,
        });
    }

    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
        \\
        \\const std = @import("std");
        \\const CodePoint = @import("encoding").CodePoint;
        \\const utils = @import("utils");
        \\
        \\pub const Mapping = struct {
        \\    lower: []const CodePoint,
        \\    upper: []const CodePoint,
        \\    title: []const CodePoint,
        \\    locale: Locale,
        \\    condition: Condition,
        \\};
        \\
        \\pub const CaseMapEntry = struct {
        \\    code_point: CodePoint,
        \\    mappings: []const Mapping,
        \\};
        \\
        \\pub const Condition = enum(u8) {
        \\    none,
        \\
    );

    var cond_iter = unique_conditions.keyIterator();
    while (cond_iter.next()) |key| try writer.print("    {s},\n", .{key.*});
    try writer.writeAll(
        \\
        \\    /// panic if any other condition
        \\    /// is used
        \\    _,
        \\};
        \\
        \\
    );

    try writer.writeAll(
        \\pub const Locale = enum(u8) {
        \\    none,
        \\
    );
    var locale_iter = unique_locale.keyIterator();
    while (locale_iter.next()) |key| try writer.print("    {s},\n", .{key.*});
    try writer.writeAll(
        \\
        \\    /// panic if any other locale
        \\    /// is used
        \\    _,
        \\};
        \\
        \\// zig fmt: off
        \\pub const mappings_table = [_]CaseMapEntry{
        \\
    );

    var sorted_code_points = std.ArrayList(u21).empty;
    try sorted_code_points.ensureTotalCapacity(arena, special_folding_map.count());
    var key_iter = special_folding_map.keyIterator();
    while (key_iter.next()) |cp| try sorted_code_points.append(arena, cp.*);

    std.mem.sort(u21, sorted_code_points.items, {}, struct {
        fn lessThan(_: void, a: u21, b: u21) bool {
            return a < b;
        }
    }.lessThan);

    for (sorted_code_points.items) |code_point| {
        const mappings = special_folding_map.get(code_point).?;

        try writer.print(
            "    .{{\n        .code_point = 0x{X},\n        .mappings = &.{{\n",
            .{code_point},
        );

        for (mappings.items) |mapping| {
            try writer.writeAll("            .{ .lower = ");
            try emitOptionalCpArray(writer, mapping.lower);
            try writer.writeAll(", .upper = ");
            try emitOptionalCpArray(writer, mapping.upper);
            try writer.writeAll(", .title = ");
            try emitOptionalCpArray(writer, mapping.title);

            try writer.writeAll(", .locale = ");
            if (mapping.locale) |l| try writer.print(".{s}", .{l}) else try writer.writeAll(".none");

            try writer.writeAll(", .condition = ");
            if (mapping.condition) |c| try writer.print(".{s}", .{c}) else try writer.writeAll(".none");

            try writer.writeAll(" },\n");
        }

        try writer.writeAll("        }\n    },\n");
    }

    try writer.writeAll(
        \\};
        \\// zig fmt: on
        \\
        \\fn compareEntry(needle: CodePoint, item: CaseMapEntry) std.math.Order {
        \\    return std.math.order(needle, item.code_point);
        \\}
        \\
        \\fn findEntry(code_point: CodePoint) ?CaseMapEntry {
        \\    return utils.binarySearchEntry(CaseMapEntry, &mappings_table, code_point, compareEntry);
        \\}
        \\
        \\pub fn lookup(comptime locale: Locale, comptime condition: Condition, code_point: CodePoint) ?Mapping {
        \\    const entry = findEntry(code_point) orelse return null;
        \\
        \\    for (entry.mappings) |mapping| {
        \\        if (mapping.locale == locale and mapping.condition == condition) return mapping;
        \\    }
        \\
        \\    if (comptime locale != .none and condition != .none) {
        \\        for (entry.mappings) |mapping| {
        \\            if (mapping.locale == locale and mapping.condition == .none) return mapping;
        \\        }
        \\    }
        \\
        \\    if (comptime condition != .none) {
        \\        for (entry.mappings) |mapping| {
        \\            if (mapping.locale == .none and mapping.condition == condition) return mapping;
        \\        }
        \\    }
        \\
        \\    for (entry.mappings) |mapping| {
        \\        if (mapping.locale == .none and mapping.condition == .none) return mapping;
        \\    }
        \\
        \\    return null;
        \\}
        \\
        \\pub inline fn lookupDefault(code_point: CodePoint) ?Mapping {
        \\    return lookup(.none, .none, code_point);
        \\}
        \\
        \\pub inline fn lookupTurkish(code_point: CodePoint) ?Mapping {
        \\    return lookup(.tr, .none, code_point);
        \\}
        \\
        \\pub inline fn lookupAzeri(code_point: CodePoint) ?Mapping {
        \\    return lookup(.az, .none, code_point);
        \\}
        \\
        \\pub inline fn lookupLithuanian(code_point: CodePoint) ?Mapping {
        \\    return lookup(.lt, .none, code_point);
        \\}
        \\
        \\pub inline fn lookupFinalSigma(code_point: CodePoint) ?Mapping {
        \\    return lookup(.none, .final_sigma, code_point);
        \\}
    );

    try file_writer.flush();
    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn emitRangePredicate(writer: *std.Io.Writer, arena: std.mem.Allocator, normalized_name: []const u8) !void {
    const fn_name = try normalizeFnName(arena, normalized_name);
    const head: u8 = std.ascii.toUpper(fn_name[0]);
    try writer.print(
        \\pub inline fn is{c}{s}(cp: CodePoint) bool {{
        \\    return utils.containsInRange(Range, CodePoint, "start", "end", &{s}_ranges, cp);
        \\}}
        \\
        \\
    , .{ head, fn_name[1..], normalized_name });
}

fn emitPagePredicate(writer: *std.Io.Writer, arena: std.mem.Allocator, normalized_name: []const u8) !void {
    const fn_name = try normalizeFnName(arena, normalized_name);
    const head: u8 = std.ascii.toUpper(fn_name[0]);
    try writer.print(
        \\pub inline fn is{c}{s}(cp: CodePoint) bool {{
        \\    if (cp > 0x10FFFF) return false;
        \\    const page = {s}_level1[cp >> 8];
        \\    return {s}_level2[page][cp & 0xFF];
        \\}}
        \\
        \\
    , .{ head, fn_name[1..], normalized_name, normalized_name });
}

fn generatePropList(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();
    var file = try dir.createFile(io, file_name, .{ .truncate = true, .permissions = .default_file });
    defer file.close(io);
    const buf = try arena.alloc(u8, 4096);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    var split_lines = std.mem.splitScalar(u8, data, '\n');

    var tables: std.StringHashMapUnmanaged(struct {
        normalized_name: []const u8,
        ranges: std.ArrayList(RangeType) = .empty,
    }) = .empty;

    line_loop: while (split_lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue :line_loop;

        var split_comments = std.mem.splitScalar(u8, line, '#');
        const tokens_raw = split_comments.next() orelse continue :line_loop;
        var tokens_iter = std.mem.splitScalar(u8, tokens_raw, ';');

        const code_points_raw = tokens_iter.next() orelse @panic("code point not found");
        const property_name_raw = tokens_iter.next() orelse @panic("property name not found");

        const entry = try tables.getOrPut(arena, property_name_raw);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{ .normalized_name = try normalizeKey(arena, property_name_raw) };
        }

        const code_point_raw_trimmed = std.mem.trim(u8, code_points_raw, " ");
        var code_points_tokens = std.mem.splitSequence(u8, code_point_raw_trimmed, "..");

        const start = try std.fmt.parseInt(u21, code_points_tokens.next() orelse @panic("code point start not found"), 16);
        const end = if (code_points_tokens.next()) |end_token| try std.fmt.parseInt(u21, end_token, 16) else start;

        try entry.value_ptr.ranges.append(arena, .{ .start = start, .end = end });
    }

    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
        \\
        \\const CodePoint = @import("encoding").CodePoint;
        \\const utils = @import("utils");
        \\
        \\const Range = struct { start: CodePoint, end: CodePoint };
        \\
        \\
    );

    var tables_iter = tables.valueIterator();
    table_generator: while (tables_iter.next()) |table| {
        // Small property: emit a sorted range list + linear/binary-search
        // predicate. Page tables only pay off above this threshold.
        if (table.ranges.items.len <= 256) {
            std.mem.sort(RangeType, table.ranges.items, {}, struct {
                fn lessThan(_: void, a: RangeType, b: RangeType) bool {
                    return a.start < b.start;
                }
            }.lessThan);

            try writer.print("//zig fmt: off\nconst {s}_ranges = [_]Range {{", .{table.normalized_name});
            for (table.ranges.items, 0..) |range, n| {
                if (n % 4 == 0) try writer.writeAll("\n    ");
                try writer.print(".{{ .start = 0x{X}, .end = 0x{X} }},", .{ range.start, range.end });
                if (n + 1 != table.ranges.items.len) try writer.writeAll(" ");
            }
            try writer.writeAll("\n};\n//zig fmt: on\n\n");

            try emitRangePredicate(writer, arena, table.normalized_name);
            continue :table_generator;
        }

        const values = try arena.alloc(bool, 0x110000);
        @memset(values, false);

        for (table.ranges.items) |range| {
            var cp = range.start;
            while (cp <= range.end) : (cp += 1) values[cp] = true;
        }

        const pt = try buildPageTable(bool, arena, values, false);

        try emitLevel1(writer, table.normalized_name, pt.level1);

        try writer.print("//zig fmt: off\nconst {s}_level2 = [_][256]bool {{\n", .{table.normalized_name});
        for (pt.unique_pages) |page| {
            try writer.writeAll("    .{\n        ");
            for (page, 0..) |val, j| {
                try writer.print("{},", .{val});
                try writePageItemSep(writer, j, page.len);
            }
            try writer.writeAll("\n    },\n");
        }
        try writer.writeAll("};\n//zig fmt: on\n\n");

        try emitPagePredicate(writer, arena, table.normalized_name);
    }

    try file_writer.flush();
    try saveUCDFile(arena, io, &dir, data, url, buf);
}

// ============================================================================
// Generators that delegate entirely to emitEnumPageTable
// ============================================================================

/// Common scaffolding for the file-per-property generators: open the output
/// file, parse the standard `<range> ; <label>` UCD shape, emit the file
/// header + enum + page table, save the upstream fixture. `default_variant`
/// is the snake_case enum variant assigned value 0 (matches each file's
/// `@missing` line: e.g. Word_Break defaults to Other, Line_Break to XX).
fn generateSimpleEnumProperty(
    arena: std.mem.Allocator,
    io: std.Io,
    data: []const u8,
    url: []const u8,
    file_name: []const u8,
    enum_name: []const u8,
    table_prefix: []const u8,
    default_variant: []const u8,
    lookup_fn_name: []const u8,
) !void {
    var dir: std.Io.Dir = .cwd();
    var file = try dir.createFile(io, file_name, .{ .truncate = true, .permissions = .default_file });
    defer file.close(io);
    const buf = try arena.alloc(u8, 4096);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    var labels = try parseSemicolonRangeFile(arena, data);
    const properties = try labelMapToProperties(arena, &labels);

    try writer.writeAll(generated_file_header);
    try emitEnumPageTable(arena, writer, properties, enum_name, table_prefix, default_variant, lookup_fn_name);

    try file_writer.flush();
    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn generateGraphemeBreakProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    return generateSimpleEnumProperty(arena, io, data, url, file_name, "GraphemeBreakProperty", "grapheme_break", "none", "graphemeBreakProperty");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
/// Shape: `<range> ; <property>` where property is one of Emoji,
/// Emoji_Presentation, Emoji_Modifier, Emoji_Modifier_Base, Emoji_Component,
/// Extended_Pictographic. The format is identical to PropList.txt — `<range> ;
/// <Label> # comment` — so we delegate to the prop_list generator. It already
/// emits one `is{PascalCase}` predicate per unique label, picking range-list
/// vs 2-level page table by range count.
fn generateEmojiData(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    return generatePropList(arena, io, data, url, file_name);
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/WordBreakProperty.txt
fn generateWordBreakProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    return generateSimpleEnumProperty(arena, io, data, url, file_name, "WordBreakProperty", "word_break", "other", "wordBreakProperty");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/SentenceBreakProperty.txt
fn generateSentenceBreakProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    return generateSimpleEnumProperty(arena, io, data, url, file_name, "SentenceBreakProperty", "sentence_break", "other", "sentenceBreakProperty");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/LineBreak.txt
/// Default `xx` matches the file's @missing line (Unknown). UAX #14
/// pair-table logic on top of this is a separate algorithm module; this
/// generator only emits the per-codepoint property.
fn generateLineBreak(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    return generateSimpleEnumProperty(arena, io, data, url, file_name, "LineBreak", "line_break", "xx", "lineBreak");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/EastAsianWidth.txt
/// Default `n` (Neutral) matches the file's @missing line. `terminalColumnWidth`
/// lives in the consumer module because it needs `general_category`.
fn generateEastAsianWidth(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    return generateSimpleEnumProperty(arena, io, data, url, file_name, "EastAsianWidth", "east_asian_width", "n", "eastAsianWidth");
}

// ----- Tier 2: normalization ------------------------------------------------

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/DerivedNormalizationProps.txt
/// Shape: same `<range> ; <property> [; <value>]` style as DerivedCoreProperties,
/// but several properties carry a tri-state value (Yes/No/Maybe) — NFC_QC,
/// NFD_QC, NFKC_QC, NFKD_QC — not a plain bool.
fn generateDerivedNormalizationProps(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateDerivedNormalizationProps");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/CompositionExclusions.txt
fn generateCompositionExclusions(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateCompositionExclusions");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/NormalizationTest.txt
/// NOT a code generator — this is the conformance fixture for NFC/NFD/NFKC/NFKD.
fn generateNormalizationTestFixture(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateNormalizationTestFixture (download + save only, no Zig output)");
}

/// Generic "download-only" generator: just persist the upstream UCD file
/// into `ucd/` for use as a test fixture. No Zig source is emitted. Used
/// for the UAX #14 / UAX #29 segmentation conformance fixtures.
fn saveUCDFixtureOnly(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = file_name;
    var dir: std.Io.Dir = .cwd();
    var buf: [4096]u8 = undefined;
    try saveUCDFile(arena, io, &dir, data, url, &buf);
}

// ----- Tier 3: script & bidi ------------------------------------------------

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/Scripts.txt
fn generateScripts(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateScripts");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/ScriptExtensions.txt
fn generateScriptExtensions(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateScriptExtensions (depends on generateScripts)");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/BidiBrackets.txt
fn generateBidiBrackets(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateBidiBrackets");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/BidiMirroring.txt
fn generateBidiMirroring(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateBidiMirroring");
}

// ----- Tier 4: numeric & metadata -------------------------------------------

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedNumericType.txt
fn generateDerivedNumericType(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateDerivedNumericType");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedNumericValues.txt
fn generateDerivedNumericValues(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateDerivedNumericValues");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/Blocks.txt
fn generateBlocks(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateBlocks");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/HangulSyllableType.txt
fn generateHangulSyllableType(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateHangulSyllableType");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/DerivedAge.txt
fn generateDerivedAge(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateDerivedAge");
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena;
    const arena_allocator = arena.allocator();
    const io = init.io;

    const clock: std.Io.Clock = .real;
    const start = clock.now(io);

    var max_memory: u64 = 0;

    const generators = [_]struct {
        file_name: []const u8,
        url: []const u8,
        generatorFn: *const fn (std.mem.Allocator, std.Io, data: []const u8, url: []const u8, file_name: []const u8) anyerror!void,
    }{
        .{
            .file_name = "src/unicode/generated/unicode_data.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt",
            .generatorFn = generateUnicodeData,
        },
        .{
            .file_name = "src/unicode/properties/generated/derived_core_properties.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/DerivedCoreProperties.txt",
            .generatorFn = generateDerivedCoreProperty,
        },
        .{
            .file_name = "src/unicode/casing/generated/case_folding.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/CaseFolding.txt",
            .generatorFn = generateCaseFolding,
        },
        .{
            .file_name = "src/unicode/casing/generated/special_casing.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/SpecialCasing.txt",
            .generatorFn = generateSpecialCasing,
        },
        .{
            .file_name = "src/unicode/properties/generated/prop_list.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/PropList.txt",
            .generatorFn = generatePropList,
        },
        .{
            .file_name = "src/unicode/segmentation/generated/grapheme_break.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/GraphemeBreakProperty.txt",
            .generatorFn = generateGraphemeBreakProperty,
        },
        .{
            .file_name = "src/unicode/segmentation/generated/emoji_data.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt",
            .generatorFn = generateEmojiData,
        },
        .{
            .file_name = "src/unicode/segmentation/generated/word_break.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/WordBreakProperty.txt",
            .generatorFn = generateWordBreakProperty,
        },
        .{
            .file_name = "src/unicode/segmentation/generated/sentence_break.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/SentenceBreakProperty.txt",
            .generatorFn = generateSentenceBreakProperty,
        },
        .{
            .file_name = "src/unicode/segmentation/generated/line_break.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/LineBreak.txt",
            .generatorFn = generateLineBreak,
        },
        .{
            .file_name = "src/unicode/width/generated/east_asian_width.zig",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/EastAsianWidth.txt",
            .generatorFn = generateEastAsianWidth,
        },

        // ----- Test fixtures (download-only; no Zig source emitted) -----
        // These are parsed at test time by `src/unicode/tests/ucd_conformance.zig`
        // to validate the segmentation/line-break algorithms against the
        // upstream Unicode reference data. The `file_name` field is unused
        // for these — the saved location is always `ucd/<basename-of-url>`.
        .{
            .file_name = "ucd/GraphemeBreakTest.txt",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/GraphemeBreakTest.txt",
            .generatorFn = saveUCDFixtureOnly,
        },
        .{
            .file_name = "ucd/WordBreakTest.txt",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/WordBreakTest.txt",
            .generatorFn = saveUCDFixtureOnly,
        },
        .{
            .file_name = "ucd/SentenceBreakTest.txt",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/SentenceBreakTest.txt",
            .generatorFn = saveUCDFixtureOnly,
        },
        .{
            .file_name = "ucd/LineBreakTest.txt",
            .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/LineBreakTest.txt",
            .generatorFn = saveUCDFixtureOnly,
        },

        // ----- Tier 2: normalization -----
        // .{
        //     .file_name = "src/unicode/normalization/generated/derived_normalization_props.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/DerivedNormalizationProps.txt",
        //     .generatorFn = generateDerivedNormalizationProps,
        // },
        // .{
        //     .file_name = "src/unicode/normalization/generated/composition_exclusions.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/CompositionExclusions.txt",
        //     .generatorFn = generateCompositionExclusions,
        // },
        // .{
        //     .file_name = "ucd/NormalizationTest.txt", // fixture only, not Zig output
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/NormalizationTest.txt",
        //     .generatorFn = generateNormalizationTestFixture,
        // },

        // ----- Tier 3: script & bidi -----
        // .{
        //     .file_name = "src/unicode/scripts/generated/scripts.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/Scripts.txt",
        //     .generatorFn = generateScripts,
        // },
        // .{
        //     .file_name = "src/unicode/scripts/generated/script_extensions.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/ScriptExtensions.txt",
        //     .generatorFn = generateScriptExtensions,
        // },
        // .{
        //     .file_name = "src/unicode/bidi/generated/bidi_brackets.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/BidiBrackets.txt",
        //     .generatorFn = generateBidiBrackets,
        // },
        // .{
        //     .file_name = "src/unicode/bidi/generated/bidi_mirroring.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/BidiMirroring.txt",
        //     .generatorFn = generateBidiMirroring,
        // },

        // ----- Tier 4: numeric & metadata -----
        // .{
        //     .file_name = "src/unicode/numeric/generated/numeric_type.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedNumericType.txt",
        //     .generatorFn = generateDerivedNumericType,
        // },
        // .{
        //     .file_name = "src/unicode/numeric/generated/numeric_values.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedNumericValues.txt",
        //     .generatorFn = generateDerivedNumericValues,
        // },
        // .{
        //     .file_name = "src/unicode/blocks/generated/blocks.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/Blocks.txt",
        //     .generatorFn = generateBlocks,
        // },
        // .{
        //     .file_name = "src/unicode/hangul/generated/hangul_syllable_type.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/HangulSyllableType.txt",
        //     .generatorFn = generateHangulSyllableType,
        // },
        // .{
        //     .file_name = "src/unicode/age/generated/derived_age.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/DerivedAge.txt",
        //     .generatorFn = generateDerivedAge,
        // },
    };

    for (generators) |gen| {
        const local_timer_start = clock.now(io);

        var allocated_writer: std.Io.Writer.Allocating = .init(arena_allocator);
        try allocated_writer.ensureTotalCapacity(1024 * 1024);

        try downloadFileToPath(arena_allocator, io, &allocated_writer.writer, gen.url);

        const download_timer_end = clock.now(io);

        try gen.generatorFn(arena_allocator, io, allocated_writer.written(), gen.url, gen.file_name);

        max_memory = @max(@as(u64, arena.queryCapacity()), max_memory);

        const local_timer_end = clock.now(io);

        const file_name = extractFileNameFromPath(gen.url);

        std.debug.print("generating file {s}, took for download: {}ms, took to generate: {}ms\n", .{
            file_name.file_name,
            download_timer_end.toMilliseconds() - local_timer_start.toMilliseconds(),
            local_timer_end.toMilliseconds() - download_timer_end.toMilliseconds(),
        });

        _ = arena.reset(.{ .retain_with_limit = 1024 * 1024 * 4 });
    }

    const end = clock.now(io);

    std.debug.print("\n\ngenerate command took: {}ms, peak memory: {}MiB\n", .{ end.toMilliseconds() - start.toMilliseconds(), @as(f64, @floatFromInt(max_memory / (1024 * 1024))) });
}
