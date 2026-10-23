package cn.gd306.tideenglish.core

import org.junit.Assert.*
import org.junit.Test

class ConversationActivityTest {
    @Test fun oneCheckInAndExactDeadlineDespiteItsAudio() {
        val activity = ConversationActivity(100.0)
        assertEquals(ConversationActivity.Action.Wait, activity.tick(114.9))
        assertEquals(ConversationActivity.Action.CheckIn, activity.tick(115.0))
        activity.assistantActive(120.0)
        assertEquals(ConversationActivity.Action.Wait, activity.tick(124.0))
        assertEquals(ConversationActivity.Action.Warning(5), activity.tick(125.0))
        assertEquals(ConversationActivity.Action.Warning(1), activity.tick(129.1))
        assertEquals(ConversationActivity.Action.End, activity.tick(130.0))
    }
    @Test fun genuineAnswerRestartsQuietWindowAndAllowsLaterCheckIn() {
        val activity = ConversationActivity(0.0)
        assertEquals(ConversationActivity.Action.CheckIn, activity.tick(15.0))
        activity.learnerEngaged(29.0); activity.assistantActive(33.0)
        assertEquals(ConversationActivity.Action.Wait, activity.tick(47.0))
        assertEquals(ConversationActivity.Action.CheckIn, activity.tick(48.0))
        assertEquals(ConversationActivity.Action.End, activity.tick(63.0))
    }
    @Test fun microphoneNoiseAndAssistantMonologueCannotKeepSessionOpen() {
        val noisy = ConversationActivity(0.0)
        for (second in 0 until 45) { noisy.inputActive(second.toDouble()); assertNotEquals(ConversationActivity.Action.End, noisy.tick(second.toDouble())) }
        noisy.inputActive(45.0)
        assertEquals(ConversationActivity.Action.End, noisy.tick(45.0))
        val monologue = ConversationActivity(0.0)
        for (second in 0..90) monologue.assistantActive(second.toDouble())
        assertEquals(ConversationActivity.Action.End, monologue.tick(90.0))
    }
    @Test fun mutedInputDoesNotPreventCloseOrTriggerCheckIn() {
        val activity = ConversationActivity(0.0)
        activity.inputActive(15.0)
        assertEquals(ConversationActivity.Action.Wait, activity.tick(15.0, muted = true))
        activity.inputActive(30.0)
        assertEquals(ConversationActivity.Action.End, activity.tick(30.0, muted = true))
    }
    @Test fun typingAndPendingResponseGraceAreBounded() {
        val typing = ConversationActivity(0.0)
        typing.typing(20.0)
        assertEquals(ConversationActivity.Action.Wait, typing.tick(25.0))
        for (second in 26..79) { typing.typing(second.toDouble()); assertNotEquals(ConversationActivity.Action.End, typing.tick(second.toDouble())) }
        typing.typing(80.0)
        assertEquals(ConversationActivity.Action.End, typing.tick(80.0))
        val pending = ConversationActivity(0.0)
        assertEquals(ConversationActivity.Action.Wait, pending.tick(10.0, busy = true))
        assertEquals(ConversationActivity.Action.Warning(5), pending.tick(50.0, busy = true))
        assertEquals(ConversationActivity.Action.End, pending.tick(55.0, busy = true))
    }
    @Test fun abandonedDraftAndFinishedHelperDoNotCountAsReplies() {
        val draft = ConversationActivity(0.0)
        draft.typing(20.0)
        assertEquals(ConversationActivity.Action.End, draft.tick(30.0))
        val helper = ConversationActivity(0.0)
        assertEquals(ConversationActivity.Action.Wait, helper.tick(10.0, busy = true))
        assertEquals(ConversationActivity.Action.End, helper.tick(30.0, busy = false))
        assertEquals(30.0, ConversationActivity.QUIET_SECONDS, 0.0)
    }
}
