# 原生界面视觉审查

`native-components-light.png` 与 `native-components-dark.png` 由 `NativeViewSnapshotTests` 生成。它们渲染真实的 `ResultRow`、`ClipboardHistoryRow`、`SettingsCard` 和 `SettingsRow`，使用合成长文本与文件项目；不会创建剪贴板管理器、偏好对象，也不会访问钥匙串或真实剪贴板。

2026-09-30 新增 [剪贴板亮色](clipboard-panel-light.png) 与 [剪贴板暗色](clipboard-panel-dark.png)：用 `NSHostingView` 和离屏 AppKit 窗口渲染完整剪贴板视图，覆盖工具栏、长文本、固定按钮、复制失败提示和底部快捷键。夹具使用独立偏好域、临时保险库、注入密钥与独立命名剪贴板；不读写用户历史、钥匙串或系统通用剪贴板。不能用 `ImageRenderer` 直接绘制这些 AppKit 控件，否则会输出不支持的占位图。

运行：

v0.2.3 的完整剪贴板快照使用 251 条合成记录，覆盖固定筛选、匹配计数与始终可见的“加载更多”按钮。新增 `clipboard-pinned-light.png` 与 `clipboard-pinned-dark.png`，显示固定筛选只返回固定条目。

```sh
YTOOLS_UI_SNAPSHOT_DIR="$PWD/docs/ui-review" swift test --scratch-path /tmp/ytools-ui-snapshots -Xswiftc -warnings-as-errors --filter NativeViewSnapshotTests
```

## 0.3.0 完整窗口复核（2026-10-01）

macOS 新增完整 [片段编辑](settings-snippets-dark.png)、[设置搜索](settings-search-light.png)、[目标定位](settings-target-light.png) 和 [剪贴板全文预览](clipboard-preview-dark.png) 的亮暗快照。夹具使用离屏 `NSWindow` / `NSHostingView`，等待设置定位任务与原生控件布局后绘制；不会读取真实片段、偏好、凭据或剪贴板。

Windows CI 使用固定 `--ui-snapshot` 入口，在临时目录创建偏好、加密片段及合成剪贴板展示模型，渲染真实 WPF 设置与剪贴板窗口；不启动主控制器、剪贴板监控或同步。输出设置片段、搜索、目标定位和预览的亮暗 PNG，片段与预览另有 2x 渲染。`RenderTargetBitmap` 捕获的是窗口内容；显式绘制根背景，保留实际主题色。原生标题栏不在图片中。

最终 Windows 示例：[片段亮色](windows-settings-snippets-light.png)、[片段暗色](windows-settings-snippets-dark.png)、[搜索亮色](windows-settings-search-light.png)、[搜索暗色](windows-settings-search-dark.png)、[定位亮色](windows-settings-target-light.png)、[定位暗色](windows-settings-target-dark.png)、[预览亮色](windows-clipboard-preview-light.png)、[预览暗色](windows-clipboard-preview-dark.png)。图片来自代码 `fc4e48d` 的 [Windows push CI](https://github.com/thunder951413/YTools/actions/runs/36749653080)。搜索结果左对齐，片段操作位于列表上方，密码框沿用亮暗输入主题；切换分类会移除上一次设置目标高亮。

在 Windows 上运行：

```powershell
$env:YTOOLS_UI_SNAPSHOT_DIR = Join-Path $env:TEMP 'ytools-ui-review'
src\YTools.Windows\bin\Release\net8.0-windows\YTools.exe --ui-snapshot
```

目视复核覆盖亮暗主题、长文本换行/截断、选中态、固定按钮、片段列表与编辑器、搜索空白提示、密码框主题、具体设置定位和控件对齐。Swift 和 Windows CI 都上传原生窗口图片。快照不替代真实键鼠操作、中文 IME 候选窗、多屏/实际 DPI 切换、屏幕阅读器或系统服务的端到端验收；本轮交互环境边界与最终证据记录在 [完成清单](../COMPLETION_CHECKLIST.md)。
