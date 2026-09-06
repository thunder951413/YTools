# 全项目修复与 UI 优化验收

日期：2026-09-06。基线：`windows` 分支、`1744a60`，评估时工作树干净。本轮修改保留在工作树，未提交、推送或安装。

## 修复覆盖

| 原评估 | 实现结果 | 主要证据 |
|---|---|---|
| R01 旧剪贴板回调覆盖新状态 | Windows 完成回调携带 revision，每次等待后只允许当前版本更新 UI；历史事件发布独立于 UI 版本 | `ClipboardHistoryManager.cs`；主线程回调路径复核 |
| R02 不可读密文覆盖/损坏记录被清理 | 双端通用存储认证或解码失败后锁定；存在密文不重建密钥；Windows 原子替换；部分损坏剪贴板保留原文件 | 双端 `ClipboardReliabilityTests`；Swift 损坏清单/记录保留测试已执行 |
| R03 同步旧快照回写 | 服务返回远端事件，管理器在当前历史上合并，保留请求期间的本地修改 | 双端合并回归；Swift 已执行、Windows 已编译 |
| R04 游标提前推进 | 事件与游标保存到可重放加密收件队列；历史成功落盘才确认；拉取任一设备失败不提交本批游标 | Swift 假传输测试覆盖设备 A 成功/B 失败、重试、重启恢复、确认移除 |
| R05 乱序删除冲突 | 持久化删除标记；旧 Upsert 不复活删除内容，旧 Delete 不抹去较新修改；同时间冲突确定性合并 | 双端删除/同时间冲突测试 |
| R06 正常退出强杀 | 移除超时强杀，按完整可执行路径识别目标，只发送正常关闭请求 | Windows 动作身份测试已编译；保存对话框实机待验 |
| R07 扫描与 CI 阻断 | Python 标准库统一扫描，仅精确放行已授权同步；API、端点、重复构造负例检查；双端 CI 覆盖维护分支 | 本机安全扫描与 fixture 全部通过 |
| R08 macOS 同步可重入 | actor 外的 UI 与加密分离，事务门串行执行网络批次，旧 UI revision 不漏发事件 | Swift 并发发布测试验证远端 head 顺序 `[1, 2]` |
| R09 UI 线程重操作 | 同步加密、Snippet/Recent 加载保存、Windows 文件复制移动转后台；保存显式排队；成功提示等待真实落盘 | 双端后台存储测试；Swift 已执行；Windows 编译及线程边界复核 |
| R10 回退索引不更新 | 成功索引过期后可刷新，完成通知当前查询，失败保留旧快照，单目录枚举隔离异常 | Windows 首次完成/重新刷新/失败保留测试已编译 |
| R11 目录/批量动作不闭环 | 支持目录复制与跨卷移动，拒绝源目录内目标和目录重解析点；回收站使用后台 STA 的 IFileOperation；批量按目录选择，失败保留缓冲 | Windows 严格编译；COM/文件系统实机动作待验 |
| R12 旧搜索成功结果覆盖 | 成功、失败、取消均检查请求代次、查询、取消令牌；模块收到取消令牌并受超时约束；预览也采用代次保护 | Windows 搜索发布/取消测试已编译；Swift 预览成功路径校验 |
| R13 路径策略不一致 | `LocalPathPolicy` 统一模块结果、图标和动作入口；拒绝盘符相对、根相对、URL、UNC、设备路径和 ADS | Windows 路径用例和新增 SelfTest 条目已编译 |

其他边界修正：图片同步读取原图而非缩略图；同步事件大小统一包含加密封装开销；流式接收设上限；接收设备 ID 与 head 文件名匹配；切换账号/目录时隔离序号空间，旧队列未处理完则阻止混用。

## UI 优化

- macOS 启动器补充查询进度、清除入口和快捷键/无障碍提示；剪贴板固定按钮有明确点击区域；设置说明与右侧控件分列，长文本截断不侵占操作区。
- Windows 启动器显示后台文件动作忙碌状态；剪贴板优化筛选、空状态、同步按钮禁用与反馈、工具提示和无障碍名称；列表使用虚拟化。
- Windows 预览开始时立即清除旧内容，异步解码按展示尺寸限制；关闭/切换后旧请求不得重新显示。剪贴板缩略图也限制解码尺寸。
- 使用真实 SwiftUI 组件生成 [亮色](ui-review/native-components-light.png) 和 [暗色](ui-review/native-components-dark.png) 快照。目视检查发现的固定按钮占位图已修正。快照是组件级证据，不代表 WPF 或完整窗口已实机验证。

## 本机验证

| 检查 | 本轮结果 |
|---|---|
| macOS 严格构建 + XCTest + CoreChecks | `scripts/check.sh` 通过；62 项 XCTest，0 失败 |
| 安全扫描与负例 fixture | 通过，检查 macOS 与 Windows 产品源码 |
| macOS Release 应用包 | 构建、ad-hoc 签名、Info.plist 校验及 `codesign --verify --deep --strict` 通过 |
| Windows Release 交叉编译 | 应用及 xUnit 测试程序集通过，0 警告、0 错误 |
| Windows win-x64 自包含单文件 | 生成成功，PE32+ x86-64 GUI 可执行文件 |
| Windows xUnit / SelfTest / WPF 运行 | 当前 macOS 缺少 WindowsDesktop 运行时，不能执行；尚待 Windows 验证 |
| 工作树检查 | `git diff --check` 通过；构建输出未加入 Git |

主要命令（本机独立缓存，不修改全局 Xcode 选择）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  YTOOLS_BUILD_PATH=/tmp/ytools-fix-build \
  YTOOLS_UI_SNAPSHOT_DIR=/tmp/ytools-final-ui ./scripts/check.sh

/tmp/ytools-dotnet/dotnet build YTools.Windows.sln -c Release \
  -p:EnableWindowsTargeting=true -warnaserror

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  YTOOLS_BUILD_PATH=/tmp/ytools-fix-build \
  YTOOLS_DIST_DIR=/tmp/ytools-repair-release ./scripts/build-app.sh
```

打包产物：`/tmp/ytools-repair-release/YTools.app`、`/tmp/ytools-repair-release/windows/YTools.exe`。它们用于本轮验证，临时目录可能被系统清理；可用仓库构建脚本重新生成。

## 验证边界与交接

测试仅使用临时目录、合成数据、注入密钥及假 WebDAV 传输。没有连接真实坚果云、读取真实历史/钥匙串、发送应用关闭请求或执行真实文件回收操作。Windows 需要执行 `./scripts/check.ps1`，再进行回收站、跨卷操作、中文输入法、多屏/DPI、快捷键和屏幕阅读器验收。真实跨设备同步、第三方 WebDAVClient 的完整依赖审计以及正式签名不在本次已验证结论内。

按项目成本偏好，Sol 子任务完成 Windows 动作/索引和双端后台存储，Terra 子任务完成原生 UI、组件快照和扫描/CI；主任务完成密文保护、同步状态机、回归用例、集成复核和最终构建。复核中纠正了 actor 入队顺序假设、异步测试断言、STA 线程要求及固定按钮渲染问题；未估算或虚构节省金额。
