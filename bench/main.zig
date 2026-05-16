//! Benchmark driver: UTF-8, UTF-16, UTF-32 encoding, and u8↔u16 byte conversion suites.

const std = @import("std");

const config = @import("config.zig");
const corpus = @import("corpus.zig");
const utf8_suite = @import("utf8_suite.zig");
const utf16_suite = @import("utf16_suite.zig");
const utf32_suite = @import("utf32_suite.zig");
const u16_suite = @import("u16_suite.zig");

pub fn main() !void {
    const backing = try std.heap.page_allocator.alloc(u8, config.utf8_corpus_cap_bytes);
    defer std.heap.page_allocator.free(backing);

    std.debug.print(
        \\Benchmarks — **mean of {d} timed runs** per row; wall time + heap stats (tracked allocator).
        \\Sections per corpus: UTF-8, UTF-16, UTF-32 encoding, then raw u8↔u16 byte slices.
        \\
    , .{config.sample_runs});

    const corpus_ascii = corpus.fillAsciiOnly(backing);
    try utf8_suite.runSuite(
        "=== UTF-8 — 1. ASCII-only (fast path) ===",
        corpus_ascii,
        config.throughput_inners,
    );
    try utf16_suite.runSuite(
        "=== UTF-16 — 1. ASCII-only corpus ===",
        corpus_ascii,
        config.utf16_throughput_inners,
    );
    try utf32_suite.runSuite(
        "=== UTF-32 — 1. ASCII-only corpus ===",
        corpus_ascii,
        config.utf32_throughput_inners,
    );
    try u16_suite.runSuite(
        "=== u8↔u16 bytes — 1. ASCII-only corpus ===",
        corpus_ascii,
    );

    const corpus_normal = corpus.fillFromChunks(backing, &corpus.normal_chunks);
    try utf8_suite.runSuite(
        "=== UTF-8 — 2. Normal multilingual (realistic) ===",
        corpus_normal,
        config.throughput_inners,
    );
    try utf16_suite.runSuite(
        "=== UTF-16 — 2. Normal multilingual corpus ===",
        corpus_normal,
        config.utf16_throughput_inners,
    );
    try utf32_suite.runSuite(
        "=== UTF-32 — 2. Normal multilingual corpus ===",
        corpus_normal,
        config.utf32_throughput_inners,
    );
    try u16_suite.runSuite(
        "=== u8↔u16 bytes — 2. Normal multilingual corpus ===",
        corpus_normal,
    );

    const corpus_patho = corpus.fillFromChunks(backing, &corpus.pathological_chunks);
    try utf8_suite.runSuite(
        "=== UTF-8 — 3. Pathological Unicode (worst-case valid UTF-8) ===",
        corpus_patho,
        config.throughput_inners,
    );
    try utf16_suite.runSuite(
        "=== UTF-16 — 3. Pathological corpus ===",
        corpus_patho,
        config.utf16_throughput_inners,
    );
    try utf32_suite.runSuite(
        "=== UTF-32 — 3. Pathological corpus ===",
        corpus_patho,
        config.utf32_throughput_inners,
    );
    try u16_suite.runSuite(
        "=== u8↔u16 bytes — 3. Pathological corpus ===",
        corpus_patho,
    );

    var api_buf: [config.utf8_api_overhead_corpus_bytes]u8 = undefined;
    const corpus_api = corpus.fillFromChunks(&api_buf, &corpus.normal_chunks);
    try utf8_suite.runSuite(
        "=== UTF-8 — 4. API overhead (small corpus, inner=1) ===",
        corpus_api,
        config.api_inners,
    );
    try utf16_suite.runSuite(
        "=== UTF-16 — 4. API overhead corpus ===",
        corpus_api,
        config.utf16_api_inners,
    );
    try utf32_suite.runSuite(
        "=== UTF-32 — 4. API overhead corpus ===",
        corpus_api,
        config.utf32_api_inners,
    );
    try u16_suite.runSuite(
        "=== u8↔u16 bytes — 4. API overhead corpus ===",
        corpus_api,
    );
}
