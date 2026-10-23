package cn.gd306.tideenglish.core

/** Translates only app-authored notices. Provider output and learner text pass through unchanged. */
object ProviderVoiceMessages {
    private const val nativePrefix = "Native voice is unavailable for this account. "
    private val chinese = mapOf(
        "Device speech with the selected provider. Voice requires on-device recognition; typing is always available." to "设备端语音与所选服务配合使用。语音功能需要设备端识别；文字输入始终可用。",
        "Device speech output is unavailable for this language. Replies remain visible as text." to "此语言的设备端语音播放不可用，回复仍会以文字显示。",
        "On-device speech recognition is unavailable on this device. Use typing to continue with this provider." to "此设备不支持设备端语音识别。请使用文字输入继续与所选服务对话。",
        "On-device recognition could not start. Use typing to continue with this provider." to "无法启动设备端识别。请使用文字输入继续与所选服务对话。",
        "On-device recognition is unavailable. Use typing to continue with this provider." to "设备端识别不可用。请使用文字输入继续与所选服务对话。",
        "The selected provider could not complete this voice turn. Please try again." to "所选服务无法完成本轮语音对话，请重试。",
        "Using device speech with the same selected provider." to "正在使用设备端语音，模型服务保持不变。",
        "GLM native realtime voice" to "GLM 原生实时语音",
        "Gemini native Live voice" to "Gemini 原生 Live 语音",
        "Live learning-plan updates apply at your next conversation." to "实时学习计划的更新将在下次对话生效。",
        "Microphone permission is required." to "需要麦克风权限。",
        "Device audio could not start." to "无法启动设备音频。",
        "Voice audio focus is unavailable." to "无法获取语音音频焦点。",
        "Add this provider's API key in Settings." to "请在设置中添加此服务的 API 密钥。",
        "Native voice setup could not be sent." to "无法发送原生语音配置。",
        "Native voice returned an invalid response." to "原生语音返回了无效响应。",
        "Native voice could not connect." to "无法连接原生语音。",
        "Native voice disconnected. Please reconnect." to "原生语音已断开，请重新连接。",
        "Native voice disconnected." to "原生语音已断开。",
        "Native voice is disconnected." to "原生语音未连接。",
        "Native voice could not keep up. Please reconnect." to "原生语音传输无法跟上，请重新连接。",
        "Device voice audio stopped. Please reconnect." to "设备语音音频已停止，请重新连接。",
        "Native voice connection timed out. Please try again." to "原生语音连接超时，请重试。",
        "Native voice could not start. Check model access and microphone permission." to "无法启动原生语音，请检查模型访问权限和麦克风权限。",
        "Voice playback could not keep up. Please reconnect." to "语音播放无法跟上，请重新连接。",
        "The voice update could not be sent. Please reconnect." to "无法发送语音更新，请重新连接。",
        "Gemini voice authorization could not connect." to "无法连接 Gemini 语音授权服务。",
        "Gemini native voice is unavailable for this account." to "此账号无法使用 Gemini 原生语音。",
        "Gemini voice authorization was incomplete." to "Gemini 语音授权未完成。",
        "Native voice is unavailable for this account." to "此账号无法使用原生语音。",
        "This native voice session is ending. Reconnect to continue." to "本次原生语音会话即将结束，请重新连接以继续。",
        "Invalid voice response." to "语音响应无效。",
        "Invalid voice history." to "语音历史记录无效。",
        "The model settings couldn't be saved. Check the HTTPS endpoint and model ID." to "无法保存模型设置，请检查 HTTPS 地址和模型 ID。",
        "The AI permission couldn't be saved. Please try again." to "无法保存 AI 授权，请重试。",
        "Enter a valid chat model ID." to "请输入有效的对话模型 ID。",
        "Enter a valid HTTPS API endpoint." to "请输入有效的 HTTPS API 地址。",
        "Enter an HTTPS API endpoint without credentials, query, fragment or relative paths." to "请输入不含凭据、查询参数、片段或相对路径的 HTTPS API 地址。",
        "Use the official endpoint or select Custom." to "请使用官方地址，或选择自定义服务。",
        "Enter a nonempty API key without spaces or control characters." to "请输入不含空格或控制字符的非空 API 密钥。",
        "This provider does not support current-topic search. Select OpenAI or GLM to search." to "此服务不支持当前话题搜索，请选择 OpenAI 或 GLM 进行搜索。",
        "This request could not be completed. Try another topic." to "无法完成此请求，请尝试其他话题。",
        "The provider could not be reached. Please try again." to "无法连接模型服务，请重试。",
        "This provider did not accept the API key. Check Settings." to "此服务未接受该 API 密钥，请检查设置。",
        "This API key may not have access to the selected model." to "此 API 密钥可能没有所选模型的访问权限。",
        "This provider's usage or rate limit was reached." to "已达到此服务的用量或请求频率限制。",
        "The provider returned an incomplete response. Please try again." to "模型服务返回的响应不完整，请重试。",
    )

    fun localize(message: String, chinese: Boolean): String {
        if (!chinese) return message
        this.chinese[message]?.let { return it }
        if (message.startsWith(nativePrefix)) {
            this.chinese[message.removePrefix(nativePrefix)]?.let { suffix ->
                return this.chinese.getValue(nativePrefix.trimEnd()) + suffix
            }
        }
        return message
    }
}
