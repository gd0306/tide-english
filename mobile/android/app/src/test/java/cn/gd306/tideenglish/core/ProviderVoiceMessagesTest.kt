package cn.gd306.tideenglish.core

import org.junit.Assert.*
import org.junit.Test

class ProviderVoiceMessagesTest {
    @Test fun translatesCapabilitiesAndTypingFallback() {
        assertEquals("GLM 原生实时语音", ProviderVoiceMessages.localize("GLM native realtime voice", true))
        assertEquals("此设备不支持设备端语音识别。请使用文字输入继续与所选服务对话。", ProviderVoiceMessages.localize("On-device speech recognition is unavailable on this device. Use typing to continue with this provider.", true))
        assertEquals("设备端语音与所选服务配合使用。语音功能需要设备端识别；文字输入始终可用。", ProviderVoiceMessages.localize("Device speech with the selected provider. Voice requires on-device recognition; typing is always available.", true))
    }
    @Test fun translatesSafeFailuresAndSettingsErrors() {
        assertEquals("原生语音连接超时，请重试。", ProviderVoiceMessages.localize("Native voice connection timed out. Please try again.", true))
        assertEquals("无法保存模型设置，请检查 HTTPS 地址和模型 ID。", ProviderVoiceMessages.localize("The model settings couldn't be saved. Check the HTTPS endpoint and model ID.", true))
        assertEquals("无法保存 AI 授权，请重试。", ProviderVoiceMessages.localize("The AI permission couldn't be saved. Please try again.", true))
    }
    @Test fun composesOnlyKnownNativeFallbackSuffix() {
        val english = "Native voice is unavailable for this account. On-device recognition is unavailable. Use typing to continue with this provider."
        assertEquals("此账号无法使用原生语音。设备端识别不可用。请使用文字输入继续与所选服务对话。", ProviderVoiceMessages.localize(english, true))
        val unknown = "Native voice is unavailable for this account. My private lesson sentence."
        assertEquals(unknown, ProviderVoiceMessages.localize(unknown, true))
    }
    @Test fun englishAndUnknownLearningTextRemainUnchanged() {
        val known = "Microphone permission is required."
        assertEquals(known, ProviderVoiceMessages.localize(known, false))
        for (text in listOf("I would like to practise ordering tea.", "模型学习内容。", "Native voice failed: private provider error")) {
            assertEquals(text, ProviderVoiceMessages.localize(text, true))
        }
    }
}
