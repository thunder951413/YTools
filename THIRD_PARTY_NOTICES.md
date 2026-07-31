# 第三方数据与许可证

YTools Windows 版使用以下第三方组件与数据。本仓库的 YTools 代码本身为 MIT 许可证。

## CC-CEDICT（中英词典数据）

- 来源：https://www.mdbg.net/chinese/dictionary?page=cedict （`cedict_ts.u8`）
- 许可证：CC BY-SA 4.0
- 用途：离线词典搜索。程序内嵌该数据，不发起任何网络请求。

## LibreOffice en_US 拼写词典

- 来源：https://github.com/LibreOffice/dictionaries （`en/en_US.aff`、`en/en_US.dic`）
- 该词典基于 SCOWL 词表及多来源贡献，由 LibreOffice 词典项目维护分发。
- 用途：Hunspell 离线拼写检查与建议。

## WeCantSpell.Hunspell

- 作者：Aaron Dandy（aarondandy）
- 许可证：MIT
- 用途：Hunspell 的托管实现，用于加载拼写词典。

## TinyPinyin.Net

- 核心算法来自 TinyPinyin（https://github.com/promeG/TinyPinyin）
- 许可证：Apache-2.0
- 用途：汉字转拼音（无网、本地运行）。

## Everything SDK（可选，运行时探测）

- 来源：https://www.voidtools.com/
- 仅当本机已安装 Everything 时，动态加载其官方 `Everything64.dll` 做只读文件名/内容查询；YTools 不重新分发该 DLL。Everything 的许可证以其官方分发为准。

## 应用图标

- 来自仓库原有 macOS 版资源（AppIcon.png/icns），为 YTools 项目自有资产。
