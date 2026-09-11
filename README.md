# PhotoPrivacy

PhotoPrivacy 是一个以隐私保护为目标的图像元数据检查与清理工具，主要使用
MoonBit 实现。项目计划通过 WebAssembly 在浏览器本地处理文件，用户选择的
图像不会上传到服务器。

当前原型已经能够依据文件签名识别 JPEG、PNG、WebP、GIF、BMP、TIFF、
HEIF/HEIC 和 AVIF，而不是依赖可能被修改的扩展名。比赛阶段的最小可交付版本
将重点实现 JPEG、PNG 和 WebP 的安全元数据检查与清理。

## 本地运行

```console
moon run cmd/main
moon check
moon test
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
