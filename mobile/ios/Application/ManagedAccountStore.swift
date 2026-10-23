import Foundation
import Observation
import TideEnglishCore

@MainActor @Observable
final class ManagedAccountStore {
    let configuration: ManagedAccountConfiguration?
    private(set) var session: ManagedAccountSession?
    private(set) var profile: ManagedAccountProfile?
    private(set) var hostedBalanceMilliseconds: Int?
    private(set) var hostedBalance: HostedBalance?
    private(set) var isBusy = false
    var message: String?
    @ObservationIgnored private let client: ManagedAccountClient?
    @ObservationIgnored private let keychain: ManagedAccountKeychain?
    @ObservationIgnored private let identity = ManagedAccountIdentity()
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var deletingGuest = false
    @ObservationIgnored private var gate = ManagedAccountOperationGate()
    @ObservationIgnored private var balanceRevision: (account: UUID, revision: UInt64)?
    private let isPreview: Bool

    init(configuration: ManagedAccountConfiguration? = .load()) {
        #if DEBUG && targetEnvironment(simulator)
        isPreview = ProcessInfo.processInfo.arguments.contains("--preview")
        #else
        isPreview = false
        #endif
        self.configuration = configuration
        client = configuration.map(ManagedAccountClient.init)
        keychain = configuration.map { ManagedAccountKeychain(scope: $0.storageScope) }
        // Screenshot and UI-test fixtures never read a real account or create a server session.
        if isPreview {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--preview-member") || arguments.contains("--preview-apple") ||
                arguments.contains("--preview-paid-member") || arguments.contains("--preview-paid-only") ||
                arguments.contains("--preview-paid-reserved") {
                let apple = arguments.contains("--preview-apple")
                let id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
                let exchangeData = Data("{\"accountID\":\"\(id)\",\"accessToken\":\"\(String(repeating: "x", count: 43))\",\"expiresInSeconds\":86400}".utf8)
                if let exchange = try? JSONDecoder().decode(ManagedAuthExchange.self, from: exchangeData) {
                    session = try? ManagedAccountSession(exchange: exchange, provider: apple ? .apple : .google,
                                                         scope: configuration?.storageScope ?? "preview")
                }
                let address = apple ? "a.very.long.private.relay.address.for.layout@privaterelay.appleid.com" : "preview@example.test"
                let profileData = Data("{\"accountID\":\"\(id)\",\"email\":\"\(address)\",\"providers\":[\"\(apple ? "apple" : "google")\"],\"createdAt\":\"2026-09-25T12:00:00Z\"}".utf8)
                profile = try? JSONDecoder().decode(ManagedAccountProfile.self, from: profileData)
                if arguments.contains("--preview-paid-member") || arguments.contains("--preview-paid-only") ||
                    arguments.contains("--preview-paid-reserved") {
                    hostedBalance = HostedBalance.preview(paidOnly: !arguments.contains("--preview-paid-member"),
                                                          reserved: arguments.contains("--preview-paid-reserved"))
                    hostedBalanceMilliseconds = hostedBalance?.availableMilliseconds
                } else {
                    hostedBalanceMilliseconds = 534_000
                    hostedBalance = try? HostedBalance(["unit": "milliseconds", "billingBasis": "connected-conversation-time",
                                                         "balanceMilliseconds": 534_000, "reservedMilliseconds": 0,
                                                         "availableMilliseconds": 534_000])
                }
            }
        } else {
            do { session = try keychain?.load() }
            catch { message = Self.message(for: error) }
        }
    }
    func signIn(_ provider: ManagedIdentityProvider) {
        guard !isPreview else { message = "Sign-in isn’t available in this preview."; return }
        guard !isBusy, session == nil, let client, let configuration, let keychain,
              configuration.providers.contains(provider) else { return }
        run { [self] token in
            // Claim this installation's trial before account creation so a new member can
            // keep its unused minutes. Existing members remain subject to the server's limit.
            if HostedClient.shared != nil { _ = try? await GuestAccess.shared.owner(member: nil) }
            let challenge = try await client.challenge()
            let expiresAt = Date.now.addingTimeInterval(TimeInterval(challenge.expiresInSeconds))
            let credential = try await (provider == .google
                ? identity.google(configuration: configuration, nonce: challenge.nonce, http: client.http)
                : identity.apple(nonce: challenge.nonce))
            guard gate.accepts(token), Date.now < expiresAt else { throw ManagedAccountError.cancelled }
            let exchanged = try await client.exchange(provider: provider, token: credential.idToken, challenge: challenge)
            let newSession = try ManagedAccountSession(exchange: exchanged, provider: provider, scope: configuration.storageScope)
            guard gate.accepts(token), !Task.isCancelled else {
                try? await client.signOut(session: newSession); return
            }
            do { try keychain.save(newSession) }
            catch { try? await client.signOut(session: newSession); throw error }
            session = newSession
            Task { await HostedCloseRecovery.shared.resume() }
            let result = try await client.profile(session: newSession)
            guard gate.accepts(token) else { return }
            profile = result
            if let hosted = HostedClient.shared {
                let owner = HostedOwner(accountID: newSession.accountID, accessToken: newSession.accessToken, expiresAt: newSession.expiresAt)
                let balance = try await refreshHostedBalance(hosted, owner: owner)
                guard gate.accepts(token), session?.accountID == newSession.accountID else { return }
                acceptBalance(balance, account: newSession.accountID)
            }
        }
    }
    func refresh() {
        guard !isPreview else { return }
        guard !isBusy, let client, let session else { return }
        hostedBalanceMilliseconds = nil
        hostedBalance = nil
        run { [self] token in
            let result = try await client.profile(session: session)
            guard gate.accepts(token) else { return }
            profile = result
            if let hosted = HostedClient.shared {
                let owner = HostedOwner(accountID: session.accountID, accessToken: session.accessToken, expiresAt: session.expiresAt)
                let balance = try await refreshHostedBalance(hosted, owner: owner)
                guard gate.accepts(token), self.session?.accountID == session.accountID else { return }
                acceptBalance(balance, account: session.accountID)
            }
        }
    }
    private func refreshHostedBalance(_ hosted: HostedClient, owner: HostedOwner) async throws -> HostedBalance {
        do { try await GuestAccess.shared.linkIfNeeded(to: owner) }
        catch {
            // GuestAccess keeps its pending link until the server confirms transfer.
            // A delayed guest transfer must not hide this member's existing credit.
            if error is CancellationError || error as? ManagedAccountError == .cancelled ||
                (error as? URLError)?.code == .cancelled { throw ManagedAccountError.cancelled }
        }
        try Task.checkCancellation()
        return try await hosted.balance(owner)
    }
    func connectGoogle() {
        guard !isPreview, !isBusy, let session, let client, let configuration,
              configuration.providers.contains(.google), profile?.providers.contains(.apple) == true else { return }
        run { [self] token in
            let appleChallenge = try await client.challenge()
            let apple = try await identity.apple(nonce: appleChallenge.nonce)
            guard gate.accepts(token), self.session?.accountID == session.accountID else { throw ManagedAccountError.cancelled }
            let googleChallenge = try await client.challenge()
            let google = try await identity.google(configuration: configuration, nonce: googleChallenge.nonce, http: client.http)
            guard gate.accepts(token), self.session?.accountID == session.accountID else { throw ManagedAccountError.cancelled }
            try await client.connectGoogle(session: session, apple: apple.idToken, appleChallenge: appleChallenge,
                                           google: google.idToken, googleChallenge: googleChallenge)
            let refreshed = try await client.profile(session: session)
            guard gate.accepts(token), self.session?.accountID == session.accountID else { return }
            profile = refreshed; message = "Google is connected. Use it to sign in to Tide English on Android."
        }
    }
    func refreshAndWait() async {
        refresh()
        await operation?.value
    }
    private func acceptBalance(_ balance: HostedBalance?, account: UUID) {
        if let previous = balanceRevision, previous.account == account {
            guard let revision = balance?.presentation?.revisionNumber, revision >= previous.revision else {
                hostedBalance = nil; hostedBalanceMilliseconds = nil; return
            }
        }
        if let revision = balance?.presentation?.revisionNumber { balanceRevision = (account, revision) }
        hostedBalance = balance; hostedBalanceMilliseconds = balance?.availableMilliseconds
    }
    func signOut() {
        guard !isPreview else { message = "Preview account actions don’t change a real account."; return }
        guard !isBusy, let client, let session, let keychain else { return }
        run { [self] token in
            var remoteFailed = false
            do { try await client.signOut(session: session) }
            catch let error as ManagedAccountError where error == .server("sign_in_required") { /* Already expired or revoked. */ }
            catch { remoteFailed = true }
            guard gate.accepts(token) else { return }
            try keychain.remove()
            self.session = nil; profile = nil; hostedBalanceMilliseconds = nil; hostedBalance = nil
            if remoteFailed { message = "Signed out on this iPhone. We couldn’t reach Tide English to revoke other sessions; they expire within 24 hours." }
        }
    }
    func deleteAccount() {
        guard !isPreview else { message = "Preview account actions don’t change a real account."; return }
        guard !isBusy, let client, let session, let keychain else { return }
        run { [self] token in
            var code: String?
            // A Google session may belong to an account that also linked Apple.
            // Refresh providers before deletion; the server is the source of truth.
            let currentProfile = try await client.profile(session: session)
            if currentProfile.providers.contains(.apple) {
                // A fresh code lets the server verify this Apple identity and revoke its authorization.
                code = try await identity.apple(nonce: ManagedAccountIdentity.random()).authorizationCode
            }
            guard gate.accepts(token) else { return }
            try await client.delete(session: session, appleCode: code)
            guard gate.accepts(token) else { return }
            self.session = nil; profile = nil; hostedBalanceMilliseconds = nil; hostedBalance = nil
            do { try keychain.remove() }
            catch {
                message = "Account deleted. Tide English couldn’t clear its local secure sign-in record. Unlock this iPhone and reopen Account to clear it."
                return
            }
            message = "Account deleted. Your learning history remains on this iPhone."
        }
    }
    var hasGuestAccount: Bool { GuestAccess.shared.hasUnlinkedAccount }
    func deleteGuestAccount() {
        guard !isPreview, !isBusy, session == nil, let client else { return }
        deletingGuest = true
        run { [self] _ in
            defer { deletingGuest = false }
            try await GuestAccess.shared.deleteAccount(using: client)
            message = "Guest account deleted. Your learning history remains on this iPhone."
        }
    }
    /// Close pending sign-in on dismissal. Account mutations finish so their result is not ambiguous.
    func cancelSignIn() {
        guard session == nil, !deletingGuest else { return }
        gate.cancel(); operation?.cancel(); identity.cancel(); operation = nil; isBusy = false
    }
    private func run(_ body: @escaping @MainActor (UInt64) async throws -> Void) {
        let token = gate.begin(); isBusy = true; message = nil
        operation = Task { [self] in
            defer { if gate.accepts(token) { isBusy = false; operation = nil } }
            do { try await body(token) }
            catch {
                guard gate.accepts(token) else { return }
                if error as? ManagedAccountError == .server("sign_in_required") {
                    session = nil; profile = nil
                    do { try keychain?.remove() } catch { message = Self.message(for: error); return }
                }
                if error as? ManagedAccountError != .cancelled, !(error is CancellationError) {
                    message = Self.message(for: error)
                }
            }
        }
    }
    private static func message(for error: Error) -> String {
        if let hosted = error as? HostedError { return hosted.localizedDescription }
        return switch error as? ManagedAccountError {
        case .secureStorage: "Tide English couldn’t update this iPhone’s secure account storage. Unlock the iPhone and try again."
        case .server("account_usage_pending"), .server("unresolved_billing"):
            "End your conversation and wait for its minutes to update, then try deleting your account again."
        case .server("sign_in_required"): "Please sign in again. Your learning history is still on this iPhone."
        case .server("rate_limit"): "Please try again later."
        case .server("same_account_required"): "Use the Apple account already connected to this Tide English account."
        case .server("identity_link_conflict"): "That Google account is already connected to another Tide English account. Contact 1215742191@qq.com for help. Your minutes haven’t moved."
        case .server("apple_sign_in_not_ready"), .server("apple_revocation_not_configured"):
            "Sign in with Apple is temporarily unavailable. Please try again later."
        case .server("identity_provider_not_configured"), .unavailable:
            "This sign-in option is unavailable. Please try again later."
        case .purchaseVerificationUnavailable:
            "Tide English couldn’t verify Apple purchases right now. Please try again later."
        case .invalidCallback, .invalidResponse, .server("invalid_challenge"):
            "Sign-in couldn’t be verified. Please start again."
        default: "Tide English couldn’t complete that request. Check your connection and try again."
        }
    }
}

