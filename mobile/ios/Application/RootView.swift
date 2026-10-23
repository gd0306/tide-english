import SwiftUI
import TideEnglishCore

struct RootView: View {
    @State private var coordinator: ConversationCoordinator
    @State private var tab = 0
    @State private var onboarding = false
    #if DEBUG && targetEnvironment(simulator)
    @State private var inspectedConstructionCount = 0
    @State private var vocabularyPerformanceReport = "pending"
    #endif
    @Environment(\.scenePhase) private var scenePhase
    init(store: LearningStore) {
        let coordinator = ConversationCoordinator(store: store)
        #if DEBUG && targetEnvironment(simulator)
        if InterfaceLifecyclePreview.enabled { InterfaceLifecyclePreview.constructionCount += 1 }
        #endif
        #if DEBUG && targetEnvironment(simulator)
        _tab = State(initialValue: ScreenshotPreview.tab)
        #endif
        _coordinator = State(initialValue: coordinator)
    }
    var body: some View {
        @Bindable var coordinator = coordinator
        TabView(selection: $tab) {
            Tab(UI("Talk"), systemImage: "waveform", value: 0) { shell { TalkView(coordinator: coordinator) } }
            Tab(UI("Themes"), systemImage: "square.grid.2x2", value: 1) {
                shell { ThemesView(coordinator: coordinator) { theme in coordinator.chooseTheme(theme); tab = 0 } }
            }
            Tab(UI("Words"), systemImage: "book", value: 2) { shell { WordsView(coordinator: coordinator) } }
        }
        #if DEBUG && targetEnvironment(simulator)
        .overlay(alignment: .topLeading) {
            if InterfaceLifecyclePreview.enabled {
                Button("Inspect lifecycle") { inspectedConstructionCount = InterfaceLifecyclePreview.constructionCount }
                    .font(.caption2)
                    .accessibilityIdentifier("coordinator-construction-count")
                    .accessibilityValue(String(inspectedConstructionCount))
            }
            if VocabularyPerformancePreview.enabled {
                Button("Measure vocabulary") {
                    vocabularyPerformanceReport = ProcessInfo.processInfo.arguments.contains("--verify-vocabulary-invalidation")
                        ? VocabularyPerformancePreview.validateInvalidation(coordinator)
                        : VocabularyPerformancePreview.measure(coordinator)
                }
                .font(.caption2)
                .accessibilityIdentifier("vocabulary-performance")
                .accessibilityValue(vocabularyPerformanceReport)
            }
        }
        #endif
        .toolbar(.hidden, for: .tabBar)
        .tint(TideEnglishColor.ink)
        .sheet(isPresented: $coordinator.showSettings, onDismiss: { Task { await coordinator.refreshContinuation() } }) {
            SettingsView(coordinator: coordinator)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $coordinator.showAIConsent, onDismiss: { coordinator.resumeAfterAIConsent() }) {
            AIConsentView(summary: coordinator.providerConsentSummary, agree: { coordinator.acceptAIConsent() }, decline: { coordinator.declineAIConsent() })
        }
        .fullScreenCover(isPresented: $onboarding) { OnboardingView(coordinator: coordinator) { coordinator.store.updatePreferences { $0.hasOnboarded = true }; onboarding = false } }
        .alert(UI("A little interruption"), isPresented: Binding(get: { coordinator.error != nil || coordinator.store.error != nil }, set: { if !$0 { coordinator.error = nil; coordinator.store.error = nil; coordinator.hostedAccessFailure = nil } })) {
            if coordinator.personalKeyFailure != nil {
                Button(UI("Review model settings")) {
                    coordinator.error = nil; coordinator.store.error = nil
                    coordinator.requestAdvancedFocus = true; coordinator.showSettings = true
                }
            }
            if let hostedFailure = coordinator.hostedAccessFailure {
                if case .noMinutes = hostedFailure {
                    Button(UI("Check minutes")) {
                        coordinator.error = nil; coordinator.store.error = nil; coordinator.hostedAccessFailure = nil
                        coordinator.requestAccountFocus = true; coordinator.showSettings = true
                    }
                }
                if hostedFailure.needsSignInRecovery {
                    Button(UI("Sign in")) {
                        coordinator.error = nil; coordinator.store.error = nil; coordinator.hostedAccessFailure = nil
                        coordinator.requestAccountFocus = true; coordinator.showSettings = true
                    }
                }
                Button(UI("Use my API key")) {
                    coordinator.error = nil; coordinator.store.error = nil; coordinator.hostedAccessFailure = nil
                    coordinator.requestAdvancedFocus = true; coordinator.showSettings = true
                }
            }
            Button(UI("OK"), role: .cancel) { coordinator.error = nil; coordinator.store.error = nil; coordinator.hostedAccessFailure = nil }
        } message: { Text(UI(coordinator.error ?? coordinator.store.error ?? "")) }
        .task { coordinator.resume(); AppleMinutePurchases.shared.start(); await HostedCloseRecovery.shared.resume() }
        .onChange(of: HostedCloseRecovery.shared.revision) { _, _ in Task { await coordinator.refreshContinuation() } }
        .onChange(of: AppleMinutePurchases.shared.balanceRevision) { _, _ in Task { await coordinator.refreshContinuation() } }
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            #if DEBUG && targetEnvironment(simulator)
            if arguments.contains("--preview") && arguments.contains("--preview-onboarding") {
                onboarding = !coordinator.store.preferences.hasOnboarded
                return
            }
            #endif
            onboarding = !coordinator.store.preferences.hasOnboarded && !arguments.contains("--preview") && !AudioVerification.requested
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { coordinator.background(); HostedCloseRecovery.shared.pause() }
            else if phase == .active { coordinator.resume(); Task { await HostedCloseRecovery.shared.resume(); await AppleMinutePurchases.shared.checkPurchases() } }
        }
        #if DEBUG
        .task {
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--preview-onboarding") {
                coordinator.store.updatePreferences { $0.hasOnboarded = false }
            }
            if ProcessInfo.processInfo.arguments.contains("--preview"), ProcessInfo.processInfo.arguments.contains("--preview-existing-user") {
                coordinator.store.updatePreferences { $0.hasOnboarded = true }
            }
            if let screen = ScreenshotPreview.screen { coordinator.prepareScreenshot(screen) }
            coordinator.prepareTypedReplyPreview()
            coordinator.prepareConversationPolicyPreview()
            coordinator.prepareCaptionFollowingPreview()
            coordinator.prepareVocabularyPreview()
            if VocabularyPerformancePreview.enabled { VocabularyPerformancePreview.seed(coordinator.store) }
            if ProcessInfo.processInfo.arguments.contains("--verify-network-recovery") {
                coordinator.notice = await LiveTransport.verifyRecoveryLifecycle() ? "Network recovery lifecycle passed" : "Network recovery lifecycle failed"
                return
            }
            #endif
            if AudioVerification.requested { await AudioVerification.run(coordinator) }
            else if ProcessInfo.processInfo.arguments.contains("--ended-conversation") { coordinator.prepareConversationPreview(active: false) }
            else if ProcessInfo.processInfo.arguments.contains("--active-conversation") { coordinator.prepareConversationPreview(active: true) }
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--preview-caption-following") { await coordinator.runCaptionFollowingPreview() }
            #endif
        }
        #endif
    }
    private func shell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .foregroundStyle(TideEnglishColor.ink)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    OceanNavigation(selection: $tab)
                }
                .background { OceanBackdrop(prominent: tab == 0) }.toolbar {
                ToolbarItem(placement: .topBarLeading) { Brand().fixedSize() }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { coordinator.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel(UI("Settings")).accessibilityIdentifier("settings-button")
                }
            }.toolbarBackground(TideEnglishColor.cream, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
        }
    }
}

