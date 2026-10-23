import SwiftUI
import UniformTypeIdentifiers
import TideEnglishCore

struct ThemesView: View {
    let coordinator: ConversationCoordinator
    let choose: (ConversationTheme?) -> Void
    @State private var search = ""
    @State private var category = "All"
    @State private var current = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var themes: [ConversationTheme] {
        coordinator.language.themes.filter { (category == "All" || $0.category == category) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search) || UI($0.title).localizedCaseInsensitiveContains(search) || UI($0.subtitle).localizedCaseInsensitiveContains(search) || UI($0.category).localizedCaseInsensitiveContains(search)) }
    }
    private var categories: [String] { coordinator.language.themes.map(\.category).reduce(into: ["All"]) { if !$0.contains($1) { $0.append($1) } } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "A place to begin", title: "What’s on\nyour mind?", subtitle: "Same friend. Somewhere new.")
                Button { choose(nil) } label: {
                    HStack { Image(systemName: "waveform"); Text(UI("Just talk")); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.headline).padding(22).background(TideEnglishColor.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button(UI(c)) { category = c }.font(.caption).padding(.horizontal, 15).padding(.vertical, 11)
                                .background(category == c ? TideEnglishColor.peach : TideEnglishColor.surface, in: Capsule())
                                .accessibilityAddTraits(category == c ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 150), spacing: 12)], spacing: 12) {
                    ForEach(themes) { theme in
                        Button { if theme.id == "today" { current = true } else { choose(theme) } } label: {
                            VStack(alignment: .leading, spacing: 28) {
                                Image(systemName: theme.symbol).font(.system(size: 28, weight: .light)).foregroundStyle(TideEnglishColor.secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(UI(theme.title)).font(.system(.headline, design: .serif))
                                    Text(UI(theme.subtitle)).font(.caption).foregroundStyle(TideEnglishColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, minHeight: 142, alignment: .leading).padding(19)
                                .background(TideEnglishColor.panels[theme.colorIndex], in: RoundedRectangle(cornerRadius: 14))
                                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(TideEnglishColor.ocean.opacity(0.12), lineWidth: 1) }
                        }.buttonStyle(.plain)
                    }
                }
                if themes.isEmpty { ContentUnavailableView.search(text: search) }
            }.padding(24)
        }.foregroundStyle(TideEnglishColor.ink)
            .searchable(text: $search, prompt: UI("Find a conversation"))
            .sheet(isPresented: $current) { CurrentTopicView(coordinator: coordinator) { choose(coordinator.selectedTheme) } }
    }
}

struct CurrentTopicView: View {
    let coordinator: ConversationCoordinator
    let selected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var brief: TopicBrief?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PageHeading(eyebrow: "The world today", title: "A fresh conversation.", subtitle: "What would you like to talk about?")
                    if coordinator.supportsCurrentTopics {
                        TextField(UI(coordinator.language.topicPlaceholder), text: $query, axis: .vertical).padding(18).background(TideEnglishColor.surface, in: RoundedRectangle(cornerRadius: 20))
                        Button { find() } label: {
                            HStack { Text(UI(loading ? "Finding something interesting…" : "Find a topic")); Spacer(); if loading { ProgressView() } else { Image(systemName: "sparkle.magnifyingglass") } }.padding(18).background(TideEnglishColor.peach, in: Capsule())
                        }.disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Text(UI("Current news search is unavailable with \(coordinator.modelConfiguration.provider.displayName). \(AppBrand.name) does not have a supported source-backed search for this connection."))
                            .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    }
                    if let error { Text(UI(error)).font(.footnote).foregroundStyle(TideEnglishColor.secondary) }
                    if let brief {
                        Text(.init(brief.text)).font(.body).textSelection(.enabled)
                        SourcesView(sources: brief.sources, date: brief.retrievedAt)
                        Button(UI("Talk about this"), systemImage: "waveform") { coordinator.discuss(brief); selected(); dismiss() }
                            .font(.headline).padding(18).frame(maxWidth: .infinity).foregroundStyle(TideEnglishColor.onAccent).background(TideEnglishColor.accent, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if coordinator.supportsCurrentTopics {
                        Text(UI("Current topics use your selected provider outside a conversation. Sources stay attached to the topic.")).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    }
                }.padding(26)
            }.background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(UI("Close")) { dismiss() } } }
        }
    }
    private func find() {
        loading = true; error = nil
        Task { do { brief = try await coordinator.currentTopic(query) } catch { self.error = error.localizedDescription }; loading = false }
    }
}