@MainActor @Observable
final class EmailAccountStore {
    static let shared = EmailAccountStore()
    private(set) var verificationResult: String?
    private(set) var logoutPending = false
    let configuration: EmailAccountConfiguration?
    private(set) var session: EmailAccountSession?
    private(set) var isBusy = false
    private(set) var message: String?
    private(set) var challenge: EmailAccountChallenge?
    private(set) var retryAt = Date.distantPast
    private(set) var challengeExpiresAt = Date.distantPast
    private(set) var deleting = false
    var email = ""
    var code = ""
    @ObservationIgnored private let client: (any EmailAccountServing)?
    @ObservationIgnored private let keychain: (any EmailAccountCredentialStorage)?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: (id: UUID, owner: UInt64, task: Task<EmailAccountSession, Error>)?
    @ObservationIgnored private var credentialGeneration: UInt64 = 0
    @ObservationIgnored private var generation: UInt64 = 0
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var logoutCredential: EmailAccountSession?
    private static let incompleteLogout = "Sign-out is incomplete. Unlock this iPhone and retry before closing the app."
    init(configuration: EmailAccountConfiguration? = .load()) {
        self.configuration = configuration
        #if DEBUG && targetEnvironment(simulator)
        if EmailAccountConfiguration.previewEnabled {
            let args = ProcessInfo.processInfo.arguments
            client = PreviewEmailAccountClient(arguments:args)
            keychain = args.contains("--verify-email-account-keychain") ? configuration.map { EmailAccountKeychain(scope:$0.storageScope, isolatedSimulatorTest:true) } : nil
            if args.contains("--verify-email-account-keychain-reset") {
                try? keychain?.clear(); try? keychain?.setLogoutPending(false)
            }
        } else {
            // Ordinary previews cannot access the normal account namespace.
            let preview = ProcessInfo.processInfo.arguments.contains("--preview")
            client = preview ? nil : configuration.map(EmailAccountClient.init)
            keychain = preview ? nil : configuration.map { EmailAccountKeychain(scope:$0.storageScope) }
        }
        #else
        client = configuration.map(EmailAccountClient.init)
        keychain = configuration.map { EmailAccountKeychain(scope:$0.storageScope) }
        #endif
    }
    #if DEBUG && targetEnvironment(simulator)
    private init(configuration: EmailAccountConfiguration, probeClient: any EmailAccountServing,
                 probeCredentials: any EmailAccountCredentialStorage, initial: EmailAccountSession?) {
        self.configuration = configuration; client = probeClient; keychain = probeCredentials
        session = initial; email = initial?.email ?? ""; loaded = initial != nil
    }
    #endif
    func open() {
        if !loaded, keychain?.logoutPending == true {
            // Recover only a revocation handle, never a restored signed-in identity.
            loaded = true; logoutPending = true
            logoutCredential = try? keychain?.load()
            message = Self.incompleteLogout
        }
        if logoutPending { message = Self.incompleteLogout; return }
        if !loaded {
            loaded = true
            do {
                session = try keychain?.load()
                #if DEBUG && targetEnvironment(simulator)
                if EmailAccountConfiguration.previewEnabled, keychain == nil,
                   ProcessInfo.processInfo.arguments.contains("--preview-email-renewal"), let configuration {
                    let fixture: [String:Any] = ["accountID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "email":"preview@example.test", "accessToken":String(repeating:"a",count:43), "refreshToken":String(repeating:"b",count:43), "expiresInSeconds":900, "refreshExpiresInSeconds":2592000]
                    let exchange = try JSONDecoder().decode(EmailAccountExchange.self, from:JSONSerialization.data(withJSONObject:fixture))
                    session = try EmailAccountSession(exchange:exchange, scope:configuration.storageScope, now:.now.addingTimeInterval(-901))
                }
                #endif
                email = session?.email ?? ""
            }
            catch { loaded = false; message = Self.safe(error).message }
        }
        guard session != nil, !isBusy else { return }
        run { [self] token in
            #if DEBUG && targetEnvironment(simulator)
            if EmailAccountConfiguration.previewEnabled,
               ProcessInfo.processInfo.arguments.contains("--verify-email-account-single-flight"),
               let preview = client as? PreviewEmailAccountClient {
                async let first = authenticatedSession(generation:token)
                async let second = authenticatedSession(generation:token)
                let pair = try await (first, second)
                let count = await preview.refreshCount
                guard accepts(token) else { return }
                verificationResult = pair.0 == pair.1 && count == 1 ? "passed" : "failed"
            }
            #endif
            let current = try await authenticatedSession(generation:token)
            guard let client else { throw EmailAccountError.unavailable }
            let profile = try await client.profile(session:current)
            try profile.validate(session:current)
            guard accepts(token) else { return }
        }
    }
    private func accepts(_ token: UInt64) -> Bool { generation == token && !Task.isCancelled }
    func cancel() {
        generation &+= 1; operation?.cancel(); operation = nil
        // Detach only the view waiter. The credential owns its rotation until settlement.
        isBusy = false
    }
    private func run(_ action: @escaping @MainActor (UInt64) async throws -> Void) {
        guard !isBusy else { return }
        generation &+= 1; let token = generation; isBusy = true; message = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token { isBusy = false; operation = nil } }
            do { try await action(token) }
            catch {
                guard accepts(token) else { return }
                let error = Self.safe(error)
                if error == .invalidSession {
                    retireCredentials()
                    do { try keychain?.clear() } catch { message = EmailAccountError.secureStorage.message; return }
                }
                message = error.message
            }
        }
    }
    private static func safe(_ error: Error) -> EmailAccountError { error as? EmailAccountError ?? .unavailable }
    func sendCode() {
        guard !logoutPending, !isBusy, Date.now >= retryAt, let client else { return }
        let address: String
        do { address = try EmailAccountValidation.email(session?.email ?? email) }
        catch { message = EmailAccountError.invalidEmail.message; return }
        run { [self] token in
            let result = try await client.challenge(email:address)
            try result.validate()
            guard accepts(token) else { return }
            email = address; challenge = result; code = ""
            retryAt = .now.addingTimeInterval(TimeInterval(result.retryAfterSeconds))
            challengeExpiresAt = .now.addingTimeInterval(TimeInterval(result.expiresInSeconds))
            message = deleting ? "Enter the new email code to delete your account." : "Check your email for a six-digit code."
        }
    }
    func changeEmail() {
        guard !isBusy, session == nil else { return }
        challenge = nil; code = ""; message = nil
    }
    func verify() {
        guard !logoutPending, session == nil, let challenge, let client, let configuration else { return }
        guard challengeExpiresAt > .now else { message = "Code expired. Request a new code."; return }
        guard EmailAccountValidation.code(code) else { message = EmailAccountError.invalidCode.message; return }
        let submitted = code; let mailbox = email
        run { [self] token in
            let exchange = try await client.verify(challenge:challenge.challengeID, code:submitted)
            let result = try EmailAccountSession(exchange:exchange, scope:configuration.storageScope)
            guard result.email == mailbox else { try? await client.signOut(token:result.refreshToken); throw EmailAccountError.invalidResponse }
            guard accepts(token) else { try? await client.signOut(token:result.refreshToken); return }
            do { try keychain?.save(result) }
            catch { try? await client.signOut(token:result.refreshToken); throw error }
            credentialGeneration &+= 1
            session = result; self.challenge = nil; code = ""; message = nil
        }
    }
    /// Renewal belongs to the credential, independently of any view operation generation.
    private func authenticatedSession(generation token: UInt64) async throws -> EmailAccountSession {
        guard let current = session, let client, let configuration,
              current.canRefresh(scope:configuration.storageScope) else { throw EmailAccountError.invalidSession }
        if current.accessIsUsable(scope:configuration.storageScope), current.expiresAt.timeIntervalSinceNow > 30 { return current }
        let owner = credentialGeneration
        if let flight = refreshTask, flight.owner == owner { return try await flight.task.value }
        let id = UUID()
        let task = Task { @MainActor [self] in
            defer { if refreshTask?.id == id { refreshTask = nil } }
            var replacement: EmailAccountExchange?
            do {
                try keychain?.prepareForRenewal()
                let exchange = try await client.refresh(token:current.refreshToken)
                replacement = exchange
                let renewed = try EmailAccountSession(exchange:exchange, scope:configuration.storageScope, previous:current)
                guard owns(owner, current) else { throw EmailAccountError.cancelled }
                try keychain?.save(renewed)
                session = renewed
                return renewed
            } catch {
                let stillOwned = owns(owner, current)
                var result = EmailAccountError.cancelled
                if stillOwned {
                    // The server may have consumed the old token. Never replay it, including
                    // after transport, DTO or persistence failures, or from another screen.
                    retireCredentials()
                    result = .renewalUncertain
                    do { try keychain?.clear() } catch { result = .secureStorage }
                    message = result.message
                }
                // The backend recognizes old rotated tokens for family sign-out. A late
                // success after logout/deletion is revoked without publishing credentials.
                try? await client.signOut(token:replacement?.refreshToken ?? current.refreshToken)
                throw result
            }
        }
        refreshTask = (id, owner, task)
        return try await task.value
    }
    private func owns(_ owner: UInt64, _ credential: EmailAccountSession) -> Bool {
        credentialGeneration == owner && session == credential
    }
    private func retireCredentials() {
        credentialGeneration &+= 1
        // An old task may still settle, but this token can never be issued to another flight.
        refreshTask = nil
        session = nil; challenge = nil; code = ""; deleting = false; retryAt = .distantPast
    }
    func signOut() {
        if logoutPending { retrySignOut(); return }
        guard let previous = session else { return }
        cancel()
        logoutCredential = previous
        retireCredentials() // Late renewal cannot publish, even if local cleanup fails.
        logoutPending = true
        retrySignOut()
    }
    func retrySignOut() {
        guard logoutPending, !isBusy else { return }
        // Persist intent synchronously before any asynchronous revocation. If storage is
        // unavailable, retain the handle and an honest retryable state in this process.
        try? keychain?.setLogoutPending(true)
        var canClear = true
        if logoutCredential == nil {
            do { logoutCredential = try keychain?.load() }
            catch { canClear = false }
        }
        var localCleared = false
        if canClear {
            do { try keychain?.clear(); localCleared = true } catch {}
        }
        let cleared = localCleared
        let credential = logoutCredential
        run { [self] token in
            var confirmed = false
            var disconnected = false
            // Local deletion failure must never bypass the revocation attempt.
            if let credential, let client {
                do { try await client.signOut(token:credential.refreshToken); confirmed = true }
                catch { disconnected = Self.safe(error) == .transport }
            }
            guard accepts(token), logoutPending else { return }
            guard cleared else { message = Self.incompleteLogout; return }
            do { try keychain?.setLogoutPending(false) }
            catch { message = Self.incompleteLogout; return }
            logoutPending = false; logoutCredential = nil
            message = confirmed ? "Signed out. Your learning records remain on this iPhone." :
                disconnected ? "Signed out on this iPhone. The server could not be reached; this session may remain active until it expires." :
                "Signed out on this iPhone. Server sign-out could not be confirmed; this session may remain active until it expires."
        }
        if !cleared { message = Self.incompleteLogout }
    }
    func beginDeletion() {
        guard session != nil, !isBusy else { return }
        deleting = true; challenge = nil; code = ""; sendCode()
    }
    func deleteAccount() {
        guard deleting, let challenge, let client else { return }
        guard challengeExpiresAt > .now, EmailAccountValidation.code(code) else { message = EmailAccountError.invalidCode.message; return }
        let submitted = code
        run { [self] token in
            let owner = credentialGeneration
            let current = try await authenticatedSession(generation:token)
            guard accepts(token), owns(owner, current) else { return }
            // Join any owned rotation before deletion, so it cannot complete after deletion
            // and the DELETE bearer is its valid replacement rather than the consumed token.
            try await client.delete(session:current, challenge:challenge.challengeID, code:submitted)
            guard owns(owner, current) else { return }
            retireCredentials()
            do { try keychain?.clear() } catch { throw EmailAccountError.secureStorage }
            message = "Account deleted. Your learning records remain on this iPhone."
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor private final class EmailAccountProbeCredentials: EmailAccountCredentialStorage {
    var value: EmailAccountSession?
    let failSave: Bool
    var failClear = false
    var clearFailuresRemaining = 0
    var failIntent = false
    var logoutPending = false
    func setLogoutPending(_ pending: Bool) throws {
        if failIntent { throw EmailAccountError.secureStorage }
        logoutPending = pending
    }
    init(_ value: EmailAccountSession, failSave: Bool) { self.value = value; self.failSave = failSave }
    func load() throws -> EmailAccountSession? { value }
    func save(_ session: EmailAccountSession) throws {
        if failSave { throw EmailAccountError.secureStorage }; value = session
    }
    func prepareForRenewal() throws {}
    func clear() throws {
        if failClear || clearFailuresRemaining > 0 {
            clearFailuresRemaining = max(0, clearFailuresRemaining - 1)
            throw EmailAccountError.secureStorage
        }
        value = nil
    }
}

extension EmailAccountStore {
    static func accountScreenStore() -> EmailAccountStore {
        guard EmailAccountConfiguration.previewEnabled,
              ProcessInfo.processInfo.arguments.contains("--verify-email-account-logout=screen") else { return .shared }
        return logoutScreenFixture
    }
    private static let logoutScreenFixture: EmailAccountStore = {
        let configuration = try! EmailAccountConfiguration(apiURL:"https://email-account.example.test")
        let initial = try! EmailAccountSession(exchange:EmailAccountRenewalProbe.exchange(), scope:configuration.storageScope)
        let credentials = EmailAccountProbeCredentials(initial, failSave:false)
        credentials.clearFailuresRemaining = 1
        return EmailAccountStore(configuration:configuration, probeClient:EmailAccountRenewalProbe(failure:""), probeCredentials:credentials, initial:initial)
    }()
    func runLogoutVerificationIfRequested() async -> Bool {
        guard EmailAccountConfiguration.previewEnabled,
              let flag = ProcessInfo.processInfo.arguments.first(where:{ $0.hasPrefix("--verify-email-account-logout=") }),
              let mode = flag.split(separator:"=").last, mode != "screen" else { return false }
        do { verificationResult = try await Self.logoutScenario(String(mode)) ? "passed" : "failed" }
        catch { verificationResult = "failed" }
        return true
    }
    private static func logoutScenario(_ mode: String) async throws -> Bool {
        let configuration = try EmailAccountConfiguration(apiURL:"https://email-account.example.test")
        let initial = try EmailAccountSession(exchange:EmailAccountRenewalProbe.exchange(), scope:configuration.storageScope)
        let probe = EmailAccountRenewalProbe(failure:"")
        if mode == "intent-prepare" || mode == "intent-after-relaunch" {
            guard ProcessInfo.processInfo.arguments.contains("--verify-email-account-keychain") else { return false }
            let isolated = EmailAccountKeychain(scope:configuration.storageScope, isolatedSimulatorTest:true)
            if mode == "intent-prepare" {
                try isolated.clear(); try isolated.save(initial); try isolated.setLogoutPending(true)
                return true
            }
            defer { try? isolated.clear(); try? isolated.setLogoutPending(false) }
            let relaunched = EmailAccountStore(configuration:configuration, probeClient:probe, probeCredentials:isolated, initial:nil)
            relaunched.open()
            guard relaunched.session == nil, relaunched.logoutPending else { return false }
            relaunched.retrySignOut()
            for _ in 0..<200 { if !relaunched.isBusy { break }; try await Task.sleep(for:.milliseconds(5)) }
            let removed = try isolated.load() == nil
            let revoked = !(await probe.revocations).isEmpty
            return !relaunched.logoutPending && !isolated.logoutPending && removed && revoked
        }
        let credentials = EmailAccountProbeCredentials(initial, failSave:false)
        credentials.failClear = true
        let offline = mode == "network"
        await probe.setLogoutFailure(offline)
        let store = EmailAccountStore(configuration:configuration, probeClient:probe, probeCredentials:credentials, initial:initial)
        store.signOut()
        for _ in 0..<200 { if !store.isBusy { break }; try await Task.sleep(for:.milliseconds(5)) }
        guard store.session == nil, store.logoutPending, credentials.value == initial,
              !(await probe.revocations).isEmpty else { return false }
        store.cancel(); store.open()
        guard store.logoutPending, store.session == nil else { return false }
        let relaunched = EmailAccountStore(configuration:configuration, probeClient:probe, probeCredentials:credentials, initial:nil)
        relaunched.open()
        guard relaunched.logoutPending, relaunched.session == nil else { return false }
        if offline {
            credentials.failIntent = true
            relaunched.retrySignOut()
            for _ in 0..<200 { if !relaunched.isBusy { break }; try await Task.sleep(for:.milliseconds(5)) }
            guard relaunched.logoutPending, relaunched.session == nil,
                  relaunched.message == "Sign-out is incomplete. Unlock this iPhone and retry before closing the app." else { return false }
            credentials.failIntent = false
        }
        credentials.failClear = false; await probe.setLogoutFailure(false)
        relaunched.retrySignOut()
        for _ in 0..<200 { if !relaunched.isBusy { break }; try await Task.sleep(for:.milliseconds(5)) }
        guard !relaunched.logoutPending, relaunched.session == nil, credentials.value == nil, !credentials.logoutPending else { return false }
        let finalLaunch = EmailAccountStore(configuration:configuration, probeClient:probe, probeCredentials:credentials, initial:nil)
        finalLaunch.open()
        return finalLaunch.session == nil && !finalLaunch.logoutPending
    }
    private convenience init(probe: EmailAccountRenewalProbe, credentials: EmailAccountProbeCredentials,
                             configuration: EmailAccountConfiguration, initial: EmailAccountSession) {
        self.init(configuration:configuration, probeClient:probe, probeCredentials:credentials, initial:initial)
    }
    func runRenewalVerificationIfRequested() async -> Bool {
        guard EmailAccountConfiguration.previewEnabled,
              let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--verify-email-account-renewal=") }),
              let mode = flag.split(separator:"=").last else { return false }
        do { verificationResult = try await Self.renewalScenario(String(mode)) ? "passed" : "failed" }
        catch { verificationResult = "failed" }
        return true
    }
    private static func renewalScenario(_ mode: String) async throws -> Bool {
        let configuration = try EmailAccountConfiguration(apiURL:"https://email-account.example.test")
        let initial = try EmailAccountSession(exchange:EmailAccountRenewalProbe.exchange(), scope:configuration.storageScope, now:.now.addingTimeInterval(-901))
        if mode == "marker-prepare" || mode == "marker-after-relaunch" {
            guard ProcessInfo.processInfo.arguments.contains("--verify-email-account-keychain") else { return false }
            let isolated = EmailAccountKeychain(scope:configuration.storageScope, isolatedSimulatorTest:true)
            if mode == "marker-prepare" {
                try isolated.clear(); try isolated.save(initial); try isolated.prepareForRenewal()
                return true
            }
            defer { try? isolated.clear() }
            return try isolated.load() == nil && isolated.load() == nil
        }
        let failures = mode == "ambiguous" ? ["transport", "validation", "storage"] : [""]
        for failure in failures {
            let probe = EmailAccountRenewalProbe(failure:failure)
            let credentials = EmailAccountProbeCredentials(initial, failSave:failure == "storage")
            let store = EmailAccountStore(probe:probe, credentials:credentials, configuration:configuration, initial:initial)
            store.open()
            for _ in 0..<100 {
                if await probe.refreshCalls > 0 { break }
                try await Task.sleep(for:.milliseconds(5))
            }
            if mode == "navigation" { store.cancel(); store.open() }
            if mode == "logout" { store.signOut() }
            if mode == "deletion" {
                store.cancel()
                store.deleting = true; store.code = "123456"
                store.challenge = try JSONDecoder().decode(EmailAccountChallenge.self, from:Data("{\"challengeID\":\"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa\",\"expiresInSeconds\":300,\"retryAfterSeconds\":60}".utf8))
                store.challengeExpiresAt = .now.addingTimeInterval(300)
                store.deleteAccount()
            }
            for _ in 0..<200 {
                if await probe.active == 0, !store.isBusy { break }
                try await Task.sleep(for:.milliseconds(5))
            }
            if mode == "ambiguous" { store.cancel(); store.open(); try await Task.sleep(for:.milliseconds(400)) }
            let calls = await probe.refreshCalls, peak = await probe.peak
            guard calls == 1, peak == 1 else { return false }
            switch mode {
            case "navigation":
                guard let renewed = store.session, renewed != initial, credentials.value == renewed else { return false }
            case "logout":
                for _ in 0..<100 {
                    if await probe.revocations.contains(String(repeating:"d",count:43)) { break }
                    try await Task.sleep(for:.milliseconds(5))
                }
                let revocations = await probe.revocations
                guard store.session == nil, credentials.value == nil, revocations.contains(String(repeating:"d",count:43)) else { return false }
            case "deletion":
                let deletedWith = await probe.deletedWith
                guard store.session == nil, credentials.value == nil, deletedWith == String(repeating:"c",count:43) else { return false }
            case "ambiguous":
                guard store.session == nil, credentials.value == nil,
                      store.message == "Account renewal could not be confirmed. Sign in again. Your learning records and model keys remain on this iPhone." else { return false }
            default: return false
            }
        }
        return true
    }
}
#endif
