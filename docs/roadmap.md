# Development Roadmap

## Registration baseline

- [x] Initialize MoonBit and Git repositories.
- [x] Define scope, privacy claims, architecture, and format matrix.
- [x] Implement signature-based multi-format detection.
- [x] Add tests for normal and malformed inputs.
- [x] Publish the baseline to a public GitHub repository and submit registration.

## Milestone 1 — 通用基础设施

- [x] 完成 Issue 1：安全二进制读取器与统一图像信息模型。

## Milestone 2 — JPEG 完整闭环

- [x] 完成 Issue 2：JPEG/Exif 检查、清理与二次验证。
- [x] 建立 Issue 5 的 MoonBit/Wasm 浏览器桥接。
- [x] 完成 JPEG 的选择、检查、清理、复检和下载界面。
- [x] 使用真实 JPEG 完成浏览器人工验收。
- [x] 合并并部署 GitHub Pages 在线演示。

## Milestone 3 — 多格式扩展

- [x] 完成 Issue 3 的 PNG 检查、清理、复检和网页接入。
- [x] 完成普通、透明和动画 PNG 的浏览器人工验收。
- [x] 推送并合并 `feat/png`，确认 GitHub Pages 中的 PNG 闭环。
- [x] 完成 Issue 4 的 WebP 检查、清理、复检和网页接入。
- [ ] 完成有损、无损、透明、动画和带元数据 WebP 的浏览器人工验收。
- [ ] 推送并合并 `feat/webp`，确认 GitHub Pages 中的 WebP 闭环。

## Milestone 4 — 可用交付与验收

- [x] 完成 Issue 5 的 JPEG WebAssembly MVP、文档与线上演示。
- [x] 将 Issue 3 的 PNG 检查与清理接入网页。
- [x] 将 Issue 4 的 WebP 检查与清理接入网页。
- [ ] 完成 WebP 真实文件验收、全新克隆复现和最终文档。
- [ ] 在 JPEG、PNG、WebP 全部合并并部署后重新提交比赛报名。

## GitHub Issues

具体内容与验收标准见 [issues.md](issues.md)。
