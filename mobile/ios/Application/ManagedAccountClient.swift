import Foundation
import Security
import CryptoKit
import TideEnglishCore

extension ManagedAccountConfiguration {
    /// These keys contain public client IDs, never OAuth secrets or TideEnglish bearer tokens.
    static func load(bundle: Bundle = .main) -> Self? {
        #if TIDE_ENGLISH_SIGN_IN_WITH_APPLE
        let appleCapabilityEnabled = true
        #else
        let appleCapabilityEnabled = false
        #endif
        func enabled(_ key: String) -> Bool {
            let value = bundle.object(forInfoDictionaryKey: key)
            return value as? Bool == true || (value as? String)?.uppercased() == "YES"
        }
        guard enabled("TideEnglishManagedAccountsEnabled"),
              let api = bundle.object(forInfoDictionaryKey: "TideEnglishManagedAPIURL") as? String,
              let bundleID = bundle.bundleIdentifier else { return nil }
        let google = enabled("TideEnglishGoogleSignInEnabled")
            ? bundle.object(forInfoDictionaryKey: "TideEnglishGoogleClientID") as? String : nil
        let apple = enabled("TideEnglishAppleSignInEnabled") && appleCapabilityEnabled
            ? bundle.object(forInfoDictionaryKey: "TideEnglishAppleClientID") as? String : nil
        let schemes = (bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return try? Self(apiURL: api, googleClientID: google, appleClientID: apple,
                         bundleID: bundleID, registeredURLSchemes: schemes, appleCapabilityEnabled: appleCapabilityEnabled)
    }
}

/// No redirect can carry an account token, provider code or verifier to another destination.
final class ManagedAccountHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let request = try await AppleStorePurchaseContext.shared.attachingProof(to: request)
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  response.url == request.url, response.expectedContentLength <= 65_536
            else { throw ManagedAccountError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65_536 else { throw ManagedAccountError.invalidResponse }
                data.append(byte)
            }
            return (data, http)
        } catch let error as ManagedAccountError { throw error }
        catch is CancellationError { throw ManagedAccountError.cancelled }
        catch let error as URLError where error.code == .cancelled { throw ManagedAccountError.cancelled }
        catch {
            #if DEBUG
            if AudioVerification.requested, let network = error as? URLError {
                UserDefaults.standard.set(network.code.rawValue, forKey: "verificationNetworkErrorCode")
            }
            #endif
            throw ManagedAccountError.transport
        }
    }
}

struct ManagedAccountClient {
    private struct Failure: Decodable {
        struct Detail: Decodable { let code: String }
        let error: Detail
    }
    let configuration: ManagedAccountConfiguration
    let http: ManagedAccountHTTP
    init(configuration: ManagedAccountConfiguration) { self.configuration = configuration; http = ManagedAccountHTTP() }

