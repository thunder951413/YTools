import Foundation

struct ActionRegistry {
    func actions(for result: LauncherResult) -> [LauncherAction] {
        var actions: [LauncherAction] = []

        if let url = result.resourceURL {
            let isApplication = result.isApplication
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

            if isDirectory {
                actions.append(action(
                    "browse",
                    "在 YTools 中浏览",
                    "进入该目录并继续键盘导航",
                    "arrow.right.circle",
                    .perform(.navigate(navigationQuery(for: url)))
                ))
            }
            actions.append(action(
                "open",
                isApplication ? "启动应用" : "打开",
                "使用系统默认方式打开",
                "arrow.up.forward.app",
                .perform(.open(url))
            ))
            actions.append(action(
                "reveal",
                "在访达中显示",
                "选择该项目并打开所在目录",
                "folder",
                .perform(.reveal(url))
            ))
            actions.append(action(
                "copy-path",
                "复制路径",
                url.path,
                "doc.on.doc",
                .copyPath(url)
            ))
            if isApplication, let bundleID = Bundle(url: url)?.bundleIdentifier {
                actions.append(action(
                    "hide-application",
                    "隐藏应用",
                    "隐藏正在运行的应用窗口",
                    "eye.slash",
                    .perform(.hideApplication(bundleID))
                ))
                actions.append(action(
                    "quit-application",
                    "退出应用",
                    "请求应用正常退出",
                    "xmark.circle",
                    .perform(.quitApplication(bundleID))
                ))
            }
            if !isApplication {
                actions.append(action(
                    "preview",
                    "快速预览",
                    "在 YTools 右侧显示 Quick Look",
                    "eye",
                    .preview(url)
                ))
                if !isDirectory {
                    actions.append(action(
                        "open-with",
                        "打开方式…",
                        "选择本机应用打开该文件",
                        "square.stack.3d.up",
                        .openWith(url)
                    ))
                }
                actions.append(action(
                    "copy-file",
                    "复制到…",
                    "选择本机目标目录；不会覆盖同名项目",
                    "doc.on.doc",
                    .copyFile(url)
                ))
                actions.append(action(
                    "move-file",
                    "移动到…",
                    "选择本机目标目录；不会覆盖同名项目",
                    "folder.badge.plus",
                    .moveFile(url)
                ))
                actions.append(action(
                    "trash-file",
                    "移入废纸篓…",
                    "需要确认；不提供永久删除",
                    "trash",
                    .trash(url)
                ))
            }
        } else {
            switch result.action {
            case let .copy(text):
                actions.append(action("copy", "复制", "复制结果到剪贴板", "doc.on.doc", .copyText(text)))
                actions.append(action("large-type", "大字显示", "全屏清晰显示文本", "textformat.size.larger", .largeType(text)))
                actions.append(action("save-snippet", "保存为文本片段", "加密保存到默认分类", "text.badge.plus", .saveSnippet(text)))
            case let .openDictionary(term):
                actions.append(action(
                    "open-dictionary",
                    "在系统词典中打开",
                    "使用本机 Dictionary 查询“\(term)”",
                    "character.book.closed",
                    .perform(.openDictionary(term))
                ))
                actions.append(action("copy-word", "复制单词", term, "doc.on.doc", .copyText(term)))
            case .openSettings:
                actions.append(action("settings", "打开设置", result.subtitle, "gearshape", .perform(.openSettings)))
            default:
                if !result.title.isEmpty {
                    actions.append(action("copy-title", "复制标题", result.title, "doc.on.doc", .copyText(result.title)))
                }
            }
        }
        return actions
    }

    func actions(forBufferedURLs urls: [URL]) -> [LauncherAction] {
        guard !urls.isEmpty else { return [] }
        return [
            action(
                "open-buffer",
                "打开全部",
                "打开缓冲区中的 \(urls.count) 个项目",
                "arrow.up.forward.app",
                .openMany(urls)
            ),
            action(
                "reveal-buffer",
                "在访达中显示",
                "在访达中选择全部项目",
                "folder",
                .revealMany(urls)
            ),
            action(
                "copy-buffer-paths",
                "复制全部路径",
                "每行一个完整路径",
                "doc.on.doc",
                .copyPaths(urls)
            )
        ]
    }

    private func action(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ icon: String,
        _ kind: LauncherActionKind
    ) -> LauncherAction {
        LauncherAction(id: id, title: title, subtitle: subtitle, systemIcon: icon, kind: kind)
    }

    private func navigationQuery(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path: String
        if url.path == home || url.path.hasPrefix(home + "/") {
            path = "~" + url.path.dropFirst(home.count)
        } else {
            path = url.path
        }
        return path.hasSuffix("/") ? path : path + "/"
    }
}
