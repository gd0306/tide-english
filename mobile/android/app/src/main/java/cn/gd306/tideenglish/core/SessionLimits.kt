package cn.gd306.tideenglish.core

object SessionLimits {
    const val IDLE_VOICE_SECONDS = 30.0
    fun endsForInactivity(voice: Boolean, idleSeconds: Double): Boolean = voice && idleSeconds >= IDLE_VOICE_SECONDS
}