struct WordsView: View {
    let coordinator: ConversationCoordinator
    @State private var search = ""
    @State private var selected: WordState?
    @State private var sessions = false
    @State private var flashcards: FlashcardSession?
    private var learner: LearnerState { coordinator.store.learner }
    private var words: [WordState] {
        guard !search.isEmpty else { return learner.words }
        return learner.words.filter { word in
            let definition = coordinator.vocabularyValue(for: word)
            return [word.lemma, word.meaning, definition?.learningDefinition ?? "",
                definition?.meaningDefinition ?? ""].contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(UI("Little by little · \(coordinator.language.name)"))
                        .font(.system(.caption, weight: .medium)).foregroundStyle(TideEnglishColor.secondary)
                    HStack(spacing: 16) {
                        Text(UI("Your words.")).font(.system(.largeTitle, design: .serif, weight: .semibold)).tracking(-0.8)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        Button {
                            flashcards = FlashcardSession(deck: FlashcardDeck(words: learner.words, languageID: coordinator.language.id))
                        } label: {
                            Image(systemName: "rectangle.on.rectangle").font(.system(size: 20)).frame(width: 48, height: 48).modifier(SoftGlass())
                        }.buttonStyle(.plain).accessibilityLabel(UI("Practice flashcards")).accessibilityIdentifier("open-flashcards")
                            .disabled(learner.words.isEmpty)
                    }
                    Text(UI("Familiar words, ready for another conversation.")).font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                    Picker(UI("Meaning language"), selection: Binding(get: { coordinator.store.preferences.meaningLanguage },
                        set: { coordinator.selectMeaningLanguage($0) })) {
                        ForEach(MeaningLanguages.all, id: \.self) { Text(UI($0)).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("vocabulary-meaning-language")
                }
                if let error = coordinator.store.vocabularyCacheError {
                    Text(UI(error)).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                }
                if words.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "book.closed").font(.system(size: 34, weight: .light)).foregroundStyle(TideEnglishColor.ocean).accessibilityHidden(true)
                        Text(UI(search.isEmpty ? "They’ll grow from here." : "No matching words yet.")).font(.system(.title2, design: .serif, weight: .medium))
                        Text(UI(search.isEmpty ? "As we talk, useful words and phrases find a home here. Their strength grows when you recall them over time." : "Search a word or either definition.")).font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                    }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(TideEnglishColor.sage, in: RoundedRectangle(cornerRadius: 28))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(words) { word in
                            Button { selected = word } label: {
                                HStack(spacing: 18) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(word.lemma).font(.system(.title2, design: .rounded, weight: .medium))
                                        VocabularyDefinitionContent(coordinator: coordinator, word: word,
                                            learningID: "vocabulary-learning-definition", meaningID: "vocabulary-meaning-definition")
                                    }
                                    Spacer(minLength: 10)
                                    VStack(alignment: .trailing, spacing: 8) { RecallBars(count: word.bars); Text(UI(word.label)).font(.caption2).foregroundStyle(TideEnglishColor.secondary) }
                                }.padding(.vertical, 20)
                            }.buttonStyle(.plain).accessibilityIdentifier("vocabulary-word-\(word.lemma)")
                                .task(id: coordinator.vocabularyContext) { coordinator.requestVocabulary(for: word) }
                            VocabularyDefinitionStatus(coordinator: coordinator, word: word)
                            Divider().overlay(TideEnglishColor.peach)
                        }
                    }
                }
                HStack { Text(UI("1 · Fragile")); Spacer(); Text(UI("2 · Growing")); Spacer(); Text(UI("3 · Steady")) }.font(.caption).foregroundStyle(TideEnglishColor.secondary)
                Text(UI("The bars estimate spoken recall, not permanent mastery. Using a word with visible meanings counts as supported practice.")).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                if !learner.capabilities.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(UI("Finding your voice")).font(.system(.title3, design: .rounded, weight: .semibold))
                        ForEach(learner.capabilities, id: \.self) { Text($0).font(.subheadline) }
                        Text(UI("Observed across conversations. These are provisional, not formal level certificates.")).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    }.padding(22).background(TideEnglishColor.butter, in: RoundedRectangle(cornerRadius: 24))
                }
                Button(UI("Past conversations"), systemImage: "clock.arrow.circlepath") { sessions = true }.font(.subheadline).padding(.vertical, 8)
            }.padding(26)
        }.foregroundStyle(TideEnglishColor.ink).searchable(text: $search, prompt: UI("Find a word"))
            .sheet(item: $selected) { word in WordDetailView(word: word, coordinator: coordinator) }
            .sheet(isPresented: $sessions) { SessionHistoryView(store: coordinator.store) }
            .sheet(item: $flashcards) { session in FlashcardsView(deck: session.deck, coordinator: coordinator) }
    }
}

struct WordDetailView: View {
    let word: WordState
    let coordinator: ConversationCoordinator
    private var store: LearningStore { coordinator.store }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(word.lemma).font(.system(.largeTitle, design: .serif, weight: .medium))
                    if store.language.id == "zh" { PinyinHelp(text: word.lemma) }
                    VocabularyDefinitionContent(coordinator: coordinator, word: word,
                        learningID: "word-detail-learning-definition", meaningID: "word-detail-meaning-definition")
                    VocabularyDefinitionStatus(coordinator: coordinator, word: word)
                    HStack { RecallBars(count: word.bars); Text(UI(word.label)).font(.subheadline) }
                    Text(UI(word.explanation)).font(.body)
                    Text("“\(word.example)”").font(.system(.title3, design: .rounded)).padding(20).frame(maxWidth: .infinity, alignment: .leading).background(TideEnglishColor.peach, in: RoundedRectangle(cornerRadius: 14))
                    Text(UI("\(word.independentCount) independent uses · Last seen \(word.lastSeen.formatted(date: .abbreviated, time: .omitted))")).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    Button(UI("Remove from my words"), role: .destructive) { store.hideWord(word.id); dismiss() }.font(.footnote)
                    Spacer()
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }.background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink)
                .task(id: coordinator.vocabularyContext) { coordinator.requestVocabulary(for: word) }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() } } }
        }.presentationDetents([.large])
    }
}

