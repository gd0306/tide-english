import SwiftUI
import TideEnglishCore

struct OnboardingView: View {
    let coordinator: ConversationCoordinator
    let done: () -> Void
    @State private var step = 0
    @State private var targetID: String
    @State private var meaningLanguage: String
    @State private var hasChosenMeaning: Bool
    @State private var greetingIndex = 0
    @State private var adultConfirmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    init(coordinator: ConversationCoordinator, done: @escaping () -> Void) {
        self.coordinator = coordinator
        self.done = done
        _targetID = State(initialValue: coordinator.language.id)
        _meaningLanguage = State(initialValue: coordinator.store.preferences.meaningLanguage)
        _hasChosenMeaning = State(initialValue: coordinator.store.preferences.meaningLanguage != Preferences().meaningLanguage)
    }

    private var target: LanguageModule { LanguageRegistry.module(for: targetID) ?? .norwegian }
    private var greeting: String { reduceMotion ? target.greeting : LanguageRegistry.all[greetingIndex].greeting }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step == 1 {
                    Button { move(to: 0) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium)).frame(width: 44, height: 44)
                            .modifier(SoftGlass())
                    }.accessibilityLabel(UI("Back to learning language")).accessibilityIdentifier("onboarding-back")
                } else { Brand() }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<2) { index in
                        Capsule().fill(index == step ? TideEnglishColor.orange : TideEnglishColor.peach)
                            .frame(width: index == step ? 24 : 8, height: 6)
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel(UI("Step \(step + 1) of 2"))
            }.padding(.horizontal, 26).padding(.top, 8).frame(height: 54)

            ScrollView {
                VStack(spacing: step == 0 ? 22 : 18) {
                    VStack(spacing: 4) {
                        Image(systemName: "book.closed").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(TideEnglishColor.accent).frame(height: 64)
                        Text(greeting)
                            .font(.system(size: typeSize.isAccessibilitySize ? 46 : step == 0 ? 60 : 48, weight: .medium, design: .serif))
                            .tracking(-2).id(greeting)
                            .transition(.opacity)
                            .frame(height: step == 0 ? 76 : 60)
                            .accessibilityIdentifier("onboarding-greeting")
                    }.padding(.top, step == 0 ? 8 : 0).accessibilityElement(children: .ignore).accessibilityLabel(UI("Welcome to \(AppBrand.name)"))

                    Group {
                        if step == 0 { languageStep }
                        else { meaningStep }
                    }.id(step).transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 14)))
                    if step == 1 && typeSize.isAccessibilitySize { consentDetails }
                }.padding(.horizontal, 26).padding(.bottom, 22)
            }.scrollIndicators(.hidden).id(step)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                if step == 1 && !typeSize.isAccessibilitySize { consentDetails }
                Button { advance() } label: {
                    Text(UI(step == 0 ? "Continue" : "Agree and continue"))
                        .font(.system(.headline, design: .rounded)).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 19)
                        .foregroundStyle(TideEnglishColor.onAccent).background(TideEnglishColor.accent, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Capsule())
                }
                    .buttonStyle(.plain)
                    .disabled(step == 1 && !adultConfirmed)
                    .accessibilityIdentifier("onboarding-continue")
                if !typeSize.isAccessibilitySize {
                    Text(UI(step == 0 ? "We’ll find your pace through conversation." : "You can change both languages in Settings."))
                        .font(.caption).foregroundStyle(TideEnglishColor.secondary).multilineTextAlignment(.center)
                }
            }.padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 16)
                .background(TideEnglishColor.cream)
        }
        .background(OnboardingBackground())
        .foregroundStyle(TideEnglishColor.ink).tint(TideEnglishColor.ink)
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: targetID)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3.8)) } catch { return }
                guard !Task.isCancelled else { return }
                if scenePhase == .active {
                    withAnimation(.easeInOut(duration: 0.6)) { greetingIndex = (greetingIndex + 1) % LanguageRegistry.all.count }
                }
            }
        }
    }

    private var consentDetails: some View {
        VStack(spacing: 12) {
            Toggle(UI("I’m 18 or older"), isOn: $adultConfirmed)
                .font(.footnote).accessibilityIdentifier("onboarding-adult-confirmation")
            Text(UI(AIProcessingConsent.summary))
                .font(.footnote).foregroundStyle(TideEnglishColor.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding-ai-consent")
            Link(UI("Privacy policy"), destination: URL(string: "https://tide-english.example/privacy/")!)
                .font(.footnote).underline().accessibilityIdentifier("onboarding-privacy-policy")
        }
    }

    private var languageStep: some View {
        VStack(spacing: 18) {
            Text(UI("What would you\nlike to speak?"))
                .font(.system(.title2, design: .serif, weight: .semibold)).tracking(-0.5)
                .multilineTextAlignment(.center).accessibilityIdentifier("onboarding-language-title")
            Menu {
                ForEach(LanguageRegistry.all) { language in
                    Button { targetID = language.id } label: {
                        if targetID == language.id {
                            Label(UI(language.settingsTitle), systemImage: "checkmark")
                        } else {
                            Text(UI(language.settingsTitle))
                        }
                    }.accessibilityIdentifier("onboarding-language-\(language.id)")
                }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.nativeName).font(.system(.title3, design: .rounded, weight: .medium))
                        Text(UI(target.settingsTitle)).font(.caption).foregroundStyle(TideEnglishColor.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(TideEnglishColor.secondary)
                }.padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: .infinity)
                    .background(TideEnglishColor.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 24))
                    .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(TideEnglishColor.rule.opacity(0.9), lineWidth: 1) }
            }
            .accessibilityLabel(UI("Learning language, \(target.settingsTitle)"))
            .accessibilityIdentifier("onboarding-language-picker")
        }
    }

    private var meaningStep: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Text(UI("A little help,\nin your language."))
                    .font(.system(.title2, design: .serif, weight: .semibold)).tracking(-0.5)
                Text(UI("\(AppBrand.name) speaks \(target.name). Choose the language you read most easily for meanings."))
                    .font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
            }.multilineTextAlignment(.center).accessibilityIdentifier("onboarding-meaning-title")
            Picker(UI("Subtitle language"), selection: Binding(get: { meaningLanguage }, set: { meaningLanguage = $0; hasChosenMeaning = true })) {
                ForEach(MeaningLanguages.all, id: \.self) { Text(UI($0)).tag($0) }
            }.pickerStyle(.menu).font(.system(.headline, design: .rounded))
                .padding(20).frame(maxWidth: .infinity)
                .background(TideEnglishColor.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("onboarding-meaning-picker")
            VStack(spacing: 8) {
                Text(target.greeting).font(.system(.title2, design: .rounded, weight: .medium))
                if target.id == "zh", let reading = MandarinPinyin.reading(target.greeting) {
                    Text(reading).font(.callout).foregroundStyle(TideEnglishColor.secondary)
                }
                Text(MeaningLanguages.greeting(in: meaningLanguage)).font(.body).foregroundStyle(TideEnglishColor.secondary)
                    .accessibilityIdentifier("onboarding-meaning-example")
                Text(UI("Turn meanings on whenever you need a hand.")).font(.caption).foregroundStyle(TideEnglishColor.secondary).padding(.top, 8)
            }.multilineTextAlignment(.center).padding(.vertical, 12)
        }
    }

    private func advance() {
        if step == 0 {
            if !hasChosenMeaning && meaningLanguage == target.name {
                let preferredNames = Locale.preferredLanguages.map { identifier in
                    let code = Locale(identifier: identifier).language.languageCode?.identifier ?? identifier
                    if code == "zh" { return "Chinese (Simplified)" }
                    if code == "sr" { return "Serbian (Latin)" }
                    if code == "fil" { return "Tagalog (Filipino)" }
                    return LanguageRegistry.module(for: code)?.name ?? Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized ?? ""
                }
                meaningLanguage = preferredNames.first { MeaningLanguages.all.contains($0) && $0 != target.name }
                    ?? MeaningLanguages.all.first { $0 != target.name } ?? "English"
            }
            move(to: 1)
        } else {
            coordinator.selectLanguage(targetID)
            coordinator.selectMeaningLanguage(meaningLanguage)
            coordinator.store.updatePreferences { $0.meaningVisible = true; $0.aiConsentVersion = AIProcessingConsent.version }
            done()
        }
    }

    private func move(to value: Int) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { step = value }
    }
}

