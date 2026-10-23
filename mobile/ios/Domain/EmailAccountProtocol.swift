import Foundation

/// Only fixed app-authored errors cross the account transport boundary.
public enum EmailAccountError: Error, Equatable, Sendable {
    case unavailable, invalidResponse, invalidEmail, invalidCode, invalidSession, rateLimited, deliveryUnavailable, transport, cancelled, secureStorage, renewalUncertain
    public static func server(code: String) -> Self {
        switch code {
        case "invalid_code": .invalidCode
        case "invalid_session": .invalidSession
        case "rate_limited": .rateLimited
        case "email_delivery_unavailable": .deliveryUnavailable
        case "invalid_request", "request_too_large": .invalidResponse
        default: .unavailable
        }
    }
    public var message: String {
        switch self {
        case .renewalUncertain: "Account renewal could not be confirmed. Sign in again. Your learning records and model keys remain on this iPhone."
        case .invalidEmail: "Enter a valid email address."
        case .invalidCode: "That code is invalid or expired. Try again or request a new code."
        case .invalidSession: "Your account session expired. Sign in again."
        case .rateLimited: "Too many requests. Wait a minute and try again."
        case .deliveryUnavailable: "The email could not be sent. Wait a minute and try again."
        case .transport: "Couldn’t reach the account service. Check your connection and try again."
        case .secureStorage: "Your account session couldn’t be saved or removed securely. Unlock this iPhone and try again."
        case .cancelled: "Account action cancelled."
        case .invalidResponse: "The account service returned an invalid response. Please try again."
        case .unavailable: "Account service is unavailable. Please try again later."
        }
    }
}

public struct EmailAccountConfiguration: Equatable, Sendable {
    public let origin: URL
    public var storageScope: String { "tideenglish.email-account.v1|" + origin.absoluteString }
    public init(apiURL: String) throws {
        guard var c = URLComponents(string:apiURL), c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              c.port == nil || (1...65535).contains(c.port!)
        else { throw EmailAccountError.unavailable }
        c.scheme = "https"; c.host = host.lowercased(); c.path = ""
        if c.port == 443 { c.port = nil }
        guard let origin = c.url else { throw EmailAccountError.unavailable }
        self.origin = origin
    }
    public func endpoint(_ path: String) throws -> URL {
        guard ["/v1/email-auth/challenge", "/v1/email-auth/verify", "/v1/email-auth/refresh", "/v1/email-auth/sign-out", "/v1/email-account"].contains(path),
              var c = URLComponents(url:origin, resolvingAgainstBaseURL:false)
        else { throw EmailAccountError.unavailable }
        c.path = path
        guard let url = c.url else { throw EmailAccountError.unavailable }; return url
    }
}

public enum EmailAccountValidation {
    public static func email(_ value: String) throws -> String {
        guard value.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else { throw EmailAccountError.invalidEmail }
        let email = value.trimmingCharacters(in:.whitespaces).lowercased()
        let parts = email.split(separator:"@", omittingEmptySubsequences:false)
        guard email.utf8.count <= 254, parts.count == 2, (1...64).contains(parts[0].utf8.count),
              String(parts[0]).range(of:"^[a-z0-9!#$%&'*+\\-/=?^_`{|}~]+(?:\\.[a-z0-9!#$%&'*+\\-/=?^_`{|}~]+)*$", options:.regularExpression) != nil
        else { throw EmailAccountError.invalidEmail }
        let labels = parts[1].split(separator:".", omittingEmptySubsequences:false)
        guard labels.count >= 2, labels.allSatisfy({ String($0).range(of:"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", options:.regularExpression) != nil })
        else { throw EmailAccountError.invalidEmail }; return email
    }
    public static func code(_ value: String) -> Bool { value.range(of:"^[0-9]{6}$", options:.regularExpression) != nil }
    public static func token(_ value: String) -> Bool { value.range(of:"^[A-Za-z0-9_-]{43}$", options:.regularExpression) != nil }
    public static func identity(_ value: UUID) -> Bool {
        value.uuidString.range(of:"^[0-9A-F]{8}-[0-9A-F]{4}-[1-5][0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$", options:.regularExpression) != nil
    }
}

public struct EmailAccountChallenge: Decodable, Sendable {
    public let challengeID: UUID
    public let expiresInSeconds: Int
    public let retryAfterSeconds: Int
    public func validate() throws {
        guard EmailAccountValidation.identity(challengeID), expiresInSeconds == 300, retryAfterSeconds == 60
        else { throw EmailAccountError.invalidResponse }
    }
}
public struct EmailAccountExchange: Decodable, Sendable {
    public let accountID: UUID
    public let email: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresInSeconds: Int
    public let refreshExpiresInSeconds: Int
    public func validate() throws {
        guard EmailAccountValidation.identity(accountID), (try? EmailAccountValidation.email(email)) == email,
              EmailAccountValidation.token(accessToken), EmailAccountValidation.token(refreshToken), accessToken != refreshToken,
              expiresInSeconds == 900, (1...2_592_000).contains(refreshExpiresInSeconds)
        else { throw EmailAccountError.invalidResponse }
    }
}
public struct EmailAccountSession: Codable, Equatable, Sendable {
    public let accountID: UUID
    public let email: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let refreshExpiresAt: Date
    public let scope: String
    public init(exchange: EmailAccountExchange, scope: String, now: Date = .now, previous: Self? = nil) throws {
        try exchange.validate()
        guard !scope.isEmpty, now.timeIntervalSince1970.isFinite else { throw EmailAccountError.invalidResponse }
        let refreshExpiry = now.addingTimeInterval(TimeInterval(exchange.refreshExpiresInSeconds))
        if let previous {
            // TTL is measured at server response creation, not receipt. Network latency
            // may make a valid receipt-relative deadline later; retain the original bound.
            guard previous.accountID == exchange.accountID, previous.email == exchange.email, previous.scope == scope,
                  previous.canRefresh(scope:scope, now:now), previous.accessToken != exchange.accessToken,
                  previous.refreshToken != exchange.refreshToken, previous.accessToken != exchange.refreshToken,
                  previous.refreshToken != exchange.accessToken
            else { throw EmailAccountError.invalidResponse }
        }
        accountID = exchange.accountID; email = exchange.email; accessToken = exchange.accessToken; refreshToken = exchange.refreshToken
        expiresAt = now.addingTimeInterval(TimeInterval(exchange.expiresInSeconds))
        refreshExpiresAt = previous.map { min($0.refreshExpiresAt, refreshExpiry) } ?? refreshExpiry
        self.scope = scope
    }
    public func canRefresh(scope: String, now: Date = .now) -> Bool {
        self.scope == scope && EmailAccountValidation.identity(accountID) && (try? EmailAccountValidation.email(email)) == email &&
        EmailAccountValidation.token(accessToken) && EmailAccountValidation.token(refreshToken) && accessToken != refreshToken &&
        expiresAt.timeIntervalSince1970.isFinite && refreshExpiresAt.timeIntervalSince1970.isFinite &&
        expiresAt.timeIntervalSince(now) <= 900 && refreshExpiresAt > now && refreshExpiresAt.timeIntervalSince(now) <= 2_592_000
    }
    public func accessIsUsable(scope: String, now: Date = .now) -> Bool { canRefresh(scope:scope, now:now) && expiresAt > now }
}
public struct EmailAccountProfile: Decodable, Sendable {
    public let accountID: UUID
    public let email: String
    public func validate(session: EmailAccountSession) throws {
        guard accountID == session.accountID, email == session.email, (try? EmailAccountValidation.email(email)) == email
        else { throw EmailAccountError.invalidResponse }
    }
}