struct TalkView: View {
    @Bindable var coordinator: ConversationCoordinator
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var targetLineHeight = 30.0
    @ScaledMetric(relativeTo: .subheadline) private var meaningLineHeight = 21.0
    @State private var typing = false
    @State private var conversationChoice = false
    @State private var openAccountAfterContinuation = false
    @State private var transcript: SessionRecord?
    @State private var lookup: WordLookup?
    init(coordinator: ConversationCoordinator) {
        self.coordinator = coordinator
        #if DEBUG && targetEnvironment(simulator)
        if ScreenshotPreview.screen == .meaning {
            _lookup = State(initialValue: WordLookup(word: "sobremesa", sentence: "Podemos quedarnos de sobremesa y charlar un rato."))
        }
        #endif
    }
    var body: some View {
        GeometryReader { geometry in
            let scrollPage = typeSize >= .xxxLarge || geometry.size.height < 480 || geometry.size.width < 365
            let compact = !scrollPage && geometry.size.height < 620
            if scrollPage {
                ScrollView {
                    talkContent(scrollPage: true, compact: compact)
                        .frame(minHeight: geometry.size.height)
                }.scrollIndicators(.hidden)
            } else {
                talkContent(scrollPage: false, compact: compact)
                    .frame(height: geometry.size.height)
            }
        }
        .sheet(isPresented: $typing) { TypedReplyView(coordinator: coordinator) }
        .onChange(of: coordinator.hasContinuation, initial: true) { _, waiting in
            if waiting && !coordinator.isRunning { conversationChoice = true }
        }
        .sheet(isPresented: $conversationChoice, onDismiss: {
            if openAccountAfterContinuation {
                openAccountAfterContinuation = false
                coordinator.requestAccountFocus = true; coordinator.showSettings = true
            }
        }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(UI(coordinator.notice ?? "Your conversation is saved. You can continue when your minutes finish updating."))
                            .font(.body).foregroundStyle(TideEnglishColor.secondary)
                        Button {
                            if coordinator.continuationNeedsMinutes { openAccountAfterContinuation = true; conversationChoice = false }
                            else { conversationChoice = false; coordinator.start() }
                        } label: {
                            Text(UI(coordinator.continuationNeedsMinutes ? "Add minutes" : "Continue conversation")).frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent).tint(TideEnglishColor.accent).foregroundStyle(TideEnglishColor.onAccent)
                        .disabled(!coordinator.continuationReady && !coordinator.continuationNeedsMinutes)
                        .accessibilityIdentifier(coordinator.continuationNeedsMinutes ? "continuation-add-minutes" : "continue-conversation")
                        Button(UI("New conversation")) { conversationChoice = false; coordinator.resetConversation() }
                            .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("new-conversation")
                    }.padding(24)
                }.background(TideEnglishColor.cream)
                    .navigationTitle(UI("Continue practicing")).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { conversationChoice = false } } }
            }
            .tint(TideEnglishColor.ink).presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: coordinator.state)
        .sheet(item: $transcript) { session in
            TranscriptView(session: session, meaningLanguage: coordinator.store.preferences.meaningLanguage)
        }
        .sheet(item: $lookup) { item in LookupView(item: item, coordinator: coordinator) }
    }
    private func talkContent(scrollPage: Bool, compact: Bool) -> some View {
        let hasLongPassage = coordinator.assistantPassage != nil &&
            (coordinator.caption.count > 60 || coordinator.language.id == "zh")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(UI("Daily practice")).font(.caption.weight(.medium)).foregroundStyle(TideEnglishColor.secondary)
                Spacer()
                Text(coordinator.selectedTheme.map { $0.id == "current" ? $0.title : UI($0.title) } ?? UI(coordinator.language.talkTitle))
                    .font(.caption).foregroundStyle(TideEnglishColor.secondary)
            }.padding(.top, compact ? 14 : 22)
            Rectangle().fill(TideEnglishColor.rule).frame(height: 1).padding(.top, 14)
            Spacer(minLength: compact ? 18 : 30)
            captionArea(scrollPage: scrollPage)
                .frame(maxHeight: scrollPage ? nil : .infinity)
            Spacer(minLength: compact ? 16 : 24)
            VStack(alignment: .leading, spacing: 10) {
                ConversationHalo(energy: max(coordinator.outputLevel, coordinator.inputLevel * 0.45), listening: coordinator.state == .active && !coordinator.isMuted, active: coordinator.state == .active)
                    .frame(height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    if coordinator.state == .active, let seconds = coordinator.inactivitySeconds {
                        Text(UI("Ending in \(seconds)s")).fontWeight(.medium).monospacedDigit()
                        Text(UI("Reply to continue")).font(.caption2)
                    } else { Text(UI(coordinator.status)) }
                }.font(.caption).foregroundStyle(TideEnglishColor.secondary).frame(minHeight: 34, alignment: .topLeading)
                    .accessibilityElement(children: .ignore).accessibilityLabel(UI(coordinator.status))
                    .accessibilityAddTraits([.isStaticText, .updatesFrequently]).accessibilityIdentifier("conversation-status")
                Rectangle().fill(TideEnglishColor.rule).frame(height: 1)
            }
            controls(stacked: scrollPage).padding(.top, compact ? 16 : 20)
            Group {
                let actionLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 24))
                actionLayout {
                    if coordinator.state == .active {
                        Button(UI("Type instead"), systemImage: "keyboard") { typing = true }
                        Button(UI("A little help"), systemImage: "sparkles") { coordinator.help() }
                    }
                }.font(.caption)
            }.frame(minHeight: compact ? 28 : 42).accessibilityHidden(coordinator.state != .active && coordinator.session == nil)
        }.padding(.horizontal, 30).frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: hasLongPassage)
    }
    private func captionArea(scrollPage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if coordinator.assistantPassage == nil && !scrollPage {
                VStack(alignment: .leading, spacing: 14) {
                    targetPassage
                    if coordinator.store.preferences.meaningVisible { meaningPassage }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                followingPassage(text: coordinator.caption) { targetPassage }
                    .frame(height: targetLineHeight * 3 + (coordinator.language.id == "zh" ? 58 : 0))
                    .accessibilityIdentifier("target-passage-scroll")
                if coordinator.store.preferences.meaningVisible {
                    followingPassage(text: coordinator.meaning, isMeaning: true) { meaningPassage }
                        .frame(height: meaningLineHeight * 3 + (coordinator.meaningError == nil ? 0 : 60))
                        .accessibilityIdentifier("meaning-passage-scroll")
                }
            }
            if let user = coordinator.userPassage {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(UI("YOU")).font(.system(.caption2, design: .rounded, weight: .medium))
                    Text(String(user.text.suffix(160))).font(.caption).lineLimit(1)
                }.foregroundStyle(TideEnglishColor.secondary).multilineTextAlignment(.center).padding(.top, 3)
            }
            if coordinator.working { ProgressView(UI("Checking that for you…")).font(.caption).tint(TideEnglishColor.secondary) }
            if let sources = coordinator.session?.topics.last?.sources, !sources.isEmpty {
                Button(UI("Sources"), systemImage: "link") { transcript = coordinator.session }.font(.caption)
            }
            if coordinator.conversationProvider == .personalKey && coordinator.personalKeyFailure != nil && !coordinator.isRunning {
                Button(UI("Review model settings")) {
                    coordinator.requestAdvancedFocus = true; coordinator.showSettings = true
                }.font(.footnote).accessibilityIdentifier("talk-open-advanced")
            }
            if let notice = coordinator.notice, !coordinator.hasContinuation {
                Text(UI(notice)).font(.footnote).foregroundStyle(TideEnglishColor.secondary).multilineTextAlignment(.center)
            }
        }.frame(minHeight: typeSize.isAccessibilitySize ? 100 : 105).frame(maxWidth: .infinity)
    }
    private var targetPassage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(linkedCaption).font(.system(coordinator.assistantPassage == nil ? .largeTitle : .title2, design: coordinator.assistantPassage == nil ? .serif : .default, weight: .medium))
                .tracking(-0.5).multilineTextAlignment(.leading).tint(TideEnglishColor.ink)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "tideenglish-word", let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let word = components.queryItems?.first?.value else { return .discarded }
                    lookup = WordLookup(word: word, sentence: coordinator.caption); return .handled
                }).accessibilityIdentifier("target-caption")
            if coordinator.language.id == "zh" { PinyinHelp(text: coordinator.caption) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var meaningPassage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(coordinator.assistantPassage == nil ? MeaningLanguages.greeting(in: coordinator.store.preferences.meaningLanguage) : !coordinator.meaning.isEmpty ? coordinator.meaning : coordinator.translating ? UI("Finding the meaning…") : "")
                .font(.subheadline).foregroundStyle(TideEnglishColor.secondary).multilineTextAlignment(.leading)
                .accessibilityIdentifier("meaning-caption")
            if let error = coordinator.meaningError {
                Text(UI(error)).foregroundStyle(TideEnglishColor.secondary).accessibilityIdentifier("meaning-error")
                if coordinator.canRetryMeaning {
                    Button(UI("Try meaning again")) { coordinator.retryMeaning() }
                }
            }
        }.font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func followingPassage<Content: View>(text: String, isMeaning: Bool = false, @ViewBuilder content: @escaping () -> Content) -> some View {
        let following = Binding(get: { isMeaning ? coordinator.meaningCaptionFollowing : coordinator.targetCaptionFollowing },
                                set: { if isMeaning { coordinator.meaningCaptionFollowing = $0 } else { coordinator.targetCaptionFollowing = $0 } })
        return FollowingPassage(passageID: coordinator.session.map { $0.id.uuidString + ":" + (coordinator.assistantPassage?.id ?? "") },
                                text: text, content: content, following: following)
    }
    private var linkedCaption: AttributedString {
        var result = AttributedString()
        for segment in CaptionWords.segments(coordinator.caption, languageID: coordinator.language.id) {
            var part = AttributedString(segment.text)
            if coordinator.assistantPassage != nil, let word = segment.lookup {
                var components = URLComponents(); components.scheme = "tideenglish-word"; components.host = "lookup"
                components.queryItems = [URLQueryItem(name: "word", value: word)]
                part.link = components.url
            }
            part.foregroundColor = TideEnglishColor.ink; result.append(part)
        }
        return result
    }
    private func controls(stacked: Bool) -> some View {
        let outerLayout = stacked ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        let labelLayout = stacked ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 6))
        return outerLayout {
            Button { coordinator.toggleMeaning() } label: {
                labelLayout {
                    Image(systemName: coordinator.store.preferences.meaningVisible ? "captions.bubble.fill" : "captions.bubble")
                        .font(.system(size: 20)).frame(width: 48, height: 48)
                        .background(TideEnglishColor.ink.opacity(coordinator.store.preferences.meaningVisible ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                    Text(UI("Meaning")).font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(UI(coordinator.store.preferences.meaningVisible ? "Hide meaning subtitles" : "Show meaning subtitles"))
                .accessibilityValue(UI(coordinator.store.preferences.meaningVisible ? "On" : "Off"))
            Button {
                if coordinator.state == .active { coordinator.toggleMute() }
                else if coordinator.hasContinuation { conversationChoice = true }
                else if !coordinator.isRunning { coordinator.start() }
            } label: {
                HStack(spacing: 9) {
                    if coordinator.state == .connecting || coordinator.state == .closing { ProgressView().tint(TideEnglishColor.onAccent) }
                    else { Image(systemName: coordinator.isMuted && coordinator.state == .active ? "mic.slash" : "mic").font(.system(size: 20, weight: .medium)) }
                    Text(UI(coordinator.state == .active ? (coordinator.isMuted ? "Unmute" : "Mute") : coordinator.state == .connecting ? "Connecting…" : coordinator.state == .closing ? "Ending…" : "Start practice"))
                        .font(.callout.weight(.semibold)).multilineTextAlignment(.center)
                }.padding(.horizontal, 14).frame(width: stacked ? nil : 174).frame(minHeight: 60)
            }.buttonStyle(ConversationButtonStyle()).padding(.bottom, stacked ? 0 : 18)
                .disabled(coordinator.state == .connecting || coordinator.state == .closing)
                .accessibilityLabel(UI(coordinator.state == .active ? (coordinator.isMuted ? "Unmute microphone" : "Mute microphone") : "Start conversation"))
                .accessibilityIdentifier("start-conversation")
            Button { if coordinator.isRunning { coordinator.end() } else { transcript = coordinator.session } } label: {
                labelLayout {
                    Image(systemName: coordinator.isRunning ? "phone.down" : "text.bubble").font(.system(size: 20)).frame(width: 48, height: 48)
                        .background(TideEnglishColor.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                    Text(UI(coordinator.isRunning ? "End" : "Transcript")).font(.caption2)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(UI(coordinator.isRunning ? "End conversation" : "Conversation transcript"))
                .disabled(coordinator.session == nil)
        }.foregroundStyle(TideEnglishColor.ink)
    }
}

struct WordLookup: Identifiable { var id = UUID(); var word: String; var sentence: String }
struct LookupView: View {
    let item: WordLookup
    let coordinator: ConversationCoordinator
    @State private var explanation: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(item.word).font(.system(.largeTitle, design: .rounded, weight: .medium))
                if coordinator.language.id == "zh" { PinyinHelp(text: item.word) }
                Text(item.sentence).font(.title3).foregroundStyle(TideEnglishColor.secondary)
                if let explanation { Text(explanation).font(.body).textSelection(.enabled) }
                else if let error { Text(UI(error)).foregroundStyle(TideEnglishColor.secondary) }
                else { ProgressView(UI("Finding the meaning…")) }
                Spacer()
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading).background(TideEnglishColor.cream)
                .navigationTitle(UI("A little meaning")).navigationBarTitleDisplayMode(.inline)
        }.presentationDetents([.medium, .large])
            .task {
                #if DEBUG && targetEnvironment(simulator)
                if ScreenshotPreview.screen == .meaning {
                    explanation = "The relaxed conversation that continues after a meal, when nobody is in a hurry to leave."
                    return
                }
                #endif
                do { explanation = try await coordinator.lookup(word: item.word, sentence: item.sentence) }
                catch { self.error = error.localizedDescription }
            }
    }
}

struct TypedReplyView: View {
    let coordinator: ConversationCoordinator
    @State private var text = ""
    @State private var sending = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(UI("Say it your way.")).font(.system(.title, design: .rounded, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                TextField(UI("Reply in \(coordinator.language.name) or another language"), text: $text, axis: .vertical).lineLimit(3...6).focused($focused).padding(18).background(TideEnglishColor.surface, in: RoundedRectangle(cornerRadius: 22)).accessibilityIdentifier("typed-reply-input")
                    .onChange(of: text) { _, _ in coordinator.noteTypingActivity() }
                if let error = coordinator.typedReplyError {
                    Text(UI(error)).font(.footnote).foregroundStyle(TideEnglishColor.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("typed-reply-error")
                }
                Button { sending = true; Task { let ok = await coordinator.sendTyped(text); sending = false; if ok { dismiss() } } } label: {
                    HStack { Text(UI(sending ? "Sending…" : "Send reply")).fixedSize(horizontal: false, vertical: true); Spacer(); Image(systemName: "arrow.up") }.padding(18).foregroundStyle(TideEnglishColor.onAccent).background(TideEnglishColor.accent, in: RoundedRectangle(cornerRadius: 12))
                }.disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("typed-reply-send").id("typed-reply-send")
                Spacer()
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(TideEnglishColor.ink)
            }.accessibilityIdentifier("typed-reply-scroll").background(TideEnglishColor.cream)
                .onChange(of: coordinator.typedReplyError) { _, error in
                    if error != nil { withAnimation { proxy.scrollTo("typed-reply-send", anchor: .bottom) } }
                }
            }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(UI("Close")) { dismiss() } } }
        }.presentationDetents([.medium, .large]).onAppear { coordinator.typedReplyError = nil; coordinator.noteTypingActivity(); focused = true }
    }
}


