import SwiftUI
import AuthenticationServices
import TideEnglishCore

/// Account contains identity and TideEnglish usage only. Access and keys live in Settings → Advanced.
struct ManagedAccountView: View {
    let coordinator: ConversationCoordinator
    let store: ManagedAccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false
    @State private var confirmDeletion = false
    @State private var confirmGoogleConnection = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 16) {
                    TideEnglishOrb(active: false).frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.session == nil ? "Welcome to Tide English" : "Your account")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                        if let email = store.profile?.email {
                            Text(email).font(.subheadline).textSelection(.enabled)
                                .accessibilityIdentifier("managed-account-email")
                        }
                        if let provider = store.session?.provider {
                            Text(provider == .apple ? "Signed in with Apple" : "Signed in with Google")
                                .font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Your conversations and learning history stay on this iPhone.")
                    .font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                if HostedCloseRecovery.shared.needsSignIn {
                    Text("Sign in to the account used for your last conversation so Tide English can finish updating its minutes.")
                        .font(.callout).foregroundStyle(TideEnglishColor.secondary)
                        .accessibilityIdentifier("conversation-settlement-sign-in")
                }
                if store.configuration == nil && store.session == nil {
                    Text("Account sign-in isn’t available in this build. You can continue as a guest.")
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22))
                        .accessibilityIdentifier("managedAccountUnavailable")
                } else if store.session != nil {
                    if coordinator.conversationProvider == .hosted {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tide English minutes").font(.headline)
                            if let balance = store.hostedBalance {
                                Text(balance.displayText)
                                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                                    .accessibilityIdentifier("managed-account-minutes")
                                Text(balance.paidReserved && !balance.canStart ? "Some minutes are in use" :
                                     balance.hasPaidRemainder ? "estimated conversation time remaining" : "conversation time remaining")
                                    .font(.subheadline)
                            } else {
                                Text(store.isBusy ? "Checking your minutes…" : "Couldn’t check your minutes. Pull down to retry.")
                                    .font(.subheadline)
                            }
                            Text("Updates after each conversation.").font(.footnote)
                                .foregroundStyle(TideEnglishColor.secondary)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
                    }
                    if AppleMinutePurchases.shared.enabled {
                        if coordinator.conversationProvider == .hosted {
                            NavigationLink { AddMinutesView(account: store) } label: {
                                Label("Add minutes", systemImage: "plus.circle").frame(minHeight: 44)
                            }.accessibilityIdentifier("account-add-minutes")
                                .disabled(store.isBusy || coordinator.isRunning)
                        }
                        NavigationLink { ApplePurchaseHistoryView(account: store) } label: {
                            Label("Purchase history", systemImage: "clock.arrow.circlepath").frame(minHeight: 44)
                        }.accessibilityIdentifier("account-purchase-history")
                    }
                    if store.profile?.providers.contains(.apple) == true && store.profile?.providers.contains(.google) == false {
                        Button("Connect Google for Android access") { confirmGoogleConnection = true }
                            .frame(minHeight: 44).disabled(store.isBusy || coordinator.isRunning)
                            .accessibilityIdentifier("account-connect-google")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Sign out on all devices") { confirmSignOut = true }
                            .foregroundStyle(TideEnglishColor.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("managed-account-sign-out")
                        Button("Delete account…", role: .destructive) { confirmDeletion = true }
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .controlSize(.large)
                    .padding(.top, 16)
                    .disabled(store.isBusy || coordinator.isRunning)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Sign in to keep eligible Tide English minutes with your account.")
                            .foregroundStyle(TideEnglishColor.secondary)
                        if store.configuration?.providers.contains(.google) == true {
                            Button { store.signIn(.google) } label: {
                                Image("ManagedGoogleSignIn").resizable().scaledToFit().frame(height: 48)
                            }.buttonStyle(.plain).accessibilityLabel("Sign in with Google")
                                .accessibilityIdentifier("managed-google-sign-in")
                        }
                        if store.configuration?.providers.contains(.apple) == true {
                            ManagedAppleSignInButton { store.signIn(.apple) }
                                .frame(width: 206, height: 48)
                                .accessibilityIdentifier("managed-apple-sign-in")
                        }
                        Text("By signing in, you agree to the [Terms of use](https://tide-english.example/terms/) and acknowledge the [Privacy policy](https://tide-english.example/privacy/).")
                            .font(.footnote).tint(TideEnglishColor.ink)
                            .accessibilityIdentifier("managed-sign-in-agreement")
                        Button("Continue as guest") { dismiss() }
                            .font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                            .frame(minHeight: 44).padding(.top, 6)
                        if store.hasGuestAccount {
                            Button("Delete guest account…", role: .destructive) { confirmDeletion = true }
                                .foregroundStyle(.red).frame(minHeight: 44)
                                .accessibilityIdentifier("managed-guest-delete")
                                .disabled(coordinator.isRunning)
                        }
                    }.disabled(store.isBusy)
                }
                if store.isBusy { ProgressView("Updating account") }
                if let message = store.message {
                    Text(message).font(.callout).foregroundStyle(TideEnglishColor.secondary)
                        .accessibilityIdentifier("managedAccountMessage")
                }
            }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink)
        .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refreshAndWait() }
        .task { store.refresh() }
        .onChange(of: AppleMinutePurchases.shared.balanceRevision) { _, _ in store.refresh() }
        .onChange(of: HostedCloseRecovery.shared.revision) { _, _ in store.refresh() }
        .onDisappear { store.cancelSignIn() }
        .confirmationDialog("Connect Google to this Tide English account?", isPresented: $confirmGoogleConnection, titleVisibility: .visible) {
            Button("Verify Apple and connect Google") { store.connectGoogle() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Verify your Apple account, then choose Google. You can use that Google sign-in to access these Tide English minutes on Android. Your learning history stays on this iPhone.")
        }
        .confirmationDialog("Sign out on all devices?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out") { store.signOut() }
            Button("Stay signed in", role: .cancel) {}
        } message: { Text("Your learning history stays on this iPhone. If Tide English can’t reach the server, sign-out on other devices may take up to 24 hours.") }
        .confirmationDialog("Delete your Tide English account?", isPresented: $confirmDeletion, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                if store.session == nil { store.deleteGuestAccount() } else { store.deleteAccount() }
            }
            Button("Keep account", role: .cancel) {}
        } message: {
            Text("This permanently removes your account and sign-in details. You lose access to unused free and purchased minutes. Required payment and refund records are retained without your sign-in details. Learning history stays on this iPhone.")
        }
    }
}

