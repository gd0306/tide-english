import SwiftUI
import TideEnglishCore

struct QuickTranslationView: View {
    let coordinator: ConversationCoordinator
    @State private var input = ""
    @State private var source: String
    @State private var target: String
    @State private var translator: QuickTranslationController
    @FocusState private var editing: Bool

    init(coordinator: ConversationCoordinator) {
        self.coordinator = coordinator
        let source = QuickTranslationRequest.sourceLanguage(for: coordinator.language)
        _source = State(initialValue: source)
        _target = State(initialValue: coordinator.store.preferences.meaningLanguage == source
            ? (source == "English" ? "Chinese (Simplified)" : "English") : coordinator.store.preferences.meaningLanguage)
        _translator = State(initialValue: QuickTranslationController { try await coordinator.quickTranslate($0) })
    }
    private var request: QuickTranslationRequest { .init(text: input, sourceLanguage: source, targetLanguage: target) }
    private var allowed: Bool { coordinator.hasAIConsent && coordinator.conversationProvider == .personalKey && !coordinator.isRunning }
    private var context: String {
        [coordinator.language.id, coordinator.modelConfiguration.provider.rawValue, coordinator.modelConfiguration.model,
         coordinator.modelConfiguration.baseURL, coordinator.conversationProvider.rawValue, allowed ? "ready" : "paused"].joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(UI("Quick translation")).font(.system(.title3, design: .rounded, weight: .semibold)).accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                languageMenu(selection: $source, label: "Source language", identifier: "translation-source")
                Button {
                    let output = translator.text
                    swap(&source, &target)
                    if !output.isEmpty { input = output }
                    translator.reset(); schedule()
                } label: { Image(systemName: "arrow.left.arrow.right").frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel(UI("Swap languages")).accessibilityIdentifier("translation-swap")
                languageMenu(selection: $target, label: "Target language", identifier: "translation-target")
            }
            ZStack(alignment: .topLeading) {
                if input.isEmpty { Text(UI("Enter text")).foregroundStyle(TideEnglishColor.secondary).padding(.horizontal, 5).padding(.top, 8).allowsHitTesting(false) }
                TextEditor(text: $input).frame(minHeight: 85, maxHeight: 120).scrollContentBackground(.hidden)
                    .focused($editing).accessibilityLabel(UI("Enter text")).accessibilityIdentifier("translation-input")
            }.padding(10).background(TideEnglishColor.cream, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(UI("Translation")).font(.caption).foregroundStyle(TideEnglishColor.secondary)
                    Spacer()
                    if translator.isLoading { ProgressView().accessibilityLabel(UI("Translating…")) }
                    if !translator.text.isEmpty {
                        Button { UIPasteboard.general.string = translator.text } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 32) }
                            .buttonStyle(.plain).accessibilityLabel(UI("Copy translation")).accessibilityIdentifier("translation-copy")
                    }
                }
                Text(translator.text.isEmpty ? UI("Your translation appears here.") : translator.text)
                    .foregroundStyle(translator.text.isEmpty ? TideEnglishColor.secondary : TideEnglishColor.ink)
                    .textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                    .accessibilityIdentifier("translation-output")
            }.padding(14).background(TideEnglishColor.sage.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            if input.utf16.count > 2000 { Text(UI("Keep text within 2,000 characters.")).font(.footnote).foregroundStyle(TideEnglishColor.secondary) }
            if let error = translator.error { Text(UI(error)).font(.footnote).foregroundStyle(TideEnglishColor.secondary).accessibilityIdentifier("translation-error") }
            HStack {
                Button(UI("Clear")) { input = ""; translator.reset() }.disabled(input.isEmpty).frame(minHeight: 44)
                    .accessibilityIdentifier("translation-clear")
                Spacer()
                Button(UI(translator.error == nil ? "Translate" : "Retry")) {
                    editing = false; translator.update(request, immediately: true)
                }.buttonStyle(.borderedProminent).tint(TideEnglishColor.accent)
                    .disabled(!allowed || !request.isValid || translator.isLoading).accessibilityIdentifier("translation-submit")
            }.font(.subheadline)
            if !coordinator.hasAIConsent {
                Button(UI("Allow AI translation")) { coordinator.requestVocabularyConsent() }.font(.footnote).frame(minHeight: 44)
            } else {
                Text(UI(coordinator.isRunning ? "End the conversation to use quick translation." :
                    coordinator.conversationProvider == .personalKey ? "Uses your selected model and API key." : "Choose your own API key in Settings to translate."))
                    .font(.caption).foregroundStyle(TideEnglishColor.secondary)
            }
        }.padding(18).background(TideEnglishColor.surface, in: RoundedRectangle(cornerRadius: 20))
            .onChange(of: request) { _, _ in schedule() }
            .task(id: context) { translator.reset(); schedule() }
            .onDisappear { translator.reset() }
    }
    private func schedule() {
        if allowed { translator.update(request) } else { translator.reset() }
    }
    private func languageMenu(selection: Binding<String>, label: String, identifier: String) -> some View {
        Menu {
            Picker(UI(label), selection: selection) {
                ForEach(MeaningLanguages.all, id: \.self) { Text(UI($0)).tag($0) }
            }
        } label: {
            HStack(spacing: 4) { Text(UI(selection.wrappedValue)).multilineTextAlignment(.leading); Spacer(minLength: 0); Image(systemName: "chevron.down").font(.caption2) }
                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10)
                .background(TideEnglishColor.cream, in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityLabel(UI(label) + ": " + UI(selection.wrappedValue)).accessibilityIdentifier(identifier)
    }
}
