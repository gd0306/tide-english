package cn.gd306.tideenglish.core

import org.junit.Assert.*
import org.junit.Test

class ConversationPaceTest {
    private fun sample(id: String, typed: Boolean = false, meaning: Boolean = false, level: Int = 4, outcome: Outcome = Outcome.success, evidence: EvidenceKind = EvidenceKind.independent, language: String = "nb"): Pair<Assessment, Passage> {
        val fragment = Fragment(id = id, speaker = Speaker.user, text = "Jeg liker å gå på tur", startMS = 0, endMS = 1000, meaningVisible = meaning, typed = typed)
        val passage = Passage(id, Speaker.user, listOf(fragment))
        val word = WordProposal("tur", "walk", "tur", evidence, 0.9, listOf(id), fragment.text, language)
        return Assessment(id, passage.revisionKey, outcome, level, "Fortell mer", "describes an interest", listOf(word)) to passage
    }
    @Test fun earlyAdaptationAndDuplicateRevisionCannotAccelerateIt() {
        val pace = ConversationPace()
        assertEquals(ConversationPace.Delivery.GENTLE, pace.delivery)
        val (first, passage) = sample("first")
        assertTrue(pace.observe(first, passage, "nb"))
        assertEquals(ConversationPace.Delivery.NATURAL, pace.delivery)
        assertFalse(pace.observe(first, passage, "nb"))
        val (second, next) = sample("second")
        assertTrue(pace.observe(second, next, "nb"))
        assertEquals(ConversationPace.Delivery.EXTENDED, pace.delivery)
        assertTrue(pace.askForHelp())
        assertEquals(ConversationPace.Delivery.GENTLE, pace.delivery)
        assertEquals(ConversationPace.Delivery.GENTLE, ConversationPace().delivery)
    }
    @Test fun uncertainAssistedTypedOtherLanguageAndStaleEvidenceCannotRaisePace() {
        val pace = ConversationPace()
        val cases = listOf(sample("typed", typed = true), sample("visible", meaning = true), sample("uncertain", outcome = Outcome.uncertain), sample("assisted", evidence = EvidenceKind.assisted), sample("foreign", language = "es"), sample("invalid", level = 9))
        for ((assessment, passage) in cases) assertFalse(pace.observe(assessment, passage, "nb"))
        val (stale, passage) = sample("stale")
        assertFalse(pace.observe(stale.copy(revisionKey = "older"), passage, "nb"))
        assertEquals(ConversationPace.Delivery.GENTLE, pace.delivery)
    }
    @Test fun breakdownImmediatelySimplifiesWithoutChangingAssessment() {
        val pace = ConversationPace()
        val (good, first) = sample("good")
        pace.observe(good, first, "nb")
        val (bad, next) = sample("struggle", outcome = Outcome.breakdown)
        assertTrue(pace.observe(bad, next, "nb"))
        assertEquals(ConversationPace.Delivery.GENTLE, pace.delivery)
        assertEquals(4, bad.suggestedLevel)
        assertTrue(pace.instruction.contains("unhurried"))
    }
    @Test fun helpWinsOverAnAssessmentThatWasAlreadyInFlight() {
        val pace = ConversationPace()
        val (assessment, passage) = sample("in-flight")
        pace.askForHelp(passage)
        assertFalse(pace.observe(assessment, passage, "nb"))
        assertEquals(ConversationPace.Delivery.GENTLE, pace.delivery)
        val (fresh, next) = sample("fresh")
        assertTrue(pace.observe(fresh, next, "nb"))
        assertEquals(ConversationPace.Delivery.NATURAL, pace.delivery)
    }
}
