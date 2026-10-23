import XCTest
@testable import TideEnglishCore

final class ConversationPaceTests: XCTestCase {
    private func sample(_ id: String, typed: Bool = false, meaning: Bool = false, level: Int = 4, outcome: Outcome = .success, evidence: EvidenceKind = .independent, language: String = "nb") -> (Assessment, Passage) {
        let fragment = Fragment(id: id, speaker: .user, text: "Jeg liker å gå på tur", startMS: 0, endMS: 1000, meaningVisible: meaning, typed: typed)
        let passage = Passage(id: id, speaker: .user, fragments: [fragment])
        let word = WordProposal(lemma: "tur", meaning: "walk", form: "tur", kind: evidence, confidence: 0.9, sourceIDs: [id], quote: fragment.text, language: language)
        return (Assessment(passageID: id, revisionKey: passage.revisionKey, outcome: outcome, suggestedLevel: level, nextGoal: "Fortell mer", capability: "describes an interest", words: [word]), passage)
    }
    func testEarlyAdaptationAndDuplicateRevisionCannotAccelerateIt() {
        var pace = ConversationPace()
        XCTAssertEqual(pace.delivery, .gentle)
        let (first, passage) = sample("first")
        XCTAssertTrue(pace.observe(first, passage: passage, languageID: "nb"))
        XCTAssertEqual(pace.delivery, .natural)
        XCTAssertFalse(pace.observe(first, passage: passage, languageID: "nb"))
        let (second, next) = sample("second")
        XCTAssertTrue(pace.observe(second, passage: next, languageID: "nb"))
        XCTAssertEqual(pace.delivery, .extended)
        XCTAssertTrue(pace.askForHelp())
        XCTAssertEqual(pace.delivery, .gentle)
        XCTAssertEqual(ConversationPace().delivery, .gentle)
    }
    func testUncertainAssistedTypedOtherLanguageAndStaleEvidenceCannotRaisePace() {
        var pace = ConversationPace()
        let cases = [sample("typed", typed: true), sample("visible", meaning: true), sample("uncertain", outcome: .uncertain), sample("assisted", evidence: .assisted), sample("foreign", language: "es"), sample("invalid", level: 9)]
        for (assessment, passage) in cases { XCTAssertFalse(pace.observe(assessment, passage: passage, languageID: "nb")) }
        var (stale, passage) = sample("stale")
        stale.revisionKey = "older"
        XCTAssertFalse(pace.observe(stale, passage: passage, languageID: "nb"))
        XCTAssertEqual(pace.delivery, .gentle)
    }
    func testBreakdownImmediatelySimplifiesWithoutChangingAssessment() {
        var pace = ConversationPace()
        let (good, first) = sample("good")
        pace.observe(good, passage: first, languageID: "nb")
        let (bad, next) = sample("struggle", outcome: .breakdown)
        XCTAssertTrue(pace.observe(bad, passage: next, languageID: "nb"))
        XCTAssertEqual(pace.delivery, .gentle)
        XCTAssertEqual(bad.suggestedLevel, 4)
        XCTAssertTrue(pace.instruction.contains("unhurried"))
    }
    func testHelpWinsOverAnAssessmentThatWasAlreadyInFlight() {
        var pace = ConversationPace()
        let (assessment, passage) = sample("in-flight")
        pace.askForHelp(after: passage)
        XCTAssertFalse(pace.observe(assessment, passage: passage, languageID: "nb"))
        XCTAssertEqual(pace.delivery, .gentle)
        let (fresh, next) = sample("fresh")
        XCTAssertTrue(pace.observe(fresh, passage: next, languageID: "nb"))
        XCTAssertEqual(pace.delivery, .natural)
    }
}
