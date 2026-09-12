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

## Robust parsing and compatibility principle

> 严格验证“必须正确的结构”，宽容接受“规范允许而实现尚未认识的内容”。

解析器需要区分格式完整性、安全性要求和常见写入布局，不能因为输入不是当前实现
熟悉的典型排列就直接判定文件损坏。

| 输入情况 | 检查行为 | 清理行为 |
|---|---|---|
| 签名、长度、偏移、校验和或必要结构错误 | 拒绝，返回结构化错误 | 不生成输出 |
| 违反非强制的推荐顺序，但仍可安全定界 | 接受并给出诊断 | 在能够证明安全时规范化 |
| 规范允许且解码器应忽略的未知可选内容 | 接受、报告名称和范围 | 按公开隐私策略保留或删除并记录 |
| 未知内容可能影响解码或显示语义 | 允许安全检查时报告风险 | 无法证明安全重写时拒绝清理 |

这一原则仍以边界检查为前提。“宽容”不表示忽略异常长度或继续读取越界数据，也不
表示清理器可以对未知内容作无依据的安全承诺。JPEG 未知非隐私段可以保留；PNG
未知辅助块可以删除而未知关键块禁止清理；WebP 中解码器应忽略的未知 RIFF 块可
按隐私清理目的删除。所有格式的输出都必须再次通过同一解析器复检。
