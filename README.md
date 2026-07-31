# YTools (Windows)

YTools 是一个面向个人使用的 **Windows 原生启动器与本地效率工具**，目标是提供接近 Alfred 的高频体验，同时保持离线优先、最小权限和可审计实现。本分支是原 macOS 版（Swift 6/AppKit/SwiftUI）的完整 Windows 移植，使用 **C# / .NET 8 / WPF** 重写。

主程序不包含 Electron、Node、网页插件、插件市场、广告、遥测、心跳、自动更新或任何网络客户端。

## 功能

- **应用启动**：索引开始菜单快捷方式（.lnk，经 Shell COM 解析）与 WindowsApps 应用执行别名，支持名称、英文缩写、中文拼音全拼及首字母搜索；可在设置中为任意应用添加中文名、简称或拼音别名。
- **本地文件搜索**：已安装 [Everything](https://www.voidtools.com/) 时自动使用 Everything 引擎（文件名、`in/内容` 内容与 `tag/标签` 语法）；未安装时回退到内置文件名扫描。支持 `open/打开`、`find/查找` 前缀与 `/`、`~`、盘符目录导航。
- **文件操作**：目录导航、资源管理器显示、打开方式、复制/移动、路径复制及 Option（Alt）文件缓冲。
- **剪贴板历史**：独立快捷键、类型筛选、忽略进程、暂停、固定、分段清理、文本长度限制及 AES-GCM 加密存储（密钥由 DPAPI 保护）。
- **本地工具**：安全表达式计算、白名单数学函数、离线单位换算、离线中英词典（CC-CEDICT）、英文拼写建议（Hunspell）、大字显示、Snippets 和最近文档。
- **系统命令**：可配置关键词；显示/清空回收站、启动屏幕保护、关闭显示器、专注模式与外观设置入口。
- **原生设置**：开机启动、面板外观样式、位置、宽度、快捷键、剪贴板、片段、系统命令、应用别名与隐私控制。
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

## 构建

需要 .NET 8 SDK：

```powershell
./scripts/check.ps1      # 严格编译、58 项单元测试、23 项自检与禁止 API 扫描
./scripts/build.ps1      # 生成 dist/YTools.Windows/YTools.exe 单文件发布版
```

运行调试版：

```powershell
dotnet run --project src/YTools.Windows
```

自检模式（无 UI，CI 冒烟用）：

```powershell
src\YTools.Windows\bin\Debug\net8.0-windows\YTools.exe --selftest
```

## 安全与隐私

- 主程序没有网络客户端，不发送查询、剪贴板、文件名、使用记录或设备信息。
- 剪贴板、Snippets 与最近文档分别用 AES-GCM 加密，随机密钥由 Windows DPAPI（当前用户）保护；数据目录 ACL 仅允许当前用户。
- 查询文本不能成为 Shell、脚本、可执行路径或任意 URL 参数；系统动作是编译期白名单。
- 清空回收站只在用户确认后调用固定的 `SHEmptyRecycleBin`；文件移入回收站使用系统 `IFileOperation` 等价 API，不提供永久删除。
- 不动态加载未签名的库；仅当本机已安装 Everything 时加载其官方 `Everything64.dll` 做只读查询。
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
Sources/                  # macOS 原版 Swift 源码（仅作移植参考，本分支不参与构建）
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
