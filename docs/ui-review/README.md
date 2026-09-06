# 原生组件视觉审查

`native-components-light.png` 与 `native-components-dark.png` 由 `NativeViewSnapshotTests` 生成。它们渲染真实的 `ResultRow`、`ClipboardHistoryRow`、`SettingsCard` 和 `SettingsRow`，使用合成长文本与文件项目；不会创建剪贴板管理器、偏好对象，也不会访问钥匙串或真实剪贴板。

运行：

```sh
YTOOLS_UI_SNAPSHOT_DIR="$PWD/docs/ui-review" swift test --scratch-path /tmp/ytools-ui-snapshots -Xswiftc -warnings-as-errors --filter NativeViewSnapshotTests
```

这是一项组件级视觉检查，覆盖亮暗主题、长文本截断、选中态、固定按钮和设置行右侧控件对齐；不替代完整窗口或系统服务的端到端验收。
