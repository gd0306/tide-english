import XCTest
@testable import TideEnglishCore

final class ProviderConsentTests: XCTestCase {
    func testGeminiConsentCannotReuseOpenAIOrLegacyConsent() throws {
        var openAI = ProviderConfiguration(provider: .openAI)
        var gemini = ProviderConfiguration(provider: .gemini)
        openAI.model = "shared-model"
        gemini.model = "shared-model"
        let openAIIdentity = try ProviderConsent.identity(for: openAI)
        let geminiIdentity = try ProviderConsent.identity(for: gemini)
        XCTAssertNotEqual(openAIIdentity, geminiIdentity)
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: gemini, version: 1, requiredVersion: 1, acceptedIdentity: nil))
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: gemini, version: 1, requiredVersion: 1, acceptedIdentity: openAIIdentity))
        XCTAssertTrue(ProviderConsent.isAllowed(configuration: gemini, version: 1, requiredVersion: 1, acceptedIdentity: geminiIdentity))
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: openAI, version: 1, requiredVersion: 1, acceptedIdentity: geminiIdentity))
    }
    func testLegacyOpenAIConsentCannotAuthorizeAnotherSupplier() throws {
        XCTAssertTrue(ProviderConsent.isAllowed(configuration: .init(provider: .openAI), version: 1, requiredVersion: 1, acceptedIdentity: nil))
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: .init(provider: .deepSeek), version: 1, requiredVersion: 1, acceptedIdentity: nil))
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: .init(provider: .glm), version: 1, requiredVersion: 1, acceptedIdentity: nil))
    }
    func testSameHostWithAnotherCustomPathCannotReuseConsent() throws {
        var first = ProviderConfiguration(provider: .custom)
        first.model = "chat"
        first.baseURL = "https://example.com/one"
        var second = first; second.baseURL = "https://example.com/two"
        let identity = try ProviderConsent.identity(for: first)
        XCTAssertTrue(ProviderConsent.isAllowed(configuration: first, version: 1, requiredVersion: 1, acceptedIdentity: identity))
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: second, version: 1, requiredVersion: 1, acceptedIdentity: identity))
    }
    func testWithdrawalAndInvalidDestinationAlwaysDenyProcessing() throws {
        let configuration = ProviderConfiguration(provider: .glm)
        let identity = try ProviderConsent.identity(for: configuration)
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: configuration, version: nil, requiredVersion: 1, acceptedIdentity: identity))
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: configuration, version: 0, requiredVersion: 1, acceptedIdentity: identity))
        var unsafe = ProviderConfiguration(provider: .custom); unsafe.baseURL = "http://example.com"
        XCTAssertFalse(ProviderConsent.isAllowed(configuration: unsafe, version: 1, requiredVersion: 1, acceptedIdentity: identity))
    }
}
