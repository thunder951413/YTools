# AGENTS.md

## 项目定位

YTools 是仅面向 macOS 14+ 的个人原生效率工具，采用 Swift 6、AppKit 和 SwiftUI。仓库不包含 Electron、Node、网页插件、插件市场、心跳、遥测、广告、自动更新、HTTP/MCP Server 或任意 Shell 能力。

核心能力包括应用启动、拼音搜索、Spotlight 本地搜索、文件导航与动作、计算器、系统词典、拼写、加密剪贴板历史、Snippets、最近文档和源码级个人工具模块。

## 常用命令

```bash
./scripts/check.sh       # 严格编译、Core 回归和禁止 API 扫描
swift run YTools   # 运行调试版本
./scripts/build-app.sh   # 生成 dist/YTools.app 并 ad-hoc 签名
swift test               # 需要完整 Xcode/XCTest
```

## 结构

```text
Package.swift
Sources/
  YToolsCore/             # 无 UI 的计算器、快捷键路由、搜索文本规范化
  YToolsModuleKit/        # 个人源码模块协议、有限动作和宿主安全策略
  YToolsCoreChecks/       # 不依赖 XCTest 的回归入口
  YTools/
    Models/
    Modules/              # 应用、文件、计算、词典、系统、文本工具
    Services/             # 搜索、动作、加密存储、快捷键
    UI/                   # AppKit 面板与 SwiftUI 界面
Tests/YToolsTests/
Resources/AppIcon.icns
scripts/
```

## 架构规则

- AppKit/SwiftUI UI 和可观察状态位于 MainActor。
- 文件扫描、图片处理、加密存储和文件复制/移动必须由 Actor 或后台任务执行。
- 模块只返回 `LauncherResult`，所有副作用统一由 `ActionDispatcher` 执行。
- 内置与个人模块统一实现异步 `YToolsModuleKit.YToolsModule`，由 `SearchCoordinator` 调度并接受 `ModuleResultPolicy` 校验。
- 无权限模块只能复制文本、返回空动作或打开 YTools 设置。
- 文件动作必须是本机 `file://` URL 并获得 `localFileRead`；网页 URL 永远拒绝。
- 不动态加载 bundle、dylib、脚本或远程模块；新增模块必须随应用重新编译签名。
- 新增网络功能必须先得到用户明确同意，并隔离到 XPC Service；不要在主程序加入 `URLSession`。
- 系统命令只允许编译期固定路径和参数；不得接受用户输入作为命令、路径或参数。
- 安全存储失败不得降级写明文，也不得用空数据覆盖不可读密文。

## 修改要求

- 使用 Swift 6 并保持 `swift build -Xswiftc -warnings-as-errors` 通过。
- 纯逻辑优先进入 `YToolsCore` 或 `YToolsModuleKit` 并增加 CoreChecks/XCTest。
- 新增能力后同步 `README.md`、`ARCHITECTURE.md`、`SECURITY_AUDIT.md` 和 Alfred 对标文档。
- 不提交 `.build/`、`dist/`、用户数据、证书、公证凭据或钥匙串内容。
