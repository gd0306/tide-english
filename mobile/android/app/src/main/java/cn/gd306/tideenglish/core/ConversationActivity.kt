package cn.gd306.tideenglish.core

import kotlin.math.ceil
import kotlin.math.max

/** An unanswered check-in never extends the paid session. Times use a monotonic clock. */
class ConversationActivity(now: Double) {
    sealed interface Action {
        data object Wait : Action
        data object CheckIn : Action
        data class Warning(val seconds: Int) : Action
        data object End : Action
    }
    private var quietSince = now
    private var outputDeadline = now + 60
    private var lastInput: Double? = null
    private var typingStarted: Double? = null
    private var lastTyping: Double? = null
    private var busyStarted: Double? = null
    private var checkedIn = false
    fun learnerEngaged(now: Double) {
        quietSince = now; outputDeadline = now + 60; checkedIn = false
        typingStarted = null; lastTyping = null; lastInput = null; busyStarted = null
    }
    fun assistantActive(now: Double) { if (!checkedIn && now <= outputDeadline) quietSince = now }
    fun inputActive(now: Double) { lastInput = now }
    fun typing(now: Double) { if (typingStarted == null) typingStarted = now; lastTyping = now }
    fun tick(now: Double, muted: Boolean = false, busy: Boolean = false): Action {
        if (busy && busyStarted == null) busyStarted = now
        if (!busy) busyStarted = null
        val recentInput = !muted && lastInput?.let { now - it < 1.5 } == true
        val editing = lastTyping?.let { now - it < 10 } == true
        var deadline = quietSince + QUIET_SECONDS
        if (recentInput) deadline += SPEECH_GRACE_SECONDS
        if (editing) typingStarted?.let { deadline = max(deadline, it + TYPING_GRACE_SECONDS) }
        if (busy) busyStarted?.let { deadline = max(deadline, it + RESPONSE_GRACE_SECONDS) }
        if (now >= deadline) return Action.End
        if (deadline - now <= 5) return Action.Warning(ceil(deadline - now).toInt())
        if (!checkedIn && !muted && !recentInput && !editing && !busy && now - quietSince >= CHECK_IN_SECONDS) {
            checkedIn = true; return Action.CheckIn
        }
        return Action.Wait
    }
    companion object {
        const val QUIET_SECONDS = SessionLimits.IDLE_VOICE_SECONDS
        const val CHECK_IN_SECONDS = 15.0
        const val SPEECH_GRACE_SECONDS = 15.0
        const val TYPING_GRACE_SECONDS = 60.0
        const val RESPONSE_GRACE_SECONDS = 45.0
    }
}
