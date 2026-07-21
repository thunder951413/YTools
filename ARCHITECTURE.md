# 原生版架构与安全边界

## 定位

YTools 是个人使用的 macOS 工具，不再是通用插件平台。功能以源码级“工具模块”编译进应用，由宿主统一负责窗口、列表、键盘导航和动作执行。

应用入口直接创建 `NSApplication` 并交给 `AppDelegate` 管理；不声明隐式 SwiftUI Window/Settings Scene。SwiftUI 只通过 `NSHostingController` 嵌入明确创建的 AppKit 面板和设置窗口，避免系统生成空白或重复窗口。

```text
AppKit 搜索面板
      │
SwiftUI 统一界面
      │
LauncherModel（查询状态、排序、选择）
 ├─ SearchCoordinator actor（统一异步模块、应用扫描、文件导航、取消过期查询）
 ├─ SpotlightSearchService（独立请求代次）
 ├─ ResultAggregator（合并、排序与隐私化使用学习）
 ├─ ActionMenuController（类型化动作菜单状态）
 ├─ FileBufferStore（文件缓冲状态）
 ├─ YToolsModuleKit（内置与个人源码模块的统一异步契约）
 └─ ActionDispatcher（有限动作词汇）
       └─ FileOperationService actor（复制、移动）

YToolsCore（纯 Swift、可测试）
 ├─ ExpressionCalculator
 ├─ PanelCommandRouter
 └─ SearchTextNormalizer（拼音、首字母和缩写）

YToolsModuleKit（无 AppKit 的公共边界）
 ├─ YToolsModule / ModuleDescriptor
 ├─ LauncherResult / 有限 ResultAction
 └─ ModuleResultPolicy（能力、file URL、数量与分数校验）

加密数据层
 ├─ ClipboardCaptureProcessor actor（哈希、图片转换、缩略图）
 ├─ ClipboardPersistenceService actor（密文串行读写）
 ├─ ClipboardHistoryStore（增量加密清单、记录、缩略图）
 ├─ SecureCodableStore（结构化加载状态）
 ├─ SnippetManager
 └─ RecentDocumentsManager
```

模块只返回 `LauncherResult` 数据。内置模块与个人模块都由 `SearchCoordinator` 并发执行，并统一经过 `ModuleResultPolicy` 的描述符、字段长度、分数、能力与动作校验。复制、打开应用等副作用由宿主根据有限的 `ResultAction` 执行，避免向模块暴露一个包罗万象的全局 API。

`LauncherModel` 是供 SwiftUI 使用的窄 facade，不再直接实现排序学习、动作菜单或文件缓冲；它只协调查询并把用户选择交给 `ActionDispatcher`。应用目录扫描、文件导航及复制/移动都不占用主 Actor。每次查询都有取消边界，旧查询不能覆盖新结果。预览使用独立 URL 状态，不伪造模块结果。

## 性能与响应性契约

- 文本输入热路径只能更新轻量状态、取消任务和推进请求代次；不得同步停止 Spotlight、访问磁盘、扫描目录、加密或全量过滤。
- 普通本地模块使用用户配置的输入防抖；`NSMetadataQuery` 至少等待输入稳定 300 毫秒，避免在正常打字间隔内反复启动和停止。
- 空查询直接重置内存状态，不执行一次“空搜索”；Spotlight 清理延后到按键完成渲染以后。
- 后台请求同时使用任务取消和 query/generation 校验。取消后不再创建新的任务组子任务，迟到结果不能覆盖新查询。
- 面板窗口只观察会改变几何尺寸的语义信号：结果数量、pending、模式、宽度和紧凑度。查询字符、选中项和无关偏好变化不进入窗口布局链路。
- 预览、输入、片段编辑分别使用独立防抖器，不能互相阻塞。文件图标使用有上限且可受内存压力驱逐的 `NSCache`。
- 剪贴板搜索在后台执行、支持取消并限制 UI 同时呈现最近 100 条；持久化仍保留完整的加密历史。用户执行复制或删除前会同步确认最终过滤状态。
- 剪贴板保留策略由 `YToolsCore.ClipboardRetentionPolicy` 统一计算；最大条目数为 `0` 表示不按数量裁剪，但仍遵守 200 MB 加密存储硬上限。复制历史项会增加本机使用次数，达到 5 次后不再按保留天数过期，固定和手动删除语义不变。
- Alfred 迁移 Actor 只读打开固定路径的本机 SQLite 数据库，只读取文字记录；进入内存后先按当前 `ClipboardTextPolicy` 过滤、精确去重，再以当前时间顺序写入既有 AES-GCM 存储。源数据库不会被修改，也不接受用户提供的数据库路径或查询。
- 边界必须明确：模块最多返回 40 条、Spotlight 最多读取 100 个元数据项、应用结果最多 12 条。小型设置搜索只有 7 个固定项，直接计算比创建异步任务更便宜，因此不做无意义防抖。

