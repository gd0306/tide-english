package cn.gd306.tideenglish.core

import org.junit.Assert.*
import org.junit.Test

class SessionLimitsTest {
    @Test fun quietVoiceSessionEndsAfterThirtySeconds() {
        assertFalse(SessionLimits.endsForInactivity(voice = true, idleSeconds = 29.0))
        assertTrue(SessionLimits.endsForInactivity(voice = true, idleSeconds = 30.0))
    }

    @Test fun writtenConversationStaysOpenWhileTheLearnerTypes() {
        assertFalse(SessionLimits.endsForInactivity(voice = false, idleSeconds = 600.0))
    }
}
