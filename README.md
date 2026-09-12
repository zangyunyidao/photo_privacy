# PhotoPrivacy

PhotoPrivacy 是一个以隐私保护为目标的图像元数据检查与清理工具，主要使用
MoonBit 实现。项目计划通过 WebAssembly 在浏览器本地处理文件，用户选择的
图像不会上传到服务器。

当前版本已经能够依据文件签名识别 JPEG、PNG、WebP、GIF、BMP、TIFF、
HEIF/HEIC 和 AVIF，而不是依赖可能被修改的扩展名。JPEG 已支持段结构检查、
Exif/TIFF 常用字段解析，以及 Exif、XMP、IPTC、注释和尾随数据清理；清理过程
不会解码或重新压缩 JPEG 像素数据，并会再次解析输出结果进行验证。

比赛阶段接下来将扩展 PNG、WebP，并把这些能力接入本地 WebAssembly 页面。

## 本地运行

```console
moon run cmd/main
moon check
moon test
```

## 浏览器 MVP

当前网页 MVP 使用 MoonBit 编译出的 WebAssembly 在浏览器本地完成 JPEG 检查与
清理。浏览器只负责文件选择、预览和下载，不会把图像发送到服务器。

在 Windows PowerShell 中构建：

```powershell
.\scripts\build-web.ps1
python -m http.server 8000 --directory web\dist
```

然后访问 <http://127.0.0.1:8000/>。页面目前支持：

- 拖放或手动选择本地图像；
- 显示 JPEG 尺寸、方向、元数据及隐私风险；
- 清除 Exif、XMP、IPTC、注释和尾随数据；
- 保留 JPEG 压缩扫描数据和必要的显示方向；
- 对清理结果进行二次解析，并下载干净副本。

PNG、WebP 和其他格式可以预览或识别，但当前版本会明确拒绝清理。

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

## 开源许可

项目采用 Apache-2.0 许可证开源。
