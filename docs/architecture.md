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

## Current implementation layout

- `photo_privacy.mbt`：文件签名与 ISO-BMFF 品牌识别。
- `binary_reader.mbt`：带边界检查和字节序支持的二进制读取器。
- `image_model.mbt`：统一图像信息、元数据、风险和诊断模型。
- `exif.mbt`：JPEG APP1、PNG eXIf 与 WebP EXIF 共用的 TIFF/IFD 解析和最小方向信息生成。
- `jpeg.mbt`：JPEG 段解析、隐私清理和清理后复检。
- `png.mbt`：PNG 块与 CRC 校验、隐私元数据解析、允许列表清理和清理后复检。
- `web/wasm`：面向浏览器宿主的整数 ABI 与 Wasm 导出。
- `web/site`：静态网页、预览、报告和下载适配器。
- `webp.mbt`：WebP RIFF/嵌套动画块解析、隐私清理、标志修正和清理后复检。

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