private struct VocabularyDefinitionContent: View {
    let coordinator: ConversationCoordinator
    let word: WordState
    let learningID: String
    let meaningID: String
    var body: some View {
        let definition = coordinator.vocabularyValue(for: word)
        let combined = coordinator.language.id == "en" && coordinator.store.preferences.meaningLanguage == "English"
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(UI(definition != nil || coordinator.language.id == "en" ? "Learning-language definition" : "English reference"))
                    .font(.caption2).foregroundStyle(TideEnglishColor.secondary)
                Text(definition?.learningDefinition ?? word.meaning).font(.subheadline)
                    .accessibilityIdentifier(learningID)
            }
            if let definition, !combined {
                VStack(alignment: .leading, spacing: 3) {
                    Text(UI("Meaning-language definition")).font(.caption2).foregroundStyle(TideEnglishColor.secondary)
                    Text(definition.meaningDefinition).font(.subheadline).accessibilityIdentifier(meaningID)
                }
            }
        }.foregroundStyle(TideEnglishColor.secondary)
    }
}

private struct VocabularyDefinitionStatus: View {
    let coordinator: ConversationCoordinator
    let word: WordState
    var body: some View {
        if coordinator.vocabularyValue(for: word) == nil {
            if !coordinator.hasAIConsent {
                Button(UI("Allow AI definitions")) { coordinator.requestVocabularyConsent() }
                    .font(.footnote).frame(minHeight: 44).accessibilityIdentifier("vocabulary-consent")
            } else if coordinator.vocabularyIsLoading(for: word) {
                ProgressView(UI("Loading definitions…")).font(.footnote)
            } else if coordinator.vocabularyHasError(for: word) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(UI("Definitions couldn’t be loaded.")).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    Button(UI("Retry definitions")) { coordinator.requestVocabulary(for: word, retry: true) }
                        .font(.footnote).frame(minHeight: 44).accessibilityIdentifier("vocabulary-retry")
                }
            }
        }
    }
}

struct SourcesView: View {
    var sources: [SourceLink]
    var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UI("Sources · \(date.formatted(date: .abbreviated, time: .omitted))")).font(.caption).foregroundStyle(TideEnglishColor.secondary)
            ForEach(sources) { source in if let url = source.safeURL { Link(destination: url) { Label(source.title, systemImage: "arrow.up.right").font(.subheadline) } } }
        }
    }
}

struct TranscriptView: View {
    let session: SessionRecord?
    var meaningLanguage = "English"
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let session {
                        ForEach(session.passages) { passage in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(UI(passage.speaker == .assistant ? "TIDE ENGLISH" : "YOU")).font(.caption).tracking(1).foregroundStyle(TideEnglishColor.secondary)
                                Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                                    .accessibilityIdentifier(passage.speaker == .user ? "transcript-user-passage" : "transcript-assistant-passage")
                                if session.languageID == "zh" { PinyinHelp(text: passage.text) }
                                if let translation = session.translations[MeaningRequest.cacheKey(revisionKey: passage.revisionKey, language: meaningLanguage)] ?? session.translations[meaningLanguage + "::" + passage.revisionKey] ?? session.translations[passage.revisionKey] {
                                    Text(translation).font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(session.topics) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                        if session.fragments.isEmpty && session.topics.isEmpty { Text(UI("Your conversation will appear here.")).foregroundStyle(TideEnglishColor.secondary) }
                    } else { Text(UI("Start a conversation and your words will appear here.")) }
                }.padding(26)
            }.background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink)
                .navigationTitle(UI("Our conversation")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() } } }
        }
    }
}

