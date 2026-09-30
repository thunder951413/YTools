# 原生界面视觉审查

`native-components-light.png` 与 `native-components-dark.png` 由 `NativeViewSnapshotTests` 生成。它们渲染真实的 `ResultRow`、`ClipboardHistoryRow`、`SettingsCard` 和 `SettingsRow`，使用合成长文本与文件项目；不会创建剪贴板管理器、偏好对象，也不会访问钥匙串或真实剪贴板。

2026-09-30 新增 [剪贴板亮色](clipboard-panel-light.png) 与 [剪贴板暗色](clipboard-panel-dark.png)：用 `NSHostingView` 和离屏 AppKit 窗口渲染完整剪贴板视图，覆盖工具栏、长文本、固定按钮、复制失败提示和底部快捷键。夹具使用独立偏好域、临时保险库、注入密钥与独立命名剪贴板；不读写用户历史、钥匙串或系统通用剪贴板。不能用 `ImageRenderer` 直接绘制这些 AppKit 控件，否则会输出不支持的占位图。

运行：

```sh
YTOOLS_UI_SNAPSHOT_DIR="$PWD/docs/ui-review" swift test --scratch-path /tmp/ytools-ui-snapshots -Xswiftc -warnings-as-errors --filter NativeViewSnapshotTests
```

快照检查覆盖亮暗主题、长文本截断、选中态、固定按钮和设置行右侧控件对齐。Swift CI 显式设置快照输出目录并上传图片，避免因缺少环境变量跳过。它不替代真实窗口输入、中文 IME、多屏/DPI、WPF 或系统服务的端到端验收。
