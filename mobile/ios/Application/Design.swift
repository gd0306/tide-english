import SwiftUI
import Observation
import TideEnglishCore

@MainActor @Observable final class InterfacePreferences {
    static let shared = InterfacePreferences()
    private(set) var theme: InterfaceTheme
    private(set) var language: InterfaceLanguage
    private let memoryOnly: Bool
    private let defaults = UserDefaults.standard
    private init() {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        memoryOnly = arguments.contains("--preview") || arguments.contains(where: { $0.hasPrefix("--preview-interface-") })
        #else
        memoryOnly = false
        #endif
        var initial: InterfaceConfiguration
        if memoryOnly {
            initial = InterfaceConfiguration(theme: .paper, language: .english)
        } else {
            initial = InterfaceConfiguration.restored(theme: defaults.string(forKey: "tideenglish.interface.theme.v1"), language: defaults.string(forKey: "tideenglish.interface.language.v1"), preferredLanguages: Locale.preferredLanguages)
        }
        #if DEBUG && targetEnvironment(simulator)
        if let raw = arguments.first(where: { $0.hasPrefix("--preview-interface-theme=") })?.split(separator: "=").last, let value = InterfaceTheme(rawValue: String(raw)) { initial.theme = value }
        if let raw = arguments.first(where: { $0.hasPrefix("--preview-interface-language=") })?.split(separator: "=").last, let value = InterfaceLanguage(rawValue: String(raw)) { initial.language = value }
        #endif
        theme = initial.theme
        language = initial.language
    }
    func setTheme(_ value: InterfaceTheme) {
        theme = value
        if !memoryOnly { defaults.set(value.rawValue, forKey: "tideenglish.interface.theme.v1") }
    }
    func setLanguage(_ value: InterfaceLanguage) {
        language = value
        if !memoryOnly { defaults.set(value.rawValue, forKey: "tideenglish.interface.language.v1") }
    }
    var colorScheme: ColorScheme { theme == .midnight ? .dark : .light }
    var locale: Locale { Locale(identifier: language == .chinese ? "zh-Hans" : "en") }
}

@MainActor func UI(_ english: String) -> String {
    InterfaceText.string(english, language: InterfacePreferences.shared.language)
}

@MainActor enum TideEnglishColor {
    private static func token(_ paper: UInt32, _ midnight: UInt32, _ grove: UInt32) -> Color {
        let value = switch InterfacePreferences.shared.theme { case .paper: paper; case .midnight: midnight; case .grove: grove }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    static var cream: Color { token(0xF5F1E8, 0x20221F, 0xEDF2E9) }
    static var ink: Color { token(0x262820, 0xEEEADF, 0x263D31) }
    static var secondary: Color { token(0x62665A, 0xBCBBAF, 0x566B5B) }
    static var accent: Color { token(0x445548, 0xD6B77A, 0x4F715A) }
    static var surface: Color { token(0xFFFCF5, 0x2C2F29, 0xF8FAF4) }
    static var onAccent: Color { token(0xFFFFFF, 0x20221F, 0xFFFFFF) }
    static var rule: Color { ink.opacity(0.15) }
    static var orange: Color { accent }
    static var ocean: Color { accent }
    static var seaAccent: Color { accent }
    static var sky: Color { token(0xE8E6DA, 0x353A31, 0xDFE8D9) }
    static var peach: Color { sky }
    static var lilac: Color { token(0xEBE5D8, 0x36352E, 0xE3EADA) }
    static var sage: Color { token(0xE3E7DB, 0x30392F, 0xDCE7D8) }
    static var butter: Color { token(0xEEE8D9, 0x3A352A, 0xE7ECDB) }
    static var panels: [Color] { [peach, lilac, sage, butter] }
}

enum AppBrand { static let name = "Tide English" }

struct Brand: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "book.closed").font(.system(size: 21, weight: .regular)).foregroundStyle(TideEnglishColor.accent)
            Text("Tide English").font(.system(size: 22, weight: .medium, design: .serif)).tracking(-0.6)
        }.foregroundStyle(TideEnglishColor.ink).accessibilityElement(children: .ignore).accessibilityLabel(AppBrand.name)
    }
}

struct SoftGlass: ViewModifier {
    var tint: Color = .clear
    func body(content: Content) -> some View {
        content.background(TideEnglishColor.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(TideEnglishColor.rule, lineWidth: 1) }
    }
}

