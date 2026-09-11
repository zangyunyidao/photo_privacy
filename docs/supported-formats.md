# Supported Format Matrix

| Format | Detect now | MVP inspection | MVP sanitize | Notes |
|---|---:|---:|---:|---|
| JPEG/JPG | Yes | Yes | Yes | Exif/TIFF, XMP, IPTC, comments, APP segments |
| PNG/APNG | Yes | Yes | Yes | Chunks, textual data, eXIf, time; preserve animation |
| WebP | Yes | Yes | Yes | RIFF, EXIF, XMP, ICC, alpha, animation flags |
| GIF87a/89a | Yes | Basic | Stretch | Preserve animation and loop behavior |
| BMP | Yes | Basic | Stretch | Usually little removable metadata |
| TIFF | Yes | Partial | No | Metadata and image storage are tightly coupled |
| HEIF/HEIC | Yes | Basic container | No | ISO-BMFF item relations are out of MVP scope |
| AVIF | Yes | Basic container | No | ISO-BMFF item relations are out of MVP scope |
| SVG | Planned reject | No | No | XML/script sanitization is a different task |

"Yes" will only be claimed when tests cover valid, malformed, truncated, and
misleading-extension inputs. Unsupported formats are never silently rewritten.

## Primary specifications

- CIPA Exif 3.1: <https://www.cipa.jp/e/std/history_sec.html>
- PNG Third Edition: <https://www.w3.org/TR/png-3/>
- WebP RIFF Container: <https://developers.google.com/speed/webp/docs/riff_container>
