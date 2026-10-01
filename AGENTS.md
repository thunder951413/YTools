# AGENTS.md（Windows + macOS）

## 项目定位

YTools 是面向 Windows 10/11 与 macOS 的个人原生效率工具：Windows 使用 C#、.NET 8 与 WPF，macOS 使用 Swift/AppKit/SwiftUI。两个实现都在本仓库主动维护；不得把 `Sources/` 当作仅供参考的遗留代码。仓库不包含 Electron、Node、网页插件、插件市场、心跳、遥测、广告、自动更新、HTTP/MCP Server 或任意 Shell 能力。

核心能力包括应用启动、拼音搜索、本地文件搜索、文件导航与动作、计算器、离线词典、拼写、加密剪贴板历史、Snippets、最近文档和源码级个人工具模块。Windows 构建不编译 `Sources/`，但 macOS CI 独立验证它。

## 常用命令（PowerShell）

```powershell
./scripts/check.ps1       # 严格编译、单元测试、自检和禁止 API 扫描
./scripts/build.ps1       # 生成 dist/YTools.Windows/YTools.exe 单文件发布版
dotnet test               # 单元测试
src\YTools.Windows\bin\Debug\net8.0-windows\YTools.exe --selftest
```

## 结构

```text
YTools.Windows.sln
src/YTools.Windows/
  Core/             # 无 UI 逻辑：计算器、拼音搜索、命令路由、策略
  ModuleKit/        # IYToolsModule 契约、LauncherResult、ModuleResultPolicy
  Models/           # AppPreferences、剪贴板/片段/最近文档模型
  Services/         # 搜索、动作、加密存储、热键、剪贴板、系统命令
  UI/               # WPF：启动器、剪贴板、设置、大字显示、预览、托盘
  Resources/        # 图标、CC-CEDICT、Hunspell 词库（嵌入程序集）
Tests/YTools.Windows.Tests/
scripts/
```

## 架构规则

- 所有 WPF UI 与可变状态位于 UI 线程（Dispatcher）；文件扫描、图片处理、加密存储与文件复制/移动必须放到后台任务（`Task.Run`/actor 式服务）。
- 模块只返回 `LauncherResult`，所有副作用统一由 `ActionDispatcher` 执行。
- 内置与个人模块统一实现异步 `IYToolsModule`，由 `SearchCoordinator` 调度并经过 `ModuleResultPolicy` 校验。
- 无权限模块只能复制文本、返回空动作或打开 YTools 设置。
- 文件动作必须是本机完整绝对路径；Windows 统一使用 `LocalPathPolicy`，拒绝相对路径、URL、UNC、设备路径与备用数据流。
- 不动态加载 bundle、dylib、脚本、远程模块或 Everything SDK DLL。
- Everything 集成仅能通过已运行 Everything 的 `WM_COPYDATA` 本机 IPC 做只读查询；不得联网、读取其数据库或加载第三方搜索代码。
- 新增网络功能必须先得到用户明确同意。现有坚果云剪贴板同步是唯一例外：用户保存凭据并显式启用后，两端仅可使用固定 `https://dav.jianguoyun.com/dav/` WebDAV 端点；其他 `HttpClient`/`WebClient`/Socket/`URLSession` 调用会被统一安全扫描拒绝。
- 系统命令只允许编译期固定 API（`SHEmptyRecycleBin`、`SendMessage` 固定消息、`ms-settings:` URI、固定 `rundll32 shell32.dll,OpenAs_RunDLL` 参数模板）；不得接受用户输入作为命令、路径或参数。
- 加密存储失败不得降级写明文，也不得用空数据覆盖不可读密文。
- 源码模块不是沙箱或安全边界。它们与宿主同进程、同用户权限运行，必须经过代码审查并重新编译；`ModuleResultPolicy` 只约束模块返回的数据和已注册动作。

## 修改要求

- 保持 `dotnet build -warnaserror` 通过（`TreatWarningsAsErrors` 已启用）。
- 纯逻辑优先进入 `Core`/`ModuleKit` 并补充 xUnit 测试与 `SelfTest` 条目。
- 新增能力后同步 `README.md`、`ARCHITECTURE.md`、`SECURITY_AUDIT.md` 和 Alfred 对标文档。
- 不提交 `bin/`、`obj/`、`dist/`、用户数据、密钥或日志。
