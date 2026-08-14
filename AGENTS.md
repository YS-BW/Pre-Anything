# Pre-Anything 项目说明

这是一个 macOS Quick Look 扩展项目，用于在 Finder 中预览开发者常用的文本文件，当前支持 Markdown、JSON、YAML 和常见编程语言源码。

长期产品定位、设计原则与功能准入标准见 `docs/PRODUCT_DESIGN.md`。涉及产品范围或用户体验的决策应以该文档为基线。

## 技术方向

- 使用 Swift 和 SwiftUI，主目标为 macOS。
- 使用原生 Quick Look Preview Extension 接入 Finder 的空格预览。
- 第一版不引入 `WKWebView` 或 Electron；保持扩展轻量、快速、可靠。
- Markdown 使用原生阅读视图，并原生渲染常用 Mermaid、LaTeX 数学公式与常见代码语言高亮；JSON 使用保真格式化源码；YAML 使用原文高亮；Source Code 保留原文并提供原生高亮、行号和横向滚动。
- Markdown、JSON、YAML 和 Source Code 分别作为独立 Quick Look 扩展，由 macOS 负责启停；不同编程语言统一归入一个 Source Code 扩展，避免系统设置中出现大量开关。
- Containing App 提供扩展说明、系统管理入口，以及四类预览各自的透明背景开关；除此之外不扩展为通用设置中心。
- App 与四个扩展通过由签名 Team 派生的 macOS App Group（`<TeamID>.com.lixinlv.PreAnything`）共享这一项外观偏好；不得改回需要 provisioning profile 的 `group.` 前缀。

## 产品边界（MVP）

- `.md` / `.markdown`：固定渲染为原生阅读视图。
- `.json`：保留键顺序、重复键和数字写法的格式化、语法着色与解析错误提示。
- `.yaml` / `.yml`：不改写原文的语法着色与解析错误提示。
- 常见源码：保留全部文本，提供有界的原生词法高亮、行号、选择复制与长行横向滚动；不得执行或编译源码。
- 自动适配浅色与深色模式，并对超大文件安全降级。

## 实现约定

- 优先采用 Apple 平台 API 和最小依赖；新增第三方依赖前先说明必要性。
- Quick Look 扩展应避免网络请求、长时间任务和不必要的文件写入。
- 文件读取与解析必须处理无效内容、未知编码和大文件，不得让扩展崩溃。
- UI 文案优先使用英文，便于后续国际化；代码与注释使用清晰英文。
- 改动后优先运行相关的单元测试或构建验证。

## Git 约定

- 不提交 Xcode 用户数据、构建产物、DerivedData 或本地签名配置。
- 保持提交小而聚焦；不要在未经明确要求时重写历史或覆盖既有改动。
