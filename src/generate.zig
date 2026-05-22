const std = @import("std");
const utils = @import("utils/root.zig");

pub fn downloadFileToPath(allocator: std.mem.Allocator, io: std.Io, writer: *std.Io.Writer, url: []const u8) !void {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    const uri: std.Uri = try .parse(url);

    _ = try client.fetch(.{ .location = .{ .uri = uri }, .response_writer = writer });
}

const file_name = "src/unicode/unicode_generated.zig";
const unicode_data_url = "https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt";

fn downloadAndGenerateUnicodeData(arena: std.mem.Allocator, io: std.Io) !void {
    var allocated_writer: std.Io.Writer.Allocating = .init(arena);
    defer allocated_writer.deinit();

    try downloadFileToPath(arena, io, &allocated_writer.writer, unicode_data_url);

    const dir: std.Io.Dir = .cwd();

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

    var split_iter = std.mem.splitScalar(u8, allocated_writer.written(), '\n');

    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
        \\
        \\const CodePoint = @import("encoding").CodePoint;
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
        \\    canonical_combining_class: u8,
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
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .canonical_combining_class = {s} }},\n",
                    .{ combining_start_range.?, combining_end_range.?, current_combining_class.? },
                );

                try combining_buffer.appendSlice(arena, p);

                combining_start_range = cp;
                combining_end_range = cp;
                current_combining_class = combining_class;
            }
        } else if (current_combining_class != null) {
            const p = try std.fmt.allocPrint(
                arena,
                "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .canonical_combining_class = {s} }},\n",
                .{ combining_start_range.?, combining_end_range.?, current_combining_class.? },
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
            "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .canonical_combining_class = {s} }},\n",
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

    std.debug.print("parsed and wrote {} table data\n", .{i});
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena;
    const arena_allocator = arena.allocator();
    const io = init.io;

    const clock: std.Io.Clock = .real;

    const start = clock.now(io);

    {
        try downloadAndGenerateUnicodeData(arena_allocator, io);
        _ = arena.reset(.free_all);
    }

    const end = clock.now(io);

    std.debug.print("generate command took: {}ms\n", .{end.toMilliseconds() - start.toMilliseconds()});
}
