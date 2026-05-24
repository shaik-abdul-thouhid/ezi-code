const std = @import("std");
const utils = @import("utils/root.zig");

const property_alias = @import("unicode/property_alias.zig");
const CanonicalCombiningClass = property_alias.CanonicalCombiningClass;

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

fn downloadAndGenerateUnicodeData(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
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

    var title_case_mapping_range: std.ArrayList(u8) = .empty;
    var title_case_range_start: ?u21 = null;
    var title_case_range_end: ?u21 = null;
    var title_case_current_difference: i32 = 0;

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
        const title_case_mapping = field_iter.next() orelse "";
        const cp = try std.fmt.parseInt(u21, code_point, 16);

        const category_name = blk: {
            if (std.mem.eql(u8, category, "Lu")) break :blk "uppercase_letter";
            if (std.mem.eql(u8, category, "Ll")) break :blk "lowercase_letter";
            if (std.mem.eql(u8, category, "Lt")) break :blk "title_case_letter";
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
        if (title_case_mapping.len != 0) {
            const cp_num_from = cp;
            const cp_num_to = try std.fmt.parseInt(u21, title_case_mapping, 16);
            const difference = @as(i32, @intCast(cp_num_to)) - @as(i32, @intCast(cp_num_from));

            if (title_case_range_start == null or title_case_range_end == null or title_case_current_difference == 0) {
                title_case_range_start = cp;
                title_case_range_end = cp;
                title_case_current_difference = difference;
            } else if (title_case_current_difference == difference and cp == title_case_range_end.? + 1) {
                title_case_range_end = cp;
            } else if (title_case_current_difference != difference or cp != title_case_range_end.? + 1) {
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
                    .{ title_case_range_start.?, title_case_range_end.?, title_case_current_difference },
                );

                try title_case_mapping_range.appendSlice(arena, p);

                title_case_range_start = cp;
                title_case_range_end = cp;
                title_case_current_difference = difference;
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
        \\const property_alias = @import("property_alias.zig");
        \\
        \\const CanonicalCombiningClass = property_alias.CanonicalCombiningClass;
        \\
        \\pub const GeneralCategory = enum(u8) {
        \\    uppercase_letter,
        \\    lowercase_letter,
        \\    title_case_letter,
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

    if (title_case_range_start != null) {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .start = 0x{X}, .end = 0x{X}, .delta = {} }},\n",
            .{ title_case_range_start.?, title_case_range_end.?, title_case_current_difference },
        );
        try title_case_mapping_range.appendSlice(arena, p);
    }

    try writer.writeAll("pub const lowercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(lowercase_mapping_range.items);

    try writer.writeAll("};\n\npub const uppercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(uppercase_mapping_range.items);

    try writer.writeAll("};\n\npub const title_case_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(title_case_mapping_range.items);

    try writer.writeAll("};\n");

    try file_writer.flush();

    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn downloadAndGenerateDerivedCoreProperty(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
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

    const normalizeKey = struct {
        fn normalize(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
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
                            if (!prev) {
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
    }.normalize;

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
        \\const Property = enum(32) {
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

fn downloadAndGenerateCaseFolding(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
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
        \\const property_alias = @import("property_alias.zig");
        \\const CaseFoldingMode = property_alias.CaseFoldingMode;
        \\const CaseFoldingLocale = property_alias.CaseFoldingLocale;
        \\const FoldResult = property_alias.FoldResult;
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
        \\pub fn lookup(comptime mode: CaseFoldingMode, comptime locale: CaseFoldingLocale, code_point: CodePoint) ?FoldResult(mode) {
        \\    const table = switch (locale) {
        \\        .default => switch (mode) {
        \\            .simple => &common_simple_table,
        \\            .full => &common_full_table,
        \\        },
        \\        .turkic => switch (mode) {
        \\            .simple => &turkic_simple_table,
        \\            .full => &turkic_full_table,
        \\        },
        \\    };
        \\
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
    );

    // 10. Preserve file_writer.flush
    try file_writer.flush();

    try saveUCDFile(arena, io, &dir, data, url, buf);
}

fn downloadAndGenerateSpecialCasing(arena: std.mem.Allocator, io: std.Io, data: []const u8, url: []const u8, file_name: []const u8) !void {
    var dir: std.Io.Dir = .cwd();

    var file = try dir.createFile(io, file_name, .{
        .truncate = true,
        .permissions = .default_file,
    });
    defer file.close(io);

    const buf = try arena.alloc(u8, 4096);
    var file_writer = file.writer(io, buf);
    const writer = &file_writer.interface;
    _ = writer;

    try file_writer.flush();

    try saveUCDFile(arena, io, &dir, data, url, buf);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena;
    const arena_allocator = arena.allocator();
    const io = init.io;

    const clock: std.Io.Clock = .real;

    const start = clock.now(io);

    {
        var allocated_writer: std.Io.Writer.Allocating = .init(arena_allocator);
        defer allocated_writer.deinit();

        try allocated_writer.ensureTotalCapacity(1024 * 1024);

        const file_name = "src/unicode/unicode_data_generated.zig";
        const unicode_data_url = "https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt";

        try downloadFileToPath(arena_allocator, io, &allocated_writer.writer, unicode_data_url);

        try downloadAndGenerateUnicodeData(arena_allocator, io, allocated_writer.written(), unicode_data_url, file_name);

        _ = arena.reset(.{ .retain_with_limit = 1024 * 1024 * 4 });
    }

    {
        var allocated_writer: std.Io.Writer.Allocating = .init(arena_allocator);
        defer allocated_writer.deinit();

        try allocated_writer.ensureTotalCapacity(1024 * 1024);

        const file_name = "src/unicode/derived_core_properties_generated.zig";
        const derived_core_properties_url = "https://www.unicode.org/Public/UCD/latest/ucd/DerivedCoreProperties.txt";

        try downloadFileToPath(arena_allocator, io, &allocated_writer.writer, derived_core_properties_url);

        try downloadAndGenerateDerivedCoreProperty(arena_allocator, io, allocated_writer.written(), derived_core_properties_url, file_name);

        allocated_writer.clearRetainingCapacity();

        _ = arena.reset(.{ .retain_with_limit = 1024 * 1024 * 4 });
    }

    {
        var allocated_writer: std.Io.Writer.Allocating = .init(arena_allocator);
        defer allocated_writer.deinit();

        try allocated_writer.ensureTotalCapacity(1024 * 1024);

        const file_name = "src/unicode/case_folding_generated.zig";
        const source_url = "https://www.unicode.org/Public/UCD/latest/ucd/CaseFolding.txt";

        try downloadFileToPath(arena_allocator, io, &allocated_writer.writer, source_url);
        try downloadAndGenerateCaseFolding(arena_allocator, io, allocated_writer.written(), source_url, file_name);
        allocated_writer.clearRetainingCapacity();
    }

    {
        var allocated_writer: std.Io.Writer.Allocating = .init(arena_allocator);
        defer allocated_writer.deinit();

        try allocated_writer.ensureTotalCapacity(1024 * 1024);

        const file_name = "src/unicode/special_casing_generated.zig";
        const source_url = "https://www.unicode.org/Public/UCD/latest/ucd/SpecialCasing.txt";

        try downloadFileToPath(arena_allocator, io, &allocated_writer.writer, source_url);
        try downloadAndGenerateSpecialCasing(arena_allocator, io, allocated_writer.written(), source_url, file_name);
        allocated_writer.clearRetainingCapacity();
    }

    const end = clock.now(io);

    std.debug.print("generate command took: {}ms\n", .{end.toMilliseconds() - start.toMilliseconds()});
}
