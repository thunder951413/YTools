import Foundation

/// One line produced by the date and time tools.
public struct DateTimeLine: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let copyText: String

    public init(title: String, subtitle: String, copyText: String) {
        self.title = title
        self.subtitle = subtitle
        self.copyText = copyText
    }
}

public enum TimestampUnit: String, CaseIterable, Codable, Sendable {
    case automatic
    case seconds
    case milliseconds
}

/// Offline timestamp conversion, date arithmetic and world clock.
/// `now`, the local time zone and the calendar are injected so results are
/// deterministic in tests. Mirrored by `Core/DateTimeTools.cs`.
public struct DateTimeTools: Sendable {
    public let now: Date
    public let localTimeZone: TimeZone
    public let timestampUnit: TimestampUnit
    public let worldClockZones: [String]

    public init(now: Date = Date(), localTimeZone: TimeZone = .current,
                timestampUnit: TimestampUnit = .automatic, worldClockZones: [String] = DateTimeTools.defaultWorldClockZones) {
        self.now = now
        self.localTimeZone = localTimeZone
        self.timestampUnit = timestampUnit
        self.worldClockZones = worldClockZones
    }

    public static let defaultWorldClockZones = ["Asia/Shanghai", "America/New_York", "Europe/London", "America/Los_Angeles"]