struct SessionHistoryView: View {
    let store: LearningStore
    @State private var selected: SessionRecord?
    @State private var deleting: SessionRecord?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if store.learningSessions.isEmpty { Text(UI("Your \(store.language.name) conversations will appear here.")).foregroundStyle(TideEnglishColor.secondary) }
                ForEach(store.learningSessions) { session in
                    Button { selected = session } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.title).font(.headline)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(TideEnglishColor.secondary)
                        }.padding(.vertical, 8)
                    }.swipeActions { Button(UI("Delete"), role: .destructive) { deleting = session }.disabled(session.endedAt == nil) }
                }
            }.scrollContentBackground(.hidden).background(TideEnglishColor.cream)
                .navigationTitle(UI("Past conversations")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() } } }
        }.sheet(item: $selected) { session in EditableTranscriptView(sessionID: session.id, store: store) }
            .confirmationDialog(UI("Delete this conversation and its learning evidence?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button(UI("Delete conversation"), role: .destructive) { if let deleting { store.deleteSession(deleting.id) }; deleting = nil }
            }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct EditableTranscriptView: View {
    let sessionID: UUID
    let store: LearningStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: String?
    @State private var editedText = ""
    private var session: SessionRecord? { store.sessions.first { $0.id == sessionID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(session?.passages ?? []) { passage in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(UI(passage.speaker == .user ? "YOU" : "TIDE_ENGLISH")).font(.caption).tracking(1)
                                Spacer()
                                if passage.speaker == .user && session?.endedAt != nil {
                                    Button(UI("Edit")) { editedText = passage.text; editingID = passage.id }.font(.caption)
                                }
                            }.foregroundStyle(TideEnglishColor.secondary)
                            Text(passage.text).font(.system(.title3, design: .rounded)).textSelection(.enabled)
                                    .accessibilityIdentifier(passage.speaker == .user ? "transcript-user-passage" : "transcript-assistant-passage")
                            if session?.languageID == "zh" { PinyinHelp(text: passage.text) }
                        }
                    }
                    ForEach(session?.topics ?? []) { topic in Text(.init(topic.text)); SourcesView(sources: topic.sources, date: topic.retrievedAt) }
                }.padding(26)
            }.background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink)
                .navigationTitle(UI("Our conversation")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() } } }
        }.sheet(isPresented: Binding(get: { editingID != nil }, set: { if !$0 { editingID = nil } })) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    TextField(UI("What you said"), text: $editedText, axis: .vertical).lineLimit(4...10).padding(18).background(TideEnglishColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    Text(UI("Correct a misheard phrase. Learning evidence from the old wording will be removed; the original remains in your backup history.")).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    Spacer()
                }.padding(24).background(TideEnglishColor.cream).navigationTitle(UI("What you said")).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(UI("Cancel")) { editingID = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button(UI("Save")) { if let id = editingID { store.correctPassage(sessionID: sessionID, passageID: id, text: editedText) }; editingID = nil } }
                    }
            }.presentationDetents([.medium, .large])
        }
    }
}

