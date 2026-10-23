import Foundation
import CoreFoundation

public struct ChatCompletionResult {
    public var text: String
    public var sources: [SourceLink]
    public var inputTokens: Int
    public var outputTokens: Int
    public var searches: Int
}

public enum ChatCompletion {
    public enum Failure: LocalizedError {
        case malformed, incomplete, refused, tooLarge, searchUnavailable
        public var errorDescription: String? {
            switch self {
            case .malformed, .incomplete: "The selected provider returned an incomplete response. Please try again."
            case .refused: "Tide English couldn’t complete that request. Try a different topic."
            case .tooLarge: "The selected provider’s response exceeded the safe size limit. Try a shorter request."
            case .searchUnavailable: "This provider does not support current-topic search. Select OpenAI or GLM in Settings to search."
            }
        }
    }
    public static func payload(configuration: ProviderConfiguration, instructions: String, input: String,
                               schema: [String: Any]? = nil, search: Bool = false, stream: Bool = false) throws -> [String: Any] {
        let config = try configuration.validated()
        guard config.provider != .openAI else { throw Failure.malformed }
        guard !search || config.provider == .glm else { throw Failure.searchUnavailable }
        var system = instructions
        if let schema {
            let encoded = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
            system += "\nReturn only a complete JSON object matching this JSON schema, including every required field. Do not include markdown or commentary.\n" + String(decoding: encoded, as: UTF8.self)
        }
        var body: [String: Any] = ["model": config.model, "messages": [["role": "system", "content": system], ["role": "user", "content": input]], "max_tokens": schema == nil ? 1400 : 2200, "stream": stream]
        if let _ = schema { body["response_format"] = ["type": "json_object"] }
        if stream { body["stream_options"] = ["include_usage": true] }
        // Do not send thinking parameters to older models or newer thinking-only families.
        let glmThinkingFamilies = ["glm-4.5", "glm-4.6", "glm-4.7", "glm-5", "glm-5.1", "glm-5.2"]
        if config.provider == .deepSeek || (config.provider == .glm && glmThinkingFamilies.contains(where: { config.model == $0 || config.model.hasPrefix($0 + "-") })) {
            body["thinking"] = ["type": "disabled"]
        }
        if search {
            body["tools"] = [["type": "web_search", "web_search": ["enable": true, "search_engine": "search_pro", "search_result": true]]]
            body["tool_choice"] = "auto"
        }
        return body
    }
    public static func decode(_ json: [String: Any], schema: [String: Any]? = nil) throws -> ChatCompletionResult {
        guard json["error"] == nil, let choices = json["choices"] as? [[String: Any]], choices.count == 1,
              let choice = choices.first, choice["index"] as? Int == 0,
              let message = choice["message"] as? [String: Any], message["role"] as? String == "assistant" else { throw Failure.malformed }
        if let refusal = message["refusal"], !(refusal is NSNull) { throw Failure.refused }
        try validateFinish(choice["finish_reason"] as? String)
        try validateTools(message["tool_calls"])
        guard let text = message["content"] as? String else { throw Failure.incomplete }
        return try result(text: text, usage: json["usage"] as? [String: Any], sources: sources(json), schema: schema)
    }
    static func validateTools(_ value: Any?) throws {
        guard let value, !(value is NSNull) else { return }
        guard let tools = value as? [Any] else { throw Failure.malformed }
        guard tools.isEmpty else { throw Failure.incomplete }
    }
    static func validateFinish(_ reason: String?) throws {
        if ["content_filter", "sensitive"].contains(reason) { throw Failure.refused }
        guard reason == "stop" else { throw Failure.incomplete }
    }
    static func result(text: String, usage: [String: Any]?, sources: [SourceLink], schema: [String: Any]?) throws -> ChatCompletionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.incomplete }
        guard text.utf8.count <= 65_536 else { throw Failure.tooLarge }
        if let schema {
            guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)), matches(json, schema: schema) else { throw Failure.incomplete }
        }
        return .init(text: text, sources: sources, inputTokens: max(0, usage?["prompt_tokens"] as? Int ?? 0),
                     outputTokens: max(0, usage?["completion_tokens"] as? Int ?? 0), searches: sources.isEmpty ? 0 : 1)
    }
    static func sources(_ json: [String: Any]) -> [SourceLink] {
        var result: [SourceLink] = []
        for item in (json["web_search"] as? [[String: Any]] ?? []).prefix(50) {
            guard let link = item["link"] as? String, link.utf8.count <= 2048,
                  !link.contains(where: { $0.isWhitespace || $0.isNewline }),
                  let url = URLComponents(string: link), url.scheme == "https", url.host?.isEmpty == false,
                  url.user == nil, url.password == nil, !result.contains(where: { $0.url == link }) else { continue }
            result.append(.init(title: String((item["title"] as? String ?? "Source").prefix(300)), url: link))
        }
        return result
    }
    private static func matches(_ value: Any, schema: [String: Any], depth: Int = 0) -> Bool {
        guard depth <= 20 else { return false }
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { ($0 as? NSObject)?.isEqual(value) == true }) { return false }
        switch schema["type"] as? String {
        case "object":
            guard let object = value as? [String: Any] else { return false }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            let required = schema["required"] as? [String] ?? []
            guard required.allSatisfy({ object[$0] != nil }) else { return false }
            if schema["additionalProperties"] as? Bool == false && !object.keys.allSatisfy({ properties[$0] != nil }) { return false }
            return object.allSatisfy { key, val in properties[key].map { matches(val, schema: $0, depth: depth + 1) } ?? true }
        case "array":
            guard let array = value as? [Any], array.count <= (schema["maxItems"] as? Int ?? Int.max), array.count >= (schema["minItems"] as? Int ?? 0) else { return false }
            guard let items = schema["items"] as? [String: Any] else { return true }
            return array.allSatisfy { matches($0, schema: items, depth: depth + 1) }
        case "string": return value is String
        case "integer", "number":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            let n = number.doubleValue
            guard n.isFinite, n >= ((schema["minimum"] as? NSNumber)?.doubleValue ?? -.infinity), n <= ((schema["maximum"] as? NSNumber)?.doubleValue ?? .infinity) else { return false }
            return schema["type"] as? String != "integer" || n.rounded() == n
        case "boolean": return (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        default: return false
        }
    }
}

