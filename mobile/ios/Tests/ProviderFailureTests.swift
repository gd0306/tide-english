import XCTest
@testable import TideEnglishCore

final class ProviderFailureTests: XCTestCase {
    func testPaymentRequiredIsAnAccountCreditFailureEvenWithoutAnErrorBody() {
        for body in [Data(), Data(#"{"error":{"code":"payment_required","message":"private account"}}"#.utf8)] {
            let failure = ProviderFailure(status: 402, body: body)
            XCTAssertEqual(failure.kind, .creditExhausted)
            XCTAssertFalse(failure.localizedDescription.contains("try again"))
            XCTAssertFalse(failure.localizedDescription.contains("private"))
        }
        XCTAssertEqual(ProviderFailure(status: 429).kind, .rateLimit)
        XCTAssertEqual(ProviderFailure(status: 401).kind, .authentication)
    }
    func testLiveDiagnosticRetainsOnlyValidatedNumericServerErrors() throws {
        let wire = Data(#"{"error":{"code":403,"status":"PERMISSION_DENIED","message":"private key and transcript"}}"#.utf8)
        let failure = try XCTUnwrap(ProviderDiagnosticFailure.fromLiveMessage(wire))
        XCTAssertEqual(failure.status, 403)
        XCTAssertEqual(failure.providerStatus, "PERMISSION_DENIED")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(failure), as: UTF8.self).contains("private"))
        for value in [#"{"error":{"code":true}}"#, #"{"error":{"code":403.5}}"#,
                      #"{"error":{"code":-1}}"#, #"{"error":{"code":99999999}}"#,
                      #"{"serverContent":{"error":{"code":403}}}"#, String(repeating: "x", count: 16_385)] {
            XCTAssertNil(ProviderDiagnosticFailure.fromLiveMessage(Data(value.utf8)))
        }
    }

    func testDiagnosticReportAllowsGoogleCodesButNeverPrivateDetails() throws {
        let body = Data(#"{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"private API key and prompt","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID","domain":"googleapis.com","metadata":{"consumer":"private project"}}]}}"#.utf8)
        let failure = ProviderDiagnosticFailure(status: 400, body: body)
        XCTAssertEqual(failure.status, 400)
        XCTAssertEqual(failure.providerStatus, "INVALID_ARGUMENT")
        XCTAssertEqual(failure.reason, "API_KEY_INVALID")
        let encoded = String(decoding: try JSONEncoder().encode(failure), as: UTF8.self)
        XCTAssertFalse(encoded.contains("private"))
        XCTAssertFalse(encoded.contains("message"))
        XCTAssertFalse(encoded.contains("metadata"))
    }

    func testDiagnosticReportRejectsUntrustedOrOversizedFields() throws {
        for body in [#"{"error":{"status":"private_secret","details":[{"reason":"private_secret"}]}}"#,
                     "not json", String(repeating: "x", count: 16_385)] {
            let failure = ProviderDiagnosticFailure(status: 403, body: Data(body.utf8))
            XCTAssertEqual(failure.status, 403)
            XCTAssertNil(failure.providerStatus)
            XCTAssertNil(failure.reason)
            let encoded = String(decoding: try JSONEncoder().encode(failure), as: UTF8.self)
            XCTAssertFalse(encoded.contains("private_secret"))
        }
        let unrelated = ProviderDiagnosticFailure(status: 403, body: Data(#"{"error":{"status":"PERMISSION_DENIED","details":[{"@type":"private","reason":"API_KEY_INVALID"}]}}"#.utf8))
        XCTAssertEqual(unrelated.providerStatus, "PERMISSION_DENIED")
        XCTAssertNil(unrelated.reason)
    }

    func testCreditAndTemporaryLimitsGiveDifferentRecoveryAdvice() {
        let quota = ProviderFailure(status: 429, body: Data(#"{"error":{"code":"insufficient_quota","message":"private billing data"}}"#.utf8), reference: "req_support")
        let rate = ProviderFailure(status: 429, body: Data(#"{"error":{"code":"rate_limit_exceeded"}}"#.utf8))
        XCTAssertEqual(quota.kind, .quota)
        XCTAssertEqual(rate.kind, .rateLimit)
        XCTAssertTrue(quota.errorDescription!.contains("billing"))
        XCTAssertTrue(rate.errorDescription!.contains("Wait"))
        XCTAssertFalse(quota.errorDescription!.contains("private"))
        XCTAssertTrue(quota.errorDescription!.contains("req_support"))
    }
    func testMalformedAndUntrustedProviderDetailsStayOutOfTheInterface() {
        for body in ["not json", #"{"error":{"code":"secret_value","message":"private"}}"#, String(repeating: "x", count: 16_385)] {
            let error = ProviderFailure(status: 503, body: Data(body.utf8), reference: "private\nheader")
            XCTAssertEqual(error.kind, .unavailable)
            XCTAssertNil(error.code); XCTAssertNil(error.reference)
            XCTAssertFalse(error.errorDescription!.contains("private"))
        }
        XCTAssertEqual(ProviderFailure(status: 401, body: Data(#"{"error":{"code":"insufficient_quota"}}"#.utf8)).kind, .authentication)
        XCTAssertEqual(ProviderFailure(status: 403).kind, .modelAccess)
    }
    func testSpecificBillingCodesAreNotMistakenForTemporaryRateLimits() {
        let cases: [(String, ProviderFailureKind)] = [
            ("credit_balance_exhausted", .creditExhausted),
            ("organization_spend_limit_exceeded", .spendLimit),
            ("project_spend_limit_exceeded", .spendLimit),
            ("organization_usage_limit_exceeded", .usageLimit),
            ("insufficient_quota", .quota),
            ("slow_down", .rateLimit)
        ]
        for (code, expected) in cases {
            let body = Data("{\"error\":{\"code\":\"\(code)\",\"message\":\"private billing details\"}}".utf8)
            let failure = ProviderFailure(status: 429, body: body)
            XCTAssertEqual(failure.kind, expected, code)
            XCTAssertFalse(failure.localizedDescription.contains("private billing details"))
            XCTAssertEqual(ProviderFailure(status: 401, body: body).kind, .authentication)
        }
    }
    func testRealtimeBillingFailureUsesTheSameSafeRecovery() {
        XCTAssertEqual(ProviderFailure.fromRealtime(code: "credit_balance_exhausted")?.kind, .creditExhausted)
        XCTAssertEqual(ProviderFailure.fromRealtime(code: "project_spend_limit_exceeded")?.kind, .spendLimit)
        XCTAssertEqual(ProviderFailure.fromRealtime(code: "invalid_api_key")?.kind, .authentication)
        XCTAssertNil(ProviderFailure.fromRealtime(code: "slow_down"))
        XCTAssertNil(ProviderFailure.fromRealtime(code: "private_api_key_here"))
    }
}
