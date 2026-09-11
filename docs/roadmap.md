# Development Roadmap

## Registration baseline

- [x] Initialize MoonBit and Git repositories.
- [x] Define scope, privacy claims, architecture, and format matrix.
- [x] Implement signature-based multi-format detection.
- [x] Add tests for normal and malformed inputs.
- [ ] Publish the baseline to a public GitHub repository and submit registration.

## Milestone 1 — safe container model

- Bounds-checked binary reader and structured diagnostics.
- Normalized `ImageInfo`, `MetadataItem`, and `PrivacyRisk` types.
- JPEG segment, PNG chunk, and WebP RIFF inventories.

## Milestone 2 — metadata inspection

- Shared Exif/TIFF IFD reader with both byte orders.
- JPEG Exif/XMP/IPTC/comment extraction.
- PNG textual/eXIf/time extraction.
- WebP EXIF/XMP/ICC extraction and animation reporting.

## Milestone 3 — sanitization and proof

- Format-specific lossless structural sanitizers.
- Explicit retention/removal report.
- Post-clean re-scan and structural validity checks.
- Tests for truncation, malicious lengths, unknown fields, and round trips.

## Milestone 4 — usable delivery

- Native CLI for inspection, cleaning, and verification.
- Static WebAssembly page with drag-and-drop, preview, report, and download.
- GitHub Actions checks and reproducible demo instructions.

## Suggested GitHub issues

1. Implement bounds-checked endian-aware binary reader.
2. Add JPEG segment inventory and malformed-length diagnostics.
3. Add PNG chunk inventory and CRC validation.
4. Add WebP RIFF chunk inventory and feature flags.
5. Define normalized metadata and privacy-risk model.
6. Build browser drag-and-drop and Wasm bridge.