/// The viewport stays put; the text advances at a reading pace until touched.
private struct FollowingPassage<Content: View>: View {
    let passageID: String?
    let text: String
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Binding var following: CaptionFollowing
    @State private var position = ScrollPosition(y: 0)
    @State private var offset = 0.0
    @State private var maximum = 0.0
    private var followingValue: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-caption-following") {
            return "\(Int(offset))|\(following.interrupted ? "paused" : "following")"
        }
        #endif
        return following.interrupted ? UI("Automatic scrolling paused") : ""
    }
    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content().frame(maxWidth: .infinity).frame(minHeight: viewport.size.height)
            }
            .scrollPosition($position)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Double.self) { geometry in
                max(0, geometry.contentSize.height - geometry.containerSize.height)
            } action: { _, value in maximum = value }
            .onScrollGeometryChange(for: Double.self) { $0.contentOffset.y } action: { _, value in offset = value }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating { following.interrupt() }
            }
            .accessibilityValue(followingValue)
            .task(id: passageID) {
                following.receive(passageID)
                position.scrollTo(y: 0)
                guard passageID != nil else { return }
                do {
                    try await Task.sleep(for: .milliseconds(900))
                    while !Task.isCancelled {
                        if !voiceOver && !following.interrupted {
                            let next = following.nextOffset(current: offset, maximum: maximum, elapsed: 0.05, reducedMotion: reduceMotion)
                            if next > offset + 0.01 {
                                if reduceMotion { position.scrollTo(y: next) }
                                else { withAnimation(.linear(duration: 0.05)) { position.scrollTo(y: next) } }
                            }
                        }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                } catch { /* Passage change or view dismissal cancels following. */ }
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Counts the actual side-effectful construction site, not the retained State identity.
/// The explicit preview flag guarantees an in-memory learning store and presentation.
@MainActor private enum InterfaceLifecyclePreview {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--preview")
        && ProcessInfo.processInfo.arguments.contains("--verify-interface-lifecycle")
    static var constructionCount = 0
}

/// Synthetic, in-memory workload. No credentials, network or owner records are used.
@MainActor private enum VocabularyPerformancePreview {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--preview")
        && ProcessInfo.processInfo.arguments.contains("--verify-page-performance")
    static func seed(_ store: LearningStore) {
        var archive = Archive()
        store.selectLanguage("en")
        store.updatePreferences { $0.meaningLanguage = "English"; $0.hasOnboarded = true }
        for index in 0..<100 {
            let lemma = "sample\(index)"
            let date = Date().addingTimeInterval(-Double(index) * 60)
            var record = SessionRecord(languageID: "en")
            record.startedAt = date; record.endedAt = date.addingTimeInterval(30)
            record.append(Fragment(speaker: .user, text: "I use \(lemma) today.", startMS: 0, endMS: 3000, receivedAt: date))
            let passage = record.passages[0]
            record.assessments = [Assessment(passageID: passage.id, revisionKey: passage.revisionKey,
                outcome: .success, suggestedLevel: 1, nextGoal: "", capability: "",
                words: [WordProposal(lemma: lemma, meaning: "a synthetic example", form: lemma,
                    kind: .independent, confidence: 0.95, sourceIDs: passage.fragments.map(\.id),
                    quote: passage.text, language: "en")], createdAt: date)]
            archive.sessions.append(record)
        }
        try! store.importData(archive.encoded())
    }
    static func measure(_ coordinator: ConversationCoordinator) -> String {
        let words = coordinator.store.learner.words
        let start = ProcessInfo.processInfo.systemUptime
        var resolved = 0
        for word in words {
            if coordinator.vocabularyValue(for: word)?.meaningDefinition == "a synthetic example" { resolved += 1 }
            coordinator.requestVocabulary(for: word)
        }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        return "\(resolved)|\(Int(milliseconds.rounded()))"
    }
    static func validateInvalidation(_ coordinator: ConversationCoordinator) -> String {
        let store = coordinator.store
        let words = store.learner.words
        guard words.count == 100 else { return "fixture failed" }
        let first = words[0], second = words[1], third = words[2], fourth = words[3]
        guard coordinator.vocabularyValue(for: first) != nil else { return "initial failed" }
        var altered = first
        altered.example += " Changed source."
        guard coordinator.vocabularyValue(for: altered) == nil else { return "source identity failed" }
        store.hideWord(first.id)
        guard coordinator.vocabularyValue(for: first) == nil,
              coordinator.vocabularyValue(for: second) != nil else { return "hide failed" }
        let record = store.sessions.first { $0.assessments.first?.words.first?.lemma == second.lemma }!
        store.correctPassage(sessionID: record.id, passageID: record.passages[0].id, text: "A corrected passage.")
        guard coordinator.vocabularyValue(for: second) == nil else { return "correction failed" }
        let removed = store.sessions.first { $0.assessments.first?.words.first?.lemma == third.lemma }!
        store.deleteSession(removed.id)
        guard coordinator.vocabularyValue(for: third) == nil else { return "delete failed" }
        coordinator.selectMeaningLanguage("Chinese (Simplified)")
        guard coordinator.vocabularyValue(for: fourth) == nil else { return "meaning scope failed" }
        coordinator.selectMeaningLanguage("English")
        guard coordinator.vocabularyValue(for: fourth) != nil else { return "restore failed" }
        store.selectLanguage("es")
        guard coordinator.vocabularyValue(for: fourth) == nil else { return "learning scope failed" }
        store.selectLanguage("en")
        store.deleteAll()
        guard coordinator.vocabularyValue(for: fourth) == nil else { return "erase failed" }
        return "passed"
    }
}
#endif
