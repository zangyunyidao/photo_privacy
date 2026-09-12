# PhotoPrivacy — Project Proposal

## Problem

Image files can carry more than visible pixels. Camera and phone photos may
contain location, capture time, device model, editing software, comments, or
application-specific metadata. Users often share those files without an easy
way to see what else is included.

## Proposed solution

PhotoPrivacy is a MoonBit-first library and deployed browser tool that identifies an
image from its bytes, presents its container and metadata in understandable
categories, explains privacy risks, and creates a cleaned copy locally. The
browser host uses WebAssembly so image bytes do not need to leave the
device.

The current public demo completes the inspect, sanitize, verify, and download
workflow for JPEG, PNG, and WebP:
<https://zangyunyidao.github.io/photo_privacy/>.

## Competition MVP

1. Detect JPEG, PNG, WebP, GIF, BMP, TIFF, HEIF/HEIC, and AVIF by signature.
2. Safely parse JPEG, PNG, and WebP container structures with bounded reads.
3. Report dimensions, encoding properties, segment/chunk layout, and recognized
   Exif, XMP, IPTC, textual, time, and location metadata.
4. Remove non-rendering metadata from JPEG, PNG, and WebP without altering the
   encoded image payload where the format permits it.
5. Re-scan sanitized output and report exactly what was removed.
6. Provide malformed-input tests and a static WebAssembly demo with
   drag-and-drop, preview, and download.

## Non-goals for the MVP

- Image editing, face or license-plate redaction, and visual-content analysis.
- A guarantee against steganography or facts visible in the image itself.
- Full interpretation of proprietary camera MakerNote data.
- Sanitization of TIFF, HEIF/HEIC, AVIF, SVG, RAW, or future formats.
- Uploading files, user accounts, databases, or remote processing services.

## Verification

Every parser rejects truncated or out-of-bounds structures without crashing.
Tests cover both byte orders where applicable, known metadata fixtures,
unknown metadata policy, and the invariant that sanitized output remains valid
and contains none of the supported removable metadata. The reproducible baseline
currently passes 38 MoonBit tests and 9 WebAssembly bridge tests.

## Deliverables

- Public Apache-2.0 GitHub repository with reviewable development history.
- Reusable MoonBit packages and generated public interfaces.
- Executable documentation, tests, and continuous integration.
- Deployed static local-first browser demonstration on GitHub Pages.
