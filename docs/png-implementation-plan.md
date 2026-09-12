# Issue #3：PNG 检查与清理实施计划

## 目标与边界

Issue #3 的交付目标是让普通 PNG 与 APNG 获得和 JPEG 相同的完整闭环：选择文件、
显示结构与隐私信息、生成清理副本、二次解析验证并下载。实现不解码或重新编码像素，
而是安全地重写 PNG 块结构。

本 Issue 不负责优化压缩率、修改画面、识别人脸或解析任意私有应用数据。压缩文本
可以识别并删除，但第一版不需要解压其正文。

## 阶段一：PNG 块模型、CRC32 与安全解析

新增 `png.mbt` 和 `png_test.mbt`，定义：

- `PngError`：签名错误、截断、异常长度、CRC 错误、非法顺序和块数超限。
- `PngChunk`：类型、偏移、数据范围、CRC、关键/辅助属性和处理角色。
- `PngInspection`：统一 `ImageInfo`、块列表、透明度与动画状态。
- `PngRemoval`、`PngSanitizeResult`：删除记录、输出字节数与复检状态。

解析器按顺序完成：

1. 校验 8 字节 PNG 签名。
2. 读取大端块长度、四字节类型、数据和 CRC。
3. 在任何加法或切片前检查剩余长度，并限制最大文件和块数量。
4. 校验每个块的 CRC32。
5. 要求 `IHDR` 首先且仅出现一次，读取宽度、高度、位深和色彩类型。
6. 要求至少一个 `IDAT`，并以 `IEND` 结束；报告 `IEND` 后的尾随数据。
7. 对未知关键块拒绝清理，对未知辅助块给出明确诊断。

第一阶段单独提交，建议提交信息：

```text
feat: parse PNG chunks and validate CRC
```

## 阶段二：元数据、透明度、色彩与 APNG

识别并归类以下块：

| 类别 | 块 | 默认策略 |
|---|---|---|
| 图像必需 | `IHDR`、`PLTE`、`IDAT`、`IEND` | 保留 |
| 透明度 | `tRNS` | 保留 |
| 色彩显示 | `gAMA`、`cHRM`、`sRGB`、`iCCP`、`sBIT` | 保留并报告 |
| 动画 | `acTL`、`fcTL`、`fdAT` | 保留并验证顺序 |
| 文本隐私 | `tEXt`、`zTXt`、`iTXt` | 显示关键词并删除 |
| Exif | `eXIf` | 解析常用字段并删除；必要时仅保留方向 |
| 时间 | `tIME` | 显示并删除 |
| 物理信息 | `pHYs` | 显示并删除 |
| 未知辅助块 | 其他小写首字母块 | 默认删除并列入报告 |

需要把 `exif.mbt` 当前面向 JPEG APP1 的入口整理成可复用 TIFF 解析接口。PNG 的
`eXIf` 数据直接使用 TIFF 结构，不带 JPEG 的 `Exif\0\0` 前缀。若方向值会影响
显示，则生成只包含方向的最小 `eXIf`；其余设备、时间和 GPS 字段全部移除。

第二阶段建议提交：

```text
feat: inspect PNG metadata and animation properties
```

## 阶段三：无损结构清理与复检

清理器采用允许列表重建容器：

- 原样复制关键块、像素压缩数据、透明度、色彩和 APNG 块。
- 删除隐私块和未知辅助块。
- 不修改保留块的数据和 CRC。
- 对重新生成的最小 `eXIf` 计算新的 CRC32。
- 删除 `IEND` 后的尾随数据并独立记录。
- 对输出再次运行 PNG 解析器；存在 CRC、顺序或可移除元数据问题时禁止下载。
- 第二次清理应产生完全相同的输出。

第三阶段建议提交：

```text
feat: sanitize PNG metadata and verify output
```

## 阶段四：Wasm 与网页接入

把当前 JPEG 专用桥接改为按真实签名分派：

```text
JPEG -> inspect_jpeg / sanitize_jpeg
PNG  -> inspect_png  / sanitize_png
其他 -> 明确的不支持结果
```

网页需要同步调整：

- 报告 PNG 位深、色彩类型、透明度、块数和 APNG 状态。
- 使用 `image/png` 和 `.clean.png` 下载输出。
- 清理列表展示文本、Exif、时间、物理信息、未知辅助块和尾随数据。
- 保持同一个拖放入口与统一元数据表格。
- 增加 PNG 的 Wasm 端到端测试。

第四阶段建议提交：

```text
feat: add PNG workflow to the WebAssembly app
```

## 阶段五：验收与文档

自动测试至少覆盖：

- 最小静态 PNG、调色板 PNG、透明 PNG。
- `tEXt`、`zTXt`、`iTXt`、`tIME` 和 `eXIf`。
- 大端/小端 Exif、GPS 和方向保留。
- APNG 的 `acTL`、`fcTL`、`fdAT` 保留。
- CRC 错误、截断块、超大长度、重复 `IHDR`、缺失 `IDAT/IEND`。
- 未知关键块拒绝、未知辅助块删除。
- 清理后复检与重复清理一致性。

浏览器人工验收至少使用一张普通 PNG、一张透明 PNG 和一张 APNG。测试图片不得
包含真实位置或其他个人隐私。完成后更新支持矩阵、README、Pages 与 Issue #3，
建议提交：

```text
test: validate PNG cleaning in browser
docs: document PNG support and verification
```

## 完成定义

只有同时满足以下条件才关闭 Issue #3：

- MoonBit 检查与全部测试通过。
- Wasm 端到端测试通过。
- 普通、透明和动画 PNG 清理后均可正常显示。
- 已支持隐私块在二次解析中消失。
- 透明度、色彩和动画结构保持。
- 在线 GitHub Pages 已更新，并提供可复现说明。