/// Parses bytes so SSE blank event separators and split UTF-8 scalars are preserved.
public struct ChatCompletionStream {
    public enum Update { case text(String), completed(ChatCompletionResult) }
    private var line = Data()
    private var dataLines: [String] = []
    private var totalBytes = 0
    private var eventBytes = 0
    private var text = ""
    private var stopped = false
    private var completed = false
    private var usage: [String: Any]?
    private var sources: [SourceLink] = []
    private let schema: [String: Any]?
    public init(schema: [String: Any]? = nil) { self.schema = schema }
    public mutating func consume(byte: UInt8) throws -> Update? {
        guard !completed else { return nil }
        totalBytes += 1; eventBytes += 1
        guard totalBytes <= 2_097_152, eventBytes <= 65_536 else { throw ChatCompletion.Failure.tooLarge }
        guard byte == 10 else { line.append(byte); return nil }
        if line.last == 13 { line.removeLast() }
        guard let value = String(data: line, encoding: .utf8) else { throw ChatCompletion.Failure.malformed }
        line.removeAll(keepingCapacity: true)
        if !value.isEmpty {
            if value.hasPrefix("data:") {
                let data = value.dropFirst(5); dataLines.append(String(data.first == " " ? data.dropFirst() : data))
            }
            return nil
        }
        let payload = dataLines.joined(separator: "\n")
        dataLines.removeAll(keepingCapacity: true); eventBytes = 0
        if payload.isEmpty { return nil }
        if payload == "[DONE]" {
            guard stopped else { throw ChatCompletion.Failure.incomplete }
            let result = try ChatCompletion.result(text: text, usage: usage, sources: sources, schema: schema)
            completed = true; return .completed(result)
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              json["error"] == nil, let choices = json["choices"] as? [[String: Any]], choices.count <= 1 else { throw ChatCompletion.Failure.malformed }
        if let u = json["usage"] as? [String: Any] { usage = u }
        for source in ChatCompletion.sources(json) where !sources.contains(where: { $0.url == source.url }) {
            if sources.count < 50 { sources.append(source) }
        }
        guard let choice = choices.first else {
            guard json["usage"] is [String: Any] || json["web_search"] is [[String: Any]] else { throw ChatCompletion.Failure.malformed }
            return nil
        }
        guard choice["index"] as? Int == 0, let delta = choice["delta"] as? [String: Any] else { throw ChatCompletion.Failure.malformed }
        if let role = delta["role"], role as? String != "assistant" { throw ChatCompletion.Failure.malformed }
        if let refusal = delta["refusal"], !(refusal is NSNull) { throw ChatCompletion.Failure.refused }
        try ChatCompletion.validateTools(delta["tool_calls"])
        var update: Update?
        if let content = delta["content"], !(content is NSNull) {
            guard let value = content as? String, !stopped else { throw ChatCompletion.Failure.malformed }
            text += value
            guard text.utf8.count <= 65_536 else { throw ChatCompletion.Failure.tooLarge }
            if !value.isEmpty { update = .text(text) }
        }
        if let reason = choice["finish_reason"], !(reason is NSNull) {
            guard !stopped, let reason = reason as? String else { throw ChatCompletion.Failure.malformed }
            try ChatCompletion.validateFinish(reason); stopped = true
        }
        return update
    }
    public func finish() throws { guard completed else { throw ChatCompletion.Failure.incomplete } }
}
