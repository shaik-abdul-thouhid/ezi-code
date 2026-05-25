const std = @import("std");
const utils = @import("utils/root.zig");

const every = utils.every;

const unicode_types = @import("unicode/types.zig");
const CanonicalCombiningClass = unicode_types.CanonicalCombiningClass;

const some = @import("utils/helpers.zig").some;

fn downloadFileToPath(allocator: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer, url: []const u8) !void {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    const uri: std.Uri = try .parse(url);

    _ = try client.fetch(.{ .location = .{ .uri = uri }, .response_writer = writer });
}

fn extractFileNameFromPath(path: []const u8) []const u8 {
    if (path.len == 0) return "";

    var split_iter = std.mem.splitScalar(u8, path, '/');

    while (split_iter.next()) |path_section| {
        if (split_iter.peek() == null) {
            return path_section;
        }
    }

    return "";
}

const RangeType = struct { start: u21, end: u21 };

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
                    if (!prev and idx - 1 != 0) {
                        try slice.append(allocator, '_');
                    }
                }
                try slice.append(allocator, c + 32);
            },
            'a'...'z' => {
                try slice.append(allocator, c);
            },
            else => {},
        }
    }

    return slice.toOwnedSlice(allocator);
}

// convert any pattern to camelCased
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
            else => {
                if (output_started) word_start = true;
            },
        }
    }

    return slice.toOwnedSlice(allocator);
}

