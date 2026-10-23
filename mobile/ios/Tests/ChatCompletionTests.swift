import XCTest
import TideEnglishCore

final class ChatCompletionTests: XCTestCase {
    private let schema: [String: Any] = ["type": "object", "properties": ["outcome": ["type": "string", "enum": ["success", "partial"]], "level": ["type": "integer", "minimum": 0, "maximum": 5]], "required": ["outcome", "level"], "additionalProperties": false]
    func testGeminiPayloadUsesEditedModelJSONSchemaAndStreamingUsage() throws {
        var selected = ProviderConfiguration(provider: .gemini)
        selected.model = "gemini-3.8-pro"
        let body = try ChatCompletion.payload(configuration: selected, instructions: "Assess", input: "hello", schema: schema, stream: true)
        XCTAssertEqual(body["model"] as? String, "gemini-3.8-pro")
        XCTAssertEqual(body["max_tokens"] as? Int, 2200)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual((body["stream_options"] as? [String: Bool])?["include_usage"], true)
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[1], ["role": "user", "content": "hello"])
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertTrue(messages[0]["content"]?.contains("outcome") == true)
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["tool_choice"])
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertThrowsError(try ChatCompletion.payload(configuration: selected, instructions: "", input: "", search: true)) { error in
            guard case ChatCompletion.Failure.searchUnavailable = error else { return XCTFail("Expected unavailable search") }
        }
    }
    func testGeminiCompatibleStopResultKeepsUsageAndSafetyGuards() throws {
        let good: [String: Any] = ["choices": [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": #"{"outcome":"success","level":3}"#]]],
                                   "usage": ["prompt_tokens": 17, "completion_tokens": 9, "total_tokens": 26]]
        let result = try ChatCompletion.decode(good, schema: schema)
        XCTAssertEqual(result.inputTokens, 17)
        XCTAssertEqual(result.outputTokens, 9)
        XCTAssertEqual(result.searches, 0)
        var truncated = good
        truncated["choices"] = [["index": 0, "finish_reason": "length", "message": ["role": "assistant", "content": "partial"]]]
        XCTAssertThrowsError(try ChatCompletion.decode(truncated, schema: schema))
        var refused = good
        refused["choices"] = [["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": "no", "refusal": "blocked"]]]
        XCTAssertThrowsError(try ChatCompletion.decode(refused))
    }
    func testGeminiCompatibleSSEStopDoneKeepsUsage() throws {
        var decoder = ChatCompletionStream()
        let wire = try event(chunk(["role": "assistant"])) + event(chunk(["content": "Hello "])) +
            event(chunk(["content": "there"], finish: "stop")) +
            event(["choices": [], "usage": ["prompt_tokens": 17, "completion_tokens": 9, "total_tokens": 26]]) +
            "data: [DONE]\n\n"
        let result = try XCTUnwrap(feed(wire, decoder: &decoder))
        XCTAssertEqual(result.text, "Hello there")
        XCTAssertEqual(result.inputTokens, 17)
        XCTAssertEqual(result.outputTokens, 9)
        XCTAssertNoThrow(try decoder.finish())
    }
    func testCompatiblePayloadUsesSelectedModelAndJSONInstructions() throws {
        var c = ProviderConfiguration(provider: .deepSeek); c.model = "deepseek-v4-pro"
        let body = try ChatCompletion.payload(configuration: c, instructions: "Assess", input: "hello", schema: schema, stream: true)
        XCTAssertEqual(body["model"] as? String, "deepseek-v4-pro")
        XCTAssertEqual(body["max_tokens"] as? Int, 2200)
        XCTAssertNil(body["max_output_tokens"])
        XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
        XCTAssertEqual((body["response_format"] as? [String: String])?["type"], "json_object")
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages[1], ["role": "user", "content": "hello"])
        XCTAssertTrue(messages[0]["content"]?.contains("JSON") == true)
        XCTAssertTrue(messages[0]["content"]?.contains("outcome") == true)
        XCTAssertTrue((body["stream_options"] as? [String: Bool])?["include_usage"] == true)
    }
    func testSearchNeverFallsBackAndGLMUsesDocumentedTool() throws {
        XCTAssertThrowsError(try ChatCompletion.payload(configuration: .init(provider: .deepSeek), instructions: "", input: "", search: true))
        var custom = ProviderConfiguration(provider: .custom); custom.baseURL = "https://example.com/v1"; custom.model = "chat"
        XCTAssertThrowsError(try ChatCompletion.payload(configuration: custom, instructions: "", input: "", search: true))
        let body = try ChatCompletion.payload(configuration: .init(provider: .glm), instructions: "", input: "", search: true)
        let tool = try XCTUnwrap((body["tools"] as? [[String: Any]])?.first)
        XCTAssertEqual(tool["type"] as? String, "web_search")
        let search = try XCTUnwrap(tool["web_search"] as? [String: Any])
        XCTAssertEqual(search["search_engine"] as? String, "search_pro")
        XCTAssertEqual(search["search_result"] as? Bool, true)
        var legacy = ProviderConfiguration(provider: .glm); legacy.model = "glm-4-air"
        XCTAssertNil(try ChatCompletion.payload(configuration: legacy, instructions: "", input: "")["thinking"])
        legacy.model = "glm-5.3-flash"
        XCTAssertNil(try ChatCompletion.payload(configuration: legacy, instructions: "", input: "")["thinking"])
    }
    private func reply(_ text: String, finish: String = "stop") -> [String: Any] {
        ["choices": [["index": 0, "finish_reason": finish, "message": ["role": "assistant", "content": text, "reasoning_content": "private thinking"]]], "usage": ["prompt_tokens": 11, "completion_tokens": 7]]
    }
    func testNonStreamRejectsTruncatedRefusedToolOnlyAndEmptyReplies() throws {
        let good = try ChatCompletion.decode(reply("你好"))
        XCTAssertEqual(good.text, "你好"); XCTAssertEqual(good.inputTokens, 11); XCTAssertEqual(good.outputTokens, 7)
        for finish in ["length", "tool_calls", "content_filter", "sensitive", "network_error"] { XCTAssertThrowsError(try ChatCompletion.decode(reply("partial", finish: finish))) }
        XCTAssertThrowsError(try ChatCompletion.decode(reply("  ")))
        XCTAssertThrowsError(try ChatCompletion.decode(["choices": [["finish_reason": "stop", "message": ["refusal": "raw private refusal", "content": "text"]]]]))
        XCTAssertThrowsError(try ChatCompletion.decode(["error": ["message": "private"]]))
    }
    func testNonStreamRejectsWrongChoiceRoleAndMalformedToolFields() throws {
        for choice in [
            ["index": 1, "finish_reason": "stop", "message": ["role": "assistant", "content": "wrong choice"]],
            ["index": 0, "finish_reason": "stop", "message": ["role": "user", "content": "not an answer"]],
            ["index": 0, "finish_reason": "stop", "message": ["role": "assistant", "content": "answer", "tool_calls": "malformed"]]
        ] as [[String: Any]] {
            XCTAssertThrowsError(try ChatCompletion.decode(["choices": [choice]]))
        }
        var decoder = ChatCompletionStream()
        let malformedTools = try event(chunk(["content": "answer", "tool_calls": "malformed"], finish: "stop")) + "data: [DONE]\n\n"
        XCTAssertThrowsError(try feed(malformedTools, decoder: &decoder))
    }
    func testAssessmentRequiresAllFieldsAndConstraints() throws {
        XCTAssertNoThrow(try ChatCompletion.decode(reply(#"{"outcome":"success","level":3}"#), schema: schema))
        for text in [#"{"outcome":"success"}"#, #"{"outcome":"unknown","level":3}"#, #"{"outcome":"success","level":6}"#, #"{"outcome":"success","level":3.5}"#, #"{"outcome":"success","level":true}"#, #"{"outcome":"success","level":3,"secret":1}"#, "not JSON"] {
            XCTAssertThrowsError(try ChatCompletion.decode(reply(text), schema: schema), text)
        }
    }
    func testSafeSearchSourcesComeOnlyFromProviderMetadata() throws {
        var json = reply("https://invented.example")
        json["web_search"] = [["title": "Source", "link": "https://news.example/item"], ["link": "https://news.example/item"], ["link": "javascript:alert(1)"], ["link": "https://name:password@bad.example"], ["link": "http://bad.example"]]
        let result = try ChatCompletion.decode(json)
        XCTAssertEqual(result.sources.map(\.url), ["https://news.example/item"])
        XCTAssertEqual(result.searches, 1)
    }
    private func event(_ json: [String: Any]) throws -> String {
        "data: " + String(decoding: try JSONSerialization.data(withJSONObject: json), as: UTF8.self) + "\r\n\r\n"
    }
    private func chunk(_ delta: [String: Any], finish: Any = NSNull()) -> [String: Any] {
        ["choices": [["index": 0, "delta": delta, "finish_reason": finish]]]
    }
    private func feed(_ wire: String, decoder: inout ChatCompletionStream) throws -> ChatCompletionResult? {
        var result: ChatCompletionResult?
        for byte in wire.utf8 { if case .completed(let r) = try decoder.consume(byte: byte) { result = r } }
        return result
    }
    func testByteWiseStreamRequiresStopAndDoneAndKeepsUsage() throws {
        var decoder = ChatCompletionStream()
        let wire = try event(chunk(["reasoning_content": "private"])) + event(chunk(["content": "你好"])) + event(chunk([:], finish: "stop")) + event(["choices": [], "usage": ["prompt_tokens": 11, "completion_tokens": 7]])
        XCTAssertNil(try feed(wire, decoder: &decoder))
        let result = try XCTUnwrap(feed("data: [DONE]\n\n", decoder: &decoder))
        XCTAssertEqual(result.text, "你好"); XCTAssertEqual(result.inputTokens, 11); XCTAssertEqual(result.outputTokens, 7)
    }
    func testStreamRejectsSuppliedNonAssistantRoles() throws {
        for role in ["user", NSNull(), 123] as [Any] {
            var decoder = ChatCompletionStream()
            let wire = try event(chunk(["role": role, "content": "answer"], finish: "stop")) + "data: [DONE]\n\n"
            XCTAssertThrowsError(try feed(wire, decoder: &decoder))
        }
        var decoder = ChatCompletionStream()
        let wire = try event(chunk(["role": "assistant"])) + event(chunk(["content": "answer"], finish: "stop")) + "data: [DONE]\n\n"
        XCTAssertEqual(try feed(wire, decoder: &decoder)?.text, "answer")
    }
    func testStreamRejectsPrematureDoneRefusalMalformedAndOversizedFrames() throws {
        for wire in ["data: [DONE]\n\n", "data: invalid\n\n", try event(chunk(["refusal": "private"])), try event(chunk(["content": "partial"], finish: "length")), try event(chunk(["tool_calls": [["id": "call"]]])), "data: " + String(repeating: "a", count: 65_537)] {
            var decoder = ChatCompletionStream(); XCTAssertThrowsError(try feed(wire, decoder: &decoder))
        }
        var decoder = ChatCompletionStream()
        _ = try feed(event(chunk(["content": "partial"])), decoder: &decoder)
        XCTAssertThrowsError(try decoder.finish())
        var assessment = ChatCompletionStream(schema: schema)
        let wire = try event(chunk(["content": #"{"outcome":"success"}"#])) + event(chunk([:], finish: "stop")) + "data: [DONE]\n\n"
        XCTAssertThrowsError(try feed(wire, decoder: &assessment))
    }
}
