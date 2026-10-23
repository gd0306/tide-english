import XCTest
@testable import TideEnglishCore

final class EmailAccountTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func exchange(_ changes: [String: Any] = [:]) throws -> EmailAccountExchange {
        var body: [String: Any] = ["accountID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "email":"preview@example.test", "accessToken":String(repeating:"a", count:43), "refreshToken":String(repeating:"b", count:43), "expiresInSeconds":900, "refreshExpiresInSeconds":2592000]
        body.merge(changes) { _, new in new }
        return try JSONDecoder().decode(EmailAccountExchange.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func testAccountOriginRejectsCredentialBearingURL() throws {
        XCTAssertThrowsError(try EmailAccountConfiguration(apiURL: "https://owner:secret@api.gd306.cn"))
    }
    func testTrustedOriginNormalizationAndScopeSeparation() throws {
        let a = try EmailAccountConfiguration(apiURL:"HTTPS://API.GD306.CN:443/")
        XCTAssertEqual(a.origin.absoluteString, "https://api.gd306.cn")
        XCTAssertNotEqual(a.storageScope, try EmailAccountConfiguration(apiURL:"https://other.example.test").storageScope)
        XCTAssertTrue(a.storageScope.hasPrefix("tideenglish.email-account.v1|"))
        for url in ["http://api.gd306.cn", "https://api.gd306.cn/a", "https://api.gd306.cn?x=1", "https://api.gd306.cn#x", "https://api.gd306.cn:0"] {
            XCTAssertThrowsError(try EmailAccountConfiguration(apiURL:url))
        }
        XCTAssertThrowsError(try a.endpoint("/v1/wallet"))
    }
    func testSessionRequiresNormalizedEmailIndependentTokensAndExactLifetimes() throws {
        let session = try EmailAccountSession(exchange: exchange(), scope:"scope", now:now)
        XCTAssertTrue(session.canRefresh(scope:"scope", now:now))
        XCTAssertFalse(session.canRefresh(scope:"other", now:now))
        XCTAssertFalse(session.canRefresh(scope:"scope", now:now.addingTimeInterval(2592000)))
        for bad in [["email":"Preview@example.test"], ["accessToken":"secret"], ["refreshToken":String(repeating:"a",count:43)], ["expiresInSeconds":901], ["refreshExpiresInSeconds":2592001], ["refreshExpiresInSeconds":0]] as [[String:Any]] {
            XCTAssertThrowsError(try EmailAccountSession(exchange:exchange(bad), scope:"scope", now:now))
        }
    }
    func testRefreshTTLMayBeShorterThanAccessTTL() throws {
        let session = try EmailAccountSession(exchange:exchange(["refreshExpiresInSeconds":1]), scope:"scope", now:now)
        XCTAssertTrue(session.accessIsUsable(scope:"scope", now:now))
        XCTAssertFalse(session.accessIsUsable(scope:"scope", now:now.addingTimeInterval(2)))
    }
    func testProfileAndRenewalMustKeepAccountAndMailbox() throws {
        let session = try EmailAccountSession(exchange:exchange(), scope:"scope", now:now)
        let good = try JSONDecoder().decode(EmailAccountProfile.self, from:Data("{\"accountID\":\"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa\",\"email\":\"preview@example.test\"}".utf8))
        try good.validate(session:session)
        XCTAssertThrowsError(try EmailAccountSession(exchange:exchange(["email":"other@example.test"]), scope:"scope", now:now, previous:session))
        XCTAssertThrowsError(try EmailAccountSession(exchange:exchange(["accountID":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"]), scope:"scope", now:now, previous:session))
        let mismatch = try JSONDecoder().decode(EmailAccountProfile.self, from:Data("{\"accountID\":\"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa\",\"email\":\"other@example.test\"}".utf8))
        XCTAssertThrowsError(try mismatch.validate(session:session))
    }
    func testSafeServerErrorsNeverEchoUnknownPayload() {
        XCTAssertEqual(EmailAccountError.server(code:"invalid_code"), .invalidCode)
        XCTAssertEqual(EmailAccountError.server(code:"invalid_session"), .invalidSession)
        XCTAssertEqual(EmailAccountError.server(code:"SMTP secret preview@example.test"), .unavailable)
        XCTAssertNotEqual(InterfaceText.string(EmailAccountError.invalidCode.message, language:.chinese), EmailAccountError.invalidCode.message)
    }
    func testRotationCannotReuseEitherOldTokenOrExtendFamilyExpiry() throws {
        let original = try EmailAccountSession(exchange:exchange(), scope:"scope", now:now)
        XCTAssertThrowsError(try EmailAccountSession(exchange:exchange(["accessToken":String(repeating:"b",count:43), "refreshToken":String(repeating:"a",count:43)]), scope:"scope", now:now, previous:original))
        let changes: [String:Any] = ["accessToken":String(repeating:"c",count:43), "refreshToken":String(repeating:"d",count:43)]
        let clamped = try EmailAccountSession(exchange:exchange(changes), scope:"scope", now:now.addingTimeInterval(10), previous:original)
        XCTAssertEqual(clamped.refreshExpiresAt, original.refreshExpiresAt)
        var valid = changes; valid["refreshExpiresInSeconds"] = 2591991
        let rotated = try EmailAccountSession(exchange:exchange(valid), scope:"scope", now:now.addingTimeInterval(10), previous:original)
        XCTAssertEqual(rotated.refreshExpiresAt, original.refreshExpiresAt)
    }
    func testDelayedValidRefreshClampsReceiptRelativeTTLToRetainedDeadline() throws {
        let original = try EmailAccountSession(exchange:exchange(), scope:"scope", now:now)
        let response = try exchange(["accessToken":String(repeating:"c",count:43), "refreshToken":String(repeating:"d",count:43), "refreshExpiresInSeconds":2591100])
        let received = now.addingTimeInterval(902)
        let renewed = try EmailAccountSession(exchange:response, scope:"scope", now:received, previous:original)
        XCTAssertEqual(renewed.refreshExpiresAt, original.refreshExpiresAt)
        XCTAssertTrue(renewed.accessIsUsable(scope:"scope", now:received))
        XCTAssertThrowsError(try EmailAccountSession(exchange:response, scope:"scope", now:original.refreshExpiresAt, previous:original))
    }
    func testChallengeLifetimeMatchesExactWireContract() throws {
        for retry in [0, 60, 61] {
            let dto = try JSONDecoder().decode(EmailAccountChallenge.self, from:JSONSerialization.data(withJSONObject:["challengeID":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "expiresInSeconds":300, "retryAfterSeconds":retry]))
            if retry == 60 { XCTAssertNoThrow(try dto.validate()) } else { XCTAssertThrowsError(try dto.validate()) }
        }
    }
    func testMailboxAndCodeMatchBackendValidation() throws {
        XCTAssertEqual(try EmailAccountValidation.email(" Preview@Example.test "), "preview@example.test")
        for value in ["a@example.test\n", "名@example.test", "Name <a@example.test>", "a..b@example.test", "a@localhost"] {
            XCTAssertThrowsError(try EmailAccountValidation.email(value))
        }
        XCTAssertTrue(EmailAccountValidation.code("123456"))
        XCTAssertFalse(EmailAccountValidation.code("１２３４５６"))
    }
}
