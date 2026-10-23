import SwiftUI
import TideEnglishCore

struct ModelProviderSettingsView: View {
    let coordinator: ConversationCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: ProviderConfiguration
    @State private var drafts: [ModelProvider: ProviderConfiguration] = [:]
    @State private var key = ""
    @State private var hasSavedKey = false
    @State private var previewSavedServices: Set<String> = []
    @State private var previewRemovedServices: Set<String> = []
    @State private var message: String?
    @State private var removingKey = false

    init(coordinator: ConversationCoordinator) {
        self.coordinator = coordinator
        _configuration = State(initialValue: coordinator.modelConfiguration)
    }

    var body: some View {
        Form {
            Section {
                Picker(UI("Provider"), selection: Binding(get: { configuration.provider }, set: selectProvider)) {
                    ForEach(ModelProvider.allCases, id: \.self) { provider in
                        Text(UI(provider.displayName)).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .disabled(coordinator.isRunning)
                .accessibilityIdentifier("model-provider-picker")
                TextField(UI("Chat model"), text: $configuration.model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("model-chat-model")
                if configuration.provider == .custom {
                    TextField(UI("HTTPS API base URL"), text: Binding(
                        get: { configuration.baseURL },
                        set: { value in
                            guard value != configuration.baseURL else { return }
                            configuration.baseURL = value
                            key = ""
                            message = nil
                            refreshSavedStatus()
                        }
                    ))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.URL).keyboardType(.URL)
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("model-base-url")
                }
            } header: { Text(UI("Chat model")) } footer: {
                Text(UI("The selected chat model handles conversations, meanings and learning assessment. Custom endpoints must use HTTPS and support OpenAI-compatible chat completions."))
            }

            Section {
                LabeledContent(UI("API key"), value: UI(hasSavedKey ? "Saved on this iPhone" : "No key saved"))
                    .accessibilityIdentifier("model-key-status")
                SecureField(UI(hasSavedKey ? "Replacement key" : "New key"), text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive()
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("api-key")
                if hasSavedKey {
                    Button(UI("Remove key"), role: .destructive) { removingKey = true }
                        .disabled(coordinator.isRunning)
                }
                if let failure = coordinator.personalKeyFailure,
                   configuration == coordinator.modelConfiguration {
                    Text(UI(failureMessage(failure)))
                        .foregroundStyle(TideEnglishColor.secondary)
                    if hostedAvailable && coordinator.conversationProvider == .personalKey {
                        Button(UI("Use Tide English minutes")) {
                            key = ""
                            dismiss()
                            coordinator.requestHostedSwitch = true
                        }
                    }
                }
            } footer: {
                Text(UI("Your key stays in this iPhone’s Keychain and is sent only to the selected provider. \(configuration.provider == .gemini ? "Google bills your Gemini account" : "\(configuration.provider.displayName) bills your account") for usage. Each provider and custom endpoint keeps its own key."))
            }

            Section(UI("Voice")) {
                Text(UI(voiceDescription))
                    .accessibilityIdentifier("model-voice-description")
                Text(UI("The voice model is separate from the chat model above."))
                    .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                if configuration.provider == .gemini {
                    Text(UI("Gemini Live connections may stop after about 10 minutes. Your conversation is saved; start a new conversation to continue."))
                        .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    Text(UI("Live learning-plan updates apply at your next conversation."))
                        .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                    Text(UI("Current news search is unavailable with Gemini in \(AppBrand.name)."))
                        .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                }
            }

            if let message {
                Section { Text(UI(message)).foregroundStyle(TideEnglishColor.secondary) }
            }

            Section {
                Button(UI("Save model settings")) { save() }
                    .disabled(coordinator.isRunning)
                    .accessibilityIdentifier("model-save")
                if let console = consoleURL {
                    Link(UI(configuration.provider == .gemini ? "Google AI Studio" : "\(configuration.provider.displayName) console"), destination: console)
                }
            } footer: {
                Text(UI(coordinator.isRunning ? "End this conversation before changing model settings." : "Changes apply to the next conversation. A new provider asks for AI processing permission before sending data."))
            }
        }
        .scrollContentBackground(.hidden).background(TideEnglishColor.cream)
        .navigationTitle(UI("Model provider")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(UI("Done")) { key = ""; dismiss() } } }
        .onAppear { refreshSavedStatus() }
        .onDisappear { key = "" }
        .confirmationDialog(UI("Remove the saved key?"), isPresented: $removingKey, titleVisibility: .visible) {
            Button(UI("Remove key"), role: .destructive) { removeKey() }
        } message: {
            Text(UI("The selected provider will need a new key before a conversation can start."))
        }
    }

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

    private var voiceDescription: String {
        switch configuration.provider {
        case .openAI: "Native live voice uses gpt-live-1."
        case .glm: "GLM native realtime voice uses its own voice model. If realtime access is unavailable, voice uses on-device recognition and system reading."
        case .gemini: "Gemini native live voice uses gemini-3.8-live. If realtime access is unavailable, voice uses on-device recognition and system reading."
        case .deepSeek, .custom: "Turn-based voice uses on-device recognition and system reading."
        }
    }

    private var consoleURL: URL? {
        switch configuration.provider {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")
        case .deepSeek: URL(string: "https://platform.deepseek.com/")
        case .glm: URL(string: "https://open.bigmodel.cn/")
        case .gemini: URL(string: "https://aistudio.google.com/api-keys")
        case .custom: nil
        }
    }

    private func failureMessage(_ failure: ProviderFailure) -> String {
        let name = configuration.provider.displayName
        let detail: String = switch failure.kind {
        case .authentication: "Your \(name) key wasn’t accepted. Check or replace it here."
        case .modelAccess: "This key may not have access to the selected \(name) model. Check its console."
        case .creditExhausted: configuration.provider == .gemini && failure.status == 402
            ? "Gemini returned HTTP 402: prepaid credits are unavailable. Check this key’s project and billing balance in Google AI Studio before starting again."
            : "\(name) credits are used up. Check its console before starting again."
        case .spendLimit, .usageLimit, .quota: "\(name) billing or usage limits need attention. Check its console."
        case .rateLimit: "\(name) is limiting requests. Wait briefly and check its console if this continues."
        case .unavailable: "\(name) is temporarily unavailable. Please try again shortly."
        case .invalidRequest: "\(name) could not accept this request. Check the model and endpoint."
        case .unknown: "\(name) could not complete this request. Please try again later."
        }
        return failure.reference.map { detail + "\n\nReference: " + $0 } ?? detail
    }

    private func selectProvider(_ provider: ModelProvider) {
        guard !coordinator.isRunning, provider != configuration.provider else { return }
        drafts[configuration.provider] = configuration
        configuration = drafts[provider] ?? (isPreview ? ProviderConfiguration(provider: provider) : ModelSettings.configuration(for: provider))
        key = ""
        message = nil
        refreshSavedStatus()
    }

    private func refreshSavedStatus() {
        guard let value = try? configuration.validated() else { hasSavedKey = false; return }
        if isPreview {
            let service = (try? value.credentialService()) ?? ""
            let legacyKey = ProcessInfo.processInfo.arguments.contains("--preview-key") && value.provider == .openAI &&
                !previewRemovedServices.contains(service)
            hasSavedKey = legacyKey || previewSavedServices.contains(service)
        } else {
            hasSavedKey = CredentialStore.hasKey(configuration: value)
        }
    }

    private func save() {
        guard !coordinator.isRunning else { message = "End this conversation before changing model settings."; return }
        defer { key = "" }
        do {
            let value = try configuration.validated()
            let replacement = key.isEmpty ? nil : try ProviderConfiguration.validatedCredential(key)
            if let replacement {
                if isPreview {
                    let service = try value.credentialService()
                    previewSavedServices.insert(service)
                    previewRemovedServices.remove(service)
                } else {
                    try CredentialStore.save(replacement, configuration: value)
                }
            }
            try coordinator.configureModel(value)
            configuration = value
            drafts[value.provider] = value
            refreshSavedStatus()
            message = replacement == nil ? "Model settings saved." : "Key saved on this iPhone. It will be checked when you start a conversation."
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeKey() {
        guard !coordinator.isRunning else { return }
        do {
            let value = try configuration.validated()
            if isPreview {
                let service = try value.credentialService()
                previewSavedServices.remove(service)
                previewRemovedServices.insert(service)
            } else {
                try CredentialStore.delete(configuration: value)
            }
            key = ""
            coordinator.clearPersonalKeyFailure()
            refreshSavedStatus()
            message = "Key removed. Add a key before talking with \(value.provider.displayName)."
        } catch { message = error.localizedDescription }
    }
}
