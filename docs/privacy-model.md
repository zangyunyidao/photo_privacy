# Privacy Model

## What the tool removes

The default privacy policy removes recognized metadata that is not required
to decode and display the image, including location, capture timestamps, device
and software identity, author/copyright text, comments, XMP, IPTC, and trailing
payloads outside the valid container.

Color profiles, orientation, transparency, and animation can affect visible
rendering, so their treatment is explicit in the report. When orientation is
needed for the image to display correctly, PhotoPrivacy retains a minimal Exif
orientation record while removing the other supported metadata. Encoded image
payloads are copied without decoding or recompression.

## Meaning of a clean result

A clean result means:

1. the output conforms to a documented PhotoPrivacy format profile;
2. no supported removable metadata is found by a second parse;
3. all retained non-pixel structures are listed in the report;
4. the file remains viewable in supported test environments.

It does not mean that dimensions, compression structure, visible subjects,
watermarks, pixel-level steganography, or scene-derived information disappear.

## Local-first guarantee

The deployed production page is static. Files are read with browser APIs and
processed in memory by MoonBit/WebAssembly. No image contents are sent over the
network. The browser adapter creates an object URL for preview and a Blob URL
for download, then revokes both when no longer needed.

Live application: <https://zangyunyidao.github.io/photo_privacy/>