/// Shared page surface; the name remains compatible with dormant screens.
struct OceanBackdrop: View {
    var prominent = false
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                TideEnglishColor.cream
                if prominent {
                    switch InterfacePreferences.shared.theme {
                    case .paper:
                        Path { path in
                            for index in 0..<3 {
                                let y = geometry.size.height * 0.28 + CGFloat(index) * 12
                                path.move(to: CGPoint(x: geometry.size.width * 0.68, y: y))
                                path.addLine(to: CGPoint(x: geometry.size.width - 26, y: y))
                            }
                        }.stroke(TideEnglishColor.accent.opacity(0.16), lineWidth: 1)
                    case .midnight:
                        Path { path in
                            let points = [CGPoint(x: 0.76, y: 0.22), CGPoint(x: 0.83, y: 0.26), CGPoint(x: 0.91, y: 0.20)]
                            for point in points {
                                path.addEllipse(in: CGRect(x: point.x * geometry.size.width, y: point.y * geometry.size.height, width: 3, height: 3))
                            }
                        }.fill(TideEnglishColor.accent.opacity(0.5))
                    case .grove:
                        Image(systemName: "leaf").font(.system(size: 76, weight: .ultraLight))
                            .rotationEffect(.degrees(-25)).foregroundStyle(TideEnglishColor.accent.opacity(0.15))
                            .padding(.trailing, 26).padding(.top, geometry.size.height * 0.19)
                    }
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct TideEnglishOrb: View {
    var energy: Double = 0
    var listening = false
    var active = true
    var body: some View { ConversationHalo(energy: energy, listening: listening, active: active) }
}

/// Horizontal voice bars; the adjacent status carries accessible state.
struct ConversationHalo: View {
    var energy: Double
    var listening: Bool
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || !active || scenePhase != .active)) { timeline in
            let phase = reduceMotion || !active ? 0 : timeline.date.timeIntervalSinceReferenceDate * 3
            let level = reduceMotion ? 0 : min(1, max(0, energy))
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<25) { index in
                    let envelope = 1 - abs(Double(index) - 12) / 16
                    let pulse = 0.6 + 0.4 * sin(phase + Double(index) * 0.7)
                    Capsule().fill(TideEnglishColor.accent.opacity(active && listening ? 0.9 : 0.45))
                        .frame(width: 3, height: 5 + envelope * (8 + level * pulse * 28))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }.accessibilityHidden(true)
    }
}

struct ConversationButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(TideEnglishColor.onAccent)
            .background(TideEnglishColor.accent, in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.6).scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct OceanNavigation: View {
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 0) {
            item("Talk", symbol: "text.bubble", value: 0)
            item("Themes", symbol: "square.grid.2x2", value: 1)
            item("Words", symbol: "book", value: 2)
        }
        .padding(.horizontal, 12).padding(.top, 3)
        .background(TideEnglishColor.cream)
        .overlay(alignment: .top) { Rectangle().fill(TideEnglishColor.rule).frame(height: 1) }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain).accessibilityIdentifier("main-navigation")
    }
    private func item(_ title: String, symbol: String, value: Int) -> some View {
        let selected = selection == value
        return Button { selection = value } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19, weight: selected ? .semibold : .regular))
                Text(UI(title)).font(.caption2.weight(selected ? .semibold : .medium))
            }.frame(maxWidth: .infinity, minHeight: 61)
                .foregroundStyle(selected ? TideEnglishColor.accent : TideEnglishColor.secondary)
                .overlay(alignment: .top) { if selected { Rectangle().fill(TideEnglishColor.accent).frame(width: 26, height: 2) } }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(UI(title))
            .accessibilityIdentifier("tab-\(title.lowercased())").accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RecallBars: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in Capsule().fill(index < count ? TideEnglishColor.accent : TideEnglishColor.rule).frame(width: 18, height: 6) }
        }.accessibilityLabel(UI("\(count) of 3 recall bars"))
    }
}

struct PageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UI(eyebrow)).font(.system(.caption, weight: .medium)).foregroundStyle(TideEnglishColor.secondary)
            Text(UI(title)).font(.system(.largeTitle, design: .serif, weight: .semibold)).tracking(-0.8).foregroundStyle(TideEnglishColor.ink)
            if !subtitle.isEmpty { Text(UI(subtitle)).font(.subheadline).foregroundStyle(TideEnglishColor.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
