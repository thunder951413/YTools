import Foundation
import YToolsCore
import YToolsModuleKit

/// Shared helpers for the offline tool modules. Every module only computes
/// results; copying, pasting and windows stay in `ActionDispatcher`.
enum ToolResultText {
    /// Single-line, length-limited title for long tool output.
    static func title(_ text: String, limit: Int = 160) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let lineCount = text.split(whereSeparator: \.isNewline).count
        var title = firstLine.count > limit ? String(firstLine.prefix(limit)) + "…" : firstLine
        if lineCount > 1 { title += "  (+\(lineCount - 1) 行)" }
        return title.isEmpty ? "（空白）" : title
    }

    static func stableID(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

/// `tx [transform] [text]`: converts the given text, or the clipboard text
/// when none is typed. Built per query so the clipboard is read only when the
/// keyword is used.
struct TextTransformModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "text-transform", name: "文本转换")
    let clipboardText: String

    static func accepts(_ query: String) -> Bool { TextTransformQuery.parse(query) != nil }

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        guard let parsed = TextTransformQuery.parse(request.query) else { return [] }
        let source = parsed.text ?? clipboardText
        guard !source.isEmpty else {
            return [LauncherResult(
                id: "text-transform:empty", moduleID: descriptor.id,
                title: "剪贴板中没有文本",
                subtitle: "输入 tx 加文字，或先复制要转换的文本",
                icon: .system("textformat"), score: 1_040, action: .none
            )]
        }
        let transforms = parsed.transform.map { [$0] } ?? TextTransform.allCases
        let origin = parsed.text == nil ? "剪贴板" : "输入"
        return transforms.enumerated().compactMap { index, transform in
            guard let output = transform.apply(source) else { return nil }
            return LauncherResult(
                id: "text-transform:\(transform.rawValue):\(ToolResultText.stableID(source))",
                moduleID: descriptor.id,
                title: ToolResultText.title(output),
                subtitle: "\(transform.title) · 来自\(origin) · 回车复制",
                icon: .system("textformat"),
                score: 1_040 - index,
                action: .copy(output)
            )
        }
    }
}

struct DateTimeModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "date-time", name: "时间与日期")
    let settings: ToolSettings

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let tools = DateTimeTools(now: Date(), localTimeZone: .current,
                                  timestampUnit: settings.timestampUnit, worldClockZones: settings.worldClockZones)
        return tools.results(for: request.query).enumerated().map { index, line in
            LauncherResult(
                id: "date-time:\(index):\(ToolResultText.stableID(line.copyText))",
                moduleID: descriptor.id,
                title: line.title,
                subtitle: line.subtitle + " · 回车复制",
                icon: .system("clock"),
                score: 1_035 - index,
                action: .copy(line.copyText)
            )
        }
    }
}

struct NumberBaseModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "number-base", name: "进制转换")

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        NumberBaseConverter.results(for: request.query).enumerated().map { index, line in
            LauncherResult(
                id: "number-base:\(line.label):\(line.title)",
                moduleID: descriptor.id,
                title: line.title,
                subtitle: "\(line.label) · 回车复制",
                icon: .system("number"),
                score: 1_030 - index,
                action: .copy(line.title)
            )
        }
    }
}

struct GeneratorModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "generators", name: "生成工具")
    let settings: ToolSettings

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let query = request.query
        if let length = PasswordGenerator.parse(query, defaultLength: settings.passwordLength) {
            return (0..<3).map { index in
                let password = PasswordGenerator.generate(length: length, includeSymbols: settings.passwordIncludesSymbols)
                return LauncherResult(
                    id: "generators:password:\(index)", moduleID: descriptor.id,
                    title: password,
                    subtitle: "\(length) 位随机密码\(settings.passwordIncludesSymbols ? "（含符号）" : "") · 本机生成 · 回车复制",
                    icon: .system("key"), score: 1_040 - index, action: .copy(password)
                )
            }
        }
        if UUIDGenerator.matches(query) {
            return (0..<3).map { index in
                let value = UUIDGenerator.generate(uppercase: settings.uuidUppercase)
                return LauncherResult(
                    id: "generators:uuid:\(index)", moduleID: descriptor.id,
                    title: value, subtitle: "UUID v4 · 回车复制",
                    icon: .system("number.square"), score: 1_040 - index, action: .copy(value)
                )
            }
        }
        if let text = QRCodeQuery.text(from: query) {
            return [LauncherResult(
                id: "generators:qr:\(ToolResultText.stableID(text))", moduleID: descriptor.id,
                title: "显示二维码", subtitle: ToolResultText.title(text, limit: 80) + " · 本机生成，不联网",
                icon: .system("qrcode"), score: 1_040, action: .showQRCode(text)
            )]
        }
        if let color = ColorValue.parse(query) {
            return [(color.hex, "HEX"), (color.rgb, "RGB"), (color.hsl, "HSL")].enumerated().map { index, entry in
                LauncherResult(
                    id: "generators:color:\(entry.1):\(color.hex)", moduleID: descriptor.id,
                    title: entry.0, subtitle: "\(entry.1) · 回车复制",
                    icon: .color(color.hex), score: 1_040 - index, action: .copy(entry.0)
                )
            }
        }
        return []
    }
}

struct EmojiModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "emoji", name: "Emoji 与符号")
    let skinTone: Int
    var pastesDirectly = true

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        guard let text = EmojiCatalog.searchText(from: request.query) else { return [] }
        return EmojiCatalog.shared.search(text, limit: request.maximumResults).enumerated().map { index, entry in
            let glyph = entry.glyph(skinTone: skinTone)
            return LauncherResult(
                id: "emoji:\(entry.glyph)", moduleID: descriptor.id,
                title: entry.name,
                subtitle: "\(glyph)  " + entry.keywords.prefix(4).joined(separator: " · ")
                    + (pastesDirectly ? " · 回车粘贴" : " · 回车复制"),
                icon: .glyph(glyph), score: 1_040 - index, action: pastesDirectly ? .paste(glyph) : .copy(glyph)
            )
        }
    }
}
