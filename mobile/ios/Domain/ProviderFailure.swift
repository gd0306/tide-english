import Foundation
import CoreFoundation

/// Content-free diagnostics. Unknown provider fields and messages never leave the app.
public struct ProviderDiagnosticFailure: Encodable, Sendable {
    public let status: Int
    public let providerStatus: String?
    public let reason: String?
    public static func fromLiveMessage(_ body: Data) -> Self? {
        guard body.count <= 16_384,
              let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let number = error["code"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              (0...599).contains(number.doubleValue),
              number.doubleValue == Double(number.intValue) else { return nil }
        return Self(status: number.intValue, body: body)
    }
    public init(status: Int, body: Data) {
        self.status = status
        let json = body.count <= 16_384 ? (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] : nil
        let error = json?["error"] as? [String: Any]
        let statuses = ["INVALID_ARGUMENT", "FAILED_PRECONDITION", "PERMISSION_DENIED", "UNAUTHENTICATED", "NOT_FOUND", "RESOURCE_EXHAUSTED", "INTERNAL", "UNAVAILABLE", "OUT_OF_RANGE", "DEADLINE_EXCEEDED"]
        let candidate = error?["status"] as? String
        providerStatus = candidate.flatMap { statuses.contains($0) ? $0 : nil }
        let reasons = ["API_KEY_INVALID", "API_KEY_EXPIRED", "API_KEY_NOT_FOUND", "API_KEY_SERVICE_BLOCKED", "API_KEY_IP_ADDRESS_BLOCKED", "API_KEY_ANDROID_APP_BLOCKED", "API_KEY_IOS_APP_BLOCKED", "API_KEY_HTTP_REFERRER_BLOCKED", "ACCESS_TOKEN_TYPE_UNSUPPORTED", "SERVICE_DISABLED", "BILLING_DISABLED", "CONSUMER_INVALID", "LOCATION_POLICY_VIOLATED"]
        reason = (error?["details"] as? [[String: Any]] ?? []).compactMap { detail -> String? in
            guard detail["@type"] as? String == "type.googleapis.com/google.rpc.ErrorInfo",
                  let value = detail["reason"] as? String, reasons.contains(value) else { return nil }
            return value
        }.first
    }
}

public enum ProviderFailureKind: String, Sendable {
    case authentication, modelAccess, creditExhausted, spendLimit, usageLimit, quota, rateLimit, unavailable, invalidRequest, unknown
    public static func classify(status: Int, code: String?) -> Self {
        if status == 401 { return .authentication }
        if status == 402 { return .creditExhausted }
        if status == 403 || status == 404 { return .modelAccess }
        if status == 429 {
            switch code {
            case "credit_balance_exhausted": return .creditExhausted
            case "organization_spend_limit_exceeded", "project_spend_limit_exceeded": return .spendLimit
            case "organization_usage_limit_exceeded": return .usageLimit
            case "insufficient_quota": return .quota
            default: return .rateLimit
            }
        }
        if status == 408 || status >= 500 { return .unavailable }
        if status == 400 || status == 422 { return .invalidRequest }
        return .unknown
    }
}

/// Keeps a provider's safe category and support reference, never its message or response body.
public struct ProviderFailure: LocalizedError, Sendable {
    public let status: Int
    public let code: String?
    public let reference: String?
    public var kind: ProviderFailureKind { .classify(status: status, code: code) }
    public init(status: Int, body: Data = Data(), reference: String? = nil) {
        self.status = status
        let json = body.count <= 16_384 ? (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] : nil
        let code = (json?["error"] as? [String: Any])?["code"] as? String
        self.code = Self.safeCode(code)
        self.reference = Self.safeReference(reference)
    }
    public static func fromRealtime(code: String?) -> ProviderFailure? {
        guard let code = safeCode(code) else { return nil }
        let status: Int
        switch code {
        case "invalid_api_key": status = 401
        case "credit_balance_exhausted", "organization_spend_limit_exceeded", "project_spend_limit_exceeded",
             "organization_usage_limit_exceeded", "insufficient_quota": status = 429
        default: return nil
        }
        let body = try? JSONSerialization.data(withJSONObject: ["error": ["code": code]])
        return ProviderFailure(status: status, body: body ?? Data())
    }
    public static func safeCode(_ value: String?) -> String? {
        guard let value, ["invalid_api_key", "insufficient_quota", "credit_balance_exhausted", "organization_spend_limit_exceeded", "project_spend_limit_exceeded", "organization_usage_limit_exceeded", "rate_limit_exceeded", "slow_down", "model_not_found", "permission_denied", "server_error"].contains(value) else { return nil }
        return value
    }
    public static func safeReference(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 128,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return value
    }
    public var errorDescription: String? {
        let message: String = switch kind {
        case .authentication: "Your OpenAI key wasn’t accepted. Check it in Settings."
        case .modelAccess: "This API key may not have access to the requested model. Check your OpenAI project."
        case .creditExhausted: "OpenAI credits used up. Check your OpenAI billing or use Tide English minutes."
        case .spendLimit: "Your OpenAI spending limit was reached. Check the project or organization limit, or use Tide English minutes."
        case .usageLimit: "Your OpenAI usage limit was reached. Check your organization’s limit, or use Tide English minutes."
        case .quota: "OpenAI billing needs attention. Check your billing and limits, or use Tide English minutes."
        case .rateLimit: "OpenAI is limiting requests. Wait briefly and try again. If this continues, check your project’s billing and limits."
        case .unavailable: "The voice or teaching service is temporarily unavailable. Please try again shortly."
        case .invalidRequest: "The service could not accept this request. If this continues, contact support."
        case .unknown: "The service could not complete this request. Please try again later."
        }
        return reference.map { message + "\n\nOpenAI reference: " + $0 } ?? message
    }
}