enum AIProcessingConsent {
    static let version = 1
    static let summary = "With your permission, \(AppBrand.name) sends audio and selected text to OpenAI for conversations and meanings. Tide English minutes pass through our server; your own key connects directly. Provider retention rules apply. You can withdraw permission in Settings → AI processing."
    enum ConsentError: LocalizedError {
        case required
        var errorDescription: String? { "Before using AI features, open Talk and tap the microphone to review how your selected provider processes your audio and text." }
    }
}

struct AIConsentView: View {
    let summary: String
    let agree: () -> Void
    let decline: () -> Void
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "waveform.bubble").font(.system(size: 32, weight: .light)).foregroundStyle(TideEnglishColor.orange)
            Text(UI("Before we talk.")).font(.system(.title, design: .rounded, weight: .semibold))
                .accessibilityIdentifier("ai-consent-title")
            Text(UI(summary)).font(.body)
            Text(UI("Your learning record is stored on this iPhone. \(AppBrand.name) does not save raw audio. You can keep browsing your saved words and conversations without agreeing."))
                .font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
            Link(UI("Privacy policy"), destination: URL(string: "https://tide-english.example/privacy/")!).font(.subheadline).underline()
            Button(UI("Agree and continue"), action: agree).font(.headline).frame(maxWidth: .infinity).padding(18)
                .foregroundStyle(TideEnglishColor.onAccent).background(TideEnglishColor.accent, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("ai-consent-agree")
            Button(UI("Not now"), action: decline).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("ai-consent-decline")
        }.padding(28).foregroundStyle(TideEnglishColor.ink).tint(TideEnglishColor.ink)
        }.background(TideEnglishColor.cream)
            .presentationDetents([.large]).interactiveDismissDisabled()
    }
}

