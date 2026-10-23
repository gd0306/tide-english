import Foundation
import TideEnglishCore
import UIKit

struct APIUsage { var input = 0; var output = 0; var searches = 0 }
struct APIResult { var text: String; var sources: [SourceLink]; var usage: APIUsage }

@MainActor final class APIClient {
    var configuration: ProviderConfiguration {
        didSet {
            if configuration != oldValue {
                cancelAIRequests(); credentialExpiry?.cancel(); credentialExpiry = nil; voiceCredential.clear()
            }
        }
    }
    var conversationProvider: ConversationProvider = .personalKey
    var hostedLease: HostedLease?
    var canProcessAI: () -> Bool = { true }
    #if DEBUG
    var onDiagnosticFailure: ((ProviderDiagnosticFailure) -> Void)?
    #endif
    private var responseTasks: [UUID: Task<APIResult, Error>] = [:]
    func cancelAIRequests() {
        responseTasks.values.forEach { $0.cancel() }
        responseTasks.removeAll()
    }
    private let session: URLSession
    private var voiceCredential = VoiceCredentialScope()
    private var credentialExpiry: Task<Void, Never>?
    func beginVoiceCredential() {
        credentialExpiry?.cancel(); voiceCredential.clear()
        guard let key = CredentialStore.read(configuration: configuration) else { return }
        voiceCredential.begin(key: key)
        expireVoiceCredential(after: .seconds(65 * 60))
    }
    func endVoiceCredential() {
        voiceCredential.end()
        expireVoiceCredential(after: .seconds(60))
    }
    private func expireVoiceCredential(after duration: Duration) {
        credentialExpiry?.cancel()
        credentialExpiry = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            self?.voiceCredential.clear(); self?.credentialExpiry = nil
        }
    }
    func credential() throws -> String { try credential(configuration: configuration) }
    private func credential(configuration captured: ProviderConfiguration) throws -> String {
        _ = try captured.validated()
        let stored = { CredentialStore.read(configuration: captured) }
        let key: String?
        if captured == configuration {
            key = voiceCredential.credential(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable, readStored: stored)
        } else {
            key = UIApplication.shared.isProtectedDataAvailable ? stored() : nil
        }
        guard let key else {
            if captured.provider == .openAI { throw APIError.missingKey }
            throw CredentialError(provider: captured.provider)
        }
        return try ProviderConfiguration.validatedCredential(key)
    }
    init(configuration: ProviderConfiguration = ModelSettings.load()) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 60
        config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate: ProviderNoRedirect(), delegateQueue: nil)
    }
    func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await post(path, body: body, configuration: configuration.validated())
    }
    private func request(_ path: String, body: [String: Any], configuration: ProviderConfiguration, stream: Bool = false) throws -> URLRequest {
        guard canProcessAI() else { throw AIProcessingConsent.ConsentError.required }
        try Task.checkCancellation()
        let key = try credential(configuration: configuration)
        var request = URLRequest(url: try configuration.endpoint(path))
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    private func failure(_ http: HTTPURLResponse, body: Data, configuration: ProviderConfiguration) -> Error {
        #if DEBUG
        onDiagnosticFailure?(ProviderDiagnosticFailure(status: http.statusCode, body: body))
        #endif
        let failure = ProviderFailure(status: http.statusCode, body: body, reference: http.value(forHTTPHeaderField: "x-request-id"))
        if configuration.provider == .openAI { return failure }
        return ProviderRequestError(provider: configuration.provider, failure: failure)
    }
    private func post(_ path: String, body: [String: Any], configuration: ProviderConfiguration) async throws -> [String: Any] {
        let request = try request(path, body: body, configuration: configuration)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            if configuration.provider == .openAI { throw APIError.invalidResponse }
            throw ChatCompletion.Failure.malformed
        }
        var data = Data()
        let success = (200..<300).contains(http.statusCode)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard canProcessAI() else { throw AIProcessingConsent.ConsentError.required }
            data.append(byte)
            if !success && data.count >= 16_384 { break }
            if data.count > 2_097_152 { throw ChatCompletion.Failure.tooLarge }
        }
        try Task.checkCancellation()
        guard success else { throw failure(http, body: data, configuration: configuration) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if configuration.provider == .openAI { throw APIError.invalidResponse }
            throw ChatCompletion.Failure.malformed
        }
        return json
    }
    func respond(instructions: String, input: String, schema: [String: Any]? = nil, search: Bool = false,
                 purpose: String = "meaning", onText: (@MainActor (String) -> Void)? = nil) async throws -> APIResult {
        guard canProcessAI() else { throw AIProcessingConsent.ConsentError.required }
        try Task.checkCancellation()
        let captured = try configuration.validated()
        let id = UUID()
        let task = Task { @MainActor in
            try Task.checkCancellation()
            guard self.canProcessAI() else { throw AIProcessingConsent.ConsentError.required }
            let result = try await self.performResponse(instructions: instructions, input: input, schema: schema,
                                                       search: search, purpose: purpose, onText: onText, configuration: captured)
            try Task.checkCancellation()
            guard self.canProcessAI() else { throw AIProcessingConsent.ConsentError.required }
            return result
        }
        responseTasks[id] = task
        defer { responseTasks.removeValue(forKey: id) }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    private func performResponse(instructions: String, input: String, schema: [String: Any]?, search: Bool,
                                 purpose: String, onText: (@MainActor (String) -> Void)?, configuration: ProviderConfiguration) async throws -> APIResult {
        if conversationProvider == .hosted {
            guard let hostedLease, let client = HostedClient.shared else { throw HostedError.unavailable }
            let result = try await client.helper(hostedLease, purpose: purpose, instructions: instructions, input: input,
                                                 schema: schema, search: search)
            onText?(result.text)
            return result
        }
        if configuration.provider != .openAI {
            return try await compatibleResponse(instructions: instructions, input: input, schema: schema,
                                                search: search, onText: onText, configuration: configuration)
        }
        var body: [String: Any] = ["model": configuration.model, "store": false, "instructions": instructions,
                                  "input": [["role": "user", "content": input]], "max_output_tokens": schema == nil ? 1400 : 2200,
                                  "reasoning": ["effort": "low"]]
        if let schema { body["text"] = ["format": ["type": "json_schema", "name": "tideenglish_result", "strict": true, "schema": schema]] }
        if search { body["tools"] = [["type": "web_search"]]; body["tool_choice"] = "auto"; body["max_tool_calls"] = 1 }
        let json: [String: Any]
        if let onText {
            body["stream"] = true
            json = try await streamResponse(body: body, onText: onText, configuration: configuration)
        } else { json = try await post("responses", body: body, configuration: configuration) }
        guard json["status"] as? String == "completed" else { throw APIError.incomplete }
        var text = "", sources: [SourceLink] = [], usage = APIUsage()
        for item in json["output"] as? [[String: Any]] ?? [] {
            if item["type"] as? String == "web_search_call" { usage.searches += 1 }
            for content in item["content"] as? [[String: Any]] ?? [] {
                if content["type"] as? String == "refusal" { throw APIError.refused }
                if content["type"] as? String == "output_text" { text += content["text"] as? String ?? "" }
                for citation in content["annotations"] as? [[String: Any]] ?? [] {
                    guard citation["type"] as? String == "url_citation", let url = citation["url"] as? String else { continue }
                    let source = SourceLink(title: citation["title"] as? String ?? "Source", url: url)
                    if source.safeURL != nil && !sources.contains(where: { $0.url == url }) { sources.append(source) }
                }
            }
        }
        if let u = json["usage"] as? [String: Any] { usage.input = u["input_tokens"] as? Int ?? 0; usage.output = u["output_tokens"] as? Int ?? 0 }
        guard !text.isEmpty else { throw APIError.incomplete }
        return APIResult(text: text, sources: sources, usage: usage)
    }
    private func compatibleResponse(instructions: String, input: String, schema: [String: Any]?, search: Bool,
                                    onText: (@MainActor (String) -> Void)?, configuration: ProviderConfiguration) async throws -> APIResult {
        let body = try ChatCompletion.payload(configuration: configuration, instructions: instructions, input: input,
                                              schema: schema, search: search, stream: onText != nil)
        let result: ChatCompletionResult
        if let onText {
            let request = try request("chat/completions", body: body, configuration: configuration, stream: true)
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw ChatCompletion.Failure.malformed }
            guard (200..<300).contains(http.statusCode) else {
                var data = Data()
                for try await byte in bytes { try Task.checkCancellation(); data.append(byte); if data.count >= 16_384 { break } }
                throw failure(http, body: data, configuration: configuration)
            }
            guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else { throw ChatCompletion.Failure.malformed }
            var decoder = ChatCompletionStream(schema: schema)
            var completed: ChatCompletionResult?
            for try await byte in bytes {
                try Task.checkCancellation()
                guard canProcessAI() else { throw AIProcessingConsent.ConsentError.required }
                if let update = try decoder.consume(byte: byte) {
                    switch update {
                    case .text(let text): onText(text)
                    case .completed(let value): completed = value
                    }
                }
                if completed != nil { break }
            }
            try decoder.finish()
            guard let completed else { throw ChatCompletion.Failure.incomplete }
            result = completed
        } else {
            result = try ChatCompletion.decode(try await post("chat/completions", body: body, configuration: configuration), schema: schema)
        }
        return APIResult(text: result.text, sources: result.sources,
                         usage: APIUsage(input: result.inputTokens, output: result.outputTokens, searches: result.searches))
    }
    private func streamResponse(body: [String: Any], onText: @MainActor (String) -> Void, configuration: ProviderConfiguration) async throws -> [String: Any] {
        let request = try request("responses", body: body, configuration: configuration, stream: true)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes { body.append(byte); if body.count >= 16_384 { break } }
            throw failure(http, body: body, configuration: configuration)
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else { throw APIError.invalidResponse }
        var decoder = ResponseTextStream()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard let update = try decoder.consume(byte: byte) else { continue }
                switch update {
                case .text(let value): onText(value)
                case .completed(let result): return result
                }
            }
        } catch ResponseTextStream.Failure.refused { throw APIError.refused }
        catch is ResponseTextStream.Failure { throw APIError.incomplete }
        throw APIError.incomplete
    }
    static func object(_ fields: [String: Any]) -> [String: Any] { ["type": "object", "properties": fields, "required": fields.keys.sorted(), "additionalProperties": false] }
    static let string: [String: Any] = ["type": "string"]
    static func assessmentSchema(language: LanguageModule) -> [String: Any] { object([
        "outcome": ["type": "string", "enum": ["success", "partial", "breakdown", "uncertain"]],
        "suggestedLevel": ["type": "integer", "minimum": 0, "maximum": 5], "nextGoal": string, "capability": string,
        "words": ["type": "array", "maxItems": 12, "items": object([
            "lemma": string, "meaning": string, "form": string, "quote": string, "language": ["type": "string", "enum": Array(Set([language.id, "en", "mixed", "uncertain"])).sorted()],
            "kind": ["type": "string", "enum": ["exposure", "understanding", "assisted", "independent", "lapse"]],
            "confidence": ["type": "number", "minimum": 0, "maximum": 1], "sourceIDs": ["type": "array", "items": string]
        ])]
    ]) }
    struct CredentialError: LocalizedError {
        let provider: ModelProvider
        var errorDescription: String? { "Add your \(provider.displayName) key in Settings to begin." }
    }
    struct ProviderRequestError: LocalizedError {
        let provider: ModelProvider
        let failure: ProviderFailure
        var errorDescription: String? {
            let name = provider.displayName
            switch failure.kind {
            case .authentication: return "Your \(name) key wasn’t accepted. Check it in Settings."
            case .modelAccess: return "This key may not have access to the selected \(name) model. Check the model and account."
            case .creditExhausted:
                if provider == .gemini, failure.status == 402 {
                    return "Gemini returned HTTP 402: prepaid credits are unavailable. Check this key’s project and billing balance in Google AI Studio before starting again."
                }
                return "\(name) credits are used up. Check your provider account before starting again."
            case .spendLimit, .usageLimit, .quota: return "\(name) billing or usage limits need attention. Check your provider account."
            case .rateLimit: return "\(name) is limiting requests. Wait briefly and try again."
            case .invalidRequest: return "\(name) could not accept this request. Check the model and endpoint in Settings."
            default: return "\(name) couldn’t complete the request (HTTP \(failure.status)). Please try again."
            }
        }
    }
    enum APIError: LocalizedError {
        case missingKey, invalidResponse, incomplete, refused, http(Int)
        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your OpenAI key in Settings to begin."
            case .invalidResponse, .incomplete: "OpenAI returned an incomplete response. Please try again."
            case .refused: "Tide English couldn’t complete that request. Try a different topic."
            case .http(401): "Your OpenAI key wasn’t accepted. Check it in Settings."
            case .http(403), .http(404): "This API key may not have access to the requested model. Check your OpenAI project."
            case .http(429): "OpenAI’s usage or rate limit was reached. Check your project’s billing and limits."
            case .http(let status): "OpenAI couldn’t complete the request (HTTP \(status)). Please try again."
            }
        }
    }
}
