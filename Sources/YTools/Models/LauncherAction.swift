import Foundation

enum LauncherActionKind: Equatable {
    case perform(ResultAction)
    case copyPath(URL)
    case copyText(String)
    case largeType(String)
    case saveSnippet(String)
    case preview(URL)
    case openWith(URL)
    case copyFile(URL)
    case moveFile(URL)
    case trash(URL)
    case openMany([URL])
    case revealMany([URL])
    case copyPaths([URL])
}

struct LauncherAction: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemIcon: String
    let kind: LauncherActionKind
}