struct SettingsView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var account = ManagedAccountStore()
    @State private var hasKey = Self.initialHasKey()
    @State private var showingKey = false
    @State private var confirmingPersonalKey = false
    @State private var showingHostedSwitch = false
    @State private var showingAccount = false
    @State private var showingAIProcessing = false
    private var store: LearningStore { coordinator.store }
    private var isPreview: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--preview")
        #else
        false
        #endif
    }
    private var hostedAvailable: Bool {
        if isPreview {
            return !ProcessInfo.processInfo.arguments.contains("--preview-personal") &&
                !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--preview-provider=") })
        }
        return ManagedAccountConfiguration.load() != nil
    }
    private var accountAvailable: Bool {
        if !isPreview && ManagedAccountConfiguration.load() != nil { return true }
        guard hostedAvailable else { return false }
        let args = ProcessInfo.processInfo.arguments
        return ["--preview-member", "--preview-apple", "--preview-paid-member", "--preview-paid-only",
                "--preview-paid-reserved", "--preview-purchases", "--preview-hosted-sign-in"].contains { args.contains($0) }
    }
    private var supplier: String { coordinator.modelConfiguration.provider.displayName }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    Button { showingKey = true } label: {
                        LabeledContent(UI("Model & API key"), value: UI(supplier))
                    }
                    .accessibilityIdentifier("settings-model-provider")
                    .disabled(coordinator.isRunning)
                } header: { Text(UI("AI model")) } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(UI(coordinator.isRunning ? "End this conversation before changing your model or API key." : "Choose your model provider, chat model and API key."))
                        if let failure = coordinator.personalKeyFailure {
                            Text(UI(failure.kind.settingsTitle)).accessibilityIdentifier("model-provider-issue")
                        }
                    }
                }.id("model-section")
                Section(UI("Appearance & language")) {
                    Picker(UI("Interface language"), selection: Binding(get: { InterfacePreferences.shared.language }, set: { InterfacePreferences.shared.setLanguage($0) })) {
                        Text("中文").tag(InterfaceLanguage.chinese)
                        Text("English").tag(InterfaceLanguage.english)
                    }.pickerStyle(.menu).accessibilityIdentifier("settings-interface-language")
                    InterfaceThemeChoices()
                }
                if EmailAccountConfiguration.load() != nil {
                    Section {
                        NavigationLink { EmailAccountView(coordinator:coordinator) } label: {
                            Label(UI("Account"), systemImage:"person.crop.circle")
                        }.accessibilityIdentifier("email-account-settings")
                    }
                }
                if accountAvailable { Section {
                    NavigationLink {
                        ManagedAccountView(coordinator: coordinator, store: account)
                    } label: {
                        HStack(spacing: 12) {
                            TideEnglishOrb(active: false).frame(width: 38, height: 38).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(UI("Account"))
                                Text(account.profile?.email ?? UI(account.session == nil ? "Sign in, if you’d like" : "Signed in"))
                                    .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("managed-account-settings")
                } }
                Section {
                    LearningLanguagePicker(coordinator: coordinator)
                    Toggle(UI("Meaning subtitles"), isOn: Binding(get: { store.preferences.meaningVisible }, set: { value in
                        if value != store.preferences.meaningVisible { coordinator.toggleMeaning() }
                    }))
                    Picker(UI("Meaning language"), selection: Binding(get: { store.preferences.meaningLanguage }, set: { coordinator.selectMeaningLanguage($0) })) {
                        ForEach(MeaningLanguages.all, id: \.self) { Text(UI($0)).tag($0) }
                    }.pickerStyle(.menu).disabled(coordinator.isRunning)
                    NavigationLink(UI("Interests")) { InterestsSettingsView(coordinator: coordinator) }
                        .disabled(coordinator.isRunning)
                    Text(UI("Corrections happen gently as you talk."))
                        .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                } header: { Text(UI("Your learning")) } footer: {
                    Text(UI(coordinator.isRunning ? "End this conversation to switch languages. Each language keeps its own words and progress." : "Each language keeps its own words and progress."))
                }
                Section {
                    Picker(UI("Session limit"), selection: Binding(get: { store.preferences.sessionMinutes }, set: { value in store.updatePreferences { $0.sessionMinutes = value } })) {
                        ForEach([5, 10, 15, 20, 30, 60], id: \.self) { Text(UI("\($0) minutes")).tag($0) }
                    }.pickerStyle(.menu).disabled(coordinator.isRunning)
                } header: { Text(UI("Conversation")) } footer: {
                    Text(UI(hostedAvailable ? "Ends one conversation after the selected time. Your available Tide English minutes are separate." : "Ends one conversation after the selected time."))
                }
                Section(UI("Your data")) {
                    NavigationLink(UI("Learning backup & data")) { LearningBackupView(coordinator: coordinator) }
                }
                if hostedAvailable {
                    Section {
                        Picker(UI("Conversation access"), selection: Binding(get: { coordinator.conversationProvider }, set: chooseProvider)) {
                            Text(UI("Tide English minutes")).tag(ConversationProvider.hosted)
                            Text(UI("My API key")).tag(ConversationProvider.personalKey)
                        }.pickerStyle(.menu).disabled(coordinator.isRunning)
                            .accessibilityIdentifier("settings-conversation-access")
                    } header: { Text(UI("Advanced")) }.id("advanced-section")
                }
                Section(UI("Help & privacy")) {
                    Button {
                        showingAIProcessing = true
                    } label: {
                        LabeledContent(UI("AI processing"), value: UI(coordinator.hasAIConsent ? "Allowed" : "Off"))
                    }.accessibilityIdentifier("settings-ai-processing")
                    Link(UI("Privacy policy"), destination: URL(string: "https://tide-english.example/privacy/")!)
                        .accessibilityIdentifier("settings-privacy-policy")
                    NavigationLink(UI("About \(AppBrand.name)")) { AboutTideEnglishView(coordinator: coordinator, hostedAvailable: hostedAvailable) }
                }
            }
            .scrollContentBackground(.hidden).background(TideEnglishColor.cream).tint(TideEnglishColor.ink)
            .navigationDestination(isPresented: $showingAccount) {
                if accountAvailable { ManagedAccountView(coordinator: coordinator, store: account) }
            }
            .navigationTitle(UI("Settings")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() } } }
            .onAppear {
                if coordinator.requestAccountFocus && accountAvailable {
                    coordinator.requestAccountFocus = false
                    DispatchQueue.main.async { showingAccount = true }
                }
                if coordinator.requestAdvancedFocus {
                    coordinator.requestAdvancedFocus = false
                    DispatchQueue.main.async { withAnimation { proxy.scrollTo("model-section", anchor: .top) } }
                }
            }
            }
        }
        .sheet(isPresented: $showingKey, onDismiss: {
            hasKey = Self.initialHasKey(configuration: coordinator.modelConfiguration)
            if coordinator.requestHostedSwitch && hostedAvailable {
                coordinator.requestHostedSwitch = false
                showingHostedSwitch = true
            }
        }) {
            NavigationStack {
                ModelProviderSettingsView(coordinator: coordinator)
            }
        }
        .sheet(isPresented: $showingHostedSwitch) { HostedAccessSwitchView(coordinator: coordinator) }
        .sheet(isPresented: $showingAIProcessing) {
            AIProcessingSettingsView(coordinator: coordinator)
        }
        .confirmationDialog(UI("Use your API key?"), isPresented: $confirmingPersonalKey, titleVisibility: .visible) {
            Button(UI("Use my key")) { coordinator.selectConversationProvider(.personalKey) }
            Button(UI("Cancel"), role: .cancel) {}
        } message: { Text(UI("\(supplier) bills your account for usage. Tide English minutes stay available if you switch back later.")) }
        .task { if accountAvailable { account.refresh() } }
    }
    private func chooseProvider(_ provider: ConversationProvider) {
        guard !coordinator.isRunning, provider != coordinator.conversationProvider else { return }
        if provider == .hosted && hostedAvailable { showingHostedSwitch = true }
        else if hasKey { confirmingPersonalKey = true }
        else { showingKey = true }
    }
    private static func initialHasKey(configuration: ProviderConfiguration? = nil) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            return ProcessInfo.processInfo.arguments.contains("--preview-key") &&
                (configuration?.provider ?? .openAI) == .openAI
        }
        #endif
        return CredentialStore.hasKey(configuration: configuration ?? ModelSettings.load())
    }
}