struct AIProcessingSettingsView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingWithdrawal = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(UI("AI processing")).font(.system(.title, design: .rounded, weight: .semibold))
                    Text(UI(coordinator.providerConsentSummary))
                    Text(UI(coordinator.hasAIConsent
                         ? "You’ve allowed this processing. You can withdraw permission at any time. This ends any active conversation and stops new AI requests."
                         : "AI processing is off. Your saved words and conversations remain available on this iPhone."))
                        .foregroundStyle(TideEnglishColor.secondary)
                        .accessibilityIdentifier("ai-processing-status")
                    Link(UI("Privacy policy"), destination: URL(string: "https://tide-english.example/privacy/")!).underline()
                    if coordinator.hasAIConsent {
                        Button(UI("Withdraw permission")) { confirmingWithdrawal = true }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .accessibilityIdentifier("ai-processing-withdraw")
                    } else {
                        Button(UI("Agree and enable AI")) { coordinator.acceptAIConsent() }
                            .font(.headline).frame(maxWidth: .infinity).padding(18)
                            .foregroundStyle(TideEnglishColor.onAccent).background(TideEnglishColor.accent, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("ai-processing-enable")
                    }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }.background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink).tint(TideEnglishColor.ink)
                .navigationTitle(UI("Privacy")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() }.accessibilityIdentifier("ai-processing-done") } }
        }.presentationDetents([.large])
            .confirmationDialog(UI("Withdraw AI processing permission?"), isPresented: $confirmingWithdrawal, titleVisibility: .visible) {
                Button(UI("Withdraw permission"), role: .destructive) { coordinator.withdrawAIConsent() }
                    .accessibilityIdentifier("ai-processing-confirm-withdraw")
                Button(UI("Cancel"), role: .cancel) {}
            } message: {
                Text(UI("Any active conversation will end. Your saved learning history stays on this iPhone. This does not undo processing already completed by your model provider."))
            }
    }
}

private struct OnboardingBackground: View {
    var body: some View { OceanBackdrop(prominent: true) }
}