新增高频功能时应先将工作分为“每次事件必须做”“输入稳定后做”“后台做”三类，再决定使用去重、防抖、取消、缓存或 actor；不能把统一延迟当作性能修复。

设置 UI 按通用、搜索、外观、快捷键、剪贴板、片段和隐私拆分；根视图只负责导航和组合。目录和应用选择使用非阻塞 `fileImporter`。快捷键先映射为 `PanelCommand`，再由窗口控制器执行，按键表可在不启动 AppKit 窗口的情况下测试。登录启动的 ServiceManagement 调用隔离在可替换的 `LaunchAtLoginService`。

## 明确不包含

- 插件市场、在线安装和远程插件
- `WKWebView`/JavaScript 插件运行时
- 动态加载未签名的 bundle、dylib 或脚本
- 心跳、遥测、广告、自动更新和启动联网
- 通用 HTTP Server、MCP Server 或任意 Shell API

## 自用工具的扩展方式

所有工具实现 `YToolsModuleKit.YToolsModule` 并注册到 `SearchCoordinator`。内置系统模块由宿主显式授予所需能力；个人模块默认无权限。所有模块都需要重新编译，不存在运行时安装。完整示例见 `MODULE_DEVELOPMENT.md`。

无权限个人模块只能返回复制文本、空动作或打开 YTools 设置。文件动作必须声明并获得 `localFileRead`，且 URL 必须是本地文件；网页 URL、系统控制和应用退出动作会被拒绝。主程序当前不授予 `network`。

能力声明约束模块可以交给宿主执行的结果动作，不是进程内代码沙箱。当前构建检查会拒绝主程序中的网络、网页、动态代码和 Shell API。后续若确实需要网络或可独立更新的复杂工具，应使用签名校验过的 XPC Service，并为文件、剪贴板、网络等能力分别定义窄接口。不要恢复网页插件或任意 IPC 分发器。

## 权限策略

