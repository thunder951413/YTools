# 自用原生模块开发

YTools 不加载外部插件、网页或脚本。个人工具以 Swift 源码实现，重新编译后与宿主一起签名。公共边界位于 `YToolsModuleKit`，模块只计算结构化结果，不能直接持有窗口、剪贴板、Shell 或宿主对象。

## 最小模块

```swift
import YToolsModuleKit

struct MyTextTool: YToolsModule {
    let descriptor = ModuleDescriptor(id: "my-text-tool", name: "我的文本工具")

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        guard request.query.hasPrefix("my ") else { return [] }
        let value = String(request.query.dropFirst(3))
        return [LauncherResult(
            id: "my-text-tool:result",
            moduleID: descriptor.id,
            title: value.uppercased(),
            subtitle: "回车复制",
            icon: .system("textformat"),
            score: 900,
            action: .copy(value.uppercased())
        )]
    }
}
```

将实例加入 `SearchCoordinator` 的 `personalModules` 后重新构建。内置工具也使用同一个异步协议和结果校验路径。仓库中的 `TextStatisticsModule` 是可直接参考的无权限示例，输入 `stats 文本`、`统计 文本` 或 `字数 文本` 使用。

## 能力和宿主校验

模块可声明 `localFileRead`、`clipboardRead`、`contactsRead` 或 `calendarRead`。声明不等于获得权限：宿主还必须显式授予，`ModuleResultPolicy` 才会接纳结果。

- 无权限模块只允许复制文本、空动作和打开 YTools 设置。
- 文件图标、打开、访达显示和目录导航必须同时声明并获得 `localFileRead`，且 URL 必须是本地 `file://`。
- 网页 URL 会被拒绝，不会交给 `NSWorkspace`。
- 隐藏/退出应用和系统控制动作不会开放给个人模块。
- 每个模块每次最多接纳 20 条结果，分数被限制在宿主范围内，模块身份由宿主重写。
- 错误只丢弃该模块本次结果，不关闭启动器；模块应响应 Task cancellation。

能力策略约束的是宿主接受和执行的结构化结果，并不能沙箱同一进程内的 Swift 代码。因此个人模块必须接受源码审查；`scripts/check.sh` 还会拒绝主程序中的网络、网页、动态加载和 Shell API。系统控制动作只授予仓库内明确注册的内置模块。

未来确需网络时，不应把 `URLSession` 加进主程序，也不应仅增加一个声明式 `network` 能力。应建立独立 XPC Service，并真正实施域名白名单、HTTPS、超时、响应大小上限和显式开关。

## 开发检查

```bash
./scripts/check.sh
```

`YToolsCoreChecks` 会验证计算器、快捷键路由、拼音规范化和模块结果安全策略。完整 Xcode 环境还应运行 `swift test`。
