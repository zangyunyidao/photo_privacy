# PhotoPrivacy

PhotoPrivacy is a privacy-first image metadata inspector and sanitizer written
primarily in MoonBit. The planned browser application processes files locally
with WebAssembly, so selected images are not uploaded to a server.

The pre-registration prototype recognizes JPEG, PNG, WebP, GIF, BMP, TIFF,
HEIF/HEIC, and AVIF by file signature. The competition MVP will focus on safe
metadata inspection and cleaning for JPEG, PNG, and WebP.

Run locally:

```console
moon run cmd/main
moon check
moon test
```

Detailed scope and plans:

- [One-page proposal](docs/proposal.md)
- [Architecture](docs/architecture.md)
- [Supported formats](docs/supported-formats.md)
- [Privacy model](docs/privacy-model.md)
- [Development roadmap](docs/roadmap.md)

Licensed under Apache-2.0.
