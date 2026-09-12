# Supported Format Matrix

| Format | Signature detection | Inspection | Sanitization | Notes |
|---|---:|---:|---:|---|
| JPEG/JPG | Yes | Implemented | Implemented | Segment inventory, common Exif/TIFF fields, XMP/IPTC/comments, orientation retention, post-clean verification |
| PNG/APNG | Yes | Implemented | Implemented | CRC-validated chunks, text/eXIf/time/physical data cleaning; preserves transparency, color and animation; local browser verification completed |
| WebP | Yes | Planned (Issue #4) | Planned (Issue #4) | RIFF, EXIF, XMP, ICC, alpha and animation flags |
| GIF87a/89a | Yes | Detection only | No | Cleaning is outside the current scope |
| BMP | Yes | Detection only | No | Cleaning is outside the current scope |
| TIFF | Yes | Detection only | No | Metadata and image storage are tightly coupled |
| HEIF/HEIC | Yes | Brand detection only | No | ISO-BMFF item relations are outside the current scope |
| AVIF | Yes | Brand detection only | No | ISO-BMFF item relations are outside the current scope |
| SVG | No | No | No | XML/script sanitization is a different task |

“Implemented” 仅用于已经覆盖正常、畸形、截断和误导性扩展名输入，并完成清理后
复检的格式。不支持的格式不会被静默重写。

## Primary specifications

- CIPA Exif 3.1: <https://www.cipa.jp/e/std/history_sec.html>
- PNG Third Edition: <https://www.w3.org/TR/png-3/>
- WebP RIFF Container: <https://developers.google.com/speed/webp/docs/riff_container>
