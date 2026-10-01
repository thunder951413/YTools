# Windows / macOS 交付状态

更新日期：2026-09-06。基于 `windows` 分支当前修复工作树，尚未提交或发布。

## 本轮已验证

- macOS `scripts/check.sh` 完整通过：严格编译、62 项 XCTest（0 失败）、核心自检、统一安全扫描及其 fixture 测试。
- Windows 使用 .NET SDK 8.0.424 交叉编译 Release：应用与测试程序集均生成，0 警告、0 错误。
- 两端 Release 打包通过：macOS 应用包经过 ad-hoc 签名和校验，Windows 生成 win-x64 自包含单文件。产物位于 `/tmp/ytools-repair-release/`，没有替换已安装应用或原有 `dist/`。
- 真实 SwiftUI 组件的亮暗主题快照已生成并目视检查，覆盖长文本截断、选中态、固定按钮与设置控件对齐。见 [组件预览](docs/ui-review/README.md)。
- 修复原评估列出的 13 项问题，补充同步重试/重启恢复、删除冲突、不可读密文保护、后台存储顺序、文件索引和搜索取消测试。逐项证据见 [修复验收记录](docs/REPAIR_VALIDATION.md)。
- macOS 与 Windows CI 均覆盖 `main`、`windows` 分支，使用相同安全扫描规则。此处记录的是本机结果，未提交触发远程 CI。

## 尚需 Windows 和实际使用环境验证

- 当前主机是 macOS，不能运行 WindowsDesktop/WPF：本轮 Windows xUnit、`--selftest`、回收站 COM、跨卷移动与完整窗口交互尚未执行。测试程序集编译通过不能替代这些检查。
- Windows 执行 `./scripts/check.ps1` 后，再验证普通退出的保存提示、文件夹动作、Everything 回退刷新、大文件后台操作及批量选择。
- 双端中文输入法、全局热键、多屏/DPI、辅助功能、真实应用图标与完整窗口布局仍需实机冒烟。
- 同步状态机测试使用注入的假传输、临时密文和测试密钥；未访问真实剪贴板、钥匙串、坚果云凭据或远端数据。
- 新版可接受更大的图片事件，旧版 6 MiB 接收上限可能拒绝它们；跨设备使用时应同步升级客户端。实际端到端同步尚待验证。
- Windows Authenticode 与 macOS Developer ID/公证均未完成；本轮不作对外分发已验收的结论。

## 交付判断

代码修复、可在本机执行的检查及组件视觉检查已完成。Windows 实机、真实同步与签名分发仍是发布前验收项，不沿用历史版本的测试或冒烟结果作为本次证明。
