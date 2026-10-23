import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import CryptoKit

public enum ModelProvider: String, Codable, CaseIterable, Sendable {
    case openAI, deepSeek, glm, gemini, custom
    public var displayName: String {
        switch self { case .openAI: "OpenAI"; case .deepSeek: "DeepSeek"; case .glm: "GLM (BigModel)"; case .gemini: "Gemini"; case .custom: "Custom" }
    }
    public var defaultModel: String {
        switch self { case .openAI: "gpt-6-luna"; case .deepSeek: "deepseek-flash"; case .glm: "glm-4.7-flash"; case .gemini: "gemini-3.8-flash"; case .custom: "" }
    }
    public var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .glm: "https://open.bigmodel.cn/api/paas/v4"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .custom: ""
        }
    }
}

public struct ProviderConfiguration: Codable, Equatable, Sendable {
    public var provider: ModelProvider
    public var model: String
    public var baseURL: String
    public init(provider: ModelProvider) {
        self.provider = provider; model = provider.defaultModel; baseURL = provider.defaultBaseURL
    }
    /// Absence alone permits the legacy default. Saved selections never fall back to another supplier.
    public static func restoreSelection(from data: Data?) -> Self {
        guard let data else { return Self(provider: .openAI) }
        guard let configuration = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(provider: .custom)
        }
        // Retain invalid decoded fields so routing rejects them and Settings can repair them.
        return (try? configuration.validated()) ?? configuration
    }
    public var supportsSearch: Bool { provider == .openAI || provider == .glm }
    public func validated() throws -> Self {
        guard !model.isEmpty, model.utf8.count <= 128,
              model.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:/-]*$"#, options: .regularExpression) != nil,
              model.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { throw ValidationError.model }
        guard !baseURL.isEmpty, baseURL.utf8.count <= 2048,
              baseURL.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }),
              !baseURL.contains("\\"), !baseURL.contains("%"),
              var url = URLComponents(string: baseURL), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.port == nil || (1...65535).contains(url.port!),
              host.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 58, 91, 93].contains($0) }),
              url.path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ $0 != "." && $0 != ".." }),
              !url.path.contains("//") else { throw ValidationError.endpoint }
        url.scheme = "https"; url.host = host.lowercased()
        if url.port == 443 { url.port = nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        guard let normalized = url.url?.absoluteString else { throw ValidationError.endpoint }
        guard provider == .custom || normalized == provider.defaultBaseURL else { throw ValidationError.recipient }
        var result = self; result.baseURL = normalized
        return result
    }
    public func endpoint(_ path: String) throws -> URL {
        let config = try validated()
        guard !path.isEmpty, path.utf8.count <= 256,
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".." && $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
              }), let url = URL(string: config.baseURL + "/" + path) else { throw ValidationError.endpoint }
        return url
    }
    public func credentialService() throws -> String {
        let config = try validated()
        switch provider {
        case .openAI: return "no.william.tideenglish.openai"
        case .deepSeek: return "no.william.tideenglish.deepseek"
        case .glm: return "no.william.tideenglish.glm"
        case .gemini: return "no.william.tideenglish.gemini"
        case .custom:
            let digest = SHA256.hash(data: Data(config.baseURL.utf8)).map { String(format: "%02x", $0) }.joined()
            return "no.william.tideenglish.custom." + digest
        }
    }
    public static func validatedCredential(_ key: String) throws -> String {
        let value = key.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.utf8.count <= 4096, value.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { throw ValidationError.key }
        return value
    }
    public enum ValidationError: LocalizedError {
        case model, endpoint, recipient, key
        public var errorDescription: String? {
            switch self {
            case .model: "Enter a chat model ID in Settings using letters, numbers, dots, dashes, underscores, colons or slashes."
            case .endpoint: "Enter an HTTPS API base URL in Settings without credentials, query, fragment or relative path segments."
            case .recipient: "Use this provider’s official endpoint, or select Custom for another supplier."
            case .key: "Enter a nonempty API key without spaces or control characters."
            }
        }
    }
}

/// Authenticated requests may never be redirected to another recipient.
public final class ProviderNoRedirect: NSObject, URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
