import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TideEnglishCore

final class ModelProviderTests: XCTestCase {
    func testGeminiOfficialRoutingAndCredentialIdentity() throws {
        let c = try ProviderConfiguration(provider: .gemini).validated()
        XCTAssertEqual(c.model, "gemini-3.8-flash")
        XCTAssertEqual(c.provider.displayName, "Gemini")
        XCTAssertEqual(try c.endpoint("chat/completions").absoluteString,
                       "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        XCTAssertEqual(try c.credentialService(), "no.william.tideenglish.gemini")
        XCTAssertFalse(c.supportsSearch)
        var redirected = c; redirected.baseURL = "https://api.openai.com/v1"
        XCTAssertThrowsError(try redirected.validated())
    }
    func testGeminiRestoreKeepsChosenModelAndCanonicalRecipient() throws {
        var selected = ProviderConfiguration(provider: .gemini)
        selected.model = "gemini-3.8-pro"
        selected.baseURL += "/"
        let restored = ProviderConfiguration.restoreSelection(from: try JSONEncoder().encode(selected))
        XCTAssertEqual(restored.provider, .gemini)
        XCTAssertEqual(restored.model, "gemini-3.8-pro")
        XCTAssertEqual(restored.baseURL, "https://generativelanguage.googleapis.com/v1beta/openai")
        XCTAssertEqual(try restored.credentialService(), "no.william.tideenglish.gemini")
    }
    func testOnlyAbsentSelectionRestoresLegacyOpenAI() throws {
        let legacy = ProviderConfiguration.restoreSelection(from: nil)
        XCTAssertEqual(legacy.provider, .openAI)
        XCTAssertEqual(try legacy.endpoint("responses").absoluteString, "https://api.openai.com/v1/responses")
        for data in [Data(), Data("not JSON".utf8), Data(#"{"provider":"future","model":"chat","baseURL":"https://other.example/v1"}"#.utf8), Data(#"{"provider":"deepSeek","model":"chat"}"#.utf8)] {
            let restored = ProviderConfiguration.restoreSelection(from: data)
            XCTAssertEqual(restored.provider, .custom)
            XCTAssertEqual(restored.model, "")
            XCTAssertEqual(restored.baseURL, "")
            XCTAssertThrowsError(try restored.endpoint("responses"))
            XCTAssertThrowsError(try restored.credentialService())
        }
    }
    func testInvalidDecodedSelectionRemainsSelectedAndCannotRoute() throws {
        var custom = ProviderConfiguration(provider: .custom); custom.model = "chat"; custom.baseURL = "http://other.example/v1"
        var badModel = ProviderConfiguration(provider: .deepSeek); badModel.model = "bad\nmodel"
        var badCustomModel = custom; badCustomModel.baseURL = "https://other.example/v1"; badCustomModel.model = ""
        var badPreset = ProviderConfiguration(provider: .glm); badPreset.baseURL = "https://api.openai.com/v1"
        for invalid in [custom, badCustomModel, badModel, badPreset] {
            let restored = ProviderConfiguration.restoreSelection(from: try JSONEncoder().encode(invalid))
            XCTAssertEqual(restored, invalid)
            XCTAssertNotEqual(restored.provider, .openAI)
            XCTAssertThrowsError(try restored.endpoint("responses"))
            XCTAssertThrowsError(try restored.credentialService())
        }
    }
    func testValidRestoredSelectionUsesCanonicalSelectedRecipient() throws {
        var custom = ProviderConfiguration(provider: .custom); custom.model = "owner-chat"; custom.baseURL = "https://CUSTOM.example:443/proxy/v1/"
        let restored = ProviderConfiguration.restoreSelection(from: try JSONEncoder().encode(custom))
        XCTAssertEqual(restored.provider, .custom)
        XCTAssertEqual(restored.model, "owner-chat")
        XCTAssertEqual(restored.baseURL, "https://custom.example/proxy/v1")
        XCTAssertEqual(try restored.endpoint("chat/completions").absoluteString, "https://custom.example/proxy/v1/chat/completions")
        let glm = ProviderConfiguration.restoreSelection(from: try JSONEncoder().encode(ProviderConfiguration(provider: .glm)))
        XCTAssertEqual(try glm.endpoint("chat/completions").absoluteString, "https://open.bigmodel.cn/api/paas/v4/chat/completions")
    }
    func testPresetRoutesStayWithSelectedSupplier() throws {
        XCTAssertEqual(try ProviderConfiguration(provider: .openAI).endpoint("responses").absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(try ProviderConfiguration(provider: .deepSeek).endpoint("chat/completions").absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(try ProviderConfiguration(provider: .glm).endpoint("chat/completions").absoluteString, "https://open.bigmodel.cn/api/paas/v4/chat/completions")
        var glm = ProviderConfiguration(provider: .glm)
        glm.baseURL = "https://api.z.ai/api/paas/v4"
        XCTAssertThrowsError(try glm.validated())
    }
    func testCustomRejectsUnsafeOrAmbiguousRecipients() throws {
        for value in ["http://example.com/v1", "https://key@example.com/v1", "https://example.com/v1?q=1", "https://example.com/v1#f", "https://example.com/a/../v1", "https://example.com/%2e%2e", "https://example.com/a\\b", "https://example.com/\n", "https://", ""] {
            var c = ProviderConfiguration(provider: .custom); c.model = "chat"; c.baseURL = value
            XCTAssertThrowsError(try c.validated(), value)
        }
        var c = ProviderConfiguration(provider: .custom); c.baseURL = "https://EXAMPLE.com:443/proxy/v1/"; c.model = "org/chat-model"
        XCTAssertEqual(try c.endpoint("chat/completions").absoluteString, "https://example.com/proxy/v1/chat/completions")
        for path in ["https://attacker.com", "//attacker.com", "../secrets", "chat?key=a", "chat#f", "chat/%2e"] {
            XCTAssertThrowsError(try c.endpoint(path), path)
        }
    }
    func testInvalidModelsNeverReachNetwork() {
        for model in ["", " model", "model\n", "model?x", "model#x", String(repeating: "a", count: 129)] {
            var c = ProviderConfiguration(provider: .deepSeek); c.model = model
            XCTAssertThrowsError(try c.endpoint("chat/completions"), model)
        }
    }
    func testCredentialScopesDoNotCrossProviderOriginOrPath() throws {
        XCTAssertEqual(try ProviderConfiguration(provider: .openAI).credentialService(), "no.william.tideenglish.openai")
        XCTAssertEqual(try ProviderConfiguration(provider: .deepSeek).credentialService(), "no.william.tideenglish.deepseek")
        XCTAssertEqual(try ProviderConfiguration(provider: .glm).credentialService(), "no.william.tideenglish.glm")
        var a = ProviderConfiguration(provider: .custom); a.baseURL = "https://one.example/v1"; a.model = "chat"
        var b = a; b.baseURL = "https://two.example/v1"
        var c = a; c.baseURL = "https://one.example/other"
        XCTAssertNotEqual(try a.credentialService(), try b.credentialService())
        XCTAssertNotEqual(try a.credentialService(), try c.credentialService())
        b = a; b.model = "another"; b.baseURL += "/"
        XCTAssertEqual(try a.credentialService(), try b.credentialService())
        XCTAssertFalse(try a.credentialService().contains("one.example"))
    }
    func testRedirectDelegateNeverForwardsAuthenticatedRequest() throws {
        let original = try XCTUnwrap(URL(string: "https://api.deepseek.com/chat/completions"))
        let redirected = try XCTUnwrap(URL(string: "https://attacker.example/chat/completions"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: original)
        let response = try XCTUnwrap(HTTPURLResponse(url: original, statusCode: 307, httpVersion: nil, headerFields: ["Location": redirected.absoluteString]))
        var proposed = URLRequest(url: redirected)
        proposed.setValue("Bearer synthetic-test-key", forHTTPHeaderField: "Authorization")
        var called = false
        ProviderNoRedirect().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: proposed) { request in
            called = true; XCTAssertNil(request)
        }
        XCTAssertTrue(called)
    }
    func testKeysPermitGLMFormatAndRejectHeaderInjection() throws {
        XCTAssertEqual(try ProviderConfiguration.validatedCredential("  id.signature  "), "id.signature")
        for key in ["", "  ", "abc\r\nAuthorization: other", "a b", "密钥", "abc\u{7f}"] {
            XCTAssertThrowsError(try ProviderConfiguration.validatedCredential(key))
        }
    }
}
