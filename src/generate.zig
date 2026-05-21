const std = @import("std");

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

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    const clock: std.Io.Clock = .real;

    const start = clock.now(io);

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

    var bidi_buffer: std.ArrayList(u8) = .empty;

    var lowercase_mapping_range: std.ArrayList(u8) = .empty;
    var lowercase_range_start: []const u8 = "";
    var lowercase_range_end: []const u8 = "";
    var lowercase_current_difference: i32 = 0;

    var uppercase_mapping_range: std.ArrayList(u8) = .empty;
    var uppercase_range_start: []const u8 = "";
    var uppercase_range_end: []const u8 = "";
    var uppercase_current_difference: i32 = 0;

    var title_case_mapping_range: std.ArrayList(u8) = .empty;
    var title_case_range_start: []const u8 = "";
    var title_case_range_end: []const u8 = "";
    var title_case_current_difference: i32 = 0;

    var split_iter = std.mem.splitScalar(u8, allocated_writer.written(), '\n');

    try writer.writeAll(
        \\//! This file is auto-generated. Do not edit directly.
        \\//! To regenerate run `zig build generate` in same level
        \\//! as `build.zig` file.
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
        \\pub const CategoryEntry = struct {
        \\    range_start: u21,
        \\    range_end: u21,
        \\    category: GeneralCategory,
        \\};
        \\
        \\pub const CombiningClassEntry = struct {
        \\    range_start: u21,
        \\    range_end: u21,
        \\    canonical_combining_class: u8,
        \\};
        \\
        \\pub const BidiEntry = struct {
        \\    range_start: u21,
        \\    range_end: u21,
        \\    bidi_class: BidiClass,
        \\};
        \\
        \\pub const CaseMappingRangeEntry = struct { start: u21, end: u21, delta: i32 };
        \\
        \\pub const category_table = [_]CategoryEntry {
        \\
    );

    var i: usize = 0;

    var category_start_range: ?u21 = null;
    var category_end_range: ?u21 = null;
    var previous_category_cp: ?u21 = null;
    var current_category: ?[]const u8 = null;

    var combining_start_range: ?u21 = null;
    var combining_end_range: ?u21 = null;
    var previous_combining_cp: ?u21 = null;
    var current_combining_class: ?[]const u8 = null;

    var bidi_start_range: ?u21 = null;
    var bidi_end_range: ?u21 = null;
    var previous_bidi_cp: ?u21 = null;
    var current_bidi: ?[]const u8 = null;

    while (split_iter.next()) |line| : (i += 1) {
        if (line.len == 0) {
            continue;
        }

        var field_iter = std.mem.splitScalar(u8, line, ';');

        const code_point = field_iter.next() orelse continue;
        _ = field_iter.next() orelse continue;
        const category = field_iter.next() orelse continue;
        const canonical_combining_class = field_iter.next() orelse continue;
        const bidi_class = field_iter.next() orelse continue;

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

        if (current_category == null) {
            current_category = category_name;
            category_start_range = cp;
            category_end_range = cp;
            previous_category_cp = cp;
        } else {
            const contiguous = cp == previous_category_cp.? + 1;
            const same_category = std.mem.eql(u8, current_category.?, category_name);

            if (same_category and contiguous) {
                category_end_range = cp;
                previous_category_cp = cp;
            } else {
                try writer.print(
                    "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .category = .{s} }},\n",
                    .{ category_start_range.?, category_end_range.?, current_category.? },
                );

                current_category = category_name;
                category_start_range = cp;
                category_end_range = cp;
                previous_category_cp = cp;
            }
        }

        if (!std.mem.eql(u8, canonical_combining_class, "0")) {
            if (current_combining_class == null) {
                current_combining_class = canonical_combining_class;
                combining_start_range = cp;
                combining_end_range = cp;
                previous_combining_cp = cp;
            } else {
                const contiguous = cp == previous_combining_cp.? + 1;
                const same_class = std.mem.eql(u8, current_combining_class.?, canonical_combining_class);

                if (same_class and contiguous) {
                    combining_end_range = cp;
                    previous_combining_cp = cp;
                } else {
                    const p = try std.fmt.allocPrint(
                        arena,
                        "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .canonical_combining_class = {s} }},\n",
                        .{ combining_start_range.?, combining_end_range.?, current_combining_class.? },
                    );

                    try combining_buffer.appendSlice(arena, p);

                    current_combining_class = canonical_combining_class;
                    combining_start_range = cp;
                    combining_end_range = cp;
                    previous_combining_cp = cp;
                }
            }
        }
        if (!std.mem.eql(u8, bidi_name, "left_to_right")) {
            if (current_bidi == null) {
                current_bidi = bidi_name;
                bidi_start_range = cp;
                bidi_end_range = cp;
                previous_bidi_cp = cp;
            } else {
                const contiguous = cp == previous_bidi_cp.? + 1;
                const same_bidi = std.mem.eql(u8, current_bidi.?, bidi_name);

                if (same_bidi and contiguous) {
                    bidi_end_range = cp;
                    previous_bidi_cp = cp;
                } else {
                    const p = try std.fmt.allocPrint(
                        arena,
                        "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .bidi_class = .{s} }},\n",
                        .{ bidi_start_range.?, bidi_end_range.?, current_bidi.? },
                    );

                    try bidi_buffer.appendSlice(arena, p);

                    current_bidi = bidi_name;
                    bidi_start_range = cp;
                    bidi_end_range = cp;
                    previous_bidi_cp = cp;
                }
            }
        }

        if (uppercase_mapping.len != 0) {
            const upper_cp = try std.fmt.allocPrint(arena, "{X}", .{cp});

            const cp_num_from = try std.fmt.parseInt(u21, upper_cp, 16);
            const cp_num_to = try std.fmt.parseInt(u21, uppercase_mapping, 16);

            const difference = @as(i32, @intCast(cp_num_from)) - @as(i32, @intCast(cp_num_to));

            if (uppercase_range_start.len == 0 or uppercase_range_end.len == 0 or uppercase_current_difference == 0) {
                uppercase_range_start = upper_cp;
                uppercase_range_end = upper_cp;
                uppercase_current_difference = difference;
            } else if (uppercase_current_difference == difference) {
                uppercase_range_end = upper_cp;
            } else if (uppercase_current_difference != difference) {
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .start = 0x{s}, .end = 0x{s}, .delta = {} }},\n",
                    .{ uppercase_range_start, uppercase_range_end, uppercase_current_difference },
                );

                try uppercase_mapping_range.appendSlice(arena, p);

                uppercase_range_start = upper_cp;
                uppercase_range_end = upper_cp;
                uppercase_current_difference = difference;
            }
        }
        if (lowercase_mapping.len != 0) {
            const lower_cp = try std.fmt.allocPrint(arena, "{X}", .{cp});

            const cp_num_from = try std.fmt.parseInt(u21, lower_cp, 16);
            const cp_num_to = try std.fmt.parseInt(u21, lowercase_mapping, 16);

            const difference = @as(i32, @intCast(cp_num_from)) - @as(i32, @intCast(cp_num_to));

            if (lowercase_range_start.len == 0 or lowercase_range_end.len == 0 or lowercase_current_difference == 0) {
                lowercase_range_start = lower_cp;
                lowercase_range_end = lower_cp;
                lowercase_current_difference = difference;
            } else if (lowercase_current_difference == difference) {
                lowercase_range_end = lower_cp;
            } else if (lowercase_current_difference != difference) {
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .start = 0x{s}, .end = 0x{s}, .delta = {} }},\n",
                    .{ lowercase_range_start, lowercase_range_end, lowercase_current_difference },
                );

                try lowercase_mapping_range.appendSlice(arena, p);

                lowercase_range_start = lower_cp;
                lowercase_range_end = lower_cp;
                lowercase_current_difference = difference;
            }
        }
        if (title_case_mapping.len != 0) {
            const title_cp = try std.fmt.allocPrint(arena, "{X}", .{cp});

            const cp_num_from = try std.fmt.parseInt(u21, title_cp, 16);
            const cp_num_to = try std.fmt.parseInt(u21, title_case_mapping, 16);

            const difference = @as(i32, @intCast(cp_num_from)) - @as(i32, @intCast(cp_num_to));

            if (title_case_range_start.len == 0 or title_case_range_end.len == 0 or title_case_current_difference == 0) {
                title_case_range_start = title_cp;
                title_case_range_end = title_cp;
                title_case_current_difference = difference;
            } else if (title_case_current_difference == difference) {
                title_case_range_end = title_cp;
            } else if (title_case_current_difference != difference) {
                const p = try std.fmt.allocPrint(
                    arena,
                    "    .{{ .start = 0x{s}, .end = 0x{s}, .delta = {} }},\n",
                    .{ title_case_range_start, title_case_range_end, title_case_current_difference },
                );

                try title_case_mapping_range.appendSlice(arena, p);

                title_case_range_start = title_cp;
                title_case_range_start = title_cp;
                title_case_current_difference = difference;
            }
        }
    }

    if (current_category != null) {
        try writer.print(
            "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .category = .{s} }},\n",
            .{ category_start_range.?, category_end_range.?, current_category.? },
        );
    }

    if (current_combining_class != null) {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .canonical_combining_class = {s} }},\n",
            .{ combining_start_range.?, combining_end_range.?, current_combining_class.? },
        );

        try combining_buffer.appendSlice(arena, p);
    }

    if (current_bidi != null) {
        const p = try std.fmt.allocPrint(
            arena,
            "    .{{ .range_start = 0x{X}, .range_end = 0x{X}, .bidi_class = .{s} }},\n",
            .{ bidi_start_range.?, bidi_end_range.?, current_bidi.? },
        );

        try bidi_buffer.appendSlice(arena, p);
    }

    try writer.writeAll("};\n\npub const combining_class_table = [_]CombiningClassEntry {\n");
    try writer.writeAll(combining_buffer.items);

    try writer.writeAll("};\n\npub const bidi_table = [_]BidiEntry {\n");
    try writer.writeAll(bidi_buffer.items);

    try writer.writeAll("};\n\npub const lowercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(lowercase_mapping_range.items);

    try writer.writeAll("};\n\npub const uppercase_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(uppercase_mapping_range.items);

    try writer.writeAll("};\n\npub const title_case_range_mapping_table = [_]CaseMappingRangeEntry {\n");
    try writer.writeAll(title_case_mapping_range.items);

    try writer.writeAll("};\n");

    try file_writer.flush();

    const end = clock.now(io);

    std.debug.print("parsed and wrote {} table data, took: {}ms\n", .{ i, end.toMilliseconds() - start.toMilliseconds() });
}