    public func results(for rawQuery: String) -> [DateTimeLine] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, query.count <= 80 else { return [] }
        let lowered = query.lowercased()
        if ["now", "ts", "timestamp", "时间戳", "现在"].contains(lowered) { return currentTimestamp() }
        if let date = timestamp(from: lowered) { return describeTimestamp(date) }
        if let clock = worldClock(for: lowered) { return clock }
        return dateArithmetic(lowered)
    }

    // MARK: - Timestamps

    private func currentTimestamp() -> [DateTimeLine] {
        let seconds = Int64(now.timeIntervalSince1970.rounded(.down))
        let milliseconds = Int64((now.timeIntervalSince1970 * 1_000).rounded(.down))
        return [
            DateTimeLine(title: String(seconds), subtitle: "当前 Unix 时间戳（秒）", copyText: String(seconds)),
            DateTimeLine(title: String(milliseconds), subtitle: "当前 Unix 时间戳（毫秒）", copyText: String(milliseconds)),
            DateTimeLine(title: Self.iso8601(now), subtitle: "当前 ISO 8601（UTC）", copyText: Self.iso8601(now))
        ]
    }

    func timestamp(from query: String) -> Date? {
        var digits = query
        for prefix in ["ts ", "时间戳 "] where digits.hasPrefix(prefix) {
            digits = String(digits.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber), let value = Int64(digits) else { return nil }
        let useMilliseconds: Bool
        switch timestampUnit {
        case .seconds: useMilliseconds = false
        case .milliseconds: useMilliseconds = true
        case .automatic:
            switch digits.count {
            case 9...10: useMilliseconds = false
            case 12...13: useMilliseconds = true
            default: return nil
            }
        }
        let interval = useMilliseconds ? Double(value) / 1_000 : Double(value)
        guard interval < 253_402_300_800 else { return nil } // before year 10000
        return Date(timeIntervalSince1970: interval)
    }

    private func describeTimestamp(_ date: Date) -> [DateTimeLine] {
        let local = format(date, in: localTimeZone)
        return [
            DateTimeLine(title: local, subtitle: "本地时间 · \(Self.relative(date, to: now))", copyText: local),
            DateTimeLine(title: Self.iso8601(date), subtitle: "ISO 8601（UTC）", copyText: Self.iso8601(date))
        ]
    }

    // MARK: - World clock

    private func worldClock(for query: String) -> [DateTimeLine]? {
        if ["time", "clock", "时间", "世界时间", "时区"].contains(query) {
            var zones = [localTimeZone.identifier] + worldClockZones
            var seen = Set<String>()
            zones = zones.filter { seen.insert($0).inserted }
            return zones.compactMap { line(forZone: $0) }
        }
        var city: String
        if let prefix = ["time ", "时间 ", "clock "].first(where: { query.hasPrefix($0) }) {
            city = String(query.dropFirst(prefix.count))
        } else if query.hasSuffix("时间"), query.count > 2 {
            city = String(query.dropLast(2))
        } else {
            return nil
        }
        city = city.trimmingCharacters(in: .whitespaces)
        let matches = WorldCity.search(city)
        guard !matches.isEmpty else { return nil }
        return matches.prefix(5).compactMap { line(forZone: $0.zoneIdentifier, name: $0.name) }
    }

    private func line(forZone identifier: String, name: String? = nil) -> DateTimeLine? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        let label = name ?? WorldCity.displayName(forZone: identifier)
        let time = format(now, in: zone, pattern: "HH:mm")
        let offsetHours = Double(zone.secondsFromGMT(for: now) - localTimeZone.secondsFromGMT(for: now)) / 3_600
        let difference = offsetHours == 0 ? "与本地相同" : "\(offsetHours > 0 ? "+" : "")\(Self.trimmed(offsetHours)) 小时"
        let day = dayRelation(of: now, in: zone)
        let local = identifier == localTimeZone.identifier ? " · 本地" : ""
        return DateTimeLine(
            title: "\(time)  \(label)",
            subtitle: "\(format(now, in: zone, pattern: "yyyy-MM-dd")) \(day) · \(Self.utcOffset(zone, at: now)) · \(difference)\(local)",
            copyText: format(now, in: zone)
        )
    }

    private func dayRelation(of date: Date, in zone: TimeZone) -> String {
        let remote = calendar(zone).dateComponents([.year, .month, .day], from: date)
        let local = calendar(localTimeZone).dateComponents([.year, .month, .day], from: date)
        guard let remoteDate = Calendar(identifier: .gregorian).date(from: remote),
              let localDate = Calendar(identifier: .gregorian).date(from: local) else { return "" }
        let days = Int((remoteDate.timeIntervalSince(localDate) / 86_400).rounded())
        return days == 0 ? "今天" : days > 0 ? "明天" : "昨天"
    }

    // MARK: - Date arithmetic

    private enum Operand {
        case date(Date)
        case offset(Calendar.Component, Int)
    }

    private func dateArithmetic(_ query: String) -> [DateTimeLine] {
        let compact = query.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return [] }
        // Split at the last + or - that is not part of a yyyy-mm-dd literal.
        var splitIndex: String.Index?
        var index = compact.startIndex
        while index < compact.endIndex {
            let character = compact[index]
            if character == "+" || character == "-", index != compact.startIndex,
               parseDate(String(compact[..<index])) != nil {
                splitIndex = index
            }
            index = compact.index(after: index)
        }
        guard let splitIndex else {
            guard let date = parseDate(compact) else { return [] }
            return describeDate(date, expression: query)
        }
        let leftText = String(compact[..<splitIndex])
        let rightText = String(compact[compact.index(after: splitIndex)...])
        let sign = compact[splitIndex] == "+" ? 1 : -1
        guard let left = parseDate(leftText) else { return [] }
        if let right = parseDate(rightText) {
            guard sign < 0 else { return [] }
            let days = calendar(localTimeZone).dateComponents([.day], from: startOfDay(right), to: startOfDay(left)).day ?? 0
            let text = "\(days) 天"
            return [DateTimeLine(title: text, subtitle: "\(format(left, in: localTimeZone, pattern: "yyyy-MM-dd")) 与 \(format(right, in: localTimeZone, pattern: "yyyy-MM-dd")) 相差 · 约 \(Self.trimmed(Double(days) / 7)) 周", copyText: String(days))]
        }
        guard case let .offset(component, amount)? = parseOffset(rightText),
              let result = calendar(localTimeZone).date(byAdding: component, value: sign * amount, to: left) else { return [] }
        return describeDate(result, expression: query)
    }

    private func describeDate(_ date: Date, expression: String) -> [DateTimeLine] {
        let hasTime = !Self.isMidnightAligned(date, calendar: calendar(localTimeZone))
        let text = format(date, in: localTimeZone, pattern: hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd")
        let days = calendar(localTimeZone).dateComponents([.day], from: startOfDay(now), to: startOfDay(date)).day ?? 0
        let distance = days == 0 ? "今天" : days > 0 ? "\(days) 天后" : "\(-days) 天前"
        let weekday = Self.weekdayNames[calendar(localTimeZone).component(.weekday, from: date) - 1]
        let week = calendar(localTimeZone).component(.weekOfYear, from: date)
        return [DateTimeLine(title: "\(text) \(weekday)", subtitle: "\(distance) · 第 \(week) 周 · \(expression)", copyText: text)]
    }

    private func parseDate(_ text: String) -> Date? {
        switch text {
        case "today", "今天", "今日": return startOfDay(now)
        case "now", "现在": return now
        case "tomorrow", "明天": return calendar(localTimeZone).date(byAdding: .day, value: 1, to: startOfDay(now))
        case "yesterday", "昨天": return calendar(localTimeZone).date(byAdding: .day, value: -1, to: startOfDay(now))
        default: break
        }
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).map(String.init)
        guard parts.count == 3, parts[0].count == 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar(localTimeZone).date(from: components),
              calendar(localTimeZone).component(.day, from: date) == day else { return nil }
        return date
    }

    private func parseOffset(_ text: String) -> Operand? {
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 6, let amount = Int(digits) else { return nil }
        let unit = String(text.dropFirst(digits.count))
        let component: Calendar.Component
        switch unit {
        case "d", "day", "days", "天", "日": component = .day
        case "w", "week", "weeks", "周", "星期", "个星期": component = .weekOfYear
        case "m", "mo", "month", "months", "月", "个月": component = .month
        case "y", "year", "years", "年": component = .year
        case "h", "hour", "hours", "小时", "个小时": component = .hour
        case "min", "minute", "minutes", "分钟": component = .minute
        default: return nil
        }
        return .offset(component, amount)
    }

    // MARK: - Formatting

    private func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func startOfDay(_ date: Date) -> Date { calendar(localTimeZone).startOfDay(for: date) }

    private func format(_ date: Date, in zone: TimeZone, pattern: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    private static func isMidnightAligned(_ date: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: date) == date
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func utcOffset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3_600
        let minutes = abs(seconds) % 3_600 / 60
        return minutes == 0 ? "UTC\(sign)\(hours)" : "UTC\(sign)\(hours):" + String(format: "%02d", minutes)
    }

    static func trimmed(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func relative(_ date: Date, to now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        let magnitude = abs(seconds)
        let suffix = seconds >= 0 ? "后" : "前"
        switch magnitude {
        case ..<60: return "刚刚"
        case ..<3_600: return "\(Int(magnitude / 60)) 分钟\(suffix)"
        case ..<86_400: return "\(Int(magnitude / 3_600)) 小时\(suffix)"
        case ..<(86_400 * 365): return "\(Int(magnitude / 86_400)) 天\(suffix)"
        default: return "\(Self.trimmed((magnitude / (86_400 * 365.2425) * 10).rounded() / 10)) 年\(suffix)"
        }
    }
}

