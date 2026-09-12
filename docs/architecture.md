# Architecture

## Processing pipeline

```text
Browser File / CLI Bytes
  -> bounded binary reader
  -> signature-based format detection
  -> format-specific container parser
  -> normalized image and metadata report
  -> privacy policy
  -> format-specific sanitizer
  -> post-clean parser verification
  -> output Bytes / browser Blob download
```

## Planned MoonBit packages

- `detect`: signature and ISO-BMFF brand detection.
- `binary`: bounds-checked endian-aware readers and parse errors.
- `model`: normalized image, metadata, risk, and sanitization-report types.
- `exif`: TIFF/IFD structures shared by JPEG, PNG, and WebP metadata.
- `jpeg`, `png`, `webp`: format-specific parsers and sanitizers.
- `sanitize`: policy selection, removal accounting, and verification.
- `cmd/photo_privacy`: file-oriented native command-line host.
- `wasm/api`: byte-oriented exports for the browser host.

HTML、CSS 与少量 JavaScript 适配器负责浏览器文件 API、预览、DOM 渲染和下载。
浏览器通过整数 ABI 将图像字节分块传给 MoonBit 编译出的 WebAssembly；解析、
元数据分类、清理策略和输出复检仍由 MoonBit 核心完成。

## Security boundaries

- Never trust filenames, MIME declarations, lengths, offsets, chunk counts, or
  nested metadata supplied by an input file.
- Check bounds before every byte read and arithmetic operation.
- Enforce file-size, segment-count, chunk-count, nesting, and decoded-text limits.
- Never execute embedded scripts or fetch external resources.
- Treat unknown structures explicitly instead of silently claiming a clean file.