fn saveUCDFile(arena: std.mem.Allocator, io: std.Io, dir: *std.Io.Dir, data: []const u8, url: []const u8, buf: []u8) !void {
    const ucd_file_name: []const u8 = extractFileNameFromPath(url);

    const ucd_file = try dir.createFile(io, try std.fmt.allocPrint(arena, "ucd/{s}", .{ucd_file_name}), .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer ucd_file.close(io);

    var ucd_file_writer = ucd_file.writer(io, buf);
    const ucd_writer = &ucd_file_writer.interface;
    defer ucd_writer.flush() catch {};

    try ucd_writer.writeAll(data);
}

const ucd_folder = "ucd";

fn generateUnicodeData(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();

    var file = try dir.createFile(io, file_name, .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer file.close(io);

    const buf = try arena.alloc(u8, 1024 * 4);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    var combining_buffer: std.ArrayList(u8) = .empty;

    var lowercase_mapping_range: std.ArrayList(u8) = .empty;
    var lowercase_range_start: ?u21 = null;
    var lowercase_range_end: ?u21 = null;
    var lowercase_current_difference: i32 = 0;

    var uppercase_mapping_range: std.ArrayList(u8) = .empty;
    var uppercase_range_start: ?u21 = null;
    var uppercase_range_end: ?u21 = null;
    var uppercase_current_difference: i32 = 0;

    var titlecase_mapping_range: std.ArrayList(u8) = .empty;
    var titlecase_range_start: ?u21 = null;
    var titlecase_range_end: ?u21 = null;
    var titlecase_current_difference: i32 = 0;

    var split_iter = std.mem.splitScalar(u8, data, '\n');

    var i: usize = 0;
    // For GeneralCategory two-level page table generation:
    var category_values = std.ArrayList([]const u8).empty;
    // For BidiClass two-level page table generation:
    var bidi_values = std.ArrayList([]const u8).empty;

    var combining_start_range: ?u21 = null;
    var combining_end_range: ?u21 = null;
    var current_combining_class: ?[]const u8 = null;

    // For BidiClass page-table generation
    var next_bidi_cp: u21 = 0;

    // Build the GeneralCategory for every codepoint (0..=0x10FFFF)
    // We parse UnicodeData.txt, which is sparse, so fill gaps with "unassigned"
    var pending_range_start: ?u21 = null;
    var pending_range_category: ?[]const u8 = null;
    var pending_range_bidi: ?[]const u8 = null;
    var next_cp: u21 = 0;
    split_iter.reset();
    while (split_iter.next()) |line| : (i += 1) {
        if (line.len == 0) {
            continue;
        }

        var field_iter = std.mem.splitScalar(u8, line, ';');

        const code_point = field_iter.next() orelse continue;
        const range_hint = field_iter.next() orelse continue;
        const category = field_iter.next() orelse continue;
        const combining_class = field_iter.next() orelse continue;
        const bidi_class = field_iter.next() orelse continue;

        // UnicodeData.txt fields:
        // 5 Decomposition_Mapping
        // 6 Decimal_Digit_Value
        // 7 Digit_Value
        // 8 Numeric_Value
        // 9 Bidi_Mirrored
        // 10 Unicode_1_Name
        // 11 ISO_Comment
        _ = field_iter.next();
        _ = field_iter.next();
        _ = field_iter.next();
        _ = field_iter.next();
        _ = field_iter.next();
        _ = field_iter.next();
        _ = field_iter.next();

        const uppercase_mapping = field_iter.next() orelse "";
        const lowercase_mapping = field_iter.next() orelse "";
        const titlecase_mapping = field_iter.next() orelse "";
        const cp = try std.fmt.parseInt(u21, code_point, 16);

        const category_name = blk: {
            if (std.mem.eql(u8, category, "Lu")) break :blk "uppercase_letter";
            if (std.mem.eql(u8, category, "Ll")) break :blk "lowercase_letter";
            if (std.mem.eql(u8, category, "Lt")) break :blk "titlecase_letter";
            if (std.mem.eql(u8, category, "Lm")) break :blk "modifier_letter";
            if (std.mem.eql(u8, category, "Lo")) break :blk "other_letter";
            if (std.mem.eql(u8, category, "Mn")) break :blk "non_spacing_mark";
            if (std.mem.eql(u8, category, "Mc")) break :blk "spacing_mark";
            if (std.mem.eql(u8, category, "Me")) break :blk "enclosing_mark";
            if (std.mem.eql(u8, category, "Nd")) break :blk "decimal_number";
            if (std.mem.eql(u8, category, "Nl")) break :blk "letter_number";
            if (std.mem.eql(u8, category, "No")) break :blk "other_number";
            if (std.mem.eql(u8, category, "Pc")) break :blk "connector_punctuation";
            if (std.mem.eql(u8, category, "Pd")) break :blk "dash_punctuation";
            if (std.mem.eql(u8, category, "Ps")) break :blk "open_punctuation";
            if (std.mem.eql(u8, category, "Pe")) break :blk "close_punctuation";
            if (std.mem.eql(u8, category, "Pi")) break :blk "initial_punctuation";
            if (std.mem.eql(u8, category, "Pf")) break :blk "final_punctuation";
            if (std.mem.eql(u8, category, "Po")) break :blk "other_punctuation";
            if (std.mem.eql(u8, category, "Sm")) break :blk "math_symbol";
            if (std.mem.eql(u8, category, "Sc")) break :blk "currency_symbol";
            if (std.mem.eql(u8, category, "Sk")) break :blk "modifier_symbol";
            if (std.mem.eql(u8, category, "So")) break :blk "other_symbol";
            if (std.mem.eql(u8, category, "Zs")) break :blk "space_separator";
            if (std.mem.eql(u8, category, "Zl")) break :blk "line_separator";
            if (std.mem.eql(u8, category, "Zp")) break :blk "paragraph_separator";
            if (std.mem.eql(u8, category, "Cc")) break :blk "control";
            if (std.mem.eql(u8, category, "Cf")) break :blk "format";
            if (std.mem.eql(u8, category, "Cs")) break :blk "surrogate";
            if (std.mem.eql(u8, category, "Co")) break :blk "private_use";
            break :blk "unassigned";
        };

        const bidi_name = blk: {
            if (std.mem.eql(u8, bidi_class, "L")) break :blk "left_to_right";
            if (std.mem.eql(u8, bidi_class, "R")) break :blk "right_to_left";
            if (std.mem.eql(u8, bidi_class, "AL")) break :blk "arabic_letter";
            if (std.mem.eql(u8, bidi_class, "EN")) break :blk "european_number";
            if (std.mem.eql(u8, bidi_class, "ES")) break :blk "european_separator";
            if (std.mem.eql(u8, bidi_class, "ET")) break :blk "european_terminator";
            if (std.mem.eql(u8, bidi_class, "AN")) break :blk "arabic_number";
            if (std.mem.eql(u8, bidi_class, "CS")) break :blk "common_separator";
            if (std.mem.eql(u8, bidi_class, "NSM")) break :blk "non_spacing_mark";
            if (std.mem.eql(u8, bidi_class, "BN")) break :blk "boundary_neutral";
            if (std.mem.eql(u8, bidi_class, "B")) break :blk "paragraph_separator";
            if (std.mem.eql(u8, bidi_class, "S")) break :blk "segment_separator";
            if (std.mem.eql(u8, bidi_class, "WS")) break :blk "whitespace";
            if (std.mem.eql(u8, bidi_class, "ON")) break :blk "other_neutral";
            if (std.mem.eql(u8, bidi_class, "LRE")) break :blk "left_to_right_embedding";
            if (std.mem.eql(u8, bidi_class, "LRO")) break :blk "left_to_right_override";
            if (std.mem.eql(u8, bidi_class, "RLE")) break :blk "right_to_left_embedding";
            if (std.mem.eql(u8, bidi_class, "RLO")) break :blk "right_to_left_override";
            if (std.mem.eql(u8, bidi_class, "PDF")) break :blk "pop_directional_format";
            if (std.mem.eql(u8, bidi_class, "LRI")) break :blk "left_to_right_isolate";
            if (std.mem.eql(u8, bidi_class, "RLI")) break :blk "right_to_left_isolate";
            if (std.mem.eql(u8, bidi_class, "FSI")) break :blk "first_strong_isolate";
            break :blk "pop_directional_isolate";
        };

        // UnicodeData.txt <..., First> / <..., Last> range handling
        if (std.mem.endsWith(u8, range_hint, ", First>")) {
            pending_range_start = cp;
            pending_range_category = category_name;
            pending_range_bidi = bidi_name;
            continue;
        }

        if (std.mem.endsWith(u8, range_hint, ", Last>")) {
            const start_cp = pending_range_start orelse {
                return error.InvalidUnicodeRange;
            };
            const range_category = pending_range_category.?;
            const range_bidi = pending_range_bidi.?;

            while (next_cp < start_cp) : (next_cp += 1) {
                try category_values.append(arena, "unassigned");
            }
            while (next_bidi_cp < start_cp) : (next_bidi_cp += 1) {
                try bidi_values.append(arena, "left_to_right");
            }
            var range_cp = start_cp;
            while (range_cp <= cp) : (range_cp += 1) {
                try category_values.append(arena, range_category);
                try bidi_values.append(arena, range_bidi);
            }
            next_cp = cp + 1;
            next_bidi_cp = cp + 1;
            pending_range_start = null;
            pending_range_category = null;
            pending_range_bidi = null;
            continue;
        }

        // Fill any gaps before cp with "unassigned"
        while (next_cp < cp) : (next_cp += 1) {
            try category_values.append(arena, "unassigned");
        }
        try category_values.append(arena, category_name);
        next_cp = cp + 1;

        // Combining class range logic
        if (!std.mem.eql(u8, combining_class, "0")) {
            if (current_combining_class == null) {
                combining_start_range = cp;
                combining_end_range = cp;
                current_combining_class = combining_class;
            } else if (std.mem.eql(u8, current_combining_class.?, combining_class) and cp == combining_end_range.? + 1) {
                combining_end_range = cp;
            } else {
                const ccc = try std.fmt.parseInt(u8, current_combining_class.?, 10);

                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .ccc = {any} }},\n",
                    .{ combining_start_range.?, combining_end_range.?, CanonicalCombiningClass.fromU8(ccc) },
                );

                try combining_buffer.appendSlice(arena, p);

                combining_start_range = cp;
                combining_end_range = cp;
                current_combining_class = combining_class;
            }
        } else if (current_combining_class != null) {
            const ccc = try std.fmt.parseInt(u8, current_combining_class.?, 10);

            const p = try std.fmt.allocPrint(
                arena,
                "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .ccc = {any} }},\n",
                .{ combining_start_range.?, combining_end_range.?, CanonicalCombiningClass.fromU8(ccc) },
            );

            try combining_buffer.appendSlice(arena, p);

            combining_start_range = null;
            combining_end_range = null;
            current_combining_class = null;
        }

        // Fill any gaps before cp with "left_to_right"
        while (next_bidi_cp < cp) : (next_bidi_cp += 1) {
            try bidi_values.append(arena, "left_to_right");
        }
        try bidi_values.append(arena, bidi_name);
        next_bidi_cp = cp + 1;

        if (uppercase_mapping.len != 0) {
            const cp_num_from = cp;
            const cp_num_to = try std.fmt.parseInt(u21, uppercase_mapping, 16);
            const difference = @as(i32, @intCast(cp_num_to)) - @as(i32, @intCast(cp_num_from));

            if (uppercase_range_start == null or uppercase_range_end == null or uppercase_current_difference == 0) {
                uppercase_range_start = cp;
                uppercase_range_end = cp;
                uppercase_current_difference = difference;
            } else if (uppercase_current_difference == difference and cp == uppercase_range_end.? + 1) {
                uppercase_range_end = cp;
            } else if (uppercase_current_difference != difference or cp != uppercase_range_end.? + 1) {
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
                    .{ uppercase_range_start.?, uppercase_range_end.?, uppercase_current_difference },
                );

                try uppercase_mapping_range.appendSlice(arena, p);

                uppercase_range_start = cp;
                uppercase_range_end = cp;
                uppercase_current_difference = difference;
            }
        }
        if (lowercase_mapping.len != 0) {
            const cp_num_from = cp;
            const cp_num_to = try std.fmt.parseInt(u21, lowercase_mapping, 16);
            const difference = @as(i32, @intCast(cp_num_to)) - @as(i32, @intCast(cp_num_from));

            if (lowercase_range_start == null or lowercase_range_end == null or lowercase_current_difference == 0) {
                lowercase_range_start = cp;
                lowercase_range_end = cp;
                lowercase_current_difference = difference;
            } else if (lowercase_current_difference == difference and cp == lowercase_range_end.? + 1) {
                lowercase_range_end = cp;
            } else if (lowercase_current_difference != difference or cp != lowercase_range_end.? + 1) {
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
                    .{ lowercase_range_start.?, lowercase_range_end.?, lowercase_current_difference },
                );

                try lowercase_mapping_range.appendSlice(arena, p);

                lowercase_range_start = cp;
                lowercase_range_end = cp;
                lowercase_current_difference = difference;
            }
        }
        if (titlecase_mapping.len != 0) {
            const cp_num_from = cp;
            const cp_num_to = try std.fmt.parseInt(u21, titlecase_mapping, 16);
            const difference = @as(i32, @intCast(cp_num_to)) - @as(i32, @intCast(cp_num_from));

            if (titlecase_range_start == null or titlecase_range_end == null or titlecase_current_difference == 0) {
                titlecase_range_start = cp;
                titlecase_range_end = cp;
                titlecase_current_difference = difference;
            } else if (titlecase_current_difference == difference and cp == titlecase_range_end.? + 1) {
                titlecase_range_end = cp;
            } else if (titlecase_current_difference != difference or cp != titlecase_range_end.? + 1) {
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
                    .{ titlecase_range_start.?, titlecase_range_end.?, titlecase_current_difference },
                );

                try titlecase_mapping_range.appendSlice(arena, p);

                titlecase_range_start = cp;
                titlecase_range_end = cp;
                titlecase_current_difference = difference;
            }
        }
    }

    // Fill any remaining codepoints with "unassigned"
    while (next_cp <= 0x10FFFF) : (next_cp += 1) {
        try category_values.append(arena, "unassigned");
    }

    // Fill any remaining codepoints with "left_to_right" for bidi
    while (next_bidi_cp <= 0x10FFFF) : (next_bidi_cp += 1) {
        try bidi_values.append(arena, "left_to_right");
    }

    // Build two-level page table
    const PAGE_BITS = 8;
    const PAGE_SIZE = 1 << PAGE_BITS;
    // const PAGE_COUNT = (0x10FFFF + PAGE_SIZE) >> PAGE_BITS;

    // Build unique pages and level1/level2 tables
    var unique_pages = std.ArrayList([]const []const u8).empty;
    // var unique_page_indices = std.ArrayList(usize).empty;
    var level1 = std.ArrayList(usize).empty;

    var page_map: std.AutoHashMapUnmanaged(u64, usize) = .empty;
    const page_buf = try arena.alloc([]const u8, PAGE_SIZE);

    var total_cps: usize = 0;
    while (total_cps < category_values.items.len) : (total_cps += PAGE_SIZE) {
        const page_start = total_cps;
        const page_end = @min(page_start + PAGE_SIZE, category_values.items.len);
        for (page_buf, 0..) |*slot, j| {
            const idx = page_start + j;
            if (idx < page_end) {
                slot.* = category_values.items[idx];
            } else {
                slot.* = "unassigned";
            }
        }
        // Hash the page for deduplication
        var hasher = std.hash.Wyhash.init(0);
        for (page_buf) |cat| {
            hasher.update(cat);
        }
        const page_hash = hasher.final();
        var found = false;
        var found_idx: usize = 0;
        if (page_map.get(page_hash)) |idx| {
            var same = true;
            for (unique_pages.items[idx], page_buf) |a, b| {
                if (!std.mem.eql(u8, a, b)) {
                    same = false;
                    break;
                }
            }
            if (same) {
                found = true;
                found_idx = idx;
            }
        }
        if (!found) {
            // Copy the page to arena and add to unique_pages
            const new_page = try arena.alloc([]const u8, PAGE_SIZE);
            for (page_buf, 0..) |cat, j| new_page[j] = cat;
            found_idx = unique_pages.items.len;
            try unique_pages.append(arena, new_page);
            try page_map.put(arena, page_hash, found_idx);
        }
        try level1.append(arena, found_idx);
    }

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
        \\pub const GeneralCategory = enum(u8) {
        \\    uppercase_letter,
        \\    lowercase_letter,
        \\    titlecase_letter,
        \\    modifier_letter,
        \\    other_letter,
        \\    non_spacing_mark,
        \\    spacing_mark,
        \\    enclosing_mark,
        \\    decimal_number,
        \\    letter_number,
        \\    other_number,
        \\    connector_punctuation,
        \\    dash_punctuation,
        \\    open_punctuation,
        \\    close_punctuation,
        \\    initial_punctuation,
        \\    final_punctuation,
        \\    other_punctuation,
        \\    math_symbol,
        \\    currency_symbol,
        \\    modifier_symbol,
        \\    other_symbol,
        \\    space_separator,
        \\    line_separator,
        \\    paragraph_separator,
        \\    control,
        \\    format,
        \\    surrogate,
        \\    private_use,
        \\    unassigned,
        \\};
        \\
        \\pub const BidiClass = enum(u8) {
        \\    left_to_right,
        \\    right_to_left,
        \\    arabic_letter,
        \\    european_number,
        \\    european_separator,
        \\    european_terminator,
        \\    arabic_number,
        \\    common_separator,
        \\    non_spacing_mark,
        \\    boundary_neutral,
        \\    paragraph_separator,
        \\    segment_separator,
        \\    whitespace,
        \\    other_neutral,
        \\    left_to_right_embedding,
        \\    left_to_right_override,
        \\    right_to_left_embedding,
        \\    right_to_left_override,
        \\    pop_directional_format,
        \\    left_to_right_isolate,
        \\    right_to_left_isolate,
        \\    first_strong_isolate,
        \\    pop_directional_isolate,
        \\};
        \\
        \\pub const CombiningClassEntry = struct {
        \\    range_start: CodePoint,
        \\    range_end: CodePoint,
        \\    ccc: CanonicalCombiningClass,
        \\};
        \\
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

    // Emit the tables
    try writer.writeAll("//zig fmt: off\nconst category_level1 = [_]u16 {");
    for (level1.items, 0..) |idx, n| {
        if (n % 12 == 0) try writer.writeAll("\n    ");
        try writer.print("{},", .{idx});
        if (n + 1 != level1.items.len) {
            try writer.writeAll(" ");
        }
    }
    try writer.writeAll("\n};\n//zig fmt: on\n\n");

    try writer.writeAll("//zig fmt: off\nconst category_level_2 = [_][256]GeneralCategory {\n");
    for (unique_pages.items) |page| {
        try writer.writeAll("    .{\n        ");
        for (page, 0..) |cat, j| {
            try writer.writeAll(".");
            try writer.writeAll(cat);
            try writer.writeAll(",");
            if ((j + 1) % 12 == 0 and (j + 1) != page.len) try writer.writeAll("\n        ");
        }
        try writer.writeAll("\n    },\n");
    }
    try writer.writeAll("};\n//zig fmt: on\n\n");

    try writer.writeAll(
        \\pub inline fn generalCategory(cp: CodePoint) GeneralCategory {
        \\    if (cp > 0x10FFFF) return .unassigned;
        \\    const page = category_level1[cp >> 8];
        \\    return category_level_2[page][cp & 0xFF];
        \\}
        \\
        \\
    );

    if (current_combining_class != null) {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .ccc = {s} }},\n",
            .{ combining_start_range.?, combining_end_range.?, current_combining_class.? },
        );

        try combining_buffer.appendSlice(arena, p);
    }

    try writer.writeAll("pub const combining_class_table = [_]CombiningClassEntry {\n");
    try writer.writeAll(combining_buffer.items);
    try writer.writeAll("};\n\n");

    // --- BidiClass two-level page table generation ---
    const bidi_PAGE_BITS = 8;
    const bidi_PAGE_SIZE = 1 << bidi_PAGE_BITS;
    var unique_bidi_pages = std.ArrayList([]const []const u8).empty;
    var bidi_level1_items = std.ArrayList(usize).empty;
    var bidi_page_map: std.AutoHashMapUnmanaged(u64, usize) = .empty;
    const bidi_page_buf = try arena.alloc([]const u8, bidi_PAGE_SIZE);
    var total_bidi_cps: usize = 0;
    while (total_bidi_cps < bidi_values.items.len) : (total_bidi_cps += bidi_PAGE_SIZE) {
        const page_start = total_bidi_cps;
        const page_end = @min(page_start + bidi_PAGE_SIZE, bidi_values.items.len);
        for (bidi_page_buf, 0..) |*slot, j| {
            const idx = page_start + j;
            if (idx < page_end) {
                slot.* = bidi_values.items[idx];
            } else {
                slot.* = "left_to_right";
            }
        }
        // Hash the page for deduplication
        var hasher = std.hash.Wyhash.init(0);
        for (bidi_page_buf) |cat| {
            hasher.update(cat);
        }
        const page_hash = hasher.final();
        var found = false;
        var found_idx: usize = 0;
        if (bidi_page_map.get(page_hash)) |idx| {
            var same = true;
            for (unique_bidi_pages.items[idx], bidi_page_buf) |a, b| {
                if (!std.mem.eql(u8, a, b)) {
                    same = false;
                    break;
                }
            }
            if (same) {
                found = true;
                found_idx = idx;
            }
        }
        if (!found) {
            const new_page = try arena.alloc([]const u8, bidi_PAGE_SIZE);
            for (bidi_page_buf, 0..) |cat, j| new_page[j] = cat;
            found_idx = unique_bidi_pages.items.len;
            try unique_bidi_pages.append(arena, new_page);
            try bidi_page_map.put(arena, page_hash, found_idx);
        }
        try bidi_level1_items.append(arena, found_idx);
    }

    // Emit the tables
    try writer.writeAll("//zig fmt: off\nconst bidi_level1 = [_]u16 {");
    for (bidi_level1_items.items, 0..) |idx, n| {
        if (n % 12 == 0) try writer.writeAll("\n    ");
        try writer.print("{},", .{idx});
        if (n + 1 != bidi_level1_items.items.len) {
            try writer.writeAll(" ");
        }
    }
    try writer.writeAll("\n};\n//zig fmt: on\n\n");

    try writer.writeAll("//zig fmt: off\nconst bidi_level_2 = [_][256]BidiClass {\n");
    for (unique_bidi_pages.items) |page| {
        try writer.writeAll("    .{\n        ");
        for (page, 0..) |cat, j| {
            try writer.writeAll(".");
            try writer.writeAll(cat);
            try writer.writeAll(",");
            if ((j + 1) % 12 == 0 and (j + 1) != page.len) try writer.writeAll("\n        ");
        }
        try writer.writeAll("\n    },\n");
    }
    try writer.writeAll("};\n//zig fmt: on\n\n");

    try writer.writeAll(
        \\pub inline fn bidiClass(cp: CodePoint) BidiClass {
        \\    const page = bidi_level1[cp >> 8];
        \\    return bidi_level_2[page][cp & 0xFF];
        \\}
        \\
        \\
    );

    if (lowercase_range_start != null) {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
            .{ lowercase_range_start.?, lowercase_range_end.?, lowercase_current_difference },
        );
        try lowercase_mapping_range.appendSlice(arena, p);
    }

    if (uppercase_range_start != null) {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
            .{ uppercase_range_start.?, uppercase_range_end.?, uppercase_current_difference },
        );
        try uppercase_mapping_range.appendSlice(arena, p);
    }

    if (titlecase_range_start != null) {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
            .{ titlecase_range_start.?, titlecase_range_end.?, titlecase_current_difference },
        );
        try titlecase_mapping_range.appendSlice(arena, p);
    }

    try writer.writeAll("pub const lowercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(lowercase_mapping_range.items);

    try writer.writeAll("};\n\npub const uppercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(uppercase_mapping_range.items);

    try writer.writeAll("};\n\npub const titlecase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(titlecase_mapping_range.items);

    try writer.writeAll("};\n");

    try file_writer.flush();

    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn generateDerivedCoreProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();

    var file = try dir.createFile(io, file_name, .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer file.close(io);

    const buf = try arena.alloc(u8, 1024 * 4);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    var total_keys: u8 = 0;

    // the raw labels like `Alphabetic`, `Grapheme_Extend`, `InCB; Extend`, etc
    // will be converted to `alphabetic`, `grapheme_extend`, `in_cb_extend`
    var derived_label_hash: std.StringHashMapUnmanaged(struct {
        index: u8,
        normalized_key: []u8,
        items: std.ArrayList(RangeType) = .empty,
    }) = .empty;

    var lines = std.mem.splitScalar(u8, data, '\n');

    loop: while (lines.next()) |line| {
        // skip empty and comment lines.
        if (line.len == 0 or line[0] == '#') {
            continue :loop;
        }

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

    // print keys and normalized keys
    var iter = derived_label_hash.valueIterator();

    while (iter.next()) |val| {
        sorted_normalize_keys[val.index] = val.normalized_key;
        sorted_property_ranges[val.index] = val.items.items;
    }

    // assert that the number of properties is less than 32.
    // for 32 bit mask.
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

    var i_min_max: usize = 1;

    while (i_min_max < sorted_property_ranges.len) : (i_min_max += 1) {
        if (sorted_property_ranges[i_min_max][0].start < min) {
            min = sorted_property_ranges[i_min_max][0].start;
        }

        if (sorted_property_ranges[i_min_max][sorted_property_ranges[i_min_max].len - 1].end > max) {
            max = sorted_property_ranges[i_min_max][sorted_property_ranges[i_min_max].len - 1].end;
        }
    }

    var code_point: u21 = min;

    while (some(usize, sorted_property_ranges, items_indices, predicate) and
        code_point <= max) : (code_point += 1)
    {
        var i: usize = 0;
        var current_mask: u32 = 0;

        inner_loop: while (i < sorted_property_ranges.len) {
            var idx = items_indices[i];
            const ranges = sorted_property_ranges[i];

            while (idx < ranges.len and code_point > ranges[idx].end) {
                idx += 1;
            }

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
                try final_result_table.append(arena, .{
                    .start = code_point,
                    .end = code_point,
                    .bitmask = current_mask,
                });
            }
        } else if (previous_bit_mask == current_mask and current_mask != 0) {
            final_result_table.items[final_result_table.items.len - 1].end = code_point;
        } else if (current_mask != 0) {
            try final_result_table.append(arena, .{
                .start = code_point,
                .end = code_point,
                .bitmask = current_mask,
            });
        }

        previous_bit_mask = current_mask;
    }

    // Expand merged ranges into dense bitmask array and build deduplicated 2-level page table.
    const PROPERTY_PAGE_BITS = 8;
    const PROPERTY_PAGE_SIZE = 1 << PROPERTY_PAGE_BITS;

    var property_values = try arena.alloc(u32, 0x110000);
    @memset(property_values, 0);

    for (final_result_table.items) |entry| {
        var cp = entry.start;
        while (cp <= entry.end) : (cp += 1) {
            property_values[cp] = entry.bitmask;
        }
    }

    var unique_property_pages = std.ArrayList([]const u32).empty;
    var property_level1_items = std.ArrayList(usize).empty;
    var property_page_map: std.AutoHashMapUnmanaged(u64, usize) = .empty;

    const property_page_buf = try arena.alloc(u32, PROPERTY_PAGE_SIZE);

    var total_property_cps: usize = 0;
    while (total_property_cps < property_values.len) : (total_property_cps += PROPERTY_PAGE_SIZE) {
        const page_start = total_property_cps;
        const page_end = @min(page_start + PROPERTY_PAGE_SIZE, property_values.len);

        for (property_page_buf, 0..) |*slot, j| {
            const idx = page_start + j;
            slot.* = if (idx < page_end) property_values[idx] else 0;
        }

        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.sliceAsBytes(property_page_buf));
        const page_hash = hasher.final();

        var found = false;
        var found_idx: usize = 0;

        if (property_page_map.get(page_hash)) |idx| {
            if (std.mem.eql(u32, unique_property_pages.items[idx], property_page_buf)) {
                found = true;
                found_idx = idx;
            }
        }

        if (!found) {
            const new_page = try arena.alloc(u32, PROPERTY_PAGE_SIZE);
            @memcpy(new_page, property_page_buf);

            found_idx = unique_property_pages.items.len;
            try unique_property_pages.append(arena, new_page);
            try property_page_map.put(arena, page_hash, found_idx);
        }

        try property_level1_items.append(arena, found_idx);
    }

    // Emit generated Zig file for property page table.
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

    for (sorted_normalize_keys, 0..) |key, idx| {
        try writer.print("    {s} = 1 << {},\n", .{ key, idx + 1 });
    }
    try writer.writeAll(
        \\};
        \\
    );

    // Emit property_level1 table
    try writer.writeAll("//zig fmt: off\nconst property_level1 = [_]u16 {");
    for (property_level1_items.items, 0..) |idx, n| {
        if (n % 12 == 0) try writer.writeAll("\n    ");
        try writer.print("{},", .{idx});
        if (n + 1 != property_level1_items.items.len) {
            try writer.writeAll(" ");
        }
    }
    try writer.writeAll("\n};\n//zig fmt: on\n\n");

    // Emit property_level2 table
    try writer.writeAll("//zig fmt: off\nconst property_level2 = [_][256]u32 {\n");
    for (unique_property_pages.items) |page| {
        try writer.writeAll("    .{\n        ");
        for (page, 0..) |val, j| {
            try writer.print("0x{X},", .{val});
            if ((j + 1) % 12 == 0 and (j + 1) != page.len)
                try writer.writeAll("\n        ")
            else if (j + 1 != page.len) try writer.writeAll(" ");
        }
        try writer.writeAll("\n    },\n");
    }
    try writer.writeAll("};\n//zig fmt: on\n\n");

    // Emit propertyMask() and codePointProperty() functions
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

    const ucd_file_name: []const u8 = extractFileNameFromPath(url);

    const ucd_file = try dir.createFile(io, try std.fmt.allocPrint(arena, "ucd/{s}", .{ucd_file_name}), .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer ucd_file.close(io);

    var ucd_file_writer = ucd_file.writer(io, buf);
    const ucd_writer = &ucd_file_writer.interface;
    defer ucd_writer.flush() catch {};

    try ucd_writer.writeAll(data);
}

fn generateCaseFolding(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();

    var file = try dir.createFile(io, file_name, .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer file.close(io);

    const buf = try arena.alloc(u8, 4096);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    // --- Begin new implementation ---
    // 1. Define FoldEntry
    const FoldEntry = struct {
        from: u21,
        to: []const u21,
    };

    // 2. Create four arrays
    var common_simple = std.ArrayList(FoldEntry).empty;
    var common_full = std.ArrayList(FoldEntry).empty;
    var turkic_simple = std.ArrayList(FoldEntry).empty;
    var turkic_full = std.ArrayList(FoldEntry).empty;

    // 3. Parse every non-comment line of CaseFolding.txt.
    var split_lines = std.mem.splitScalar(u8, data, '\n');
    line_loop: while (split_lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue :line_loop;

        // 4. For each record:
        // - Parse source code point.
        // - Parse fold status (C,S,F,T).
        // - Parse fold sequence into a heap allocated slice.
        var semi = std.mem.splitScalar(u8, trimmed, ';');
        const src_raw = semi.next() orelse continue :line_loop;
        const status_raw = semi.next() orelse continue :line_loop;
        const mapping_raw = semi.next() orelse continue :line_loop;
        // Ignore any comment after the mapping

        const from = try std.fmt.parseInt(u21, std.mem.trim(u8, src_raw, " \t"), 16);
        const status = std.mem.trim(u8, status_raw, " \t");
        const mapping_str = std.mem.trim(u8, mapping_raw, " \t");

        // Parse mapping_str as 1 or more hex codepoints
        var mapping_buf = std.ArrayList(u21).empty;
        var mapping_split = std.mem.splitScalar(u8, mapping_str, ' ');
        while (mapping_split.next()) |cpstr| {
            const cp_trim = std.mem.trim(u8, cpstr, " \t");
            if (cp_trim.len == 0) continue;
            try mapping_buf.append(arena, try std.fmt.parseInt(u21, cp_trim, 16));
        }
        const to = try arena.dupe(u21, mapping_buf.items);

        // 5. Route entries
        if (std.mem.eql(u8, status, "C")) {
            try common_simple.append(arena, FoldEntry{ .from = from, .to = to });
            try common_full.append(arena, FoldEntry{ .from = from, .to = to });
        } else if (std.mem.eql(u8, status, "S")) {
            try common_simple.append(arena, FoldEntry{ .from = from, .to = to });
        } else if (std.mem.eql(u8, status, "F")) {
            try common_full.append(arena, FoldEntry{ .from = from, .to = to });
        } else if (std.mem.eql(u8, status, "T")) {
            try turkic_simple.append(arena, FoldEntry{ .from = from, .to = to });
            try turkic_full.append(arena, FoldEntry{ .from = from, .to = to });
        }
    }

    // 7. Write the header
    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
        \\
        \\const CodePoint = @import("encoding").CodePoint;
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
        \\
    );

    // 8. Add a local helper emitTable
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

    // 9. Emit the four tables
    try emitTable(writer, "common_simple_table", common_simple.items);
    try emitTable(writer, "common_full_table", common_full.items);
    try emitTable(writer, "turkic_simple_table", turkic_simple.items);
    try emitTable(writer, "turkic_full_table", turkic_full.items);

    try writer.writeAll(
        \\fn lookupTable(comptime mode: CaseFoldingMode, comptime table: []const FoldEntry, code_point: CodePoint) ?FoldResult(mode) {
        \\    var left: usize = 0;
        \\    var right: usize = table.len;
        \\
        \\    while (left < right) {
        \\        const mid = left + (right - left) / 2;
        \\        const entry = table[mid];
        \\
        \\        if (code_point < entry.from) {
        \\            right = mid;
        \\        } else if (code_point > entry.from) {
        \\            left = mid + 1;
        \\        } else {
        \\            return if (FoldResult(mode) == CodePoint)
        \\                entry.to[0]
        \\            else entry.to;
        \\        }
        \\    }
        \\
        \\    return null;
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

    // 10. Preserve file_writer.flush
    try file_writer.flush();

    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn generateSpecialCasing(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();

    var file = try dir.createFile(io, file_name, .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer file.close(io);

    const buf = try arena.alloc(u8, 4096);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;

    var split_lines = std.mem.splitScalar(u8, data, '\n');

    var special_folding_map: std.AutoHashMapUnmanaged(
        u21,
        std.ArrayList(struct {
            lower: ?[]u21 = null,
            upper: ?[]u21 = null,
            title: ?[]u21 = null,
            locale: ?[]const u8 = null,
            condition: ?[]const u8 = null,
        }),
    ) = .empty;

    var unique_locale: std.StringHashMapUnmanaged(void) = .empty;
    var unique_conditions: std.StringHashMapUnmanaged(void) = .empty;

    line_loop: while (split_lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') {
            continue :line_loop;
        }

        var split_comments = std.mem.splitScalar(u8, line, '#');

        var tokens = std.mem.splitScalar(u8, split_comments.next() orelse continue :line_loop, ';');

        const code_point_raw = std.mem.trim(u8, tokens.next() orelse @panic("code point not found"), " ");
        const lower_point_raw = std.mem.trim(u8, tokens.next() orelse "", " ");
        const title_point_raw = std.mem.trim(u8, tokens.next() orelse "", " ");
        const upper_point_raw = std.mem.trim(u8, tokens.next() orelse "", " ");
        const condition_raw = std.mem.trim(u8, tokens.next() orelse "", " ");

        const code_point = try std.fmt.parseInt(u21, code_point_raw, 16);
        const lower_point = if (lower_point_raw.len > 0) if_blk: {
            var split_tokens = std.mem.splitScalar(u8, lower_point_raw, ' ');
            var new_slice: std.ArrayList(u21) = .empty;

            while (split_tokens.next()) |token| {
                const cp = try std.fmt.parseInt(u21, token, 16);
                try new_slice.append(arena, cp);
            }

            break :if_blk try new_slice.toOwnedSlice(arena);
        } else null;

        const title_point = if (title_point_raw.len > 0) if_blk: {
            var split_tokens = std.mem.splitScalar(u8, title_point_raw, ' ');
            var new_slice: std.ArrayList(u21) = .empty;

            while (split_tokens.next()) |token| {
                const cp = try std.fmt.parseInt(u21, token, 16);
                try new_slice.append(arena, cp);
            }

            break :if_blk try new_slice.toOwnedSlice(arena);
        } else null;

        const upper_point = if (upper_point_raw.len > 0) if_blk: {
            var split_tokens = std.mem.splitScalar(u8, upper_point_raw, ' ');
            var new_slice: std.ArrayList(u21) = .empty;

            while (split_tokens.next()) |token| {
                const cp = try std.fmt.parseInt(u21, token, 16);
                try new_slice.append(arena, cp);
            }

            break :if_blk try new_slice.toOwnedSlice(arena);
        } else null;

        var locale: ?[]const u8 = null;
        var condition: ?[]const u8 = null;

        var conditional_tokens = std.mem.splitScalar(u8, condition_raw, ' ');

        while (conditional_tokens.next()) |token| {
            // check if it is locale
            // locale's are 2 character lower case labels.
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

        if (!entry.found_existing) {
            entry.value_ptr.* = .empty;
        }

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
        \\const CodePoint = @import("encoding").CodePoint;
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

    var unique_keys_iter = unique_conditions.keyIterator();

    while (unique_keys_iter.next()) |key| {
        try writer.print("    {s},\n", .{key.*});
    }
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
    var unique_locale_iter = unique_locale.keyIterator();

    while (unique_locale_iter.next()) |key| {
        try writer.print("    {s},\n", .{key.*});
    }
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
    while (key_iter.next()) |cp| {
        try sorted_code_points.append(arena, cp.*);
    }

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
            try writer.writeAll("            .{ ");

            try writer.writeAll(".lower = ");
            if (mapping.lower) |v| {
                try writer.writeAll("&.{");
                for (v) |i| {
                    try writer.print(" 0x{X},", .{i});
                }
                try writer.writeAll(" }");
            } else try writer.writeAll("&.{}");

            try writer.writeAll(", .upper = ");
            if (mapping.upper) |v| {
                try writer.writeAll("&.{");
                for (v) |i| {
                    try writer.print(" 0x{X},", .{i});
                }
                try writer.writeAll(" }");
            } else try writer.writeAll("&.{}");

            try writer.writeAll(", .title = ");
            if (mapping.title) |v| {
                try writer.writeAll("&.{");
                for (v) |i| {
                    try writer.print(" 0x{X},", .{i});
                }
                try writer.writeAll(" }");
            } else try writer.writeAll("&.{}");

            try writer.writeAll(", .locale = ");
            if (mapping.locale) |locale|
                try writer.print(".{s}", .{locale})
            else
                try writer.writeAll(".none");

            try writer.writeAll(", .condition = ");
            if (mapping.condition) |condition|
                try writer.print(".{s}", .{condition})
            else
                try writer.writeAll(".none");

            try writer.writeAll(" },\n");
        }

        try writer.writeAll(
            "        }\n    },\n",
        );
    }

    try writer.writeAll(
        \\};
        \\// zig fmt: on
        \\
        \\fn findEntry(code_point: CodePoint) ?CaseMapEntry {
        \\    var left: usize = 0;
        \\    var right: usize = mappings_table.len;
        \\    while (left < right) {
        \\        const mid = left + (right - left) / 2;
        \\        const entry = mappings_table[mid];
        \\
        \\        if (code_point < entry.code_point) {
        \\            right = mid;
        \\        } else if (code_point > entry.code_point) {
        \\            left = mid + 1;
        \\        } else return entry;
        \\    }
        \\
        \\    return null;
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

fn generatePropList(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();

    var file = try dir.createFile(io, file_name, .{
        .truncate = true,
        .permissions = .default_file,
    });
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
        if (line.len == 0 or line[0] == '#') {
            continue :line_loop;
        }

        var split_comments = std.mem.splitScalar(u8, line, '#');

        const tokens_raw = split_comments.next() orelse continue :line_loop;
        var tokens_iter = std.mem.splitScalar(u8, tokens_raw, ';');

        const code_points_raw = tokens_iter.next() orelse @panic("code point not found");
        const property_name_raw = tokens_iter.next() orelse @panic("property name not found");

        const entry = try tables.getOrPut(arena, property_name_raw);

        if (!entry.found_existing) {
            entry.value_ptr.* = .{
                .normalized_name = try normalizeKey(arena, property_name_raw),
            };
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
        \\
        \\const Range = struct { start: CodePoint, end: CodePoint };
        \\
        \\fn searchRange(cp: CodePoint, ranges: []const Range) bool {
        \\    var lo: usize = 0;
        \\    var hi: usize = ranges.len;
        \\    while (lo < hi) {
        \\        const mid = lo + (hi - lo) / 2;
        \\        const r = ranges[mid];
        \\        if (cp < r.start) {
        \\            hi = mid;
        \\        } else if (cp > r.end) {
        \\            lo = mid + 1;
        \\        } else {
        \\            return true;
        \\        }
        \\    }
        \\    return false;
        \\}
        \\
        \\
    );

    var tables_iter = tables.valueIterator();

    table_generator: while (tables_iter.next()) |table| {
        // a normal binary search should suffice
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

            const fn_name = try normalizeFnName(arena, table.normalized_name);
            const fn_name_pascal_head: u8 = std.ascii.toUpper(fn_name[0]);

            try writer.print(
                \\pub inline fn is{c}{s}(cp: CodePoint) bool {{
                \\    return searchRange(cp, &{s}_ranges);
                \\}}
                \\
                \\
            , .{ fn_name_pascal_head, fn_name[1..], table.normalized_name });

            continue :table_generator;
        }

        // create page based lookup table.
        const PAGE_BITS = 8;
        const PAGE_SIZE = 1 << PAGE_BITS;

        const values = try arena.alloc(bool, 0x110000);
        @memset(values, false);

        for (table.ranges.items) |range| {
            var cp = range.start;
            while (cp <= range.end) : (cp += 1) {
                values[cp] = true;
            }
        }

        var unique_pages = std.ArrayList([]const bool).empty;
        var level1_items = std.ArrayList(usize).empty;
        var page_map: std.AutoHashMapUnmanaged(u64, usize) = .empty;

        const page_buf = try arena.alloc(bool, PAGE_SIZE);

        var total_cps: usize = 0;
        while (total_cps < values.len) : (total_cps += PAGE_SIZE) {
            const page_start = total_cps;
            const page_end = @min(page_start + PAGE_SIZE, values.len);

            for (page_buf, 0..) |*slot, j| {
                const idx = page_start + j;
                slot.* = if (idx < page_end) values[idx] else false;
            }

            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.sliceAsBytes(page_buf));
            const page_hash = hasher.final();

            var found = false;
            var found_idx: usize = 0;

            if (page_map.get(page_hash)) |idx| {
                if (std.mem.eql(bool, unique_pages.items[idx], page_buf)) {
                    found = true;
                    found_idx = idx;
                }
            }

            if (!found) {
                const new_page = try arena.alloc(bool, PAGE_SIZE);
                @memcpy(new_page, page_buf);
                found_idx = unique_pages.items.len;
                try unique_pages.append(arena, new_page);
                try page_map.put(arena, page_hash, found_idx);
            }

            try level1_items.append(arena, found_idx);
        }

        try writer.print("//zig fmt: off\nconst {s}_level1 = [_]u16 {{", .{table.normalized_name});
        for (level1_items.items, 0..) |idx, n| {
            if (n % 12 == 0) try writer.writeAll("\n    ");
            try writer.print("{},", .{idx});
            if (n + 1 != level1_items.items.len) try writer.writeAll(" ");
        }
        try writer.writeAll("\n};\n//zig fmt: on\n\n");

        try writer.print("//zig fmt: off\nconst {s}_level2 = [_][256]bool {{\n", .{table.normalized_name});
        for (unique_pages.items) |page| {
            try writer.writeAll("    .{\n        ");
            for (page, 0..) |val, j| {
                try writer.print("{},", .{val});
                if ((j + 1) % 12 == 0 and (j + 1) != page.len) {
                    try writer.writeAll("\n        ");
                } else if (j + 1 != page.len) {
                    try writer.writeAll(" ");
                }
            }
            try writer.writeAll("\n    },\n");
        }
        try writer.writeAll("};\n//zig fmt: on\n\n");

        const fn_name = try normalizeFnName(arena, table.normalized_name);
        const fn_name_pascal_head: u8 = std.ascii.toUpper(fn_name[0]);

        try writer.print(
            \\pub inline fn is{c}{s}(cp: CodePoint) bool {{
            \\    if (cp > 0x10FFFF) return false;
            \\    const page = {s}_level1[cp >> 8];
            \\    return {s}_level2[page][cp & 0xFF];
            \\}}
            \\
            \\
        , .{ fn_name_pascal_head, fn_name[1..], table.normalized_name, table.normalized_name });
    }

    // 7. Keep file flush/save logic
    try file_writer.flush();

    try saveUCDFile(arena, io, &dir, data, url, buf);
}

// ============================================================================
// Placeholders for upcoming UCD generators
// ----------------------------------------------------------------------------
// Each stub keeps the standard generator signature so it can be slotted into
// the `generators` array below without further plumbing. The doc comments
// describe the data shape, recommended output table strategy, and the public
// API the generated file should expose. Replace the @panic body with the
// implementation when you start work.
// ============================================================================

// ----- Tier 1: segmentation & layout ----------------------------------------

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/GraphemeBreakProperty.txt
/// Shape: `<range> ; <Grapheme_Cluster_Break value>` lines. Default value is `Other`.
/// Output: enum `GraphemeBreakProperty` + 2-level page table (cp → enum).
/// API: `pub inline fn graphemeBreakProperty(cp: CodePoint) GraphemeBreakProperty`.
/// Consumers will combine this with `emoji-data` (Extended_Pictographic) to
/// implement the UAX #29 extended grapheme cluster algorithm.
fn generateGraphemeBreakProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateGraphemeBreakProperty");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt
/// Shape: `<range> ; <property>` where property is one of Emoji, Emoji_Presentation,
/// Emoji_Modifier, Emoji_Modifier_Base, Emoji_Component, Extended_Pictographic.
/// Output: one bool predicate per property (mirror prop_list strategy).
/// API: `isEmoji`, `isEmojiPresentation`, `isEmojiModifier`,
/// `isEmojiModifierBase`, `isEmojiComponent`, `isExtendedPictographic`.
fn generateEmojiData(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateEmojiData");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/WordBreakProperty.txt
/// Shape: `<range> ; <Word_Break value>` lines. Default value is `Other`.
/// Output: enum `WordBreakProperty` + 2-level page table.
/// API: `pub inline fn wordBreakProperty(cp: CodePoint) WordBreakProperty`.
fn generateWordBreakProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateWordBreakProperty");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/SentenceBreakProperty.txt
/// Shape: `<range> ; <Sentence_Break value>` lines. Default value is `Other`.
/// Output: enum `SentenceBreakProperty` + 2-level page table.
/// API: `pub inline fn sentenceBreakProperty(cp: CodePoint) SentenceBreakProperty`.
fn generateSentenceBreakProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateSentenceBreakProperty");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/LineBreak.txt
/// Shape: `<range> ; <Line_Break value>` lines. Default value is `XX` (Unknown).
/// Output: enum `LineBreak` (~45 values) + 2-level page table.
/// API: `pub inline fn lineBreak(cp: CodePoint) LineBreak`.
/// Note: implementing UAX #14 pair-table logic on top of this is a separate
/// algorithm module; this generator only emits the per-codepoint property.
fn generateLineBreak(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateLineBreak");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/EastAsianWidth.txt
/// Shape: `<range> ; <East_Asian_Width value>` (N, Na, A, W, F, H).
/// Output: enum `EastAsianWidth` + 2-level page table.
/// API: `pub inline fn eastAsianWidth(cp: CodePoint) EastAsianWidth`,
/// plus convenience `pub fn terminalColumnWidth(cp: CodePoint) u2`
/// (0 for zero-width, 1 for Na/N/A/H, 2 for W/F).
fn generateEastAsianWidth(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateEastAsianWidth");
}

// ----- Tier 2: normalization ------------------------------------------------

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/DerivedNormalizationProps.txt
/// Shape: same `<range> ; <property> [; <value>]` style as DerivedCoreProperties,
/// but several properties carry a tri-state value (Yes/No/Maybe) — NFC_QC,
/// NFD_QC, NFKC_QC, NFKD_QC — not a plain bool.
/// Output: bool predicates for binary properties (Full_Composition_Exclusion,
/// Changes_When_NFKC_Casefolded), tri-state lookup for QC properties,
/// plus a separate codepoint→codepoints map for NFKC_Casefold and NFKC_Simple_Casefold.
/// API surface is big — design before implementing.
fn generateDerivedNormalizationProps(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateDerivedNormalizationProps");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/CompositionExclusions.txt
/// Shape: bare codepoint per line. Single-property set (~80 entries).
/// Output: sorted `const composition_exclusions = [_]CodePoint{...}` plus
/// `pub fn isCompositionExclusion(cp: CodePoint) bool` (binary search).
/// Used by the NFC composition step to skip excluded canonical compositions.
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
/// Save the raw text to `ucd/NormalizationTest.txt`. The actual test driver
/// lives in `src/unicode/tests/` and parses the saved file at test time.
fn generateNormalizationTestFixture(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateNormalizationTestFixture (download + save only, no Zig output)");
}

// ----- Tier 3: script & bidi ------------------------------------------------

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/Scripts.txt
/// Shape: `<range> ; <Script value>` lines. Default value is `Unknown`.
/// Output: enum `Script` (~160 values) + 2-level page table.
/// API: `pub inline fn script(cp: CodePoint) Script`.
fn generateScripts(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateScripts");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/ScriptExtensions.txt
/// Shape: `<range> ; <space-separated Script_Extension values>`.
/// Output: for each unique set-of-scripts pattern, emit a sorted array; map
/// codepoint → set-index via 2-level page table. Many codepoints share the
/// same extension set so this dedups very well.
/// API: `pub fn scriptExtensions(cp: CodePoint) []const Script`.
fn generateScriptExtensions(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateScriptExtensions (depends on generateScripts)");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/BidiBrackets.txt
/// Shape: `<cp> ; <paired cp> ; <o|c>` (open or close). ~120 entries.
/// Output: sorted `const bracket_pairs = [_]BracketPair{...}` keyed by `cp`,
/// plus binary-search lookup.
/// API: `pub fn bidiBracket(cp: CodePoint) ?BidiBracket` returning the paired
/// codepoint and direction.
fn generateBidiBrackets(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateBidiBrackets");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/BidiMirroring.txt
/// Shape: `<cp> ; <mirrored cp>` lines. ~370 entries.
/// Output: sorted `[_]MirrorEntry{ .source, .target }` + binary search.
/// API: `pub fn bidiMirrored(cp: CodePoint) ?CodePoint`.
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
/// Shape: `<range> ; <Numeric_Type>` (Decimal | Digit | Numeric | None).
/// Output: enum `NumericType` + 2-level page table.
/// API: `pub inline fn numericType(cp: CodePoint) NumericType`.
fn generateDerivedNumericType(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateDerivedNumericType");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/extracted/DerivedNumericValues.txt
/// Shape: `<range> ; <decimal value> ; ; <rational value>` (can be 1, 1/2, -1, etc.)
/// Output: sorted `[_]NumericEntry{ .cp, .numerator, .denominator }` plus
/// binary-search lookup. Values are exact rationals — store both parts as
/// `i64` to handle fractions like 1/16 and large numerators like 1000000.
/// API: `pub fn numericValue(cp: CodePoint) ?NumericValue`.
fn generateDerivedNumericValues(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateDerivedNumericValues");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/Blocks.txt
/// Shape: `<range> ; <Block name>` (~330 entries, contiguous, non-overlapping).
/// Output: sorted `[_]BlockEntry{ .start, .end, .name_index }` plus a
/// `[]const []const u8` of unique block names.
/// API: `pub fn block(cp: CodePoint) []const u8` (returns "No_Block" for gaps).
fn generateBlocks(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateBlocks");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/HangulSyllableType.txt
/// Shape: `<range> ; <Hangul_Syllable_Type>` (L | V | T | LV | LVT | NA).
/// Output: enum `HangulSyllableType` + 2-level page table.
/// API: `pub inline fn hangulSyllableType(cp: CodePoint) HangulSyllableType`.
/// Needed if you implement algorithmic Hangul L+V+T composition outside the
/// generic NFC tables.
fn generateHangulSyllableType(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    _ = arena;
    _ = io;
    _ = data;
    _ = url;
    _ = file_name;
    @panic("TODO: generateHangulSyllableType");
}

/// Source: https://www.unicode.org/Public/UCD/latest/ucd/DerivedAge.txt
/// Shape: `<range> ; <Unicode version>` (e.g., "1.1", "17.0").
/// Output: sorted `[_]AgeEntry{ .start, .end, .major, .minor }` + binary search.
/// API: `pub fn unicodeAge(cp: CodePoint) ?UnicodeVersion`.
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

        // ----- Tier 1: segmentation & layout (uncomment as implementations land) -----
        // .{
        //     .file_name = "src/unicode/segmentation/generated/grapheme_break.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/GraphemeBreakProperty.txt",
        //     .generatorFn = generateGraphemeBreakProperty,
        // },
        // .{
        //     .file_name = "src/unicode/segmentation/generated/emoji_data.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/emoji/emoji-data.txt",
        //     .generatorFn = generateEmojiData,
        // },
        // .{
        //     .file_name = "src/unicode/segmentation/generated/word_break.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/WordBreakProperty.txt",
        //     .generatorFn = generateWordBreakProperty,
        // },
        // .{
        //     .file_name = "src/unicode/segmentation/generated/sentence_break.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/SentenceBreakProperty.txt",
        //     .generatorFn = generateSentenceBreakProperty,
        // },
        // .{
        //     .file_name = "src/unicode/segmentation/generated/line_break.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/LineBreak.txt",
        //     .generatorFn = generateLineBreak,
        // },
        // .{
        //     .file_name = "src/unicode/width/generated/east_asian_width.zig",
        //     .url = "https://www.unicode.org/Public/UCD/latest/ucd/EastAsianWidth.txt",
        //     .generatorFn = generateEastAsianWidth,
        // },

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
            file_name,
            download_timer_end.toMilliseconds() - local_timer_start.toMilliseconds(),
            local_timer_end.toMilliseconds() - download_timer_end.toMilliseconds(),
        });

        _ = arena.reset(.{ .retain_with_limit = 1024 * 1024 * 4 });
    }

    const end = clock.now(io);

    std.debug.print("\n\ngenerate command took: {}ms, peak memory: {}MiB\n", .{ end.toMilliseconds() - start.toMilliseconds(), @as(f64, @floatFromInt(max_memory / (1024 * 1024))) });
}
