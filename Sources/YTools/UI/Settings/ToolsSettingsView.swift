import SwiftUI
import YToolsCore

struct ToolsSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "文本转换", isNew: true) {
                SettingsRow(title: "关键词", detail: "输入 tx 或“转换”后接文本；只输入关键词时转换剪贴板内容",
                            target: "TextTransformKeyword") {
                    HStack(spacing: 4) {
                        keyword("tx")
                        keyword("转换")
                    }
                }
                SettingsDivider()
                SettingsNoteRow("可用转换：大小写 · 去格式 · JSON 格式化 / 压缩 · Base64 · URL 编码 · MD5 / SHA-256 · 按行排序去重 等 \(TextTransform.allCases.count) 种。")
            }

            SettingsGroup(title: "时间与日期", isNew: true) {
                SettingsRow(title: "时间戳单位", detail: "识别 10 位或 13 位数字并转换为日期", target: "TimestampUnit") {
                    Picker("时间戳单位", selection: $preferences.tools.timestampUnit) {
                        Text("自动").tag(TimestampUnit.automatic)
                        Text("秒").tag(TimestampUnit.seconds)
                        Text("毫秒").tag(TimestampUnit.milliseconds)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 170)
                }
                SettingsDivider()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        clockRow(zone: TimeZone.current.identifier, isLocal: true, now: context.date)
                        ForEach(preferences.tools.worldClockZones, id: \.self) { zone in
                            SettingsDivider()
                            clockRow(zone: zone, isLocal: false, now: context.date)
                        }
                    }
                }
                .settingsTarget("WorldClockZones")
                SettingsDivider()
                SettingsNoteRow("输入 time 或城市名查看时间；时区数据库随系统离线提供。") {
                    Menu("添加城市…") {
                        ForEach(availableCities, id: \.zoneIdentifier) { city in
                            Button(city.name) { preferences.tools.worldClockZones.append(city.zoneIdentifier) }
                        }
                    }
                    .fixedSize()
                    .disabled(availableCities.isEmpty)
                }
            }

            SettingsGroup(title: "计算器") {
                SettingsToggleRow("进制转换", detail: "输入 0x、0b、0o 开头的数字时同时显示十、十六、二进制",
                                  isNew: true, target: "NumberBaseConversion",
                                  isOn: $preferences.tools.numberBaseConversion)
                SettingsDivider()
                SettingsToggleRow("百分比写法", detail: "支持“300 的 20%”“200+15%”",
                                  isNew: true, target: "PercentExpressions",
                                  isOn: $preferences.tools.percentExpressions)
            }

            SettingsGroup(title: "生成工具", isNew: true) {
                SettingsRow(title: "密码长度", detail: "输入 pwd 或“密码”；pwd 32 可临时指定长度", target: "PasswordLength") {
                    SettingsStepper(value: $preferences.tools.passwordLength,
                                    range: PasswordGenerator.lengthRange) { "\($0) 位" }
                }
                SettingsDivider()
                SettingsToggleRow("密码包含符号", target: "PasswordIncludesSymbols",
                                  isOn: $preferences.tools.passwordIncludesSymbols)
                SettingsDivider()
                SettingsToggleRow("UUID 使用大写", target: "UUIDUppercase", isOn: $preferences.tools.uuidUppercase)
                SettingsDivider()
                SettingsNoteRow("qr 加文本生成二维码；输入 #RRGGBB、rgb() 或 hsl() 显示色块与换算。")
            }

            SettingsGroup(title: "Emoji 与符号", isNew: true) {
                SettingsRow(title: "默认肤色", detail: "适用于支持肤色的手势与人物", target: "EmojiSkinTone") {
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { tone in
                            Button {
                                preferences.tools.emojiSkinTone = tone
                            } label: {
                                Text(skinToneSample(tone))
                                    .font(.system(size: 18))
                                    .frame(width: 30, height: 30)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(preferences.tools.emojiSkinTone == tone
                                                  ? Color.accentColor.opacity(0.18) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(preferences.tools.emojiSkinTone == tone
                                                    ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tone == 0 ? "默认肤色" : "肤色 \(tone)")
                            .accessibilityAddTraits(preferences.tools.emojiSkinTone == tone ? .isSelected : [])
                        }
                    }
                }
                SettingsDivider()
                SettingsToggleRow("选中后直接粘贴", detail: "需要辅助功能权限；关闭时仅复制",
                                  target: "EmojiPastesDirectly", isOn: $preferences.tools.emojiPastesDirectly)
            }
        }
    }

    private func keyword(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
    }

    private var availableCities: [WorldCity] {
        var seen = Set(preferences.tools.worldClockZones)
        seen.insert(TimeZone.current.identifier)
        var cities: [WorldCity] = []
        for city in WorldCity.all where !seen.contains(city.zoneIdentifier) {
            seen.insert(city.zoneIdentifier)
            cities.append(city)
        }
        return cities
    }

    private func clockRow(zone: String, isLocal: Bool, now: Date) -> some View {
        SettingsListItem(title: WorldCity.displayName(forZone: zone) + (isLocal ? " · 本地" : ""),
                         subtitle: offsetDescription(zone, now: now)) {
            Image(systemName: isLocal ? "location.fill" : "globe")
                .foregroundStyle(isLocal ? Color.accentColor : Color.secondary)
                .frame(width: 22)
        } trailing: {
            Text(time(in: zone, now: now))
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            if !isLocal {
                RemoveButton(label: "移除" + WorldCity.displayName(forZone: zone)) {
                    preferences.tools.worldClockZones.removeAll { $0 == zone }
                }
            }
        }
    }

    private func time(in zone: String, now: Date) -> String {
        guard let timeZone = TimeZone(identifier: zone) else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: now)
    }

    private func offsetDescription(_ zone: String, now: Date) -> String {
        guard let timeZone = TimeZone(identifier: zone) else { return zone }
        let seconds = timeZone.secondsFromGMT(for: now)
        let sign = seconds >= 0 ? "+" : "-"
        let hours = abs(seconds) / 3_600
        let minutes = abs(seconds) % 3_600 / 60
        return minutes == 0 ? "UTC\(sign)\(hours)" : String(format: "UTC%@%d:%02d", sign, hours, minutes)
    }

    private func skinToneSample(_ tone: Int) -> String {
        guard tone > 0, let modifier = Unicode.Scalar(UInt32(0x1F3FA + tone)) else { return "👋" }
        return "👋" + String(Character(modifier))
    }
}
