import SwiftUI
import TideEnglishCore

/// Keeps Han text selectable and word links intact, with an optional reading below it.
struct PinyinHelp: View {
    let text: String
    @State private var expanded = true

    var body: some View {
        if let reading = MandarinPinyin.reading(text) {
            VStack(spacing: 6) {
                Button { expanded.toggle() } label: {
                    Label(UI(expanded ? "Hide pinyin" : "Show pinyin"), systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("pinyin-toggle")
                if expanded {
                    Text(reading).font(.callout).textSelection(.enabled)
                        .accessibilityIdentifier("pinyin-reading")
                }
            }.foregroundStyle(TideEnglishColor.secondary)
        }
    }
}
