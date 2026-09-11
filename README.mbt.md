# PhotoPrivacy

PhotoPrivacy is a privacy-first image metadata inspector and sanitizer written
primarily in MoonBit. The planned browser application processes files locally
with WebAssembly: selected images are not uploaded to a server.

## Why

Photos and exported images may contain location, capture time, device, software,
comments, and other metadata. PhotoPrivacy will make that information visible,
explain its privacy impact, and create a cleaned copy while preserving the image
for ordinary viewing.

## Current status

This repository is the pre-registration prototype. It detects actual container
formats from file signatures rather than trusting filenames or MIME labels:

- JPEG/JPG
- PNG/APNG container
- WebP
- GIF87a/GIF89a
- BMP
- TIFF (little- and big-endian)
- HEIF/HEIC-family ISO-BMFF brands
- AVIF

Run the demonstration and tests from the repository root:

```text
moon run cmd/main
moon check
moon test
```

## Planned deliverable

The competition MVP targets full inspection and metadata sanitization for JPEG,
PNG, and WebP. GIF and BMP are stretch goals. TIFF, HEIF/HEIC, AVIF, and SVG
will initially be detected and reported as unsupported for sanitization unless a
safe implementation is completed and tested.

The browser UI will provide drag-and-drop and file selection, image preview,
format and metadata reports, privacy-risk explanations, sanitization, post-clean
verification, and download of the cleaned image. The UI is a thin host around a
MoonBit/WebAssembly inspection and sanitization core.

## Privacy promise and limits

"Clean" means that the tool removes non-rendering metadata supported by its
documented format profile and then scans the output again. An image must retain
structural information such as dimensions, pixel format, compression data,
transparency, and animation data in order to remain viewable. PhotoPrivacy cannot
remove information visible in the pixels, watermarks, unknown steganography, or
facts that can be inferred from the depicted scene.

The planned application performs processing locally. It will not require an
account, upload image bytes, or call a remote image-processing API.

## Project documents

- [One-page proposal](docs/proposal.md)
- [Architecture](docs/architecture.md)
- [Supported formats](docs/supported-formats.md)
- [Privacy model](docs/privacy-model.md)
- [Development roadmap](docs/roadmap.md)

## Open source

Licensed under Apache-2.0. Specifications and third-party references used during
implementation will be recorded with their URLs and licenses; no third-party
source code will be copied without compatible attribution.