private struct ManagedAppleSignInButton: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .whiteOutline)
        button.cornerRadius = 24
        button.addTarget(context.coordinator, action: #selector(Coordinator.signIn), for: .touchUpInside)
        return button
    }
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action; uiView.isEnabled = context.environment.isEnabled
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func signIn() { action() }
    }
}

struct EmailAccountView: View {
    let coordinator: ConversationCoordinator
    #if DEBUG && targetEnvironment(simulator)
    private let store = EmailAccountStore.accountScreenStore()
    #else
    private let store = EmailAccountStore.shared
    #endif
    @State private var confirmSignOut = false
    @State private var confirmDeletion = false
    @FocusState private var focused: Field?
    private enum Field { case email, code }
    var body: some View {
        @Bindable var account = store
        ScrollView {
            VStack(alignment: .leading, spacing:24) {
                Text(UI(store.logoutPending ? "Sign-out needs attention" : store.session == nil ? "Optional email account" : "Signed in"))
                    .font(.system(.title2, design:.serif, weight:.medium))
                Text(UI("You can keep learning without signing in. Your learning records and model keys stay on this iPhone."))
                    .font(.subheadline).foregroundStyle(TideEnglishColor.secondary)
                if store.logoutPending {
                    Button(UI("Retry sign out")) { store.retrySignOut() }
                        .accessibilityIdentifier("email-account-retry-sign-out")
                } else if let session = store.session {
                    Text(session.email).font(.headline).textSelection(.enabled)
                        .accessibilityIdentifier("email-account-profile")
                        .accessibilityValue(UI(session.accessIsUsable(scope:store.configuration?.storageScope ?? "") ? "Signed in" : "Updating account…"))
                    if !store.deleting {
                        Button(UI("Sign out")) { confirmSignOut = true }
                            .accessibilityIdentifier("email-account-sign-out")
                        Button(UI("Delete account"), role:.destructive) { confirmDeletion = true }
                            .accessibilityIdentifier("email-account-delete")
                    }
                } else {
                    TextField(UI("Email address"), text:$account.email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused, equals:.email).submitLabel(.done).onSubmit { focused = nil }
                        .accessibilityIdentifier("email-account-address")
                        .disabled(store.challenge != nil)
                        .padding(14).background(TideEnglishColor.surface, in:RoundedRectangle(cornerRadius:12))
                }
                if !store.logoutPending, store.session == nil, store.challenge != nil {
                    Button(UI("Change email address")) { store.changeEmail() }
                        .accessibilityIdentifier("email-account-change-address")
                }
                if !store.logoutPending && (store.session == nil || store.deleting) {
                    TimelineView(.periodic(from:.now, by:1)) { timeline in
                        let seconds = max(0, Int(ceil(store.retryAt.timeIntervalSince(timeline.date))))
                        Button(UI(seconds > 0 ? "Resend in \(seconds) seconds" : "Send code")) {
                            focused = nil; store.sendCode()
                        }.accessibilityIdentifier("email-account-send")
                            .disabled(seconds > 0 || store.isBusy || coordinator.isRunning)
                    }
                    if store.challenge != nil {
                        TextField(UI("Six-digit code"), text:$account.code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .focused($focused, equals:.code)
                            .accessibilityIdentifier("email-account-code")
                            .padding(14).background(TideEnglishColor.surface, in:RoundedRectangle(cornerRadius:12))
                            .onChange(of:store.code) { _, value in
                                let sanitized = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                                if sanitized != value { store.code = sanitized }
                                if sanitized.count == 6 { focused = nil }
                            }
                        Button(UI(store.deleting ? "Delete account" : "Continue"), role:store.deleting ? .destructive : nil) {
                            focused = nil
                            if store.deleting { store.deleteAccount() } else { store.verify() }
                        }.accessibilityIdentifier(store.deleting ? "email-account-confirm-delete" : "email-account-continue")
                            .buttonStyle(.borderedProminent).tint(store.deleting ? .red : TideEnglishColor.accent)
                            .disabled(!EmailAccountValidation.code(store.code))
                    }
                }
                if coordinator.isRunning {
                    Text(UI("End this conversation before changing your account.")).font(.footnote).foregroundStyle(TideEnglishColor.secondary)
                }
                #if DEBUG && targetEnvironment(simulator)
                if EmailAccountConfiguration.previewEnabled, let result = store.verificationResult {
                    Text(result).accessibilityIdentifier("email-account-verification")
                }
                #endif
                if store.isBusy { ProgressView(UI("Updating account…")) }
                if let message = store.message {
                    Text(UI(message)).font(.callout).foregroundStyle(TideEnglishColor.secondary)
                        .accessibilityIdentifier("email-account-message")
                }
            }.buttonStyle(.bordered).controlSize(.large)
                .disabled(store.isBusy || coordinator.isRunning)
                .padding(24).frame(maxWidth:520).frame(maxWidth:.infinity, alignment:.leading)
        }
        .background(TideEnglishColor.cream).foregroundStyle(TideEnglishColor.ink)
        .navigationTitle(UI("Account")).navigationBarTitleDisplayMode(.inline)
        .task {
            #if DEBUG && targetEnvironment(simulator)
            if await store.runLogoutVerificationIfRequested() { return }
            if await store.runRenewalVerificationIfRequested() { return }
            #endif
            store.open()
        }
        .onDisappear { store.cancel() }
        .alert(UI("Sign out?"), isPresented:$confirmSignOut) {
            Button(UI("Sign out"), role:.destructive) { store.signOut() }
            Button(UI("Cancel"), role:.cancel) {}
        } message: { Text(UI("Your learning records and model keys stay on this iPhone.")) }
        .alert(UI("Delete account?"), isPresented:$confirmDeletion) {
            Button(UI("Send deletion code"), role:.destructive) { store.beginDeletion() }
            Button(UI("Cancel"), role:.cancel) {}
        } message: { Text(UI("This removes your account identity and sessions. Your learning records and model keys remain on this iPhone. Confirm with a new email code.")) }
    }
}