    func challenge() async throws -> ManagedAuthChallenge {
        let result: ManagedAuthChallenge = try await request("/v1/auth/challenge", method: "POST", body: [:])
        try result.validate(); return result
    }
    func exchange(provider: ManagedIdentityProvider, token: String, challenge: ManagedAuthChallenge) async throws -> ManagedAuthExchange {
        guard !token.isEmpty, token.utf8.count <= 16_384 else { throw ManagedAccountError.invalidResponse }
        let result: ManagedAuthExchange = try await request("/v1/auth/exchange", method: "POST", body: [
            "provider": provider.rawValue, "idToken": token, "challengeID": challenge.challengeID.uuidString
        ])
        try result.validate(); return result
    }
    func wallet(session: ManagedAccountSession) async throws -> ManagedWallet {
        let result: ManagedWallet = try await request("/v1/wallet", method: "GET", session: session)
        try result.validate(); return result
    }
    func connectGoogle(session: ManagedAccountSession, apple: String, appleChallenge: ManagedAuthChallenge,
                       google: String, googleChallenge: ManagedAuthChallenge) async throws {
        struct Result: Decodable { let accountID: UUID; let connected: Bool }
        let result: Result = try await request("/v1/account/connect-google", method: "POST", body: [
            "confirmation": "connect_google", "appleToken": apple, "appleChallengeID": appleChallenge.challengeID.uuidString,
            "googleToken": google, "googleChallengeID": googleChallenge.challengeID.uuidString
        ], session: session)
        guard result.accountID == session.accountID, result.connected else { throw ManagedAccountError.invalidResponse }
    }
    func profile(session: ManagedAccountSession) async throws -> ManagedAccountProfile {
        let result: ManagedAccountProfile = try await request("/v1/account", method: "GET", session: session)
        try result.validate(session: session); return result
    }
    func signOut(session: ManagedAccountSession) async throws {
        struct Response: Decodable { let signedOut: Bool }
        let result: Response = try await request("/v1/auth/sign-out", method: "POST", body: [:], session: session)
        guard result.signedOut else { throw ManagedAccountError.invalidResponse }
    }
    func delete(session: ManagedAccountSession, appleCode: String?) async throws {
        struct Response: Decodable { let deleted: Bool }
        let result: Response = try await request("/v1/account", method: "DELETE",
            body: appleCode.map { ["appleAuthorizationCode": $0] } ?? [:], session: session,
            confirmCreditAccessLoss: true)
        guard result.deleted else { throw ManagedAccountError.invalidResponse }
    }
    func deleteGuest(owner: HostedOwner) async throws {
        struct Response: Decodable { let deleted: Bool }
        let result: Response = try await request("/v1/guest/account", method: "DELETE", body: [:], guest: owner, confirmCreditAccessLoss: true)
        guard result.deleted else { throw ManagedAccountError.invalidResponse }
    }
    private func request<T: Decodable>(_ path: String, method: String, body: [String: String]? = nil,
                                        session: ManagedAccountSession? = nil, guest: HostedOwner? = nil,
                                        confirmCreditAccessLoss: Bool? = nil) async throws -> T {
        var request = URLRequest(url: try configuration.endpoint(path))
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var payload: [String: Any] = body
            if let confirmCreditAccessLoss { payload["confirmCreditAccessLoss"] = confirmCreditAccessLoss }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        if let session {
            guard session.isUsable(scope: configuration.storageScope) else { throw ManagedAccountError.server("sign_in_required") }
            request.setValue("Bearer " + session.accessToken, forHTTPHeaderField: "Authorization")
        }
        if let guest {
            guard guest.usable else { throw ManagedAccountError.server("sign_in_required") }
            request.setValue("Bearer " + guest.accessToken, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await http.send(request)
        guard (200...299).contains(response.statusCode) else {
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error.code ?? "service_unavailable"
            if response.statusCode == 401 {
                if ["invalid_challenge", "invalid_identity_token"].contains(code) { throw ManagedAccountError.invalidResponse }
                throw ManagedAccountError.server("sign_in_required")
            }
            // Only a small allowlist is displayed. Never surface raw provider/server response text.
            let safe = ["account_usage_pending", "unresolved_billing", "rate_limit", "apple_sign_in_not_ready", "apple_revocation_not_configured", "invalid_challenge", "identity_provider_not_configured", "same_account_required", "identity_link_conflict"]
            throw ManagedAccountError.server(safe.contains(code) ? code : "service_unavailable")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ManagedAccountError.invalidResponse }
    }
}

struct ManagedAccountKeychain {
    private let scope: String
    init(scope: String) { self.scope = scope }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "cn.gd306.tideenglish.managed-account",
         kSecAttrAccount as String: Data(SHA256.hash(data: Data(scope.utf8))).base64EncodedString(),
         kSecAttrSynchronizable as String: false]
    }
    func load() throws -> ManagedAccountSession? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw ManagedAccountError.secureStorage }
        guard let value = try? JSONDecoder().decode(ManagedAccountSession.self, from: data), value.isUsable(scope: scope)
        else { try remove(); return nil }
        return value
    }
    func save(_ value: ManagedAccountSession) throws {
        guard value.isUsable(scope: scope) else { throw ManagedAccountError.invalidResponse }
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
            else { throw ManagedAccountError.secureStorage }
        } else if status != errSecSuccess { throw ManagedAccountError.secureStorage }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ManagedAccountError.secureStorage }
    }
}

// Optional email accounts are independent of commercial identities and model credentials.
extension EmailAccountConfiguration {
    static var previewEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--preview") && args.contains("--preview-email-account")
        #else
        return false
        #endif
    }
    static func load(bundle: Bundle = .main) -> Self? {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--preview") {
            return previewEnabled ? try? Self(apiURL: "https://email-account.example.test") : nil
        }
        #endif
        let flag = bundle.object(forInfoDictionaryKey: "TideEnglishEmailAccountsEnabled")
        guard flag as? Bool == true || (flag as? String)?.uppercased() == "YES",
              let api = bundle.object(forInfoDictionaryKey: "TideEnglishEmailAccountAPIURL") as? String
        else { return nil }
        return try? Self(apiURL: api)
    }
}

