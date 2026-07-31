# Windows 版架构与安全边界

## 定位

YTools 是个人使用的 Windows 原生工具，不再是通用插件平台。功能以源码级“工具模块”编译进应用，由宿主统一负责窗口、列表、键盘导航和动作执行。

应用入口直接创建 WPF `Application` 并交给 `MainController` 管理。启动器与剪贴板面板是无边框、透明背景、置顶的自绘窗口；设置是标准窗口；托盘图标提供与 macOS 菜单栏等价的操作入口。

```text
LauncherWindow / ClipboardWindow（WPF）
      │
LauncherModel（查询状态、排序、选择、缓冲、预览）
 ├─ SearchCoordinator（应用索引、文件导航、内置与个人模块并发调度）
 ├─ FileSearchService（Everything 引擎 → 内置文件名扫描回退）
 ├─ ResultAggregator（合并、排序与隐私化使用学习）
 ├─ ActionMenuController / ActionRegistry（类型化动作菜单）
 ├─ FileBufferStore（文件缓冲）
 ├─ IYToolsModule（内置与个人源码模块统一异步契约）
 └─ ActionDispatcher（有限动作词汇）
       └─ 文件复制/移动、回收站、资源管理器、系统设置 URI

Core（纯逻辑、可测试）
 ├─ ExpressionCalculator
 ├─ PanelCommandRouter
 └─ SearchTextNormalizer（TinyPinyin 拼音、首字母、缩写、模糊分）

ModuleKit（无 UI 的公共边界）
 ├─ IYToolsModule / ModuleDescriptor
 ├─ LauncherResult / 有限 ResultAction
 └─ ModuleResultPolicy（能力、路径、数量与分数校验）

加密数据层
 ├─ DpapiKeyAccessor（DPAPI 当前用户保护 32 字节随机密钥）
 ├─ AesGcmBox（AES-256-GCM：nonce + 密文 + tag）
 ├─ SecureCodableStore（Snippets / 最近文档）
 ├─ ClipboardHistoryStore（增量清单 + 独立记录与缩略图密文）
 ├─ ClipboardPersistenceService（串行化 + 修订号防旧快照覆盖）
 └─ UsageRankingStore（仅存 SHA-256 哈希）
```

模块只返回 `LauncherResult` 数据。内置模块与个人模块都由 `SearchCoordinator` 并发执行，并统一经过 `ModuleResultPolicy` 的描述符、字段长度、分数、能力与动作校验。复制、打开应用等副作用由宿主根据有限的 `ResultAction` 执行，避免向模块暴露一个包罗万象的全局 API。

## 平台映射（macOS → Windows）

| macOS 原实现 | Windows 实现 |
|---|---|
| Carbon `RegisterEventHotKey` | Win32 `RegisterHotKey` + 隐藏消息窗口 |
| `NSPasteboard` 轮询 | `AddClipboardFormatListener` + 序列号轮询回退 |
| Keychain（Security） | DPAPI `ProtectedData`（CurrentUser） |
| ServiceManagement 登录启动 | HKCU `...\CurrentVersion\Run` 固定值 |
| Spotlight `NSMetadataQuery` | Everything SDK（可选）+ 内置文件名扫描 |
| `/Applications` 应用扫描 | 开始菜单 `.lnk`（IShellLink）+ WindowsApps 别名 |
| `NSWorkspace` 打开/显示 | `Process.Start`（ShellExecute）与 `explorer.exe /select` |
| Quick Look | 内置预览面板（图片/文本/元信息） |
| 系统词典 `DCSCopyTextDefinition` | 离线 CC-CEDICT 索引 |
| `NSSpellChecker` | WeCantSpell.Hunspell + en_US 词库 |
| Finder 清空废纸篓 Apple Event | `SHEmptyRecycleBin`（二次确认） |
| `/usr/bin/pmset displaysleepnow` | `SendMessage` `SC_MONITORPOWER` |
| 系统设置面板 URI | `ms-settings:` URI |

## 性能与响应性契约

- 文本输入热路径只能更新轻量状态、取消任务和推进请求代次；不得同步扫描磁盘、加密或全量过滤。
- 普通本地模块使用用户配置的输入防抖；文件搜索额外等待至少 300ms 的稳定窗口。
- 空查询直接重置内存状态；后台请求同时使用 `CancellationToken` 与查询文本校验，迟到结果不能覆盖新查询。
- 面板高度只随结果数量、pending、动作菜单和样式变化；连续输入时保持输入行高度，最终查询完成后一次性展开。
- 剪贴板过滤在后台执行、支持取消并限制 UI 同时呈现最近 100 条；持久化仍保留完整加密历史。
- 边界必须明确：模块最多返回 40 条、文件搜索最多 100 条、应用结果最多 12 条。

## 明确不包含

- 插件市场、在线安装和远程插件
- WebView/JavaScript 插件运行时
- 动态加载未签名的程序集、库或脚本
- 心跳、遥测、广告、自动更新和启动联网
- 通用 HTTP Server、MCP Server 或任意 Shell API

## 自用工具的扩展方式

所有工具实现 `IYToolsModule` 并注册到 `SearchCoordinator`。内置系统模块由宿主显式授予所需能力；个人模块默认无权限。所有模块都需要重新编译，不存在运行时安装。完整示例见 `MODULE_DEVELOPMENT.md`。

无权限个人模块只能返回复制文本、空动作或打开 YTools 设置。文件动作必须声明并获得 `LocalFileRead`，且路径必须是本机绝对路径。主程序当前不授予网络能力；构建检查会拒绝网络、动态代码和 Shell API。

## 权限策略

- 计算器/单位换算/文本统计：无权限。
- 词典：只读内嵌 CC-CEDICT。
- 应用启动：只索引固定的开始菜单与 WindowsApps 目录，由宿主用 ShellExecute 启动。
- 文件搜索：Everything 只读 IPC；回退扫描器跳过 AppData、node_modules、系统目录并限制访问条目数。
- 剪贴板：单一管理器读取系统剪贴板；默认排除密码管理器进程与敏感格式（含 Windows 的 `ExcludeClipboardContentFromMonitorProcessing`），支持自定义忽略进程、暂停、固定和分段清理。持久化使用 AES-GCM，密钥由 DPAPI 保护；文本/文件默认记录，图片默认关闭且单项限制 5 MB。
- 窗口位置：拖动后的左上角换算为显示器工作区中的比例并保存；显示器变化时自动钳制在可见区域。
- 托盘：可按偏好隐藏，隐藏后全局快捷键、剪贴板监听与后台运行不受影响。
- 启动器样式：极简（默认）、经典、现代、玻璃四种原生预设，通过布局令牌与半透明画刷实现，不加载外部主题资源。
- 系统命令：只允许编译期固定的动作；关键词可在设置中修改或关闭，但永远不会成为 Shell、URL 或可执行参数。清空回收站始终二次确认；不读取受保护目录内容。
- 网络：主程序默认没有任何网络模块。

## 沙箱取舍

Windows 桌面应用以普通用户权限运行，数据目录位于 `%APPDATA%\YTools` 并做 ACL 收紧；未使用代码签名或 MSIX 沙箱。若未来需要对外分发，建议补充代码签名并评估 MSIX 打包。