private extension ProviderFailureKind {
    var settingsTitle: String {
        switch self {
        case .creditExhausted: "Credits used up"
        case .spendLimit: "Spending limit reached"
        case .usageLimit: "Usage limit reached"
        case .quota: "Billing needs attention"
        case .authentication: "Key not accepted"
        default: "Provider needs attention"
        }
    }
}

private struct InterestsSettingsView: View {
    let coordinator: ConversationCoordinator
    var body: some View {
        Form {
            Section {
                TextField(UI("A few things you enjoy"), text: Binding(get: { coordinator.store.preferences.interests }, set: { value in
                    coordinator.store.updatePreferences { $0.interests = String(value.prefix(500)) }
                }), axis: .vertical)
                .lineLimit(4...10).disabled(coordinator.isRunning)
                .accessibilityIdentifier("settings-interests")
            } footer: { Text(UI("Helps \(AppBrand.name) suggest conversations that matter to you. Saved as you type on this iPhone.")) }
        }.scrollContentBackground(.hidden).background(TideEnglishColor.cream).navigationTitle(UI("Interests"))
    }
}

private struct HostedAccessSwitchView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var available: HostedBalance?
    @State private var checking = true
    @State private var failed = false
    @State private var switchTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if checking { ProgressView(UI("Checking your minutes…")) }
                    else if let available {
                        LabeledContent(UI("Available"), value: available.displayText)
                        if !available.canStart {
                            Text(UI(available.paidReserved ? "Some minutes are in use. Check again shortly." :
                                 "Not enough minutes to start a conversation."))
                        }
                    }
                    else { Text(UI("Couldn’t check your minutes. Try again.")) }
                    if failed { Text(UI("Your minutes changed. Check again before switching.")).foregroundStyle(TideEnglishColor.secondary) }
                    if !checking && available == nil { Button(UI("Try again")) { Task { await check() } } }
                } header: { Text(UI("Tide English minutes")) } footer: { Text(UI("Your saved \(coordinator.modelConfiguration.provider.displayName) key will remain on this iPhone. Switching changes the next conversation only.")) }
                if let available, available.canStart, !checking {
                    Section {
                        Button(UI("Use Tide English minutes")) {
                            switchTask = Task {
                                checking = true
                                guard let latest = await coordinator.hostedBalanceForSwitch(), latest.canStart,
                                      !Task.isCancelled, coordinator.conversationProvider == .personalKey,
                                      !coordinator.isRunning else {
                                    self.available = nil; failed = true; checking = false; return
                                }
                                coordinator.selectConversationProvider(.hosted)
                                dismiss()
                            }
                        }.frame(maxWidth: .infinity).fontWeight(.semibold)
                    }
                }
            }.scrollContentBackground(.hidden).background(TideEnglishColor.cream)
                .navigationTitle(UI("Conversation access")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(UI("Cancel")) { dismiss() } } }
        }
        .task { await check() }
        .onDisappear { switchTask?.cancel() }
    }
    private func check() async {
        checking = true; failed = false
        available = await coordinator.hostedBalanceForSwitch()
        checking = false
    }
}

private struct LearningBackupView: View {
    let coordinator: ConversationCoordinator
    @State private var backup: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var deleting = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button(UI("Export learning backup"), systemImage: "square.and.arrow.up") {
                    do { backup = BackupDocument(data: try coordinator.store.exportData()); exporting = true }
                    catch { message = error.localizedDescription }
                }
                Button(UI("Import learning backup"), systemImage: "square.and.arrow.down") { importing = true }
                    .disabled(coordinator.isRunning)
                Button(UI("Delete all conversations and learning"), role: .destructive) { deleting = true }
                    .disabled(coordinator.isRunning)
            } footer: { Text(UI("Backups include transcripts and learning evidence, never your API key. Import adds conversations with new IDs. Learning stays on this iPhone unless you export it.")) }
            if let message { Section { Text(UI(message)) } }
        }.scrollContentBackground(.hidden).background(TideEnglishColor.cream).navigationTitle(UI("Learning data"))
            .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "Tide-English-learning-backup") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let granted = url.startAccessingSecurityScopedResource()
                    defer { if granted { url.stopAccessingSecurityScopedResource() } }
                    try coordinator.store.importData(Archive.readImportData(from: url)); message = "Your backup has been imported."
                } catch { message = error.localizedDescription }
            }
            .confirmationDialog(UI("Delete all learning data on this phone?"), isPresented: $deleting, titleVisibility: .visible) {
                Button(UI("Delete all learning data"), role: .destructive) { coordinator.deleteLearningData() }
            } message: { Text(UI("This removes conversations, vocabulary and progress. Export a backup first if you want to keep them. Your key and account remain.")) }
    }
}

