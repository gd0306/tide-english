import Foundation

/// Temporary delivery guidance; it never changes saved learning progress.
public struct ConversationPace: Sendable {
    public enum Delivery: Sendable { case gentle, natural, extended }
    public private(set) var delivery: Delivery = .gentle
    private var successfulPassages = Set<String>()
    private var highSuccesses = 0
    private var helpPassageID: String?
    public init() {}
    @discardableResult public mutating func askForHelp(after passage: Passage? = nil) -> Bool {
        highSuccesses = 0
        helpPassageID = passage?.id
        return set(.gentle)
    }
    /// Call only after LearningEngine.validate has accepted the assessment.
    @discardableResult public mutating func observe(_ assessment: Assessment, passage: Passage, languageID: String) -> Bool {
        guard assessment.passageID == passage.id, assessment.revisionKey == passage.revisionKey,
              passage.speaker == .user, !passage.fragments.isEmpty,
              (0...5).contains(assessment.suggestedLevel) else { return false }
        if assessment.outcome == .breakdown { return askForHelp(after: passage) }
        guard passage.id != helpPassageID, assessment.outcome == .success,
              !passage.fragments.contains(where: { $0.typed || $0.meaningVisible }),
              assessment.words.contains(where: { $0.language == languageID && $0.kind == .independent && $0.confidence >= 0.8 }),
              successfulPassages.insert(passage.id).inserted else { return false }
        highSuccesses = assessment.suggestedLevel >= 4 ? highSuccesses + 1 : 0
        if assessment.suggestedLevel <= 1 { return set(.gentle) }
        return set(highSuccesses >= 2 ? .extended : .natural)
    }
    private mutating func set(_ next: Delivery) -> Bool {
        guard delivery != next else { return false }
        delivery = next
        return true
    }
    public var instruction: String {
        let guidance: String = switch delivery {
        case .gentle: "Use one short sentence at a time, familiar words and a calm, unhurried speaking pace. Leave space to answer."
        case .natural: "Use one or two short sentences and a clear, natural speaking pace. Ask a relevant follow-up that lets the learner expand."
        case .extended: "Use natural connected sentences and a conversational speaking pace. Invite reasons or a short story, keeping each turn concise."
        }
        return "Temporary delivery guidance for the next replies: \(guidance) Keep the selected language and accent. This is provisional; simplify immediately if the learner struggles. Never read this guidance aloud."
    }
}
