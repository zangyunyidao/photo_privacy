# PhotoPrivacy

PhotoPrivacy 是一个以隐私保护为目标的图像元数据检查与清理工具，主要使用
MoonBit 实现。应用通过 WebAssembly 在浏览器本地处理文件，用户选择的
图像不会上传到服务器。

**在线演示：** <https://zangyunyidao.github.io/photo_privacy/>

当前版本已经能够依据文件签名识别 JPEG、PNG、WebP、GIF、BMP、TIFF、
HEIF/HEIC 和 AVIF，而不是依赖可能被修改的扩展名。JPEG、PNG 与 WebP 已支持容器结构
检查、常用 Exif/TIFF 字段解析、隐私元数据清理和清理后复检。清理过程不会解码
或重新压缩像素数据；透明度、色彩信息及动画结构会被保留。

JPEG 浏览器闭环已经在真实手机照片上完成验收；PNG 已接入同一 WebAssembly
页面，并通过核心测试、Wasm 桥接测试以及普通、透明和动画 PNG 的本地浏览器
人工验收，现已合并并部署到在线演示。WebP 已在 `feat/webp` 完成功能实现与
自动测试，等待浏览器人工验收、推送和部署。

## 本地运行

```console
moon run cmd/main
moon check
moon test
```

## 浏览器 MVP

当前网页 MVP 使用 MoonBit 编译出的 WebAssembly 在浏览器本地完成 JPEG/PNG/WebP 检查与
清理。浏览器只负责文件选择、预览和下载，不会把图像发送到服务器。

也可以直接使用[在线演示](https://zangyunyidao.github.io/photo_privacy/)。

### 在 VS Code 中一键运行

使用 VS Code 打开项目根目录后，按 `Ctrl+Shift+B`，或选择菜单“终端 → 运行生成
任务”。默认任务 `PhotoPrivacy: 构建并打开网页` 会依次完成：

1. 将 MoonBit 浏览器接口编译为 WebAssembly；
2. 选择从 8000 开始的可用本地端口并启动静态服务器；
3. 等待服务器就绪后用系统默认浏览器打开页面。

任务运行期间服务器会保持开启。使用 `Ctrl+C` 或点击 VS Code 终端中的“终止任务”
即可停止服务器。

这个任务只是开发入口，不会取代 MoonBit 代码接口。其他 MoonBit 包仍可直接调用
`detect_format`、`inspect_jpeg`、`sanitize_jpeg`、`inspect_png`、`sanitize_png`、
`inspect_webp` 和 `sanitize_webp`。

在 Windows PowerShell 中构建：

```powershell
.\scripts\build-web.ps1
python -m http.server 8000 --directory web\dist
```

然后访问 <http://127.0.0.1:8000/>。页面目前支持：

- 拖放或手动选择本地图像；
- 显示 JPEG/PNG/WebP 尺寸、结构、编码、方向、透明度、动画状态、元数据及隐私风险；
- 清除 Exif、文本、时间、物理尺寸和尾随数据等非显示必需信息；
- 保留 JPEG 扫描数据、PNG IDAT、WebP 位流、显示方向、透明度、色彩及动画结构；
- 对清理结果进行二次解析，并下载干净副本。

核心能够依据文件签名识别其他列出的格式；网页会明确提示尚未支持的
格式，不会生成可能损坏的输出。

构建后可以额外运行 Wasm 桥接测试：

```console
node --test web/tests/bridge.test.mjs
```

## 项目文档

- [项目申报书](docs/申报书.md)
- [一页项目方案](docs/proposal.md)
- [架构设计](docs/architecture.md)
- [支持格式](docs/supported-formats.md)
- [隐私模型](docs/privacy-model.md)
- [开发路线图](docs/roadmap.md)
- [GitHub Issues 设计](docs/issues.md)
- [PNG 实施计划](docs/png-implementation-plan.md)
- [WebP 实施计划](docs/webp-implementation-plan.md)

## 开源许可

项目采用 Apache-2.0 许可证开源。
