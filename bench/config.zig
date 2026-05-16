//! Shared benchmark parameters (samples, corpus size, iteration counts).

pub const sample_runs: usize = 7;

pub const utf8_corpus_cap_bytes: usize = 3 * 1024 * 1024;
pub const utf8_api_overhead_corpus_bytes: usize = 8 * 1024;

pub const inner_validate_scan: usize = 20;
pub const inner_init_view: usize = 10;
pub const inner_count_scalar: usize = 24;
pub const inner_slice_iter: usize = 16;
pub const inner_to_string: usize = 6;
pub const inner_reverse_checked: usize = 10;
pub const inner_api_overhead: usize = 1;

/// Stack / buffer conversions: how many full-corpus passes per timed sample.
pub const inner_u16_buffer_passes: usize = 28;
/// Heap alloc+free conversion pairs per timed sample (lighter than buffer path).
pub const inner_u16_alloc_passes: usize = 14;

pub const Utf8InnerPasses = struct {
    validate_scan: usize,
    init_view: usize,
    count_scalar: usize,
    slice_iter: usize,
    to_string: usize,
    reverse_checked: usize,
};

pub const throughput_inners = Utf8InnerPasses{
    .validate_scan = inner_validate_scan,
    .init_view = inner_init_view,
    .count_scalar = inner_count_scalar,
    .slice_iter = inner_slice_iter,
    .to_string = inner_to_string,
    .reverse_checked = inner_reverse_checked,
};

pub const api_inners = Utf8InnerPasses{
    .validate_scan = inner_api_overhead,
    .init_view = inner_api_overhead,
    .count_scalar = inner_api_overhead,
    .slice_iter = inner_api_overhead,
    .to_string = inner_api_overhead,
    .reverse_checked = inner_api_overhead,
};

pub const Utf16InnerPasses = Utf8InnerPasses;
pub const Utf32InnerPasses = Utf8InnerPasses;

pub const utf16_throughput_inners = throughput_inners;
pub const utf16_api_inners = api_inners;
pub const utf32_throughput_inners = throughput_inners;
pub const utf32_api_inners = api_inners;