protocol EmailAccountServing: Sendable {
    func challenge(email: String) async throws -> EmailAccountChallenge
    func verify(challenge: UUID, code: String) async throws -> EmailAccountExchange
    func refresh(token: String) async throws -> EmailAccountExchange
    func profile(session: EmailAccountSession) async throws -> EmailAccountProfile
    func signOut(token: String) async throws
    func delete(session: EmailAccountSession, challenge: UUID, code: String) async throws
}

final class EmailAccountHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, response.url == request.url,
                  response.expectedContentLength <= 65_536 else { throw EmailAccountError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 65_536 else { throw EmailAccountError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return (data, http)
        } catch let error as EmailAccountError { throw error }
        catch is CancellationError { throw EmailAccountError.cancelled }
        catch let error as URLError where error.code == .cancelled { throw EmailAccountError.cancelled }
        catch { throw EmailAccountError.transport }
    }
}

struct EmailAccountClient: EmailAccountServing {
    let configuration: EmailAccountConfiguration
    private let http = EmailAccountHTTP()
    private struct Failure: Decodable {
        struct Detail: Decodable { let code: String }
        let error: Detail
    }
    private struct SignOut: Decodable { let signedOut: Bool }
    private struct Deletion: Decodable { let deleted: Bool }
    private func request<T: Decodable>(_ path: String, method: String, body: [String: String]? = nil,
                                      bearer: String? = nil, status: Int = 200) async throws -> T {
        var request = URLRequest(url: try configuration.endpoint(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            let data = try JSONSerialization.data(withJSONObject: body)
            guard data.count <= 2048 else { throw EmailAccountError.invalidResponse }
            request.httpBody = data; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer {
            guard EmailAccountValidation.token(bearer) else { throw EmailAccountError.invalidSession }
            request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await http.send(request)
        guard response.statusCode == status else {
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                throw EmailAccountError.server(code: failure.error.code)
            }
            throw EmailAccountError.invalidResponse
        }
        guard response.mimeType == "application/json" else { throw EmailAccountError.invalidResponse }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw EmailAccountError.invalidResponse }
    }
    func challenge(email: String) async throws -> EmailAccountChallenge {
        let normalized = try EmailAccountValidation.email(email)
        let result: EmailAccountChallenge = try await request("/v1/email-auth/challenge", method: "POST", body: ["email": normalized], status: 202)
        try result.validate(); return result
    }
    func verify(challenge: UUID, code: String) async throws -> EmailAccountExchange {
        guard EmailAccountValidation.code(code) else { throw EmailAccountError.invalidCode }
        let result: EmailAccountExchange = try await request("/v1/email-auth/verify", method: "POST", body: ["challengeID":challenge.uuidString, "code":code])
        try result.validate(); return result
    }
    func refresh(token: String) async throws -> EmailAccountExchange {
        guard EmailAccountValidation.token(token) else { throw EmailAccountError.invalidSession }
        let result: EmailAccountExchange = try await request("/v1/email-auth/refresh", method: "POST", body: ["refreshToken":token])
        try result.validate(); return result
    }
    func profile(session: EmailAccountSession) async throws -> EmailAccountProfile {
        guard session.accessIsUsable(scope: configuration.storageScope) else { throw EmailAccountError.invalidSession }
        let result: EmailAccountProfile = try await request("/v1/email-account", method: "GET", bearer:session.accessToken)
        try result.validate(session:session); return result
    }
    func signOut(token: String) async throws {
        let result: SignOut = try await request("/v1/email-auth/sign-out", method: "POST", body:["refreshToken":token])
        guard result.signedOut else { throw EmailAccountError.invalidResponse }
    }
    func delete(session: EmailAccountSession, challenge: UUID, code: String) async throws {
        guard session.accessIsUsable(scope:configuration.storageScope), EmailAccountValidation.code(code)
        else { throw EmailAccountError.invalidCode }
        let result: Deletion = try await request("/v1/email-account", method: "DELETE", body:["challengeID":challenge.uuidString, "code":code], bearer:session.accessToken)
        guard result.deleted else { throw EmailAccountError.invalidResponse }
    }
}

/// Accesses exactly one email-account item; never queries an owner model credential.
@MainActor protocol EmailAccountCredentialStorage {
    var logoutPending: Bool { get }
    func setLogoutPending(_ pending: Bool) throws
    func load() throws -> EmailAccountSession?
    func save(_ session: EmailAccountSession) throws
    func prepareForRenewal() throws
    func clear() throws
}

struct EmailAccountKeychain: EmailAccountCredentialStorage {
    private var logoutIntentKey: String { service + ".logout-intent" }
    var logoutPending: Bool { UserDefaults.standard.bool(forKey:logoutIntentKey) }
    func setLogoutPending(_ pending: Bool) throws {
        // Only a non-secret, origin/service-scoped intent is persisted outside Keychain.
        if pending { UserDefaults.standard.set(true, forKey:logoutIntentKey) }
        else { UserDefaults.standard.removeObject(forKey:logoutIntentKey) }
        guard UserDefaults.standard.synchronize() else { throw EmailAccountError.secureStorage }
    }
    private let service: String
    private let scope: String
    init(scope: String, isolatedSimulatorTest: Bool = false) {
        self.scope = scope
        let hash = SHA256.hash(data:Data(scope.utf8)).map { String(format:"%02x", $0) }.joined()
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        let isolated = isolatedSimulatorTest && args.contains("--preview") && args.contains("--preview-email-account") && args.contains("--verify-email-account-keychain")
        service = isolated ? "cn.gd306.tideenglish.ios.email-account.simulator-verification.v1." + hash : "cn.gd306.tideenglish.ios.email-account.v1." + hash
        #else
        service = "cn.gd306.tideenglish.ios.email-account.v1." + hash
        #endif
    }
    private var query: [String: Any] {
        [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"session"]
    }
    func load() throws -> EmailAccountSession? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 65_536 else { throw EmailAccountError.secureStorage }
        guard let session = try? JSONDecoder().decode(EmailAccountSession.self, from:data), session.canRefresh(scope:scope)
        else { try clear(); return nil }
        return session
    }
    func save(_ session: EmailAccountSession) throws {
        guard session.canRefresh(scope:scope) else { throw EmailAccountError.invalidSession }
        let data = try JSONEncoder().encode(session)
        let update = [kSecValueData as String:data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw EmailAccountError.secureStorage }
        } else if status != errSecSuccess { throw EmailAccountError.secureStorage }
    }
    func prepareForRenewal() throws {
        // Replace the persisted old credential before sending it. A crash or a failed
        // replacement/clear can leave only this undecodable marker, never a consumed token.
        let marker = [kSecValueData as String:Data("email-account-renewal-pending-v1".utf8)]
        guard SecItemUpdate(query as CFDictionary, marker as CFDictionary) == errSecSuccess
        else { throw EmailAccountError.secureStorage }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw EmailAccountError.secureStorage }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// A fake mailbox/server, available only behind both explicit simulator preview flags.
