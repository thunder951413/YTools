# 个人源码模块开发（Windows 版）

个人工具以源码形式编译进 YTools，宿主负责权限、UI 与副作用。模块只需要实现 `IYToolsModule`。模块不是沙箱：它与宿主同进程、同用户权限运行；`ModuleResultPolicy` 约束返回结果和宿主动作，不隔离模块自行写出的代码。因此只接受经过代码审查并重新编译的模块。

```csharp
using YTools.ModuleKit;

public sealed class MyToolModule : IYToolsModule
{
    public ModuleDescriptor Descriptor { get; } = new("my-tool", "我的工具");

    public Task<IReadOnlyList<LauncherResult>> SearchAsync(ModuleSearchRequest request)
    {
        var results = new List<LauncherResult>();
        // 只允许返回结构化结果，不允许执行任何副作用。
        results.Add(new LauncherResult(
            "my-tool:hello",
            Descriptor.Id,
            "你好",
            "回车复制",
            new ResultIcon.System("gearshape.fill"),
            800,
            new ResultAction.Copy("你好")));
        return Task.FromResult<IReadOnlyList<LauncherResult>>(results);
    }
}
```

## 注册

在 `SearchCoordinator` 构造函数的 `personalModules` 参数传入：

```csharp
public SearchCoordinator(SpellingService spelling, IReadOnlyList<IYToolsModule>? personalModules = null)
```

## 能力与动作

- 默认无权限：只能返回 `.copy(text)`、`.none` 或 `.openSettings`。
- `editQuery(text)`（Windows：`ResultAction.EditQuery`）同样无需权限：只把启动器查询框替换为给定文本（如计算器 `=` 续算回填），≤1000 字符，永远不会被当作路径或命令。
- 需要读本地文件：描述符声明 `LocalFileRead`，并在注册时用 `ModuleResultPolicy(allowedCapabilities: ...)` 授予；动作只能是本机绝对路径的 `open`/`reveal`/`navigate`。
- 特权系统动作（回收站、屏保、关显示器、系统设置）只有内置模块通过 `allowsPrivilegedActions: true` 获得。
- 主程序不授予 `ClipboardRead`/`ContactsRead`/`CalendarRead`（Windows 版当前无对应系统服务）。
- 模块最多返回 40 条；每条 id ≤ 500、标题 ≤ 1000、副标题 ≤ 4000 字符。

## 规则

- 不动态加载程序集；模块随应用编译。
- 不发起网络请求；需要网络的新能力必须先与用户确认并隔离。
- 不执行 Shell/命令；所有副作用交给 `ActionDispatcher`。
- 新增逻辑后补充 xUnit 测试，并在 `SelfTest` 中增加检查项。
- 运行 `./scripts/check.ps1` 确认构建、测试与安全扫描通过。
