import Foundation
import YToolsModuleKit

struct UnitConversionModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "unit-conversion", name: "单位换算")

    private enum Kind: Sendable { case length, mass, temperature, duration, storage }
    private struct UnitDefinition: Sendable {
        let kind: Kind
        let symbol: String
        let toBase: @Sendable (Double) -> Double
        let fromBase: @Sendable (Double) -> Double
    }

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        let normalized = request.query.lowercased()
            .replacingOccurrences(of: "转换为", with: " to ")
            .replacingOccurrences(of: "转", with: " to ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed: (value: Double, source: String, target: String)?
        if let inchMatch = normalized.wholeMatch(of: /^(-?\d+(?:\.\d+)?)\s+in\s+(\S+)$/),
           let value = Double(inchMatch.1) {
            parsed = (value, "in", String(inchMatch.2))
        } else if let match = normalized.wholeMatch(of: /^(-?\d+(?:\.\d+)?)\s*(\S+)\s+(?:to|in)\s+(\S+)$/),
                  let value = Double(match.1) {
            parsed = (value, String(match.2), String(match.3))
        } else {
            parsed = nil
        }
        guard let parsed,
              let source = Self.units[parsed.source],
              let target = Self.units[parsed.target],
              source.kind == target.kind else { return [] }
        let converted = target.fromBase(source.toBase(parsed.value))
        guard converted.isFinite else { return [] }
        let text = format(converted)
        return [LauncherResult(
            id: "convert:\(normalized)",
            moduleID: descriptor.id,
            title: "\(text) \(target.symbol)",
            subtitle: "\(format(parsed.value)) \(source.symbol) → \(target.symbol) · 离线换算",
            icon: .system("ruler"),
            score: 1_020,
            action: .copy(text)
        )]
    }

    private static let units: [String: UnitDefinition] = {
        var output: [String: UnitDefinition] = [:]
        func add(_ aliases: [String], _ unit: UnitDefinition) { aliases.forEach { output[$0] = unit } }
        func linear(_ kind: Kind, _ symbol: String, _ factor: Double) -> UnitDefinition {
            UnitDefinition(kind: kind, symbol: symbol, toBase: { $0 * factor }, fromBase: { $0 / factor })
        }
        add(["m", "米"], linear(.length, "m", 1))
        add(["km", "公里", "千米"], linear(.length, "km", 1_000))
        add(["cm", "厘米"], linear(.length, "cm", 0.01))
        add(["mm", "毫米"], linear(.length, "mm", 0.001))
        add(["mi", "mile", "miles", "英里"], linear(.length, "mi", 1_609.344))
        add(["ft", "feet", "英尺"], linear(.length, "ft", 0.3048))
        add(["in", "inch", "inches", "英寸"], linear(.length, "in", 0.0254))
        add(["kg", "千克", "公斤"], linear(.mass, "kg", 1))
        add(["g", "克"], linear(.mass, "g", 0.001))
        add(["lb", "lbs", "磅"], linear(.mass, "lb", 0.45359237))
        add(["s", "sec", "秒"], linear(.duration, "s", 1))
        add(["min", "分钟"], linear(.duration, "min", 60))
        add(["h", "hr", "小时"], linear(.duration, "h", 3_600))
        add(["mb"], linear(.storage, "MB", 1_000_000))
        add(["gb"], linear(.storage, "GB", 1_000_000_000))
        add(["mib"], linear(.storage, "MiB", 1_048_576))
        add(["gib"], linear(.storage, "GiB", 1_073_741_824))
        add(["c", "°c", "摄氏度"], UnitDefinition(kind: .temperature, symbol: "°C", toBase: { $0 }, fromBase: { $0 }))
        add(["f", "°f", "华氏度"], UnitDefinition(kind: .temperature, symbol: "°F", toBase: { ($0 - 32) * 5 / 9 }, fromBase: { $0 * 9 / 5 + 32 }))
        add(["k", "开尔文"], UnitDefinition(kind: .temperature, symbol: "K", toBase: { $0 - 273.15 }, fromBase: { $0 + 273.15 }))
        return output
    }()

    private func format(_ value: Double) -> String {
        String(format: "%.12g", value)
    }
}
