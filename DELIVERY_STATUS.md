# Windows / macOS 交付状态

更新日期：2026-08-04（`windows` 分支）

## 已通过

- C# / .NET 8 / WPF 全量移植：启动器、剪贴板面板、设置窗口、大字显示、预览面板、托盘。
- `dotnet build -warnaserror` 严格编译通过（0 警告 0 错误）。
- 80 项 xUnit 单元测试全部通过（计算器、拼音规范化、命令路由、模块策略、应用索引、Everything 协议、词典冷启动、文件查询模式、使用频次、位置、文本策略）。
- 27 项无 UI 自检全部通过（含离线词典 CC-CEDICT 加载、Hunspell 拼写和 Everything IPC 协议解析）。
- Release 自包含单文件发布：`dist/YTools.Windows/YTools.exe`（约 71 MB），无需预装 .NET。
- 发布版冒烟：进程稳定运行、空闲无异常、`%APPDATA%\YTools\error.log` 为空。
- 全局热键（`RegisterHotKey`）、剪贴板监听（`WM_CLIPBOARDUPDATE` + 轮询回退）、开机启动（Run 键）、托盘图标已实现并冒烟。
- 快捷键冲突处理：默认组合被占用时自动尝试多组备用组合并持久化；冲突提示直接显示在启动器中；二次启动会唤醒已有实例。
- 修复原生崩溃：渲染文件图标前在 UI 线程显式初始化 STA COM（`CoInitializeEx`），`SHGetFileInfo` 不再访问违规；图标提取失败会缓存为通用字形兜底。
- 修复退出异常：仅当实例真正持有单实例互斥锁时才 `ReleaseMutex`，二次启动实例退出不再弹错误框。
- 加密存储：DPAPI 密钥 + AES-256-GCM；剪贴板增量 vault、Snippets、最近文档独立密钥/文件。
- 安全扫描：无网络 API、无动态加载、无 Shell 命令（`scripts/check.ps1` 与 CI 强制）。

## macOS 对齐

- 应用搜索沿用 Spotlight 索引，并补齐自定义 `.app`、严格 bundle 校验、路径去重和设置管理。
- 应用结果按匹配分、启动频次和本地化标题稳定排序；使用记录异步串行落盘，不阻塞搜索输入。
- 应用索引采用 generation 驱动的后台刷新；已有快照立即返回，避免索引更新拖慢逐键搜索。
- macOS CI 通过 `scripts/check.sh` 严格编译并执行 48 项 Swift 测试，再由 `scripts/build-app.sh` 生成和校验应用包。

## 需要人工验收（本机无法自动覆盖）

- 多显示器拖动、比例记忆与显示器热插拔布局。
- 中文输入法组合期间的快捷键路由（已实现 IMM 组合态保护，仍需实机输入法验证）。
- 与真实应用/Everything 组合的端到端搜索体验。
- 无障碍（屏幕阅读器）流程。
- Authenticode 代码签名、SmartScreen 与对外分发流程（需要用户的签名证书）。

## 交付结论

当前 `YTools.exe` 适合本机个人使用：核心功能闭环、测试与自检全绿、单文件绿色发布。若要分发给其他用户，建议先完成代码签名与对外分发验收。
