import XCTest

final class TideEnglishUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func emailPreview(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=deepSeek", "--preview-email-account", "--screenshot=words"] + (extra.contains(where: { $0.hasPrefix("--preview-interface-language=") }) ? [] : ["--preview-interface-language=english"]) + extra
        app.launch()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["email-account-settings"].waitForExistence(timeout: 5))
        app.buttons["email-account-settings"].tap()
        return app
    }
    private func emailLogin(_ app: XCUIApplication) {
        let email = app.textFields["email-account-address"]
        XCTAssertTrue(email.waitForExistence(timeout: 5)); email.tap(); email.typeText("preview@example.test\n")
        app.buttons["email-account-send"].tap()
        let code = app.textFields["email-account-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5)); code.tap(); code.typeText("123456")
        app.buttons["email-account-continue"].tap()
        XCTAssertTrue(app.staticTexts["email-account-profile"].waitForExistence(timeout: 5))
    }
    func testEmailAccountInvalidCodeRecoveryAndLocalSignOut() {
        let app = emailPreview(["--preview-email-offline-signout"])
        let email = app.textFields["email-account-address"]
        email.tap(); email.typeText("preview@example.test\n"); app.buttons["email-account-send"].tap()
        let code = app.textFields["email-account-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5)); code.tap(); code.typeText("000000")
        app.buttons["email-account-continue"].tap()
        XCTAssertTrue(app.staticTexts["email-account-message"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["email-account-message"].label, "That code is invalid or expired. Try again or request a new code.")
        XCTAssertFalse(app.buttons["email-account-send"].isEnabled)
        code.tap(); code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "123456")
        app.buttons["email-account-continue"].tap()
        XCTAssertTrue(app.staticTexts["email-account-profile"].waitForExistence(timeout: 5))
        app.buttons["email-account-sign-out"].tap(); app.alerts.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["email-account-address"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["email-account-message"].label, "Signed out on this iPhone. The server could not be reached; this session may remain active until it expires.")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].label.contains("DeepSeek"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["vocabulary-learning-definition"].firstMatch.exists)
    }
    func testEmailAccountSyntheticKeychainRelaunchAndFreshCodeDeletion() {
        let app = emailPreview(["--verify-email-account-keychain", "--verify-email-account-keychain-reset"])
        emailLogin(app)
        app.terminate(); app.launchArguments.removeAll { $0 == "--verify-email-account-keychain-reset" }; app.launch(); app.buttons["settings-button"].tap(); app.buttons["email-account-settings"].tap()
        XCTAssertTrue(app.staticTexts["email-account-profile"].waitForExistence(timeout: 5))
        app.buttons["email-account-delete"].tap(); app.alerts.buttons["Send deletion code"].tap()
        if !app.textFields["email-account-code"].exists {
            let send = app.buttons["email-account-send"]
            expectation(for:NSPredicate(format:"enabled == true"), evaluatedWith:send)
            waitForExpectations(timeout:65)
            send.tap()
        }
        let code = app.textFields["email-account-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5)); code.tap(); code.typeText("123456")
        app.buttons["email-account-confirm-delete"].tap()
        XCTAssertTrue(app.textFields["email-account-address"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].label.contains("DeepSeek"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["vocabulary-learning-definition"].firstMatch.exists)
    }
    private func verifyEmailRenewal(_ mode: String) {
        let app = emailPreview(["--verify-email-account-renewal=" + mode])
        let result = app.staticTexts["email-account-verification"]
        XCTAssertTrue(result.waitForExistence(timeout:10)); XCTAssertEqual(result.label,"passed")
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].label.contains("DeepSeek"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["vocabulary-learning-definition"].firstMatch.exists)
    }
    private func verifyEmailLogout(_ mode: String) {
        let app = emailPreview(["--verify-email-account-logout=" + mode])
        let result = app.staticTexts["email-account-verification"]
        XCTAssertTrue(result.waitForExistence(timeout:10)); XCTAssertEqual(result.label,"passed")
    }
    func testEmailAccountFailedClearCanRetryAfterReopenAndRelaunch() { verifyEmailLogout("clear") }
    func testEmailAccountLogoutStorageAndNetworkFailureRemainRetryable() { verifyEmailLogout("network") }
    func testEmailAccountFailedClearKeepsVisibleRetryAction() {
        let app = emailPreview(["--verify-email-account-logout=screen"])
        XCTAssertTrue(app.buttons["email-account-sign-out"].waitForExistence(timeout:5))
        app.buttons["email-account-sign-out"].tap(); app.alerts.buttons["Sign out"].tap()
        let retry = app.buttons["email-account-retry-sign-out"]
        XCTAssertTrue(retry.waitForExistence(timeout:5)); XCTAssertTrue(retry.isEnabled)
        XCTAssertFalse(app.textFields["email-account-address"].exists)
        app.navigationBars.buttons.element(boundBy:0).tap(); app.buttons["email-account-settings"].tap()
        XCTAssertTrue(retry.waitForExistence(timeout:5)); retry.tap()
        XCTAssertTrue(app.textFields["email-account-address"].waitForExistence(timeout:5))
    }
    func testEmailAccountSyntheticLogoutIntentPreventsRestoredLogin() {
        let app = emailPreview(["--verify-email-account-keychain", "--verify-email-account-keychain-reset", "--verify-email-account-logout=intent-prepare"])
        XCTAssertTrue(app.staticTexts["email-account-verification"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["email-account-verification"].label,"passed")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--verify-email-account-keychain-reset" || $0.hasPrefix("--verify-email-account-logout=") }
        app.launchArguments.append("--verify-email-account-logout=intent-after-relaunch")
        app.launch(); app.buttons["settings-button"].tap(); app.buttons["email-account-settings"].tap()
        XCTAssertTrue(app.staticTexts["email-account-verification"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["email-account-verification"].label,"passed")
    }
    func testEmailAccountNavigationRetainsOwnedRefresh() { verifyEmailRenewal("navigation") }
    func testEmailAccountLogoutRevokesLateRefresh() { verifyEmailRenewal("logout") }
    func testEmailAccountDeletionWaitsForRotationAndRetiresIdentity() { verifyEmailRenewal("deletion") }
    func testEmailAccountAmbiguousRotationCannotReplayToken() { verifyEmailRenewal("ambiguous") }
    func testEmailAccountSyntheticPendingRotationCannotReplayAfterRelaunch() {
        let app = emailPreview(["--verify-email-account-keychain", "--verify-email-account-keychain-reset", "--verify-email-account-renewal=marker-prepare"])
        XCTAssertTrue(app.staticTexts["email-account-verification"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["email-account-verification"].label,"passed")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--verify-email-account-keychain-reset" || $0.hasPrefix("--verify-email-account-renewal=") }
        app.launchArguments.append("--verify-email-account-renewal=marker-after-relaunch")
        app.launch(); app.buttons["settings-button"].tap(); app.buttons["email-account-settings"].tap()
        XCTAssertTrue(app.staticTexts["email-account-verification"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["email-account-verification"].label,"passed")
    }
    func testEmailAccountOverlappingRefreshUsesOneReplacement() {
        let app = emailPreview(["--preview-email-renewal", "--verify-email-account-single-flight"])
        let result = app.staticTexts["email-account-verification"]
        XCTAssertTrue(result.waitForExistence(timeout:5))
        XCTAssertEqual(result.label, "passed")
    }
    func testEmailAccountExpiredAccessRenewsSyntheticSession() {
        let app = emailPreview(["--preview-email-renewal"])
        let profile = app.staticTexts["email-account-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout:5))
        expectation(for:NSPredicate(format:"value == %@", "Signed in"), evaluatedWith:profile)
        waitForExpectations(timeout:5)
        app.buttons["email-account-sign-out"].tap(); app.alerts.buttons["Sign out"].tap()
        XCTAssertTrue(app.textFields["email-account-address"].waitForExistence(timeout:5))
    }
    func testEmailAccountResendCountdownReplacesCodeChallenge() {
        let app = emailPreview()
        let email = app.textFields["email-account-address"]
        email.tap(); email.typeText("preview@example.test\n"); app.buttons["email-account-send"].tap()
        XCTAssertTrue(app.textFields["email-account-code"].waitForExistence(timeout:5))
        let send = app.buttons["email-account-send"]
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(send.label.hasPrefix("Resend in "))
        expectation(for:NSPredicate(format:"enabled == true"), evaluatedWith:send)
        waitForExpectations(timeout:65)
        send.tap()
        let code = app.textFields["email-account-code"]
        code.tap(); code.typeText("123456"); app.buttons["email-account-continue"].tap()
        XCTAssertTrue(app.staticTexts["email-account-profile"].waitForExistence(timeout:5))
    }
    func testEmailAccountPreviewErrorsAreSafeAndRetryable() {
        for (flag, text) in [("--preview-email-network-error", "Couldn’t reach the account service. Check your connection and try again."), ("--preview-email-rate-limit", "Too many requests. Wait a minute and try again.")] {
            let app = emailPreview([flag]); let email = app.textFields["email-account-address"]
            email.tap(); email.typeText("preview@example.test\n"); app.buttons["email-account-send"].tap()
            XCTAssertTrue(app.staticTexts["email-account-message"].waitForExistence(timeout:5))
            XCTAssertEqual(app.staticTexts["email-account-message"].label, text)
            XCTAssertTrue(app.buttons["email-account-send"].isEnabled)
            app.terminate()
        }
    }
    func testEmailAccountCancelledLoginCannotResurrectSession() {
        let app = emailPreview(["--preview-email-delayed-verify"])
        let email = app.textFields["email-account-address"]
        email.tap(); email.typeText("preview@example.test\n"); app.buttons["email-account-send"].tap()
        let code = app.textFields["email-account-code"]
        XCTAssertTrue(code.waitForExistence(timeout:5)); code.tap(); code.typeText("123456")
        app.buttons["email-account-continue"].tap()
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.buttons["email-account-settings"].tap()
        XCTAssertFalse(app.staticTexts["email-account-profile"].waitForExistence(timeout:5))
        XCTAssertTrue(app.textFields["email-account-address"].exists)
    }
    func testEmailAccountChineseAndActiveConversationGuard() {
        let app = emailPreview(["--preview-interface-language=chinese", "--active-conversation"])
        XCTAssertTrue(app.navigationBars["账户"].exists)
        XCTAssertFalse(app.buttons["email-account-send"].isEnabled)
        XCTAssertTrue(app.textFields["email-account-address"].exists)
    }

    func testVocabularyPageWorkDoesNotBlockNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--verify-page-performance",
                               "--preview-interface-language=english"]
        app.launch()
        let probe = app.buttons["vocabulary-performance"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        probe.tap()
        let report = (probe.value as? String ?? "").split(separator: "|")
        XCTAssertEqual(report.first, "100", "Every synthetic definition must remain readable offline")
        let milliseconds = report.count == 2 ? Int(report[1]) ?? Int.max : Int.max
        let timing = XCTAttachment(string: "100 synthetic vocabulary reads/requests: \(milliseconds)ms")
        timing.name = "page-performance-main-thread"
        timing.lifetime = .keepAlways
        add(timing)
        XCTAssertLessThan(milliseconds, 500, "100 definition reads/requests must not monopolize the main thread: \(milliseconds)ms")
        for _ in 0..<2 {
            app.buttons["tab-words"].tap()
            XCTAssertTrue(app.staticTexts["Your words."].waitForExistence(timeout: 3))
            app.buttons["tab-themes"].tap()
            app.buttons["tab-talk"].tap()
            XCTAssertTrue(app.buttons["start-conversation"].exists)
        }
    }

    func testVocabularyIndexRejectsRemovedOrChangedSources() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--verify-page-performance",
                               "--verify-vocabulary-invalidation", "--preview-interface-language=english"]
        app.launch()
        let probe = app.buttons["vocabulary-performance"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10))
        probe.tap()
        XCTAssertEqual(probe.value as? String, "passed", "Indexed definitions must invalidate on hide, correction, deletion, meaning/learning language switches and erasure")
    }

    private func bilingualVocabularyPreview(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=deepSeek", "--screenshot=words",
                               "--preview-vocabulary", "--preview-interface-language=english"] + extra
        app.launch()
        return app
    }

    private func keepVocabularyScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testVocabularyShowsLearningAndChineseDefinitions() {
        let app = bilingualVocabularyPreview(extra: ["--verify-interface-lifecycle"])
        let chinese = app.staticTexts["vocabulary-meaning-definition"].firstMatch
        XCTAssertTrue(chinese.waitForExistence(timeout: 10), "Saved vocabulary must display the selected meaning language")
        XCTAssertEqual(chinese.label, "旅程；从一个地方到另一个地方的旅行。")
        XCTAssertEqual(app.staticTexts["vocabulary-learning-definition"].firstMatch.label, "a trip from one place to another")
        XCTAssertTrue(app.buttons["vocabulary-meaning-language"].exists)
        let constructionCount = app.buttons["coordinator-construction-count"]
        constructionCount.tap()
        XCTAssertEqual(constructionCount.value as? String, "1", "Derived cache writes must preserve the existing coordinator and invalidation callbacks")
        keepVocabularyScreenshot(app, name: "vocabulary-paper-english")
        app.buttons["settings-button"].tap()
        app.buttons["settings-interface-language"].tap()
        app.buttons["中文"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(chinese.label, "旅程；从一个地方到另一个地方的旅行。", "Interface language must not replace generated vocabulary content")
        XCTAssertEqual(app.staticTexts["vocabulary-learning-definition"].firstMatch.label, "a trip from one place to another")
        constructionCount.tap()
        XCTAssertEqual(constructionCount.value as? String, "1")
        keepVocabularyScreenshot(app, name: "vocabulary-paper-chinese")
    }

    func testChineseVocabularySearchAndBilingualDetail() {
        let app = bilingualVocabularyPreview(extra: ["--preview-interface-theme=midnight"])
        XCTAssertTrue(app.staticTexts["vocabulary-meaning-definition"].firstMatch.waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("旅程")
        XCTAssertTrue(app.staticTexts["journey"].exists)
        XCTAssertFalse(app.staticTexts["look after"].exists)
        app.buttons["vocabulary-word-journey"].tap()
        let chinese = app.staticTexts["word-detail-meaning-definition"]
        XCTAssertTrue(chinese.waitForExistence(timeout: 5))
        XCTAssertEqual(chinese.label, "旅程；从一个地方到另一个地方的旅行。")
        XCTAssertEqual(app.staticTexts["word-detail-learning-definition"].label, "a trip from one place to another")
        keepVocabularyScreenshot(app, name: "vocabulary-detail-midnight")
    }

    func testFlashcardsRevealBothVocabularyLanguages() {
        let app = bilingualVocabularyPreview(extra: ["--preview-interface-theme=grove"])
        XCTAssertTrue(app.staticTexts["vocabulary-meaning-definition"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["open-flashcards"].tap()
        XCTAssertTrue(app.staticTexts["flashcard-word"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["flashcard-meaning-selected"].exists)
        app.buttons["reveal-flashcard"].tap()
        XCTAssertTrue(app.staticTexts["flashcard-meaning-selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["flashcard-meaning"].label, "a trip from one place to another")
        XCTAssertEqual(app.staticTexts["flashcard-meaning-selected"].label, "旅程；从一个地方到另一个地方的旅行。")
        keepVocabularyScreenshot(app, name: "vocabulary-card-grove")
        let pager = app.descendants(matching: .any)["flashcard-pager"].firstMatch
        pager.swipeLeft()
        let nextPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "2 of 2"), object: pager)
        XCTAssertEqual(XCTWaiter.wait(for: [nextPage], timeout: 3), .completed)
        XCTAssertFalse(app.staticTexts["flashcard-meaning-selected"].exists, "A new card starts unrevealed")
    }

    func testVocabularyMeaningLanguageSwitchDoesNotShowStaleChinese() {
        let app = bilingualVocabularyPreview()
        let meaning = app.staticTexts["vocabulary-meaning-definition"].firstMatch
        XCTAssertTrue(meaning.waitForExistence(timeout: 10))
        app.buttons["vocabulary-meaning-language"].tap()
        app.buttons["French"].tap()
        let french = NSPredicate(format: "label == %@", "un voyage")
        expectation(for: french, evaluatedWith: meaning)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.staticTexts["旅程；从一个地方到另一个地方的旅行。"].exists)
        XCTAssertEqual(app.staticTexts["vocabulary-learning-definition"].firstMatch.label, "a trip from one place to another")
    }

    func testVocabularyFailureRequiresRetryAndKeepsEnglishReference() {
        let app = bilingualVocabularyPreview(extra: ["--preview-vocabulary-failure"])
        let retry = app.buttons["vocabulary-retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["a trip from one place to another"].exists)
        XCTAssertFalse(app.staticTexts["vocabulary-meaning-definition"].firstMatch.exists)
        retry.tap()
        let meaning = app.staticTexts["vocabulary-meaning-definition"].firstMatch
        XCTAssertTrue(meaning.waitForExistence(timeout: 10))
        XCTAssertEqual(meaning.label, "旅程；从一个地方到另一个地方的旅行。")
    }

    func testBilingualVocabularyIgnoresSubtitleVisibilityAndSupportsLargeText() {
        let app = bilingualVocabularyPreview(extra: ["--preview-vocabulary-hidden-subtitles",
                                                      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let chinese = app.staticTexts["vocabulary-meaning-definition"].firstMatch
        XCTAssertTrue(chinese.waitForExistence(timeout: 10))
        XCTAssertEqual(chinese.label, "旅程；从一个地方到另一个地方的旅行。")
        let word = app.buttons["vocabulary-word-journey"]
        revealInterfaceControl(word, in: app)
        word.tap()
        let definition = app.staticTexts["word-detail-meaning-definition"]
        revealInterfaceControl(definition, in: app)
        XCTAssertTrue(definition.isHittable)
        XCTAssertTrue(app.buttons["Done"].isHittable)
        keepVocabularyScreenshot(app, name: "vocabulary-detail-large-text")
    }

    func testVocabularyConsentEnablesDefinitionsWithoutStartingConversation() {
        let app = bilingualVocabularyPreview(extra: ["--preview-vocabulary-without-consent"])
        XCTAssertTrue(app.staticTexts["a trip from one place to another"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["vocabulary-meaning-definition"].firstMatch.exists)
        let consent = app.buttons["vocabulary-consent"].firstMatch
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.tap()
        XCTAssertTrue(app.buttons["ai-consent-agree"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-agree"].tap()
        XCTAssertTrue(app.staticTexts["vocabulary-meaning-definition"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["tab-talk"].tap()
        XCTAssertTrue(app.buttons["start-conversation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["End conversation"].exists)
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
    }

    func testInterfaceLanguageChangesControlsButPreservesLearningCaption() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--screenshot=greeting", "--preview-interface-language=english"]
        app.launch()
        let caption = app.staticTexts["target-caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 5))
        let learningCaption = caption.label
        app.buttons["Settings"].tap()
        let language = app.buttons["settings-interface-language"]
        XCTAssertTrue(language.waitForExistence(timeout: 5), "Interface language must be independent of learning-language settings")
        language.tap()
        app.buttons["中文"].tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].label.contains("模型与 API Key"))
        app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["tab-talk"].label, "对话")
        XCTAssertEqual(app.buttons["tab-themes"].label, "话题")
        XCTAssertEqual(app.buttons["tab-words"].label, "词汇")
        XCTAssertEqual(caption.label, learningCaption, "UI language must preserve actual learning-language content")
        app.buttons["settings-button"].tap()
        app.buttons["settings-interface-language"].tap()
        app.buttons["English"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["tab-talk"].label, "Talk")
        XCTAssertEqual(caption.label, learningCaption)
    }

    func testThreeInterfaceThemesRemainSelectedAcrossMainScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--screenshot=greeting", "--preview-interface-language=english", "--preview-interface-theme=paper"]
        app.launch()
        app.buttons["Settings"].tap()
        let paper = app.buttons["interface-theme-paper"]
        XCTAssertTrue(paper.waitForExistence(timeout: 5))
        XCTAssertTrue(paper.isSelected)
        app.buttons["interface-theme-midnight"].tap()
        XCTAssertTrue(app.buttons["interface-theme-midnight"].isSelected)
        app.buttons["Done"].tap()
        app.buttons["tab-themes"].tap()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["interface-theme-midnight"].isSelected)
        app.buttons["interface-theme-grove"].tap()
        XCTAssertTrue(app.buttons["interface-theme-grove"].isSelected)
        app.buttons["Done"].tap()
        app.buttons["tab-words"].tap()
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["interface-theme-grove"].isSelected)
        app.buttons["interface-theme-paper"].tap()
        XCTAssertTrue(app.buttons["interface-theme-paper"].isSelected)
    }

    func testChineseModelEditorLocalizesControlsAndPreservesModelIdentifiers() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=deepSeek", "--preview-interface-language=chinese", "--preview-interface-theme=midnight"]
        app.launch()
        app.buttons["settings-button"].tap()
        app.buttons["settings-model-provider"].tap()
        XCTAssertTrue(app.navigationBars["模型提供方"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["model-chat-model"].value as? String, "deepseek-flash")
        XCTAssertEqual(app.secureTextFields.matching(identifier: "api-key").count, 1)
        XCTAssertTrue(app.buttons["完成"].exists)
        let provider = app.buttons["model-provider-picker"]
        provider.tap()
        app.buttons["Gemini"].tap()
        XCTAssertEqual(app.textFields["model-chat-model"].value as? String, "gemini-3.8-flash")
        XCTAssertTrue(app.descendants(matching: .any)["model-key-status"].label.contains("未保存密钥"))
        let save = app.buttons["model-save"]
        revealInterfaceControl(save, in: app)
        XCTAssertEqual(save.label, "保存模型设置")
    }

    func testChangingInterfacePresentationPreservesActiveConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=deepSeek", "--active-conversation", "--preview-interface-language=english"]
        app.launch()
        XCTAssertTrue(app.buttons["End conversation"].waitForExistence(timeout: 5))
        app.buttons["start-conversation"].tap()
        XCTAssertEqual(app.buttons["start-conversation"].label, "Unmute microphone")
        let caption = app.staticTexts["target-caption"].label
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["settings-model-provider"].isEnabled)
        XCTAssertTrue(app.buttons["interface-theme-midnight"].isEnabled)
        app.buttons["interface-theme-midnight"].tap()
        app.buttons["settings-interface-language"].tap()
        app.buttons["中文"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["结束对话"].exists)
        XCTAssertEqual(app.buttons["start-conversation"].label, "取消麦克风静音", "Presentation changes must preserve the existing coordinator's mute state")
        XCTAssertEqual(app.staticTexts["target-caption"].label, caption)
    }

    func testPersonalSettingsKeepEssentialControlsAndRemoveUsageStatistics() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--preview-interface-language=english"]
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].isHittable)
        XCTAssertTrue(app.buttons["settings-interface-language"].waitForExistence(timeout: 5))
        for _ in 0..<5 {
            XCTAssertFalse(app.staticTexts["Recorded voice time"].exists)
            XCTAssertFalse(app.staticTexts["Search calls recorded"].exists)
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Learning backup & data"].exists)
        XCTAssertTrue(app.buttons["settings-ai-processing"].exists)
        XCTAssertTrue(app.buttons["About Tide English"].exists)
    }

    func testInterfacePreferencesSurviveNormalRelaunch() {
        let app = XCUIApplication()
        app.launch()
        if app.buttons["onboarding-continue"].waitForExistence(timeout: 3) {
            for _ in 0..<2 {
                if app.switches["onboarding-adult-confirmation"].exists { confirmAdult(in: app) }
                app.buttons["onboarding-continue"].tap()
            }
        }
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 10))
        app.buttons["settings-button"].tap()
        app.buttons["interface-theme-grove"].tap()
        app.buttons["settings-interface-language"].tap()
        app.buttons["中文"].tap()
        app.buttons["完成"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-talk"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tab-talk"].label, "对话")
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["interface-theme-grove"].isSelected)
        // Restore the Simulator's ordinary presentation. No phone or model data
        // is reset; preview tests never use this persistent preference store.
        app.buttons["interface-theme-paper"].tap()
        app.buttons["settings-interface-language"].tap()
        app.buttons["English"].tap()
        app.buttons["Done"].tap()
    }

    func testChinesePinyinControlsPreserveOriginalReading() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--screenshot=mandarin", "--preview-interface-language=chinese"]
        app.launch()
        let toggle = app.buttons["pinyin-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let reading = app.staticTexts["pinyin-reading"].label
        XCTAssertEqual(toggle.label, "隐藏拼音")
        toggle.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label == %@", "显示拼音"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["pinyin-reading"].exists)
        toggle.tap()
        XCTAssertEqual(app.staticTexts["pinyin-reading"].label, reading)
        app.buttons["settings-button"].tap()
        app.buttons["settings-interface-language"].tap()
        app.buttons["English"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(toggle.label, "Hide pinyin")
        XCTAssertEqual(app.staticTexts["pinyin-reading"].label, reading)
    }

    func testChineseInterfaceAtLargestTextSizeKeepsControlsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--preview-interface-language=chinese", "--preview-interface-theme=midnight", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let mic = app.buttons["start-conversation"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5))
        revealInterfaceControl(mic, in: app)
        XCTAssertTrue(mic.isHittable)
        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].isHittable)
        let language = app.buttons["settings-interface-language"]
        revealInterfaceControl(language, in: app)
        XCTAssertTrue(language.isHittable)
        let grove = app.buttons["interface-theme-grove"]
        revealInterfaceControl(grove, in: app)
        grove.tap()
        XCTAssertTrue(grove.isSelected)
    }

    private func revealInterfaceControl(_ element: XCUIElement, in app: XCUIApplication) {
        // Talk uses a ScrollView; Settings uses a Form. Neither has the
        // onboarding footer assumed by the onboarding-only reveal helper.
        for _ in 0..<10 {
            if !element.exists { app.swipeUp(); continue }
            let top = app.frame.minY + 120
            let bottom = app.frame.maxY - 100
            if element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            let shift = element.frame.midY < top ? 220.0 : -220.0
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: shift)))
        }
        XCTAssertTrue(element.isHittable)
    }
    func testNativeVoiceEngineEnablesEchoCancellationWithoutCapture() {
        let app = XCUIApplication()
        app.launchArguments = ["--verify-echo"]
        app.launch()
        let status = app.staticTexts["echo-check-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "label == %@", "Echo cancellation enabled")
        expectation(for: enabled, evaluatedWith: status)
        waitForExpectations(timeout: 10)
    }

    private func confirmAdult(in app: XCUIApplication) {
        let control = app.switches["onboarding-adult-confirmation"]
        XCTAssertTrue(control.exists)
        if app.launchArguments.contains("UICTContentSizeCategoryAccessibilityXXXL") { reveal(control, in: app) }
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(control.value as? String, "1")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let viewport = app.scrollViews.firstMatch
            let footer = app.buttons["onboarding-continue"].frame
            let top = max(110, viewport.frame.minY)
            let bottom = min(viewport.frame.maxY, footer.minY - 4)
            if element.isHittable && element.frame.minY >= top && element.frame.maxY < bottom { return }
            let desiredCenter = (top + bottom) / 2
            let shift = max(-viewport.frame.height * 0.3, min(viewport.frame.height * 0.3, desiredCenter - element.frame.midY))
            let start = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: shift))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }

    private func selectOnboardingLanguage(_ id: String, in app: XCUIApplication) {
        let picker = app.buttons["onboarding-language-picker"]
        reveal(picker, in: app)
        picker.tap()
        let choice = app.buttons["onboarding-language-\(id)"]
        let menu = app.collectionViews.firstMatch
        for _ in 0..<6 {
            if choice.exists && choice.isHittable { break }
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.swipeUp()
        }
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertTrue(choice.isHittable)
        choice.tap()
    }

    private func checkNewOnboarding(id: String, greeting: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        let picker = app.buttons["onboarding-language-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        selectOnboardingLanguage(id, in: app)
        XCTAssertTrue(picker.exists)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Language selection - \(id)"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        confirmAdult(in: app)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, greeting)
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Hi!")
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
        XCTAssertEqual(app.buttons["start-conversation"].label, "Start conversation")
        if id == "zh" {
            XCTAssertEqual(app.staticTexts["pinyin-reading"].label, "nǐhǎo！")
            app.buttons["pinyin-toggle"].tap()
            XCTAssertFalse(app.staticTexts["pinyin-reading"].exists)
            app.buttons["pinyin-toggle"].tap()
            XCTAssertTrue(app.staticTexts["pinyin-reading"].exists)
        }
    }

    func testTagalogOnboarding() { checkNewOnboarding(id: "tl", greeting: "Kumusta!") }

    private func checkOnboardingOrangeEdge(left: Bool, agreement: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        let button = app.buttons["onboarding-continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        selectOnboardingLanguage("es", in: app)
        if agreement {
            button.tap()
            XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
            confirmAdult(in: app)
        }
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isHittable)
        let appFrame = app.frame
        // The visible capsule fills the screen minus the footer's 26-point margins.
        let x = left ? appFrame.minX + 40 : appFrame.maxX - 40
        let y = button.frame.midY
        XCTAssertTrue(appFrame.contains(CGPoint(x: x, y: y)))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(agreement ? "Agree" : "Continue") \(left ? "left" : "right") orange edge before tap"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTContext.runActivity(named: "Tap orange edge at (\(x), \(y)); accessibility frame \(button.frame)") { _ in
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: x - appFrame.minX, dy: y - appFrame.minY)).tap()
        }
        if agreement {
            XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5),
                          "Tapping the visible orange agreement capsule must finish onboarding")
        } else {
            XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5),
                          "Tapping the visible orange Continue capsule must advance to meanings")
        }
    }

    func testOnboardingContinueRespondsToLeftOrangeEdge() {
        checkOnboardingOrangeEdge(left: true, agreement: false)
    }
    func testOnboardingContinueRespondsToRightOrangeEdge() {
        checkOnboardingOrangeEdge(left: false, agreement: false)
    }
    func testOnboardingAgreeRespondsToLeftOrangeEdge() {
        checkOnboardingOrangeEdge(left: true, agreement: true)
    }
    func testOnboardingAgreeRespondsToRightOrangeEdge() {
        checkOnboardingOrangeEdge(left: false, agreement: true)
    }

    func testOnboardingAgreementRemainsDisabledUntilAdultConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        let button = app.buttons["onboarding-continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        XCTAssertFalse(button.isEnabled)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].exists)
        XCTAssertFalse(button.isEnabled)
        confirmAdult(in: app)
        XCTAssertTrue(button.isEnabled)
        button.tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
    }

    func testGermanOnboarding() { checkNewOnboarding(id: "de", greeting: "Hallo!") }
    func testItalianOnboarding() { checkNewOnboarding(id: "it", greeting: "Ciao!") }
    func testBrazilianPortugueseOnboarding() { checkNewOnboarding(id: "pt", greeting: "Olá!") }
    func testGreekOnboarding() { checkNewOnboarding(id: "el", greeting: "Γεια σου!") }
    func testSerbianOnboarding() { checkNewOnboarding(id: "sr", greeting: "Zdravo!") }
    func testMandarinOnboardingWithOptionalPinyin() { checkNewOnboarding(id: "zh", greeting: "你好！") }

    func testMandarinSelectionAtLargestAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let picker = app.buttons["onboarding-language-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        selectOnboardingLanguage("zh", in: app)
        XCTAssertTrue(picker.exists)
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        let privacy = app.descendants(matching: .any).matching(identifier: "onboarding-privacy-policy").firstMatch
        reveal(privacy, in: app)
        XCTAssertTrue(app.staticTexts["onboarding-ai-consent"].exists)
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        confirmAdult(in: app)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Mandarin onboarding - largest accessibility text"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "你好！")
    }

    func testNewLanguageSettingsThemesWordsAndReturnToNorwegian() {
        let app = launch()
        for (selection, name, greeting, theme) in [
            ("German · Germany", "German", "Hallo!", "Ein Kaffee?"),
            ("Italian · Italy", "Italian", "Ciao!", "Un caffè?"),
            ("Portuguese · Brazil", "Portuguese", "Olá!", "Um cafezinho?"),
            ("Mandarin Chinese · Mainland China", "Mandarin Chinese", "你好！", "喝杯咖啡？"),
            ("Tagalog (Filipino) · Philippines", "Tagalog (Filipino)", "Kumusta!", "Kape tayo?"),
            ("Dutch · Netherlands", "Dutch", "Hoi!", "Een koffie?"),
            ("Russian · Standard", "Russian", "Привет!", "Выпьем кофе?")
        ] {
            app.buttons["Settings"].tap()
            app.buttons["learning-language-picker"].tap()
            let choice = app.buttons[selection]
            for _ in 0..<6 {
                if choice.exists && choice.isHittable { break }
                app.collectionViews.firstMatch.swipeUp()
            }
            choice.tap()
            app.buttons["Done"].tap()
            XCTAssertEqual(app.staticTexts["target-caption"].label, greeting)
            app.buttons["Themes"].tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", theme)).firstMatch.exists)
            app.buttons["Words"].tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Little by little · \(name)")).firstMatch.exists)
            app.buttons["Talk"].tap()
        }
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        let norwegian = app.buttons["Norwegian · Bokmål"]
        for _ in 0..<6 {
            if norwegian.exists && norwegian.isHittable { break }
            app.collectionViews.firstMatch.swipeDown()
        }
        norwegian.tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
        XCTAssertFalse(app.buttons["pinyin-toggle"].exists)
    }

    func testSimplifiedChineseMeaningsAreAvailableInOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 10))
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Chinese (Simplified)"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "你好！")
        confirmAdult(in: app)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["meaning-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "你好！")
    }

    func testMandarinTranscriptRetainsSourceTextAndPinyinAfterReset() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ended-conversation", "--preview-language=zh"]
        app.launch()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["new-conversation"].exists)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "我喜欢喝咖啡。")
        XCTAssertEqual(app.staticTexts.matching(identifier: "pinyin-reading").firstMatch.label, "wǒ xǐhuān hē kāfēi。")
        app.buttons["Conversation transcript"].tap()
        XCTAssertTrue(app.staticTexts["我喜欢喝咖啡。"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "pinyin-reading").firstMatch.label, "wǒ xǐhuān hē kāfēi。")
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Mandarin transcript and pinyin"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["Done"].tap()
        let greeting = NSPredicate(format: "label == %@", "你好！")
        expectation(for: greeting, evaluatedWith: app.staticTexts["target-caption"])
        waitForExpectations(timeout: 18)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "你好！")
        app.buttons["Words"].tap()
        app.buttons["Past conversations"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "喝杯咖啡？")).firstMatch.exists)
    }

    func testTypedReplyFailureKeepsDraftAndRetrySavesOnlyOneReply() {
        for largeText in [false, true] {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--test-typed-retry"] + (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["Type instead"].waitForExistence(timeout: 10))
        app.buttons["Type instead"].tap()
        let field = app.textViews["typed-reply-input"].exists ? app.textViews["typed-reply-input"] : app.textFields["typed-reply-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Quiero un cafe.")
        app.buttons["typed-reply-send"].tap()
        XCTAssertTrue(app.staticTexts["typed-reply-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Quiero un cafe.")
        XCTAssertTrue(app.buttons["typed-reply-send"].isHittable)
        if app.keyboards.firstMatch.exists {
            XCTAssertLessThanOrEqual(app.buttons["typed-reply-send"].frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        }
        let failure = XCTAttachment(screenshot: app.screenshot())
        failure.name = largeText ? "Large text typed reply failure" : "Typed reply failure preserves draft"; failure.lifetime = .keepAlways; add(failure)
        app.buttons["typed-reply-send"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.buttons["End conversation"].tap()
        XCTAssertTrue(app.buttons["Conversation transcript"].waitForExistence(timeout: 8))
        app.buttons["Conversation transcript"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "transcript-user-passage").count, 1)
        }
    }

    func testEndNoticeKeepsReasonButClearsStaleHelp() {
        for inactivity in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["--preview", "--ended-conversation", "--test-end-notice"] + (inactivity ? ["--test-inactivity"] : [])
            app.launch()
            let expected = inactivity ? "Tide English ended this quiet session to avoid running up usage." : "Conversation saved. Final voice usage is unconfirmed."
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Tide English will make that a little simpler."].exists)
        }
    }

    func testTagalogOnboardingAtLargestAccessibilitySizePreservesSubtitleChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let picker = app.buttons["onboarding-language-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        selectOnboardingLanguage("tl", in: app)
        XCTAssertTrue(picker.label.contains("Tagalog (Filipino) · Philippines"))
        reveal(picker, in: app)
        let viewport = app.scrollViews.firstMatch.frame
        let continueButton = app.buttons["onboarding-continue"]
        XCTAssertGreaterThan(picker.frame.height, 0)
        XCTAssertTrue(viewport.contains(picker.frame), "The selected language must fit inside the visible scroll area")
        XCTAssertTrue(app.frame.contains(continueButton.frame), "Continue must fit inside the screen")
        XCTAssertLessThan(picker.frame.maxY, continueButton.frame.minY)
        XCTAssertTrue(continueButton.isHittable)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Tagalog onboarding - largest accessibility text"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["French"].tap()
        app.buttons["onboarding-back"].tap()
        reveal(picker, in: app)
        XCTAssertTrue(picker.label.contains("Tagalog (Filipino)"))
        app.buttons["onboarding-continue"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "Salut !")
        confirmAdult(in: app)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Kumusta!")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Salut !")
        XCTAssertFalse(app.buttons["pinyin-toggle"].exists)
    }

    func testTagalogTranscriptAndMeaningSurviveResetAndLanguageSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--ended-conversation", "--preview-language=tl", "--preview-free-boundary"]
        app.launch()
        XCTAssertTrue(app.buttons["new-conversation"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Gusto ko ng kape.")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "I like coffee.")
        XCTAssertFalse(app.buttons["pinyin-toggle"].exists)
        app.buttons["Conversation transcript"].tap()
        XCTAssertTrue(app.staticTexts["Gusto ko ng kape."].exists)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Tagalog transcript and English meaning"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["Done"].tap()
        app.buttons["start-conversation"].tap()
        app.buttons["new-conversation"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Kumusta!")
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Spanish · Spain"].tap()
        app.buttons["Done"].tap()
        app.buttons["Words"].tap()
        app.buttons["Past conversations"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kape tayo?")).firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Talk"].tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Tagalog (Filipino) · Philippines"].tap()
        app.buttons["Done"].tap()
        app.buttons["Words"].tap()
        app.buttons["Past conversations"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Kape tayo?")).firstMatch
        XCTAssertTrue(saved.exists)
        saved.tap()
        XCTAssertTrue(app.staticTexts["Gusto ko ng kape."].exists)
    }

    func testTagalogLanguageSwitchIsDisabledDuringConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--active-conversation", "--preview-language=tl"]
        app.launch()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Gusto ko ng kape.")
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["learning-language-picker"].isEnabled)
        XCTAssertTrue(app.staticTexts["End this conversation to switch languages. Each language keeps its own words and progress."].exists)
    }

    func testTagalogSelectionPersistsAcrossNormalRelaunch() {
        let app = XCUIApplication()
        addTeardownBlock {
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
            app.buttons["Settings"].tap()
            app.buttons["learning-language-picker"].tap()
            app.buttons["Norwegian · Bokmål"].tap()
            app.buttons["Done"].tap()
            app.terminate()
            app.launch()
            XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
            app.terminate()
        }
        app.launch()
        if app.buttons["onboarding-continue"].waitForExistence(timeout: 5) {
            let picker = app.buttons["onboarding-language-picker"]
            reveal(picker, in: app)
            picker.tap()
            app.buttons["onboarding-language-tl"].tap()
            app.buttons["onboarding-continue"].tap()
            confirmAdult(in: app)
            app.buttons["onboarding-continue"].tap()
        }
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Tagalog (Filipino) · Philippines"].tap()
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Kumusta!")
        XCTAssertFalse(app.buttons["onboarding-continue"].exists)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["learning-language-picker"].label.contains("Tagalog (Filipino)"))
    }

    private func launch(ended: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--preview"] + (ended ? ["--ended-conversation"] : [])
        app.launch(); return app
    }
    func testGreetingAndMeaningToggle() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
        XCTAssertFalse(app.staticTexts["talk-guest-minutes"].exists)
        XCTAssertFalse(app.staticTexts["Reply in whichever language comes to you."].exists)
        XCTAssertEqual(app.buttons["start-conversation"].label, "Start conversation")
        let target = app.staticTexts["target-caption"].frame
        let meaning = app.staticTexts["meaning-caption"].frame
        XCTAssertGreaterThanOrEqual(meaning.minY, target.maxY)
        XCTAssertLessThan(meaning.minY - target.maxY, 40)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Quiet idle Talk"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["Hide meaning subtitles"].tap()
        XCTAssertFalse(app.staticTexts["meaning-caption"].exists)
        app.buttons["Show meaning subtitles"].tap()
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Hi!")
    }
    func testTalkControlsStayPutWhenConversationStartsAndMeaningFails() {
        let idle = launch()
        let idleMicY = idle.buttons["start-conversation"].frame.midY
        let idleMeaningY = idle.buttons["Hide meaning subtitles"].frame.midY
        let idleTranscriptY = idle.buttons["Conversation transcript"].frame.midY
        idle.terminate()

        let active = XCUIApplication()
        active.launchArguments = ["--preview", "--screenshot=conversation"]
        active.launch()
        XCTAssertTrue(active.buttons["Type instead"].waitForExistence(timeout: 10))
        XCTAssertEqual(active.buttons["start-conversation"].frame.midY, idleMicY, accuracy: 2)
        XCTAssertEqual(active.buttons["Hide meaning subtitles"].frame.midY, idleMeaningY, accuracy: 2)
        XCTAssertEqual(active.buttons["End conversation"].frame.midY, idleTranscriptY, accuracy: 2)
        active.terminate()

        let failed = XCUIApplication()
        failed.launchArguments = ["--preview", "--preview-meaning-error"]
        failed.launch()
        XCTAssertTrue(failed.staticTexts["meaning-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(failed.staticTexts["meaning-error"].label.contains("Meaning isn’t available yet"))
        XCTAssertTrue(failed.buttons["Try meaning again"].exists)
        XCTAssertEqual(failed.buttons["start-conversation"].frame.midY, idleMicY, accuracy: 2)
        let screen = XCTAttachment(screenshot: failed.screenshot())
        screen.name = "Meaning failure keeps Talk controls fixed"; screen.lifetime = .keepAlways; add(screen)
        failed.terminate()

        let limited = XCUIApplication()
        limited.launchArguments = ["--preview", "--preview-meaning-limit"]
        limited.launch()
        XCTAssertTrue(limited.staticTexts["meaning-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(limited.staticTexts["meaning-error"].label.contains("limit for extra meanings"))
        XCTAssertFalse(limited.buttons["Try meaning again"].exists)
    }
    func testThemeSurvivesNavigationToWords() {
        let app = launch()
        app.buttons["Themes"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A coffee?")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["A coffee?"].exists)
        app.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts["Your words."].exists)
        app.buttons["Talk"].tap()
        XCTAssertTrue(app.staticTexts["A coffee?"].exists)
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
    }
    func testSettingsOfferSecureKeyEntryAndBackups() {
        let app = launch()
        XCTAssertFalse(app.staticTexts["talk-guest-minutes"].exists)
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.staticTexts["Start talking"].exists)
        if app.buttons["managed-account-settings"].exists {
            app.buttons["managed-account-settings"].tap()
            XCTAssertTrue(app.staticTexts["managed-sign-in-agreement"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["managed-google-sign-in"].isHittable || app.buttons["managed-apple-sign-in"].isHittable)
            XCTAssertFalse(app.staticTexts["managedAccountMessage"].exists)
            XCTAssertFalse(app.buttons["Buy credits"].exists)
            XCTAssertFalse(app.staticTexts["managed-account-minutes"].exists)
            let accountScreen = XCTAttachment(screenshot: app.screenshot())
            accountScreen.name = "Configured account signup"; accountScreen.lifetime = .keepAlways; add(accountScreen)
            app.navigationBars["Account"].buttons.element(boundBy: 0).tap()
        }
        XCTAssertFalse(app.secureTextFields["api-key"].exists)
        app.buttons["settings-conversation-access"].tap()
        app.buttons["My API key"].tap()
        if !app.secureTextFields["api-key"].exists { app.swipeUp() }
        XCTAssertTrue(app.secureTextFields["api-key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
        app.navigationBars["Model provider"].buttons["Done"].tap()
        XCTAssertFalse(app.buttons["advanced-api-key"].exists)
        XCTAssertTrue(app.staticTexts["Tide English minutes"].exists)
        app.buttons["Learning backup & data"].tap()
        XCTAssertTrue(app.buttons["Export learning backup"].exists)
        app.navigationBars["Learning data"].buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["start-conversation"].exists)
    }

    func testPersonalPreviewOpensModelProviderSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal"]
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["managed-account-settings"].exists)
        XCTAssertFalse(app.buttons["settings-conversation-access"].exists)
        XCTAssertFalse(app.staticTexts["Tide English minutes"].exists)
        XCTAssertTrue(app.buttons["settings-model-provider"].waitForExistence(timeout: 5))
        app.buttons["settings-model-provider"].tap()
        XCTAssertTrue(app.navigationBars["Model provider"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["model-provider-picker"].exists)
        XCTAssertTrue(app.textFields["model-chat-model"].exists)
        XCTAssertTrue(app.secureTextFields["api-key"].exists)
        XCTAssertTrue(app.staticTexts["The voice model is separate from the chat model above."].exists)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Personal model provider settings"; screen.lifetime = .keepAlways; add(screen)
    }

    private func revealTalkControl(_ control: XCUIElement, in app: XCUIApplication) {
        let top = app.buttons["Settings"].frame.maxY + 8
        let bottom = app.otherElements["main-navigation"].frame.minY - 8
        for _ in 0..<8 {
            if control.exists && control.isHittable && control.frame.minY >= top && control.frame.maxY <= bottom { return }
            if control.exists && control.frame.minY < top { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(control.isHittable)
        XCTAssertGreaterThanOrEqual(control.frame.minY, top)
        XCTAssertLessThanOrEqual(control.frame.maxY, bottom, "Show the whole control above the tab bar")
    }

    func testRefreshedTalkKeepsControlsReachableAtLargeTextSizes() {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXXL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = XCUIApplication()
            app.launchArguments = ["--preview", "--preview-provider=gemini", "-UIPreferredContentSizeCategoryName", category]
            app.launch()
            let start = app.buttons["start-conversation"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            let meaning = app.buttons["Hide meaning subtitles"]
            revealTalkControl(meaning, in: app)
            meaning.tap()
            XCTAssertTrue(app.buttons["Show meaning subtitles"].waitForExistence(timeout: 5))
            app.buttons["Show meaning subtitles"].tap()
            XCTAssertTrue(app.buttons["Hide meaning subtitles"].exists)
            revealTalkControl(start, in: app)
            XCTAssertGreaterThanOrEqual(start.frame.minX, 0)
            XCTAssertLessThanOrEqual(start.frame.maxX, app.frame.width)
            XCTAssertTrue(app.buttons["Settings"].isHittable)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "Refreshed Talk - \(category)"; screen.lifetime = .keepAlways; add(screen)
            app.terminate()
        }
        let active = XCUIApplication()
        active.launchArguments = ["--preview", "--preview-provider=gemini", "--screenshot=conversation"]
        active.launch()
        XCTAssertTrue(active.buttons["Mute microphone"].waitForExistence(timeout: 5))
        active.buttons["Mute microphone"].tap()
        XCTAssertTrue(active.buttons["Unmute microphone"].waitForExistence(timeout: 5))
        XCTAssertTrue(active.buttons["End conversation"].isHittable)
        XCTAssertTrue(active.buttons["Type instead"].isHittable)
        let screen = XCTAttachment(screenshot: active.screenshot())
        screen.name = "Refreshed Talk - active and muted"; screen.lifetime = .keepAlways; add(screen)
    }

    func testTalkKeepsUserSubtitleAboveMicrophone() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=gemini", "--screenshot=conversation"]
        app.launch()
        let userSubtitle = app.staticTexts["Un café con leche, por favor."]
        XCTAssertTrue(userSubtitle.waitForExistence(timeout: 5))
        let microphone = app.buttons["start-conversation"]
        XCTAssertTrue(microphone.isHittable)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Tide English - subtitle clearance"; screen.lifetime = .keepAlways; add(screen)
        XCTAssertLessThanOrEqual(userSubtitle.frame.maxY + 8, microphone.frame.minY, "Keep the last user subtitle fully above the microphone")
    }

    func testSeaNavigationPreservesAnActiveConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=gemini", "--screenshot=conversation"]
        app.launch()
        let navigation = app.otherElements["main-navigation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let passage = app.staticTexts["target-caption"].label
        for name in ["Words", "Themes", "Talk"] {
            let item = navigation.buttons[name]
            XCTAssertTrue(item.isHittable)
            item.tap()
            XCTAssertTrue(item.isSelected)
            XCTAssertTrue(app.buttons["Settings"].isHittable)
        }
        XCTAssertEqual(app.staticTexts["target-caption"].label, passage)
        XCTAssertTrue(app.buttons["Mute microphone"].isHittable)
        app.buttons["Mute microphone"].tap()
        XCTAssertTrue(app.buttons["Unmute microphone"].isHittable)
        XCTAssertTrue(app.buttons["End conversation"].isHittable)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Tide English - active navigation"; screen.lifetime = .keepAlways; add(screen)
    }

    func testOceanThemePreservesNavigationAcrossMainScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=gemini", "--screenshot=words"]
        app.launch()
        XCTAssertTrue(app.buttons["open-flashcards"].waitForExistence(timeout: 5))
        for name in ["Words", "Themes", "Talk"] {
            app.buttons[name].tap()
            XCTAssertTrue(app.buttons[name].isSelected)
            XCTAssertTrue(app.buttons["Settings"].isHittable)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "Ocean theme - \(name)"; screen.lifetime = .keepAlways; add(screen)
        }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].isHittable)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Ocean theme - Settings"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["settings-model-provider"].tap()
        XCTAssertTrue(app.buttons["model-provider-picker"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.secureTextFields.matching(identifier: "api-key").count, 1)
        app.navigationBars["Model provider"].buttons["Done"].tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["start-conversation"].isHittable)
    }

    func testSettingsOffersOneModelAndKeyEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=gemini"]
        app.launch()
        app.buttons["Settings"].tap()
        var editorEntries = Set<String>()
        for _ in 0..<7 {
            for identifier in ["settings-model-provider", "advanced-api-key", "advanced-provider-issue"] {
                if app.buttons[identifier].exists { editorEntries.insert(identifier) }
            }
            if app.buttons["About Tide English"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["About Tide English"].isHittable, "Inspect the whole Settings form for duplicate entries")
        XCTAssertEqual(editorEntries, ["settings-model-provider"], "Settings must offer one place to edit the model and key")
        let entry = app.buttons["settings-model-provider"]
        for _ in 0..<7 {
            if entry.isHittable { break }
            app.swipeDown()
        }
        entry.tap()
        XCTAssertTrue(app.buttons["model-provider-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["model-chat-model"].exists)
        XCTAssertEqual(app.secureTextFields.matching(identifier: "api-key").count, 1)
    }

    func testModelProviderIsVisibleWithoutScrollingAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=gemini", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["Settings"].tap()
        let entry = app.buttons["settings-model-provider"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable, "Model selection must be visible when Settings first opens, without scrolling")
        XCTAssertLessThan(entry.frame.minY, app.frame.height / 2, "Keep the provider entry near the top of Settings")
        let settingsScreen = XCTAttachment(screenshot: app.screenshot())
        settingsScreen.name = "Model entry visible at largest text size"
        settingsScreen.lifetime = .keepAlways
        add(settingsScreen)
        entry.tap()
        let picker = app.buttons["model-provider-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        for name in ["DeepSeek", "GLM (BigModel)", "Gemini", "Custom"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5), "Provider missing: \(name)")
        }
        // The native menu scrolls to the selected Gemini row at this text size.
        let openAI = app.buttons["OpenAI"]
        for _ in 0..<3 {
            if openAI.isHittable { break }
            app.collectionViews.containing(.button, identifier: "Gemini").firstMatch.swipeDown()
        }
        XCTAssertTrue(openAI.isHittable)
        openAI.tap()
        XCTAssertTrue(picker.label.contains("OpenAI"))
    }

    func testProviderPreviewShowsCapabilitiesAndCustomFields() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=deepSeek"]
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["managed-account-settings"].exists)
        app.buttons["settings-model-provider"].tap()
        XCTAssertTrue(app.staticTexts["Turn-based voice uses on-device recognition and system reading."].exists)
        let provider = app.buttons["model-provider-picker"]
        provider.tap()
        app.buttons["GLM (BigModel)"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "GLM native realtime voice")).firstMatch.exists)
        provider.tap()
        app.buttons["Custom"].tap()
        XCTAssertTrue(app.textFields["model-base-url"].exists)
        XCTAssertEqual(app.textFields["model-chat-model"].value as? String, "Chat model")
        app.buttons["model-save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "chat model ID")).firstMatch.exists)
    }

    func testGeminiPreviewKeepsProviderSettingsAndKeyIsolated() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=gemini"]
        app.launch()
        app.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["managed-account-settings"].exists)
        XCTAssertFalse(app.buttons["settings-conversation-access"].exists)
        XCTAssertFalse(app.staticTexts["Tide English minutes"].exists)
        XCTAssertTrue(app.buttons["settings-model-provider"].label.contains("Gemini"))
        app.buttons["settings-model-provider"].tap()
        XCTAssertTrue(app.navigationBars["Model provider"].waitForExistence(timeout: 5))
        let model = app.textFields["model-chat-model"]
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.value as? String, "gemini-3.8-flash")
        model.tap(); model.typeText("-preview\n")
        XCTAssertEqual(model.value as? String, "gemini-3.8-flash-preview")
        let key = app.secureTextFields["api-key"]
        key.tap(); key.typeText("synthetic-gemini-key\n")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let save = app.buttons["model-save"]
        for _ in 0..<5 { if save.exists { break }; app.swipeUp() }
        XCTAssertTrue(save.exists)
        save.tap()
        for _ in 0..<5 { if key.exists { break }; app.swipeDown() }
        XCTAssertEqual(key.value as? String, "Replacement key")
        XCTAssertTrue(app.descendants(matching: .any)["model-key-status"].label.contains("Saved on this iPhone"))
        let nativeVoice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Gemini native live voice")).firstMatch
        for _ in 0..<5 { if nativeVoice.exists { break }; app.swipeUp() }
        XCTAssertTrue(nativeVoice.exists)
        XCTAssertTrue(app.staticTexts["The voice model is separate from the chat model above."].exists)
        let timeout = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Gemini Live connections may stop after about 10 minutes")).firstMatch
        for _ in 0..<5 { if timeout.exists { break }; app.swipeUp() }
        XCTAssertTrue(timeout.exists)
        XCTAssertTrue(app.staticTexts["Live learning-plan updates apply at your next conversation."].exists)
        XCTAssertTrue(app.staticTexts["Current news search is unavailable with Gemini in Tide English."].exists)
        let console = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Google AI Studio")).firstMatch
        for _ in 0..<5 { if console.exists { break }; app.swipeUp() }
        XCTAssertTrue(console.exists)
        let provider = app.buttons["model-provider-picker"]
        for _ in 0..<5 { if provider.isHittable { break }; app.swipeDown() }
        provider.tap(); app.buttons["DeepSeek"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["model-key-status"].label.contains("No key saved"))
        provider.tap(); app.buttons["Gemini"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["model-key-status"].label.contains("Saved on this iPhone"))
        app.navigationBars["Model provider"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["settings-model-provider"].label.contains("Gemini"))
        app.terminate()

        let active = XCUIApplication()
        active.launchArguments = ["--preview", "--preview-provider=gemini", "--active-conversation"]
        active.launch()
        active.buttons["Settings"].tap()
        XCTAssertFalse(active.buttons["settings-model-provider"].isEnabled)
    }

    func testGeminiCurrentTopicExplainsUnavailableSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=gemini"]
        app.launch()
        app.buttons["Themes"].tap()
        let today = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "The world today")).firstMatch
        for _ in 0..<5 { if today.isHittable { break }; app.swipeUp() }
        today.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Current news search is unavailable with Gemini")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Choose OpenAI or GLM")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Find a topic"].exists)
    }

    func testDeepSeekCurrentTopicExplainsUnavailableSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=deepSeek"]
        app.launch()
        app.buttons["Themes"].tap()
        let today = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "The world today")).firstMatch
        for _ in 0..<5 { if today.isHittable { break }; app.swipeUp() }
        today.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Current news search is unavailable with DeepSeek")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Find a topic"].exists)
    }

    func testPreviewKeyDraftClearsOnProviderAndEndpointChange() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider=custom"]
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["settings-model-provider"].tap()
        let model = app.textFields["model-chat-model"]
        model.tap(); model.typeText("demo-model")
        let endpoint = app.textFields["model-base-url"]
        endpoint.tap(); endpoint.typeText("https://example.test/v1")
        let key = app.secureTextFields["api-key"]
        key.tap(); key.typeText("preview-secret")
        endpoint.tap(); endpoint.typeText("2")
        XCTAssertEqual(key.value as? String, "New key")
        key.tap(); key.typeText("another-secret\n")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["model-provider-picker"].tap()
        app.buttons["GLM (BigModel)"].tap()
        XCTAssertEqual(key.value as? String, "New key")
    }

    func testModelSettingsSaveInPreviewAndDisableDuringConversation() {
        let idle = XCUIApplication()
        idle.launchArguments = ["--preview", "--preview-provider=deepSeek"]
        idle.launch()
        idle.buttons["Settings"].tap()
        idle.buttons["settings-model-provider"].tap()
        idle.buttons["model-provider-picker"].tap()
        idle.buttons["GLM (BigModel)"].tap()
        let key = idle.secureTextFields["api-key"]
        key.tap(); key.typeText("preview-key-only\n")
        idle.buttons["model-save"].tap()
        XCTAssertTrue(idle.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Key saved on this iPhone")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(key.value as? String, "Replacement key")
        idle.buttons["model-provider-picker"].tap()
        idle.buttons["DeepSeek"].tap()
        XCTAssertTrue(idle.descendants(matching: .any)["model-key-status"].label.contains("No key saved"))
        idle.buttons["model-provider-picker"].tap()
        idle.buttons["GLM (BigModel)"].tap()
        XCTAssertTrue(idle.descendants(matching: .any)["model-key-status"].label.contains("Saved on this iPhone"))
        idle.navigationBars["Model provider"].buttons["Done"].tap()
        XCTAssertTrue(idle.buttons["settings-model-provider"].label.contains("GLM (BigModel)"))
        idle.terminate()

        let active = XCUIApplication()
        active.launchArguments = ["--preview", "--preview-personal", "--active-conversation"]
        active.launch()
        active.buttons["Settings"].tap()
        XCTAssertFalse(active.buttons["settings-model-provider"].isEnabled)
    }

    func testPersonalKeyKeepsAccountFreeOfTideEnglishMetersAndUsesQuietActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-key", "--preview-apple", "--preview-purchases"]
        app.launch()
        XCTAssertFalse(app.staticTexts["talk-guest-minutes"].exists)
        app.buttons["Settings"].tap()
        app.buttons["managed-account-settings"].tap()
        XCTAssertTrue(app.staticTexts["managed-account-email"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["managed-account-minutes"].exists)
        XCTAssertFalse(app.buttons["account-add-minutes"].exists)
        XCTAssertTrue(app.buttons["account-purchase-history"].exists)
        XCTAssertTrue(app.buttons["managed-account-sign-out"].isHittable)
        XCTAssertTrue(app.buttons["Delete account…"].isHittable)
        app.buttons["managed-account-sign-out"].tap()
        XCTAssertTrue(app.staticTexts["Sign out on all devices?"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.8)).tap()
        XCTAssertTrue(app.staticTexts["managed-account-email"].exists)
    }

    func testMemberTideEnglishBalanceUsesVerifiedFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-member"]
        app.launch()
        XCTAssertFalse(app.staticTexts["talk-guest-minutes"].exists)
        app.buttons["Settings"].tap()
        app.buttons["managed-account-settings"].tap()
        XCTAssertTrue(app.staticTexts["managed-account-minutes"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["managed-account-minutes"].label, "8 min 54 sec")
        XCTAssertFalse(app.buttons["settings-conversation-access"].exists)
    }

    private func purchasePreview(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-paid-member", "--preview-purchases", "-AppleLocale", "en_US", "-AppleLanguages", "(en)"] + extra
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["managed-account-settings"].tap()
        let add = app.buttons["account-add-minutes"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        if !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.buttons["minute-continue"].waitForExistence(timeout: 5))
        return app
    }
    func testPurchaseQuantityFloorsAfterAggregationAndKeepsCheckoutStationary() {
        let app = purchasePreview()
        let next = app.buttons["minute-continue"]
        XCTAssertEqual(next.label, "Continue · $7.00")
        let position = next.frame
        let stepper = app.steppers["minute-quantity"]
        stepper.buttons["minute-quantity-Increment"].tap()
        XCTAssertTrue(app.staticTexts["minute-total"].label.contains("About 73 min"))
        XCTAssertEqual(next.label, "Continue · $14.00")
        XCTAssertEqual(next.frame.minY, position.minY, accuracy: 1)
        app.buttons["minute-offer-large"].tap()
        XCTAssertEqual(next.label, "Continue · $40.00")
        XCTAssertTrue(app.staticTexts["minute-total"].label.contains("About 232 min"))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Apple packs - quantity two"; screen.lifetime = .keepAlways; add(screen)
        next.tap()
        XCTAssertTrue(app.staticTexts["Purchase preview · no payment was made."].exists)
    }
    func testPurchaseControlsRemainReachableAtLargestTextSize() {
        let app = purchasePreview(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["minute-continue"].isHittable)
        XCTAssertTrue(app.steppers["minute-quantity"].buttons["minute-quantity-Increment"].isHittable)
        app.swipeUp()
        XCTAssertTrue(app.buttons["minute-continue"].isHittable)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Apple packs - largest text"; screen.lifetime = .keepAlways; add(screen)
    }
    func testPendingPurchaseDisablesAnotherCheckout() {
        let app = purchasePreview(["--preview-purchase-pending"])
        XCTAssertFalse(app.buttons["minute-continue"].isEnabled)
        XCTAssertFalse(app.steppers["minute-quantity"].isEnabled)
        XCTAssertFalse(app.buttons["minute-offer-small"].isEnabled)
        XCTAssertTrue(app.buttons["minute-check-purchases"].isEnabled)
    }
    func testPurchaseHistoryKeepsRefundsAccountBoundAndUsesMinutesOnly() {
        let app = purchasePreview([])
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["account-purchase-history"].tap()
        XCTAssertTrue(app.staticTexts["Recent Apple purchases"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test refund recorded"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Quantity · 2"].exists)
        XCTAssertFalse(app.buttons["Request a refund"].firstMatch.isEnabled)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "USD")).firstMatch.exists)
    }
    func testPurchaseAccessibilityAudit() throws {
        let app = purchasePreview([])
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped, .trait])
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["account-purchase-history"].tap()
        XCTAssertTrue(app.staticTexts["Recent Apple purchases"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped, .trait])
    }
    func testFreeBoundaryPreservesConversationAndWaitsForSettlement() { checkFreeBoundary(largeText: false) }
    func testFreeBoundaryAtLargestTextSize() { checkFreeBoundary(largeText: true) }
    func testSettledInsufficientContinuationOpensAccountWithoutStartingACall() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-member", "--ended-conversation", "--preview-free-boundary", "--preview-continuation-insufficient"]
        app.launch()
        let add = app.buttons["continuation-add-minutes"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled)
        XCTAssertFalse(app.buttons["continue-conversation"].exists)
        XCTAssertTrue(app.staticTexts["Your conversation is saved. You don’t have enough minutes to continue. Add minutes in Account when you’re ready."].exists)
        app.buttons["Done"].tap()
        XCTAssertFalse(add.exists)
        XCTAssertFalse(app.staticTexts["Your conversation is saved. You don’t have enough minutes to continue. Add minutes in Account when you’re ready."].exists)
        app.buttons["Start conversation"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["End conversation"].exists)
    }
    private func checkFreeBoundary(largeText: Bool) {
        for pending in [true, false] {
            let app = XCUIApplication()
            app.launchArguments = ["--preview", "--ended-conversation", "--preview-free-boundary"] + (pending ? ["--preview-settlement-pending"] : []) +
                (largeText ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            app.launch()
            let next = app.buttons["continue-conversation"]
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertEqual(next.isEnabled, !pending)
            if largeText { for _ in 0..<5 { if app.buttons["new-conversation"].isHittable { break }; app.swipeUp() } }
            XCTAssertTrue(app.buttons["new-conversation"].isHittable)
            if !pending { XCTAssertTrue(next.isHittable) }
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = (pending ? "Free boundary - updating minutes" : "Free boundary - continue conversation") + (largeText ? " - largest text" : "")
            screen.lifetime = .keepAlways; add(screen)
            app.buttons["Done"].tap()
            XCTAssertFalse(app.buttons["continue-conversation"].exists)
            XCTAssertFalse(app.buttons["new-conversation"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Your free minutes have ended")).firstMatch.exists)
            XCTAssertTrue(app.staticTexts["target-caption"].exists)
            let home = XCTAttachment(screenshot: app.screenshot()); home.name = "Minimal Talk after dismissing continuation"
            home.lifetime = .keepAlways; add(home)
            let microphone = app.buttons["Start conversation"]
            if largeText { for _ in 0..<5 { if microphone.isHittable { break }; app.swipeUp() } }
            microphone.tap()
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testMixedTideEnglishMinutesFloorTheCombinedEstimate() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-paid-member"]
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["managed-account-settings"].tap()
        let balance = app.staticTexts["managed-account-minutes"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertEqual(balance.label, "About 41 min")
        XCTAssertTrue(app.staticTexts["estimated conversation time remaining"].exists)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Account with mixed Tide English minutes"; screen.lifetime = .keepAlways; add(screen)
    }

    func testPaidOnlyTideEnglishMinutesStayAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-paid-only"]
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["managed-account-settings"].tap()
        let balance = app.staticTexts["managed-account-minutes"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertEqual(balance.label, "About 36 min")
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Account with paid Tide English minutes"; screen.lifetime = .keepAlways; add(screen)
    }

    func testPaidOnlyBalanceCanSwitchFromPersonalKey() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-key", "--preview-paid-only"]
        app.launch()
        app.buttons["Settings"].tap()
        let access = app.buttons["settings-conversation-access"]
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        access.tap()
        app.buttons["Tide English minutes"].tap()
        let balance = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "About 36 min")).firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        app.buttons["Use Tide English minutes"].tap()
        XCTAssertTrue(access.label.contains("Tide English minutes"))
    }

    func testReservedPaidMinutesAreNotShownAsSpendable() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-paid-reserved"]
        app.launch()
        app.buttons["Settings"].tap()
        app.buttons["managed-account-settings"].tap()
        let balance = app.staticTexts["managed-account-minutes"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        XCTAssertEqual(balance.label, "Updating your minutes…")
        XCTAssertTrue(app.staticTexts["Some minutes are in use"].exists)
    }

    func testProviderFailureCanSwitchFromKeyDetailsToTideEnglish() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-key", "--preview-provider-quota"]
        app.launch()
        let review = app.alerts.buttons["Review model settings"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        let key = app.buttons["settings-model-provider"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        key.tap()
        app.buttons["Use Tide English minutes"].tap()
        XCTAssertTrue(app.navigationBars["Conversation access"].waitForExistence(timeout: 5))
        let confirm = app.buttons["Use Tide English minutes"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let balance = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "8 min 54 sec")).firstMatch
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        confirm.tap()
        let access = app.buttons["settings-conversation-access"]
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        XCTAssertTrue(access.label.contains("Tide English minutes"))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["start-conversation"].exists)
    }

    func testPersonalKeySwitchToTideEnglishRequiresFreshConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-key"]
        app.launch()
        app.buttons["Settings"].tap()
        let access = app.buttons["settings-conversation-access"]
        XCTAssertTrue(access.waitForExistence(timeout: 5))
        XCTAssertTrue(access.label.contains("My API key"))

        access.tap()
        app.buttons["Tide English minutes"].tap()
        XCTAssertTrue(app.buttons["Use Tide English minutes"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(access.label.contains("My API key"))

        access.tap()
        app.buttons["Tide English minutes"].tap()
        XCTAssertTrue(app.buttons["Use Tide English minutes"].waitForExistence(timeout: 5))
        app.buttons["Use Tide English minutes"].tap()
        XCTAssertTrue(access.label.contains("Tide English minutes"))
    }

    func testSettingsKeepLicensesInNoticesWithoutTransportDetails() {
        let app = launch()
        app.buttons["Settings"].tap()
        for _ in 0..<6 {
            if app.buttons["About Tide English"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["About Tide English"].tap()
        for _ in 0..<6 {
            if app.buttons["Open-source notices"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["Open-source notices"].isHittable)
        XCTAssertFalse(app.staticTexts["WebRTC distribution by stasel, BSD 3-Clause. WebRTC includes third-party open-source components."].exists)
        XCTAssertFalse(app.links["WebRTC licenses"].exists)
        app.buttons["Open-source notices"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Google WebRTC")).firstMatch.waitForExistence(timeout: 5))
    }

    func testExistingUserCanDeclineThenAcceptAIConsentWithoutRepeatingOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user"]
        app.launch()
        XCTAssertTrue(app.buttons["start-conversation"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-language-fr"].exists)
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-decline"].tap()
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-agree"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["ai-consent-title"].exists)
        XCTAssertFalse(app.buttons["onboarding-language-fr"].exists)
    }

    func testAIConsentCanBeWithdrawnAndRestoredWithoutLosingSavedWords() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user", "--screenshot=words"]
        app.launch()
        let savedWord = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "me apetece")).firstMatch
        XCTAssertTrue(savedWord.waitForExistence(timeout: 5))
        app.buttons["Talk"].tap()
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.buttons["ai-consent-agree"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-agree"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if app.buttons["settings-ai-processing"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["settings-ai-processing"].tap()
        XCTAssertTrue(app.buttons["ai-processing-withdraw"].waitForExistence(timeout: 5))
        app.buttons["ai-processing-withdraw"].tap()
        app.buttons.matching(identifier: "ai-processing-confirm-withdraw").firstMatch.tap()
        XCTAssertTrue(app.buttons["ai-processing-enable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ai-processing-status"].label.contains("saved words and conversations remain available"))
        app.buttons["ai-processing-done"].tap()
        app.buttons["Done"].tap()
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        app.buttons["ai-consent-decline"].tap()
        app.buttons["Words"].tap()
        XCTAssertTrue(savedWord.waitForExistence(timeout: 5))
        app.buttons["Talk"].tap()
        app.buttons["start-conversation"].tap()
        app.buttons["ai-consent-agree"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }

    func testWithdrawingAIConsentEndsActiveConversationAndPreservesTranscript() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--screenshot=conversation"]
        app.launch()
        XCTAssertEqual(app.buttons["start-conversation"].label, "Mute microphone")
        app.buttons["Settings"].tap()
        for _ in 0..<8 {
            if app.buttons["settings-ai-processing"].isHittable { break }
            app.swipeUp()
        }
        app.buttons["settings-ai-processing"].tap()
        XCTAssertTrue(app.buttons["ai-processing-enable"].waitForExistence(timeout: 5))
        app.buttons["ai-processing-enable"].tap()
        app.buttons["ai-processing-withdraw"].tap()
        app.buttons.matching(identifier: "ai-processing-confirm-withdraw").firstMatch.tap()
        XCTAssertTrue(app.buttons["ai-processing-enable"].waitForExistence(timeout: 5))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "AI processing permission withdrawn"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["ai-processing-done"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["start-conversation"].label, "Start conversation")
        app.buttons["Conversation transcript"].tap()
        XCTAssertTrue(app.staticTexts["Un café con leche, por favor."].waitForExistence(timeout: 5))
    }

    func testAIConsentActionsRemainReachableAtLargestAccessibilitySize() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-existing-user", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["start-conversation"].tap()
        XCTAssertTrue(app.staticTexts["ai-consent-title"].waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if app.buttons["ai-consent-decline"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["ai-consent-decline"].isHittable)
        app.buttons["ai-consent-decline"].tap()
        XCTAssertTrue(app.buttons["start-conversation"].exists)
    }

    func testOnboardingChoosesLearningAndSubtitleLanguagesWithoutAnAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        let languagePicker = app.buttons["onboarding-language-picker"]
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 10))
        let languageScreen = XCTAttachment(screenshot: app.screenshot())
        languageScreen.name = "Onboarding - language"; languageScreen.lifetime = .keepAlways; add(languageScreen)
        languagePicker.tap()
        app.buttons["onboarding-language-fr"].tap()
        XCTAssertTrue(languagePicker.label.contains("French · France"))
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Tide English speaks French")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["onboarding-ai-consent"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding-privacy-policy").firstMatch.exists)
        XCTAssertEqual(app.buttons["onboarding-continue"].label, "Agree and continue")
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Spanish"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "¡Hola!")
        let meaningScreen = XCTAttachment(screenshot: app.screenshot())
        meaningScreen.name = "Onboarding - meanings and consent"; meaningScreen.lifetime = .keepAlways; add(meaningScreen)
        confirmAdult(in: app)
        XCTAssertTrue(app.buttons["onboarding-continue"].isEnabled)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-continue"].exists)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Salut !")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "¡Hola!")
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
        XCTAssertFalse(app.secureTextFields["api-key"].exists)
    }

    func testEnglishOnboardingOffersOtherMeaningsAndPreservesAnExplicitChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-onboarding"]
        app.launch()
        let languagePicker = app.buttons["onboarding-language-picker"]
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 10))
        languagePicker.tap()
        app.buttons["onboarding-language-en"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["onboarding-meaning-picker"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.staticTexts["onboarding-meaning-example"].label, "Hi!")
        app.buttons["onboarding-meaning-picker"].tap()
        app.buttons["Spanish"].tap()
        app.buttons["onboarding-back"].tap()
        languagePicker.tap()
        app.buttons["onboarding-language-fr"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, "¡Hola!")
        confirmAdult(in: app)
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "¡Hola!")
    }

    func testSettingsCanSwitchToEnglishAndFrench() {
        let app = launch()
        for (selection, greeting) in [("English · International", "Hi!"), ("French · France", "Salut !")] {
            app.buttons["Settings"].tap()
            app.buttons["learning-language-picker"].tap()
            let choice = app.buttons[selection]
            for _ in 0..<6 {
                if choice.exists && choice.isHittable { break }
                app.collectionViews.firstMatch.swipeUp()
            }
            choice.tap()
            app.buttons["Done"].tap()
            XCTAssertEqual(app.staticTexts["target-caption"].label, greeting)
        }
    }
    func testLanguageSwitchUpdatesGreetingThemesAndWords() {
        let app = launch()
        app.buttons["Themes"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A coffee?")).firstMatch.tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Spanish · Spain"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "¡Hola!")
        XCTAssertTrue(app.staticTexts["A little everyday Spanish"].exists)
        app.buttons["Themes"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Un café")).firstMatch.exists)
        app.buttons["Words"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Little by little · Spanish")).firstMatch.exists)
        app.buttons["Talk"].tap()
        app.buttons["Settings"].tap()
        app.buttons["learning-language-picker"].tap()
        app.buttons["Norwegian · Bokmål"].tap()
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
    }

    func testMeaningLabelWorksAfterEndingAndAutomaticResetKeepsHistory() {
        let app = launch(ended: true)
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["new-conversation"].exists)
        XCTAssertTrue(app.buttons["start-conversation"].isHittable)
        XCTAssertTrue(app.buttons["Conversation transcript"].isHittable)
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "I like coffee.")
        app.buttons["Hide meaning subtitles"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        XCTAssertFalse(app.staticTexts["meaning-caption"].exists)
        app.buttons["Show meaning subtitles"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "I like coffee.")
        let greeting = NSPredicate(format: "label == %@", "Hei!")
        expectation(for: greeting, evaluatedWith: app.staticTexts["target-caption"])
        waitForExpectations(timeout: 18)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
        XCTAssertFalse(app.staticTexts["A coffee?"].exists)
        app.buttons["Words"].tap()
        app.buttons["Past conversations"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "A coffee?")).firstMatch.exists)
    }

    func testEndedConversationAutomaticallyReturnsToGreeting() {
        let app = launch(ended: true)
        XCTAssertTrue(app.staticTexts["target-caption"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["new-conversation"].exists)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Jeg liker kaffe.")
        let ready = NSPredicate(format: "label == %@", "Ready when you are")
        expectation(for: ready, evaluatedWith: app.staticTexts["conversation-status"])
        waitForExpectations(timeout: 18)
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
        XCTAssertEqual(app.staticTexts["meaning-caption"].label, "Hi!")
        XCTAssertFalse(app.buttons["new-conversation"].exists)
    }

    func testOpenTranscriptRemainsReadableAfterAutomaticReset() {
        let app = launch(ended: true)
        XCTAssertTrue(app.buttons["Conversation transcript"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["new-conversation"].exists)
        app.buttons["Conversation transcript"].tap()
        XCTAssertTrue(app.staticTexts["I like coffee."].exists)
        let delay = expectation(description: "Allow the 15-second reset to finish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { delay.fulfill() }
        waitForExpectations(timeout: 18)
        XCTAssertTrue(app.staticTexts["Jeg liker kaffe."].exists)
        XCTAssertTrue(app.staticTexts["I like coffee."].exists)
        app.buttons["Done"].tap()
        XCTAssertEqual(app.staticTexts["target-caption"].label, "Hei!")
    }
    func testNetworkRecoveryLifecycleThroughRealTransport() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--verify-network-recovery"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Network recovery lifecycle passed"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Network recovery lifecycle failed"].exists)
    }
    func testInactivityCountdownRemainsReadableAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-inactivity", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let warning = app.staticTexts["conversation-status"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        XCTAssertTrue(warning.isHittable)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Inactivity countdown - largest text"; screen.lifetime = .keepAlways; add(screen)
    }
    func testQuietSessionClosesAndPreservesItsExplanation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-inactivity-timer"]
        app.launch()
        let ended = app.staticTexts["Tide English ended this quiet session to avoid running up usage."]
        XCTAssertTrue(ended.waitForExistence(timeout: 16))
        XCTAssertFalse(app.staticTexts["microphone-status"].exists)
    }
    func testProviderQuotaShowsUsefulAdviceAndSafeSupportReference() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-provider-quota"]
        app.launch()
        let message = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "OpenAI billing needs attention")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(message.label.contains("req_support_fixture"))
        XCTAssertFalse(message.label.contains("private"))
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Provider quota error"; screen.lifetime = .keepAlways; add(screen)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testHostedMinutesExhaustedOpensKeyRecovery() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-hosted-no-minutes"]
        app.launch()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["No Tide English minutes are available for a new conversation. Check Account or use your own API key."].exists)
        XCTAssertTrue(alert.buttons["Check minutes"].exists)
        alert.buttons["Use my API key"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-conversation-access"].exists)
    }

    func testHostedSignInRequiredOpensAccount() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-hosted-sign-in"]
        app.launch()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Sign in"].tap()
        XCTAssertTrue(app.staticTexts["Welcome to Tide English"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["managed-apple-sign-in"].exists)
    }

    func testDutchOnboarding() { checkNewOnboarding(id: "nl", greeting: "Hoi!") }
    func testRussianOnboarding() { checkNewOnboarding(id: "ru", greeting: "Привет!") }

    func testDutchAndRussianMeaningChoicesReachTalk() {
        for (meaning, greeting) in [("Dutch", "Hoi!"), ("Russian", "Привет!")] {
            let app = XCUIApplication()
            app.launchArguments = ["--preview", "--preview-onboarding"]
            app.launch()
            XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 10))
            app.buttons["onboarding-continue"].tap()
            app.buttons["onboarding-meaning-picker"].tap()
            let choice = app.buttons[meaning]
            for _ in 0..<6 {
                if choice.exists && choice.isHittable { break }
                app.collectionViews.firstMatch.swipeUp()
            }
            choice.tap()
            XCTAssertEqual(app.staticTexts["onboarding-meaning-example"].label, greeting)
            confirmAdult(in: app)
            app.buttons["onboarding-continue"].tap()
            XCTAssertTrue(app.staticTexts["meaning-caption"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["meaning-caption"].label, greeting)
            app.terminate()
        }
    }

    func testFlashcardsRevealNavigateAndIgnoreVerticalSwipes() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--screenshot=words"]
        app.launch()
        let trigger = app.buttons["open-flashcards"]
        XCTAssertTrue(trigger.waitForExistence(timeout: 10))
        let heading = app.staticTexts["Your words."]
        XCTAssertGreaterThan(trigger.frame.minX, heading.frame.maxX)
        XCTAssertEqual(trigger.frame.midY, heading.frame.midY, accuracy: 3)
        trigger.tap()
        let progress = app.descendants(matching: .any)["flashcard-pager"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.value as? String, "1 of 4")
        // The page value changes in the slide animation's completion callback.
        // A synthesized swipe can return before that callback has run.
        func waitForPage(_ page: Int) {
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "\(page) of 4"), object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
        }
        if ProcessInfo.processInfo.environment["TIDE_ENGLISH_EXPERIENCE_RECORDING"] == "1" { Thread.sleep(forTimeInterval: 1.5) }
        let card = app.descendants(matching: .any)["flashcard-pager"].firstMatch
        let shortDrag = card
        let start = shortDrag.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -24, dy: 0)))
        XCTAssertEqual(progress.value as? String, "1 of 4")
        shortDrag.swipeRight()
        XCTAssertEqual(progress.value as? String, "1 of 4")
        XCTAssertFalse(app.buttons["Previous word"].exists)
        XCTAssertFalse(app.staticTexts["flashcard-progress"].exists)
        XCTAssertFalse(app.staticTexts["flashcard-meaning"].exists)
        let originalWord = app.staticTexts["flashcard-word"].label
        app.buttons["reveal-flashcard"].tap()
        XCTAssertTrue(app.staticTexts["flashcard-meaning"].waitForExistence(timeout: 3))
        if ProcessInfo.processInfo.environment["TIDE_ENGLISH_EXPERIENCE_RECORDING"] == "1" { Thread.sleep(forTimeInterval: 1.5) }
        app.buttons["reveal-flashcard"].tap()
        XCTAssertFalse(app.staticTexts["flashcard-meaning"].exists)
        if ProcessInfo.processInfo.environment["TIDE_ENGLISH_EXPERIENCE_RECORDING"] == "1" { Thread.sleep(forTimeInterval: 1.5) }
        card.swipeLeft()
        waitForPage(2)
        if ProcessInfo.processInfo.environment["TIDE_ENGLISH_EXPERIENCE_RECORDING"] == "1" { Thread.sleep(forTimeInterval: 1.5) }
        XCTAssertFalse(app.staticTexts["flashcard-meaning"].exists)
        card.swipeUp()
        XCTAssertEqual(progress.value as? String, "2 of 4")
        card.swipeDown()
        XCTAssertEqual(progress.value as? String, "2 of 4")
        card.swipeRight()
        waitForPage(1)
        XCTAssertEqual(app.staticTexts["flashcard-word"].label, originalWord)
        XCTAssertFalse(app.staticTexts["flashcard-meaning"].exists)
        for page in 2...4 { card.swipeLeft(); waitForPage(page) }
        XCTAssertEqual(progress.value as? String, "4 of 4")
        card.swipeLeft()
        XCTAssertEqual(progress.value as? String, "4 of 4")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Flashcards on iPhone"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["close-flashcards"].tap()
        XCTAssertTrue(trigger.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[originalWord].exists)
    }

    func testFlashcardsLargeTextAndLanguageIsolation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--screenshot=words", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["open-flashcards"].waitForExistence(timeout: 10))
        app.buttons["open-flashcards"].tap()
        XCTAssertTrue(app.staticTexts["flashcard-word"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["close-flashcards"].isHittable)
        app.descendants(matching: .any)["flashcard-pager"].firstMatch.swipeLeft()
        XCTAssertEqual(app.descendants(matching: .any)["flashcard-pager"].firstMatch.value as? String, "2 of 4")
        app.buttons["close-flashcards"].tap()
        // Screenshot fixtures hold their initial language; use a fresh Russian preview for isolation.
        app.terminate()
        app.launchArguments = ["--preview", "--preview-language=ru", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["Words"].tap()
        XCTAssertTrue(app.buttons["open-flashcards"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open-flashcards"].isEnabled)
    }

    func testFlashcardLongMeaningScrollsWithoutChangingCards() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--screenshot=words", "--preview-long-flashcard", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["open-flashcards"].waitForExistence(timeout: 10))
        app.buttons["open-flashcards"].tap()
        app.buttons["reveal-flashcard"].tap()
        let meaning = app.staticTexts["flashcard-meaning"]
        XCTAssertTrue(meaning.waitForExistence(timeout: 5))
        let startY = meaning.frame.minY
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertLessThan(meaning.frame.minY, startY - 10)
        XCTAssertEqual(app.descendants(matching: .any)["flashcard-pager"].firstMatch.value as? String, "1 of 4")
        XCTAssertTrue(app.buttons["close-flashcards"].isHittable)
    }

    func testCaptionPauseSurvivesMeaningVisibilityAndNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-caption-following", "--preview-caption-persistence"]
        app.launch()
        let target = app.descendants(matching: .any)["target-passage-scroll"].firstMatch
        let meaning = app.descendants(matching: .any)["meaning-passage-scroll"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let moved = NSPredicate { _, _ in Int((target.value as? String ?? "0").split(separator: "|").first ?? "0") ?? 0 > 20 }
        expectation(for: moved, evaluatedWith: target)
        waitForExpectations(timeout: 5)
        target.swipeDown()
        meaning.swipeDown()
        XCTAssertTrue((target.value as? String ?? "").contains("paused"))
        XCTAssertTrue((meaning.value as? String ?? "").contains("paused"))
        app.buttons["Hide meaning subtitles"].tap()
        app.buttons["Show meaning subtitles"].tap()
        XCTAssertTrue(meaning.waitForExistence(timeout: 3))
        XCTAssertTrue((meaning.value as? String ?? "").contains("paused"))
        app.buttons["Words"].tap()
        app.buttons["Talk"].tap()
        XCTAssertTrue((target.value as? String ?? "").contains("paused"))
        XCTAssertTrue((meaning.value as? String ?? "").contains("paused"))
    }

    func testCaptionsFollowPauseAcrossStreamingAndResumeNextReply() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-caption-following"]
        app.launch()
        let target = app.descendants(matching: .any)["target-passage-scroll"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        func offset() -> Int { Int((target.value as? String ?? "0").split(separator: "|").first ?? "0") ?? 0 }
        let moving = NSPredicate { _, _ in offset() > 20 }
        expectation(for: moving, evaluatedWith: target)
        waitForExpectations(timeout: 5)
        let micFrame = app.buttons["start-conversation"].frame
        target.swipeDown()
        XCTAssertTrue((target.value as? String ?? "").contains("paused"))
        let paused = offset()
        let stream = NSPredicate { _, _ in app.staticTexts["target-caption"].label.count > 600 }
        expectation(for: stream, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(offset(), paused, accuracy: 2)
        XCTAssertTrue((target.value as? String ?? "").contains("paused"))
        XCTAssertEqual(app.buttons["start-conversation"].frame.midY, micFrame.midY, accuracy: 2)
        let next = NSPredicate { _, _ in app.staticTexts["target-caption"].label.hasPrefix("Ещё") && offset() > 20 }
        expectation(for: next, evaluatedWith: app)
        waitForExpectations(timeout: 12)
        XCTAssertFalse((target.value as? String ?? "").contains("paused"))
    }

}


extension TideEnglishUITests {
    func testInterfaceSwitchesDoNotConstructDiscardedCoordinators() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview", "--preview-personal", "--screenshot=greeting",
                               "--verify-interface-lifecycle", "--preview-interface-theme=paper",
                               "--preview-interface-language=english"]
        app.launch()
        let probe = app.buttons["coordinator-construction-count"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        probe.tap()
        XCTAssertEqual(probe.value as? String, "1")
        var constructionCounts: [String] = []
        for theme in ["midnight", "grove"] {
            app.buttons["settings-button"].tap()
            app.buttons["interface-theme-" + theme].tap()
            app.buttons["Done"].tap()
            probe.tap()
            constructionCounts.append(probe.value as? String ?? "missing")
        }
        for (language, done) in [("中文", "完成"), ("English", "Done")] {
            app.buttons["settings-button"].tap()
            app.buttons["settings-interface-language"].tap()
            app.buttons[language].tap()
            app.buttons[done].tap()
            probe.tap()
            constructionCounts.append(probe.value as? String ?? "missing")
        }
        XCTAssertEqual(constructionCounts, ["1", "1", "1", "1"],
                       "Appearance and locale changes must not rerun the coordinator constructor that replaces store.onSessionInvalidation")
    }
}