private struct AboutTideEnglishView: View {
    let coordinator: ConversationCoordinator
    let hostedAvailable: Bool
    @State private var notices = false
    var body: some View {
        Form {
            Section {
                LabeledContent(UI("Version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                if coordinator.modelConfiguration.provider == .openAI {
                    Link(UI("AI Data Controls"), destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                }
                Link(UI("Contact support"), destination: URL(string: "https://tide-english.example/support/")!)
                    .accessibilityIdentifier("settings-support")
                Link(UI("Terms of use"), destination: URL(string: "https://tide-english.example/terms/")!)
                    .accessibilityIdentifier("settings-terms")
                Button(UI("Open-source notices")) { notices = true }
            }
            Section {
                if hostedAvailable {
                    Text(UI("Tide English minutes send audio and selected text through Tide English’s server to OpenAI. With your own key, selected data goes directly to \(coordinator.modelConfiguration.provider.displayName). Raw audio is not saved by Tide English."))
                } else {
                    Text(UI("With your own key, selected conversation data goes directly to \(coordinator.modelConfiguration.provider.displayName). Voice processing depends on the selected provider. Raw audio is not saved by \(AppBrand.name)."))
                }
            }
        }.scrollContentBackground(.hidden).background(TideEnglishColor.cream).navigationTitle(UI("About \(AppBrand.name)"))
            .sheet(isPresented: $notices) {
                NavigationStack {
                    ScrollView {
                        Text(Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
                            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? UI("Notices unavailable."))
                            .font(.footnote).padding(24).textSelection(.enabled)
                    }.navigationTitle(UI("Open-source notices")).navigationBarTitleDisplayMode(.inline)
                }
            }
    }
}

struct LearningLanguagePicker: View {
    let coordinator: ConversationCoordinator
    var body: some View {
        Picker(UI("Learning language"), selection: Binding(get: { coordinator.language.id }, set: { coordinator.selectLanguage($0) })) {
            ForEach(LanguageRegistry.all) { language in Text(UI(language.settingsTitle)).tag(language.id) }
        }
        .pickerStyle(.menu)
        .disabled(coordinator.isRunning)
        .accessibilityIdentifier("learning-language-picker")
    }
}


private struct FlashcardSession: Identifiable {
    let id = UUID()
    let deck: FlashcardDeck
}

private struct FlashcardsView: View {
    let deck: FlashcardDeck
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0
    @State private var dragOffset = 0.0
    @State private var dragAxis = 0
    @State private var advancing = false
    @State private var revealAllowedAfter = Date.distantPast
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if deck.words.isEmpty {
                    ContentUnavailableView(UI("No words yet"), systemImage: "leaf", description: Text(UI("Useful words from your conversations will appear here.")))
                } else {
                    GeometryReader { geometry in
                        let direction = dragOffset > 0 ? -1 : 1
                        let destination = deck.destination(from: selection, direction: direction)
                        ZStack {
                            if destination != selection {
                                FlashcardView(coordinator: coordinator, word: deck.words[destination], selected: false, showContent: abs(dragOffset) > 6)
                                    .padding(.horizontal, 24).scaleEffect(0.94 + min(abs(dragOffset) / geometry.size.width, 1) * 0.06)
                                    .offset(y: 12).opacity(0.7).allowsHitTesting(false).accessibilityHidden(true)
                            }
                            FlashcardView(coordinator: coordinator, word: deck.words[selection], selected: true, canReveal: { !advancing && Date() > revealAllowedAfter }).id(deck.words[selection].id)
                                .padding(.horizontal, 24).offset(x: dragOffset)
                                .rotationEffect(.degrees(reduceMotion ? 0 : dragOffset / geometry.size.width * 12))
                                .simultaneousGesture(DragGesture(minimumDistance: 12)
                                    .onChanged { value in
                                        guard !advancing else { return }
                                        revealAllowedAfter = Date().addingTimeInterval(0.3)
                                        if dragAxis == 0 { dragAxis = abs(value.translation.width) > abs(value.translation.height) ? 1 : -1 }
                                        guard dragAxis == 1 else { return }
                                        let candidate = value.translation.width
                                        let target = deck.destination(from: selection, direction: candidate < 0 ? 1 : -1)
                                        dragOffset = target == selection ? candidate * 0.2 : candidate
                                    }
                                    .onEnded { value in
                                        revealAllowedAfter = Date().addingTimeInterval(0.3)
                                        let horizontal = dragAxis == 1
                                        dragAxis = 0
                                        guard !advancing else { return }
                                        let distance = value.translation.width
                                        if horizontal && (abs(distance) > geometry.size.width * 0.22 || abs(value.predictedEndTranslation.width) > geometry.size.width * 0.5) {
                                            move(distance < 0 ? 1 : -1, width: geometry.size.width)
                                        } else {
                                            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) { dragOffset = 0 }
                                        }
                                    })
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.accessibilityElement(children: .contain)
                        .accessibilityLabel(UI("Flashcard"))
                        .accessibilityValue(UI("\(selection + 1) of \(deck.words.count)"))
                        .accessibilityIdentifier("flashcard-pager")
                        .accessibilityActions {
                            if selection > 0 { Button(UI("Previous word")) { move(-1, width: 500) } }
                            if selection < deck.words.count - 1 { Button(UI("Next word")) { move(1, width: 500) } }
                        }
                }
            }.padding(.top, 16).background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink)
                .navigationTitle(UI("Your words")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { dismiss() }.accessibilityIdentifier("close-flashcards") } }
        }.tint(TideEnglishColor.ink).presentationDetents([.large]).presentationDragIndicator(.hidden).interactiveDismissDisabled()
    }
    private func move(_ direction: Int, width: Double) {
        guard !advancing else { return }
        let destination = deck.destination(from: selection, direction: direction)
        guard destination != selection else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) { dragOffset = 0 }
            return
        }
        if reduceMotion { selection = destination; dragOffset = 0; return }
        advancing = true
        withAnimation(.easeIn(duration: 0.2), completionCriteria: .logicallyComplete) {
            dragOffset = direction > 0 ? -width * 1.2 : width * 1.2
        } completion: {
            selection = destination
            dragOffset = 0
            advancing = false
        }
    }
}