actor PreviewEmailAccountClient: EmailAccountServing {
    private var challenges: [UUID: (email: String, expiry: Date)] = [:]
    private let id = UUID(uuidString:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let offlineSignOut: Bool
    private let networkFailure: Bool
    private let rateLimited: Bool
    private let delayedVerify: Bool
    private let delayRefresh: Bool
    private(set) var refreshCount = 0
    init(arguments: [String]) {
        offlineSignOut = arguments.contains("--preview-email-offline-signout")
        networkFailure = arguments.contains("--preview-email-network-error")
        rateLimited = arguments.contains("--preview-email-rate-limit")
        delayedVerify = arguments.contains("--preview-email-delayed-verify")
        delayRefresh = arguments.contains("--verify-email-account-single-flight")
    }
    func challenge(email: String) async throws -> EmailAccountChallenge {
        if networkFailure { throw EmailAccountError.transport }
        if rateLimited { throw EmailAccountError.rateLimited }
        let normalized = try EmailAccountValidation.email(email)
        challenges = challenges.filter { $0.value.email != normalized }
        let challenge = UUID(); challenges[challenge] = (normalized, .now.addingTimeInterval(300))
        return try JSONDecoder().decode(EmailAccountChallenge.self, from:JSONSerialization.data(withJSONObject:["challengeID":challenge.uuidString, "expiresInSeconds":300, "retryAfterSeconds":60]))
    }
    private func consume(_ challenge: UUID, code: String) throws -> String {
        guard let item = challenges[challenge], item.expiry > .now, code == "123456" else { throw EmailAccountError.invalidCode }
        challenges[challenge] = nil; return item.email
    }
    private func exchange(email: String, remaining: Int = 2_592_000) throws -> EmailAccountExchange {
        func token() -> String { Data((0..<32).map { _ in UInt8.random(in:0...255) }).base64EncodedString().replacingOccurrences(of:"+", with:"-").replacingOccurrences(of:"/", with:"_").replacingOccurrences(of:"=", with:"") }
        return try JSONDecoder().decode(EmailAccountExchange.self, from:JSONSerialization.data(withJSONObject:["accountID":id.uuidString, "email":email, "accessToken":token(), "refreshToken":token(), "expiresInSeconds":900, "refreshExpiresInSeconds":remaining]))
    }
    func verify(challenge: UUID, code: String) async throws -> EmailAccountExchange {
        // Deliberately return even after cancellation to exercise the store generation guard.
        if delayedVerify { try? await Task.sleep(for:.seconds(3)) }
        return try exchange(email:consume(challenge, code:code))
    }
    // Renewal fixtures use the same synthetic mailbox and no persistent server state.
    func refresh(token: String) async throws -> EmailAccountExchange {
        refreshCount += 1
        if delayRefresh { try await Task.sleep(for:.milliseconds(200)) }
        return try exchange(email:"preview@example.test", remaining:2_591_098)
    }
    func profile(session: EmailAccountSession) async throws -> EmailAccountProfile {
        try JSONDecoder().decode(EmailAccountProfile.self, from:JSONSerialization.data(withJSONObject:["accountID":session.accountID.uuidString, "email":session.email]))
    }
    func signOut(token: String) async throws { if offlineSignOut { throw EmailAccountError.transport } }
    func delete(session: EmailAccountSession, challenge: UUID, code: String) async throws {
        guard try consume(challenge, code:code) == session.email else { throw EmailAccountError.invalidCode }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
/// Deterministic in-memory renewal adversary; no URLSession, SMTP or Keychain.
actor EmailAccountRenewalProbe: EmailAccountServing {
    private(set) var refreshCalls = 0
    private(set) var active = 0
    private(set) var peak = 0
    private(set) var revocations: [String] = []
    private(set) var deletedWith: String?
    let failure: String
    private var logoutNetworkFailure = false
    func setLogoutFailure(_ value: Bool) { logoutNetworkFailure = value }
    init(failure: String) { self.failure = failure }
    static func exchange(access: String = "a", refresh: String = "b", remaining: Int = 2592000, email: String = "preview@example.test") throws -> EmailAccountExchange {
        try JSONDecoder().decode(EmailAccountExchange.self, from:JSONSerialization.data(withJSONObject:["accountID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "email":email, "accessToken":String(repeating:access,count:43), "refreshToken":String(repeating:refresh,count:43), "expiresInSeconds":900, "refreshExpiresInSeconds":remaining]))
    }
    func refresh(token: String) async throws -> EmailAccountExchange {
        refreshCalls += 1; let call = refreshCalls; active += 1; peak = max(peak, active)
        defer { active -= 1 }
        // A detached delay ignores waiter/URL cancellation, like a server that already rotated.
        await withCheckedContinuation { continuation in
            Task.detached { try? await Task.sleep(for:.milliseconds(300)); continuation.resume() }
        }
        if failure == "transport" { throw EmailAccountError.transport }
        return try Self.exchange(access:call == 1 ? "c" : "e", refresh:call == 1 ? "d" : "f", remaining:2591095,
                                 email:failure == "validation" ? "other@example.test" : "preview@example.test")
    }
    func profile(session: EmailAccountSession) async throws -> EmailAccountProfile {
        try JSONDecoder().decode(EmailAccountProfile.self, from:JSONSerialization.data(withJSONObject:["accountID":session.accountID.uuidString,"email":session.email]))
    }
    func signOut(token: String) async throws {
        revocations.append(token)
        if logoutNetworkFailure { throw EmailAccountError.transport }
    }
    func delete(session: EmailAccountSession, challenge: UUID, code: String) async throws { deletedWith = session.accessToken }
    func challenge(email: String) async throws -> EmailAccountChallenge { throw EmailAccountError.unavailable }
    func verify(challenge: UUID, code: String) async throws -> EmailAccountExchange { throw EmailAccountError.unavailable }
}
#endif
