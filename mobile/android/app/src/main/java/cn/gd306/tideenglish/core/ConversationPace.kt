package cn.gd306.tideenglish.core

/** Temporary delivery guidance; it never changes saved learning progress. */
class ConversationPace {
    enum class Delivery { GENTLE, NATURAL, EXTENDED }
    var delivery = Delivery.GENTLE
        private set
    private val successfulPassages = mutableSetOf<String>()
    private var highSuccesses = 0
    private var helpPassageID: String? = null
    fun askForHelp(after: Passage? = null): Boolean {
        highSuccesses = 0
        helpPassageID = after?.id
        return set(Delivery.GENTLE)
    }
    /** Call only after LearningEngine.validate has accepted the assessment. */
    fun observe(assessment: Assessment, passage: Passage, languageID: String): Boolean {
        if (assessment.passageID != passage.id || assessment.revisionKey != passage.revisionKey ||
            passage.speaker != Speaker.user || passage.fragments.isEmpty() || assessment.suggestedLevel !in 0..5) return false
        if (assessment.outcome == Outcome.breakdown) return askForHelp(passage)
        if (passage.id == helpPassageID || assessment.outcome != Outcome.success || passage.fragments.any { it.typed || it.meaningVisible } ||
            assessment.words.none { it.language == languageID && it.kind == EvidenceKind.independent && it.confidence >= 0.8 } ||
            !successfulPassages.add(passage.id)) return false
        highSuccesses = if (assessment.suggestedLevel >= 4) highSuccesses + 1 else 0
        if (assessment.suggestedLevel <= 1) return set(Delivery.GENTLE)
        return set(if (highSuccesses >= 2) Delivery.EXTENDED else Delivery.NATURAL)
    }
    private fun set(next: Delivery): Boolean {
        if (delivery == next) return false
        delivery = next
        return true
    }
    val instruction: String get() {
        val guidance = when (delivery) {
            Delivery.GENTLE -> "Use one short sentence at a time, familiar words and a calm, unhurried speaking pace. Leave space to answer."
            Delivery.NATURAL -> "Use one or two short sentences and a clear, natural speaking pace. Ask a relevant follow-up that lets the learner expand."
            Delivery.EXTENDED -> "Use natural connected sentences and a conversational speaking pace. Invite reasons or a short story, keeping each turn concise."
        }
        return "Temporary delivery guidance for the next replies: $guidance Keep the selected language and accent. This is provisional; simplify immediately if the learner struggles. Never read this guidance aloud."
    }
}