/// Offline city → IANA time zone table used by the world clock.
public struct WorldCity: Equatable, Sendable {
    public let name: String
    public let aliases: [String]
    public let zoneIdentifier: String

    public static func search(_ query: String) -> [WorldCity] {
        let needle = query.lowercased().replacingOccurrences(of: " ", with: "")
        guard !needle.isEmpty else { return [] }
        let exact = all.filter { city in city.aliases.contains(needle) || city.name == needle }
        if !exact.isEmpty { return exact }
        return all.filter { city in city.name.hasPrefix(needle) || city.aliases.contains { $0.hasPrefix(needle) } }
    }

    public static func displayName(forZone identifier: String) -> String {
        all.first { $0.zoneIdentifier == identifier }?.name
            ?? identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? identifier
    }

    public static let all: [WorldCity] = [
        WorldCity(name: "北京", aliases: ["beijing", "peking", "china", "中国"], zoneIdentifier: "Asia/Shanghai"),
        WorldCity(name: "上海", aliases: ["shanghai"], zoneIdentifier: "Asia/Shanghai"),
        WorldCity(name: "香港", aliases: ["hongkong", "hk"], zoneIdentifier: "Asia/Hong_Kong"),
        WorldCity(name: "台北", aliases: ["taipei", "台湾"], zoneIdentifier: "Asia/Taipei"),
        WorldCity(name: "首尔", aliases: ["seoul", "韩国", "korea"], zoneIdentifier: "Asia/Seoul"),
        WorldCity(name: "东京", aliases: ["tokyo", "日本", "japan"], zoneIdentifier: "Asia/Tokyo"),
        WorldCity(name: "新加坡", aliases: ["singapore", "sg"], zoneIdentifier: "Asia/Singapore"),
        WorldCity(name: "吉隆坡", aliases: ["kualalumpur", "马来西亚"], zoneIdentifier: "Asia/Kuala_Lumpur"),
        WorldCity(name: "曼谷", aliases: ["bangkok", "泰国"], zoneIdentifier: "Asia/Bangkok"),
        WorldCity(name: "胡志明市", aliases: ["hochiminh", "saigon", "越南", "河内", "hanoi"], zoneIdentifier: "Asia/Ho_Chi_Minh"),
        WorldCity(name: "雅加达", aliases: ["jakarta", "印尼"], zoneIdentifier: "Asia/Jakarta"),
        WorldCity(name: "马尼拉", aliases: ["manila", "菲律宾"], zoneIdentifier: "Asia/Manila"),
        WorldCity(name: "新德里", aliases: ["newdelhi", "delhi", "india", "印度", "孟买", "mumbai"], zoneIdentifier: "Asia/Kolkata"),
        WorldCity(name: "迪拜", aliases: ["dubai", "阿联酋"], zoneIdentifier: "Asia/Dubai"),
        WorldCity(name: "莫斯科", aliases: ["moscow", "俄罗斯"], zoneIdentifier: "Europe/Moscow"),
        WorldCity(name: "伊斯坦布尔", aliases: ["istanbul", "土耳其"], zoneIdentifier: "Europe/Istanbul"),
        WorldCity(name: "柏林", aliases: ["berlin", "德国", "germany"], zoneIdentifier: "Europe/Berlin"),
        WorldCity(name: "巴黎", aliases: ["paris", "法国", "france"], zoneIdentifier: "Europe/Paris"),
        WorldCity(name: "伦敦", aliases: ["london", "英国", "uk"], zoneIdentifier: "Europe/London"),
        WorldCity(name: "马德里", aliases: ["madrid", "西班牙"], zoneIdentifier: "Europe/Madrid"),
        WorldCity(name: "罗马", aliases: ["rome", "意大利"], zoneIdentifier: "Europe/Rome"),
        WorldCity(name: "阿姆斯特丹", aliases: ["amsterdam", "荷兰"], zoneIdentifier: "Europe/Amsterdam"),
        WorldCity(name: "苏黎世", aliases: ["zurich", "瑞士"], zoneIdentifier: "Europe/Zurich"),
        WorldCity(name: "斯德哥尔摩", aliases: ["stockholm", "瑞典"], zoneIdentifier: "Europe/Stockholm"),
        WorldCity(name: "开罗", aliases: ["cairo", "埃及"], zoneIdentifier: "Africa/Cairo"),
        WorldCity(name: "约翰内斯堡", aliases: ["johannesburg", "南非"], zoneIdentifier: "Africa/Johannesburg"),
        WorldCity(name: "纽约", aliases: ["newyork", "ny", "nyc", "华盛顿", "washington", "波士顿", "boston"], zoneIdentifier: "America/New_York"),
        WorldCity(name: "多伦多", aliases: ["toronto"], zoneIdentifier: "America/Toronto"),
        WorldCity(name: "芝加哥", aliases: ["chicago"], zoneIdentifier: "America/Chicago"),
        WorldCity(name: "丹佛", aliases: ["denver"], zoneIdentifier: "America/Denver"),
        WorldCity(name: "洛杉矶", aliases: ["losangeles", "la", "旧金山", "sanfrancisco", "sf", "西雅图", "seattle", "硅谷"], zoneIdentifier: "America/Los_Angeles"),
        WorldCity(name: "温哥华", aliases: ["vancouver"], zoneIdentifier: "America/Vancouver"),
        WorldCity(name: "墨西哥城", aliases: ["mexicocity", "墨西哥"], zoneIdentifier: "America/Mexico_City"),
        WorldCity(name: "圣保罗", aliases: ["saopaulo", "巴西"], zoneIdentifier: "America/Sao_Paulo"),
        WorldCity(name: "布宜诺斯艾利斯", aliases: ["buenosaires", "阿根廷"], zoneIdentifier: "America/Argentina/Buenos_Aires"),
        WorldCity(name: "悉尼", aliases: ["sydney", "澳大利亚", "australia"], zoneIdentifier: "Australia/Sydney"),
        WorldCity(name: "墨尔本", aliases: ["melbourne"], zoneIdentifier: "Australia/Melbourne"),
        WorldCity(name: "奥克兰", aliases: ["auckland", "新西兰"], zoneIdentifier: "Pacific/Auckland"),
        WorldCity(name: "檀香山", aliases: ["honolulu", "夏威夷", "hawaii"], zoneIdentifier: "Pacific/Honolulu"),
        WorldCity(name: "UTC", aliases: ["utc", "gmt", "协调世界时"], zoneIdentifier: "UTC")
    ]
}
