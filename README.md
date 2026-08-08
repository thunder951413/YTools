# YTools（Windows + macOS）

YTools 是一个面向个人使用的原生启动器与本地效率工具，目标是提供接近 Alfred 的高频体验，同时保持离线优先、最小权限和可审计实现。仓库同时维护 macOS（Swift 6/AppKit/SwiftUI）与 Windows（C#/.NET 8/WPF）实现。

主程序不包含 Electron、Node、网页插件、插件市场、广告、遥测、心跳或自动更新。默认完全离线；唯一可选外联是用户明确启用的坚果云剪贴板同步。

## 功能

- **应用启动**：Windows 索引开始菜单入口、WindowsApps 别名与 AppsFolder 注册应用，并可加入本机 `.exe`、`.lnk`、`.appref-ms`；macOS 索引三个标准 Applications 目录，也可加入其他位置的有效 `.app` bundle。两端都支持自定义别名、拼音/缩写/模糊搜索，以及按频率、新近度、查询记忆和应用启动次数动态排名。
- **本地文件搜索**：已运行 [Everything](https://www.voidtools.com/) 时直接使用其只读本机 IPC（无需额外 SDK DLL）；可设置是否把文件加入默认结果，关闭后仅 `open/打开`、`find/查找`、`in/内容`、`tag/标签` 等显式前缀触发文件搜索。不可用时在后台回退到内置文件名扫描，不阻塞启动器 UI；支持 `/`、`~`、盘符目录导航。
- **文件操作**：目录导航、资源管理器显示、打开方式、复制/移动、路径复制及 Option（Alt）文件缓冲。
- **剪贴板历史**：独立快捷键、类型筛选、忽略进程、暂停、固定、分段清理、文本长度限制及 AES-GCM 加密存储（Windows 使用 DPAPI、macOS 使用登录钥匙串保护本机密钥）。两端可选择使用同一坚果云 WebDAV 同步协议：新内容各自端到端加密上传；重复复制只更新本机计数。后台每 15 分钟拉取轻量变更标记，无变更时不下载内容，也可从历史面板手动同步。
- **本地工具**：安全表达式计算、白名单数学函数、离线单位换算、离线中英词典（CC-CEDICT，后台预热）、英文拼写建议（Hunspell）、大字显示、Snippets 和最近文档。
- **系统命令**：可配置关键词；显示/清空回收站、启动屏幕保护、关闭显示器、专注模式与外观设置入口。
- **原生设置与启动器交互**：开机启动、面板外观样式、位置、宽度、快捷键、剪贴板、片段、系统命令、自定义应用、应用别名与隐私控制；亮色/暗色/跟随系统均使用完整的动态控件主题。支持设置 50–400 毫秒“输入停止后搜索”，连续输入会取消并重新计时，只为最终查询展开结果；启动器还包含搜索进度、清除按钮、空结果提示、鼠标双击启动、高 DPI 多屏位置校正，以及后台应用图标预取缓存。
- **源码工具模块**：内置与个人工具通过 `IYToolsModule` 契约编译进应用，结果由宿主校验，不动态加载外部代码。

默认快捷键：

- `Alt + Space`：显示启动器。
- `Alt + Ctrl + C`：显示剪贴板历史。
- `Ctrl + ,`：打开设置。

所有快捷键均可在设置中修改；被占用时自动回退到备用组合。

## 系统要求

- Windows 10 / 11（x64）。
- 发布版为自包含单文件，无需预装 .NET 运行时。
- 可选：安装 Everything 以获得即时文件搜索；未安装时自动使用内置扫描。
- macOS 14 或更高版本（从仓库根目录运行 `swift build`）。

## 构建

需要 .NET 8 SDK：

```powershell
./scripts/check.ps1      # 严格编译、80 项单元测试、27 项自检与禁止 API 扫描
./scripts/build.ps1      # 生成 dist/YTools.Windows/YTools.exe 单文件发布版
```

运行调试版：

```powershell
dotnet run --project src/YTools.Windows
```

自检模式（无 UI，CI 冒烟用）：

```powershell
src\YTools.Windows\bin\Release\net8.0-windows\YTools.exe --selftest
```

## 安全与隐私

- 默认不联网、不发送查询、文件名、使用记录或设备信息。只有用户在设置中保存坚果云应用密码与同步口令并显式启用后，才会向固定的 `https://dav.jianguoyun.com/dav/` 上传端到端加密的剪贴板增量记录；凭据和同步状态只保存在本机受保护保险库（Windows DPAPI、macOS 登录钥匙串）。
- 剪贴板、Snippets 与最近文档分别用 AES-GCM 加密；随机本机密钥受 Windows DPAPI（当前用户）或 macOS 登录钥匙串保护。
- 查询文本不能成为 Shell、脚本、可执行路径或任意 URL 参数；系统动作是编译期白名单。
- 清空回收站只在用户确认后调用固定的 `SHEmptyRecycleBin`；文件移入回收站使用系统 `IFileOperation` 等价 API，不提供永久删除。
- 不动态加载未签名的库；Everything 集成仅通过 `WM_COPYDATA` 连接本机已运行实例，发送与回复等待各设置 800ms 上限并校验返回缓冲区，不读取其数据库文件。
- 快捷键、剪贴板监听均为本机 Win32 消息；不申请辅助功能权限。

## 项目结构

```text
src/YTools.Windows/       # WPF 应用（C# / .NET 8）
  Core/                   # 纯逻辑：计算器、拼音搜索、命令路由、模块策略
  ModuleKit/              # 源码模块契约与宿主安全策略
  Models/                 # 偏好、数据模型
  Services/               # 搜索、动作、剪贴板、加密存储、热键、系统命令
  UI/                     # 启动器、剪贴板面板、设置、大字显示、预览
Tests/YTools.Windows.Tests/  # xUnit 回归测试
scripts/                  # check.ps1 / build.ps1
Sources/                  # macOS Swift 6/AppKit/SwiftUI 实现（Windows 构建忽略，macOS CI 独立验证）
```

## 文档

- [交付与验证状态](DELIVERY_STATUS.md)
- [架构和权限边界](ARCHITECTURE.md)
- [安全与外联审计](SECURITY_AUDIT.md)
- [个人模块开发](MODULE_DEVELOPMENT.md)
- [Alfred 功能对标](ALFRED_PARITY_SPEC.md)
- [实施路线图](ALFRED_ROADMAP.md)
- [第三方数据与许可证](THIRD_PARTY_NOTICES.md)

## 许可证

[MIT](LICENSE)。内置词典数据 CC-CEDICT 为 CC BY-SA 4.0，拼写词库来自 LibreOffice 词典项目，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