private struct FlashcardView: View {
    let coordinator: ConversationCoordinator
    let word: WordState
    let selected: Bool
    var canReveal: () -> Bool = { true }
    var showContent = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    var body: some View {
        ZStack {
            face(back: false).modifier(FlashcardFaceRotation(angle: revealed && !reduceMotion ? 180 : 0, back: false))
                .opacity(reduceMotion && revealed ? 0 : 1).accessibilityHidden(revealed).allowsHitTesting(!revealed)
            face(back: true).modifier(FlashcardFaceRotation(angle: reduceMotion ? 180 : (revealed ? 180 : 0), back: true))
                .opacity(reduceMotion && !revealed ? 0 : 1).accessibilityHidden(!revealed).allowsHitTesting(revealed)
        }.onChange(of: selected) { _, _ in revealed = false }
            .task(id: coordinator.vocabularyContext) {
                if selected { coordinator.requestVocabulary(for: word) }
            }
    }
    private func face(back: Bool) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack(spacing: 10) { RecallBars(count: word.bars); Text(UI(word.label)).font(.subheadline).foregroundStyle(TideEnglishColor.secondary) }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("flashcard-proficiency")
                Text(word.lemma).font(.system(.largeTitle, design: .rounded, weight: .medium))
                    .multilineTextAlignment(.center).textSelection(.enabled).accessibilityIdentifier("flashcard-word")
                if back {
                    VocabularyDefinitionContent(coordinator: coordinator, word: word,
                        learningID: "flashcard-meaning", meaningID: "flashcard-meaning-selected")
                        .multilineTextAlignment(.center)
                    if selected { VocabularyDefinitionStatus(coordinator: coordinator, word: word) }
                }
                Button(UI(back ? "Hide meaning" : "Tap to reveal meaning")) { reveal() }
                    .font(.subheadline).foregroundStyle(TideEnglishColor.secondary).frame(minHeight: 44)
                    .accessibilityIdentifier("reveal-flashcard")
            }.opacity(showContent ? 1 : 0).padding(28).frame(maxWidth: .infinity, minHeight: 320)
                .background(TideEnglishColor.surface, in: RoundedRectangle(cornerRadius: 32))
                .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(TideEnglishColor.peach.opacity(0.65), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 32)).onTapGesture { reveal() }
                .accessibilityAction(named: UI(back ? "Hide meaning" : "Reveal meaning")) { reveal() }
                .padding(.vertical, 12)
        }.defaultScrollAnchor(.center, for: .alignment).scrollIndicators(.hidden)
    }
    private func reveal() {
        guard canReveal() else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.48)) { revealed.toggle() }
    }
}

private struct FlashcardFaceRotation: AnimatableModifier {
    var angle: Double
    let back: Bool
    var animatableData: Double { get { angle } set { angle = newValue } }
    func body(content: Content) -> some View {
        content.opacity((angle >= 90) == back ? 1 : 0)
            .rotation3DEffect(.degrees(angle - (back ? 180 : 0)), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .allowsHitTesting((angle >= 90) == back)
    }
}

private struct InterfaceThemeChoices: View {
    private var selected: InterfaceTheme { InterfacePreferences.shared.theme }
    var body: some View {
        ForEach(InterfaceTheme.allCases, id: \.self) { theme in
            Button { InterfacePreferences.shared.setTheme(theme) } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol(theme)).font(.system(size: 20)).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(UI(title(theme))).font(.body)
                        Text(UI(detail(theme))).font(.caption).foregroundStyle(TideEnglishColor.secondary)
                    }
                    Spacer(minLength: 4)
                    if selected == theme { Image(systemName: "checkmark").font(.body.weight(.semibold)) }
                }.foregroundStyle(TideEnglishColor.ink).padding(.vertical, 3).frame(minHeight: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("interface-theme-\(theme.rawValue)")
                .accessibilityAddTraits(selected == theme ? .isSelected : [])
        }
    }
    private func title(_ theme: InterfaceTheme) -> String {
        switch theme { case .paper: "Paper"; case .midnight: "Midnight"; case .grove: "Grove" }
    }
    private func detail(_ theme: InterfaceTheme) -> String {
        switch theme { case .paper: "Warm paper, quiet focus"; case .midnight: "Soft light for late practice"; case .grove: "Fresh greens, a little calm" }
    }
    private func symbol(_ theme: InterfaceTheme) -> String {
        switch theme { case .paper: "book.closed"; case .midnight: "moon.stars"; case .grove: "leaf" }
    }
}
