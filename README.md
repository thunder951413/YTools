# YTools

YTools 是一个面向个人使用的 macOS 原生启动器与本地效率工具，目标是提供接近 Alfred 的高频体验，同时保持离线优先、最小权限和可审计实现。

项目使用 Swift 6、AppKit、SwiftUI 与 macOS 系统框架，不包含 Electron、Node、网页插件、插件市场、广告、遥测、心跳、自动更新或启动联网。

## 功能

- 应用启动：索引本机 Applications，支持名称、英文缩写、中文拼音全拼及首字母搜索；可在设置中为任意应用添加中文名、简称或拼音别名。
- 本地搜索：Spotlight 文件名、正文与 Finder 标签搜索；支持 `open/打开`、`find/查找`、`in/内容` 和 `tag/标签`。
- 文件操作：`/`、`~` 目录导航、Quick Look、打开方式、复制/移动、访达显示、路径复制及 Option 文件缓冲。
- 剪贴板历史：独立快捷键、类型筛选、忽略应用、暂停、固定、分段清理、文本长度限制及 AES-GCM 加密存储。
- 本地工具：安全表达式计算、白名单数学函数、离线单位换算、系统词典、拼写建议、Large Type、Snippets 和最近文档。
- 系统命令：可配置关键词；屏幕保护、显示废纸篓、关闭显示器、勿扰与外观设置入口，以及确认后通过固定 Finder 事件清空废纸篓。
- 原生设置：启动行为、跨分辨率相对窗口位置、默认输入源、搜索内容类型、应用别名、外观风格、结果展开速度、快捷键、剪贴板、系统命令、文本片段及隐私控制。
- 源码工具模块：内置与个人工具通过 `YToolsModuleKit` 编译进应用，模块结果由宿主校验，不动态加载外部代码。

默认快捷键：

- `Option + Space`：显示启动器。
- `Option + Command + C`：显示剪贴板历史。
- `Command + ,`：打开设置。

所有快捷键均可在设置中修改。

## 系统要求

- macOS 14 或更高版本。
- Swift 6；完整测试建议使用完整 Xcode。

## 构建

运行严格构建、核心回归与安全边界扫描：

```bash
./scripts/check.sh
```

运行调试版本：

```bash
swift run YTools
```

生成 ad-hoc 签名的应用：

```bash
./scripts/build-app.sh
open dist/YTools.app
```

运行完整测试：

```bash
swift test
```

Developer ID、Hardened Runtime 和公证分发需要相应的 Apple Developer 证书与凭据。

## 安全与隐私

- 主程序没有网络客户端，不发送查询、剪贴板、文件名、使用记录或设备信息。
- 剪贴板、Snippets 与最近文档分别加密，随机密钥保存在登录钥匙串。
- 查询文本不能成为 Shell、脚本、可执行路径或任意 URL 参数。
- 系统动作是编译期白名单；永久操作在执行时确认。
- 清空废纸篓只在用户确认后请求 Finder 执行固定、无参数的 `fndr/empt` 事件，不申请完全磁盘访问。
- 不申请辅助功能权限；未来确需网络的个人工具必须隔离、限制域名并由用户显式启用。

## 项目结构

```text
Sources/
  YTools/             # AppKit/SwiftUI 应用、模块、服务与界面
  YToolsCore/         # 无 UI 的可测试核心逻辑
  YToolsModuleKit/    # 源码工具模块契约与宿主安全策略
  YToolsCoreChecks/   # 不依赖 XCTest 的核心回归入口
Tests/YToolsTests/    # XCTest 回归测试
Resources/            # 应用图标
scripts/              # 构建与检查脚本
```

## 文档

- [交付与验证状态](DELIVERY_STATUS.md)
- [架构和权限边界](ARCHITECTURE.md)
- [安全与外联审计](SECURITY_AUDIT.md)
- [个人模块开发](MODULE_DEVELOPMENT.md)
- [Alfred 功能对标](ALFRED_PARITY_SPEC.md)
- [实施路线图](ALFRED_ROADMAP.md)

## 许可证

[MIT](LICENSE)
