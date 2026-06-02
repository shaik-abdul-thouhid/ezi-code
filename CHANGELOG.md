# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-02

### Added

- Collation module with DUCET (Default Unicode Collation Element Table) support
- Serialization and comparison for collation keys
- Bidi conformance test files

### Changed

- Refactored code structure for improved readability and maintainability
- Updated generated Unicode tables and documentation
- Added `sources.tar` containing documentation sources
- Cleaned up `build.zig.zon`

## [0.1.0] - 2026-05-31

### Added

- Transcoding module with UTF-8 and UTF-16 encoding/decoding
  - UTF-8 scalar counting, strict and lossy validation
  - UTF-16 surrogate pair handling, reverse decoding
- Bidi (Unicode Bidirectional Algorithm) implementation with full conformance coverage
- Unicode normalization (NFC, NFD, NFKC, NFKD) with conformance tests
- Unicode segmentation: line break, word, and sentence iterators (streaming mode)
- Unicode properties lookup (derived core properties, combining class, numeric values, blocks)
- Unicode script identification with conformance tests
- Case folding with strict, lossy, and codepoint variants; case-folded equality checks
- Hangul syllable, Bidi brackets/mirroring generation
- Benchmark infrastructure
- UCD 17.0.0 data frozen and code-generated tables

[Unreleased]: https://github.com/shaik-abdul-thouhid/ezi-code/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/shaik-abdul-thouhid/ezi-code/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/shaik-abdul-thouhid/ezi-code/releases/tag/v0.1.0
