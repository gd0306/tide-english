import SwiftUI

@main struct TideEnglishApp: App {
    @State private var store: LearningStore?
    @State private var startupError: String?
    #if DEBUG
    @State private var echoStatus = "Checking echo cancellation"
    #endif
    init() {
        do { _store = State(initialValue: try LearningStore(inMemory: ProcessInfo.processInfo.arguments.contains("--preview") || AudioVerification.requested)) }
        catch { _startupError = State(initialValue: "Tide English couldn’t open its learning record. Your existing data has not been replaced.") }
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if AudioVerification.echoRequested {
                Text(echoStatus).accessibilityIdentifier("echo-check-status")
                    .task {
                        echoStatus = ProcessInfo.processInfo.arguments.contains("--verify-input")
                            ? await AudioVerification.verifyInput() : await AudioVerification.verifyEcho()
                    }
            } else if AudioVerification.providerRequested {
                ContentUnavailableView(UI("Checking Gemini"), systemImage: "antenna.radiowaves.left.and.right", description: Text(UI("A short connection check is running. No microphone audio is captured.")))
                    .task { await AudioVerification.verifyProvider(configuration: ModelSettings.configuration(for: .gemini)) }
            } else { content }
            #else
            content
            #endif
        }
    }
    @ViewBuilder private var content: some View {
            if let store { RootView(store: store).modifier(InterfaceAppearance()) }
            else {
                ContentUnavailableView(UI("Let’s try again"), systemImage: "externaldrive.badge.exclamationmark", description: Text(UI(startupError ?? "The learning record is unavailable.")))
                    .modifier(InterfaceAppearance())
            }
    }
}

/// Observe presentation below the coordinator-construction boundary. SwiftUI can
/// reevaluate this modifier without calling RootView.init or replacing the
/// learning store's session-invalidation callback with a discarded coordinator.
private struct InterfaceAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content
            .preferredColorScheme(InterfacePreferences.shared.colorScheme)
            .environment(\.locale, InterfacePreferences.shared.locale)
    }
}
