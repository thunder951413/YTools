# 原生版交付状态

更新日期：2026-07-19

## 已通过

- Swift 6 Debug 严格编译，`-warnings-as-errors`。
- 无 XCTest Core 检查：计算器、快捷键路由、拼音/首字母转换、模块能力与外链拒绝策略。
- arm64 Release `.app` 构建及 ad-hoc `codesign --deep --strict` 验证。
- Release 二进制依赖检查：仅系统 AppKit、SwiftUI、Foundation、CryptoKit、ImageIO、Quick Look、Security、ServiceManagement 等框架。
- Release 二进制字符串检查：无 HTTP(S) URL、`URLSession`、`WKWebView`、动态加载或 Shell 路径。
- 进程启动冒烟：持续运行、空闲 CPU 接近 0%，实测 physical footprint 约 55 MB。
- 剪贴板密文实机权限：目录 `0700`、文件 `0600`。
- 剪贴板加载、图片处理和密文读写已移出 MainActor。
- 内置与个人源码模块统一异步调度且不动态加载；结果经过宿主能力、file URL、字段长度、动作、数量和分数校验。
- 启动器协调层已拆出结果聚合、动作菜单和文件缓冲；文件导航为显式 `Sendable` 值类型。
- 设置文件选择器不再阻塞主线程；快捷键主注册与回退共用同一路径。
- `AppPreferences` 已带 schema 版本迁移入口，ServiceManagement 副作用隔离在可替换服务中。
- 启动器输入采用轻量模块与 Spotlight 分级防抖；空查询不会启动搜索，输入/删除热路径无同步 MetadataQuery 停止。
- 面板布局使用窄语义发布器，不再订阅模型和偏好对象的全部变化；剪贴板过滤已后台化并限制 UI 结果规模。
- 剪贴板新增 100–10000 字符可配置的单条文本上限；默认输入源、Finder 标签搜索及完整文件导航排序已加入。
- 启动器支持拖动后记住位置；连续移动合并写入，多屏布局变化时保证窗口仍在可见区域。
- 菜单栏图标可隐藏，隐藏后全局快捷键、剪贴板监听和后台运行不受影响。
- 默认启动器空闲态已收敛为单行输入框，并提供极简、经典、现代、玻璃四种本机原生外观预设。
- 新增独立“系统命令”设置页：可启停和自定义 `empty`、`trash`、`screensaver`、`sleepdisplays`、`dnd`、`theme`；永久清空废纸篓始终二次确认并使用固定 Finder Apple Event，不申请完全磁盘访问；勿扰和主题只导航到系统设置。设置窗口支持 `Command + W` 关闭。
- 系统词典结果在列表中只显示单行精炼摘要，完整释义仍用于复制、大字显示和文本片段动作；普通结果副标题统一限制为单行，避免固定行高下发生换行裁切。
- 完整 Xcode 环境下 `swift test` 已通过 24 项测试；连续输入与逐字符删除已通过本机可访问性回归。

## 当前环境无法完成

- VoiceOver 完整流程、中文输入法候选、多屏拖动和 Quick Look 动画仍需人工感知验收；自动化已覆盖普通英文连续输入、删除和焦点保持。
- Developer ID、公证和 Gatekeeper 分发验证：需要用户的 Apple Developer 证书、完整 Xcode 和公证凭据。

## 交付结论

当前 `.app` 适合在本机个人使用和继续功能开发。若要发给其他用户，必须先完成完整 Xcode App target、Hardened Runtime、Developer ID 签名、公证和上述 UI/无障碍实机验收。