- 计算器：无权限。
- 系统词典：释义只调用本机 Dictionary Services；执行结果使用独立的 `openDictionary` 动作，经宿主权限位、长度和控制字符校验后构造固定 `dict:` 系统协议，模块不能提供任意 URL。
- 应用启动：只索引固定的 Applications 目录，由宿主调用 `NSWorkspace`。
- Spotlight：使用 `NSMetadataQuery`，只返回本地元数据；结果打开仍由宿主执行。
- 剪贴板：单一管理器读取 `NSPasteboard`；默认排除密码管理器和敏感类型，支持自定义忽略应用、暂停、固定和分段清理。文本/文件默认记录，图片默认关闭且单项限制 5 MB。持久化文件使用 AES-GCM 加密，随机密钥保存在登录钥匙串。
- 剪贴板文本在进入处理与持久化前先经过字符数策略，默认超过 1000 个 Unicode 字符不记录；该策略不修改系统剪贴板，不影响用户正常粘贴。
- 输入源：可跟随系统当前输入源，或在显示启动器/剪贴板面板时通过 macOS Text Input Source Services 选择指定的本机输入源；不监听用户在其他应用中的键盘内容。
- 全局快捷键：剪贴板历史默认使用 `Command+Shift+V`；偏好 schema 9 只把仍等于已知旧默认 `Option+Command+C` 或 `Command+Shift+C` 的安装迁移到新组合，其他用户录制的快捷键保持不变。Carbon 注册失败时恢复上一个可用组合并在设置中显示原因。
- 查询续用：面板再次唤出时保留当前查询。每次呈现都会重置一次性的首键策略；首个普通 Backspace 在文本编辑器无输入法组合文字时清空整段查询，其他首键、后续 Backspace 及 `Option+Backspace` 等快捷键仍走标准编辑或命令路由。
- 焦点恢复：启动器或剪贴板面板每次成为 key window 都通过显式请求代次重新聚焦搜索框，不依赖 SwiftUI 只执行一次的 `onAppear`；设置关闭后再次唤起、以及 Finder 再次打开已运行的 YTools，都会显示启动器并可直接输入。
- 窗口位置：启动器拖动后的左上角会换算为当前显示器可用区域中的横向/纵向比例，经防抖连同可用分辨率和显示器 UUID 写入本机偏好。再次唤出时优先恢复到原显示器；显示器缺失、分辨率、缩放或排列变化时，将比例映射到目标屏并自动钳制在可见区域。旧版绝对坐标会在首次恢复时迁移；设置中的位置/显示器选择可重置为预设位置。
- 菜单栏：状态项可按本机偏好隐藏，但应用仍保持 accessory 后台进程、全局快捷键和剪贴板服务；隐藏不改变运行状态。
- 启动器外观：极简为默认风格，空查询只保留 40pt 高的输入框；经典、现代、玻璃为内置原生预设，通过布局令牌和系统 Material 组合实现，不加载或导入外部主题资源。
- 启动器默认宽度为 720pt，可在 640–960pt 间调整；偏好迁移只收窄仍使用旧 860pt 默认值的安装，不覆盖用户手动选择的其他宽度。
- 启动器使用可接收键盘焦点的无边框 `NSPanel` 子类，外框和 SwiftUI 内容尺寸完全一致，不受标准标题栏最小高度约束。展开高度按输入区、真实结果行高和列表上下留白计算；展开/收起动画时长可在 0–400ms 间本机调整，系统启用“减少动态效果”时强制停用尺寸动画。
- 搜索防抖等待阶段只呈现输入栏，不显示进度、等待文案或空结果区；最终查询完成后才一次性展开结果，减少连续输入时的窗体跳动。
- 极简、经典和玻璃风格使用紧凑的自定义无结果视图，避免系统 `ContentUnavailableView` 的固有最小高度裁切提示；现代风格保留系统大空状态。
- Snippets/最近文档：使用独立 AES-GCM 存储与独立钥匙串密钥，不与剪贴板密钥复用。
- 钥匙串：三类数据共享经过审计的访问原语，但 service/account 与随机密钥仍完全隔离。
- 系统命令：只允许编译期固定的动作和参数；关键词可在设置中修改或关闭，但永远不会成为 Shell、URL 或可执行参数。当前唯一 `Process` 调用是 `/usr/bin/pmset displaysleepnow`。清空废纸篓在执行时始终确认，随后向固定目标 Finder 发送无参数 `fndr/empt` Apple Event；不直接读取受 TCC 保护的废纸篓目录、不申请完全磁盘访问，也不使用 AppleScript。勿扰与系统主题只打开 macOS 对应设置页，不使用私有 API 或辅助功能模拟点击。
- 网络：主程序默认没有网络模块。以后确需 API 时，采用显式域名白名单、超时、响应大小限制，并放入单独服务。

拼音索引使用稳定的 `en_US_POSIX` 折叠规则，避免随系统区域变化；基于系统转写，因此不承诺覆盖多音字的所有备选读音。

文件检索除名称和正文外支持 `tag/标签` 前缀，只查询 Spotlight 的 Finder 标签元数据。文件导航排序支持名称、创建时间、修改时间、升降序和可选文件夹优先。

## 沙箱取舍

完整磁盘 Spotlight 搜索与严格 App Sandbox 存在天然冲突。首选做法是启用沙箱并让用户明确授权需要搜索的目录；如果坚持搜索整个本机，则使用 Developer ID + Hardened Runtime，保持无网络代码、无动态代码加载，并把未来的网络能力隔离到单独的 XPC Service。
