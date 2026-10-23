import XCTest
@testable import TideEnglishCore

final class InterfacePresentationTests: XCTestCase {
    func testKnownStorageAndStartupCopyUsesChinese() {
        assertChinese([
            ("Tide English couldn’t delete the older learning backup. Your conversations are still here. Please try again.", "Tide English 无法删除旧的学习备份。你的对话仍然保留。请重试。"),
            ("Tide English couldn’t save your progress. Please export a backup and try again.", "Tide English 无法保存你的进度。请导出备份后重试。"),
            ("Enter a valid API key.", "请输入有效的 API 密钥。"),
            ("The key couldn’t be saved to this device’s Keychain.", "无法将密钥保存到此设备的钥匙串。"),
            ("The key couldn’t be removed. Unlock this iPhone and try again.", "无法移除密钥。请解锁此 iPhone 后重试。"),
            ("Tide English couldn’t open its learning record. Your existing data has not been replaced.", "Tide English 无法打开学习记录。你现有的数据未被替换。"),
            ("The learning record is unavailable.", "学习记录暂不可用。"),
            ("Provider needs attention", "请检查提供方设置"),
            ("On", "开启")
        ])
    }

    func testKnownVoiceFallbackAndOpenAIRecoveryCopyUsesChinese() {
        assertChinese([
            ("GLM realtime is unavailable for this account. Using on-device turn-based voice with your selected GLM chat model.", "此账户无法使用 GLM 实时语音。将使用设备端轮流对话语音和你选择的 GLM 对话模型。"),
            ("Gemini native realtime is unavailable for this account. Using on-device turn-based voice with your selected Gemini chat model.", "此账户无法使用 Gemini 原生实时语音。将使用设备端轮流对话语音和你选择的 Gemini 对话模型。"),
            ("The network connection was lost. Tap to start a new conversation.", "网络连接已断开。轻点以开始新对话。"),
            ("Allow microphone access in iPhone Settings → Tide English to start a conversation.", "请在 iPhone 设置 → Tide English 中允许麦克风访问，以开始对话。"),
            ("The voice connection couldn’t be established. Check your connection and try again.", "无法建立语音连接。请检查网络连接后重试。"),
            ("The voice connection took too long. Please try again.", "语音连接超时。请重试。"),
            ("The voice connection ended unexpectedly. Your conversation has been saved.", "语音连接意外结束。你的对话已保存。")
        ])
    }

    func testKnownGLMVoiceRecoveryCopyUsesChinese() {
        assertChinese([
            ("GLM native realtime is unavailable for this account.", "此账户无法使用 GLM 原生实时语音。"),
            ("Allow Tide English microphone access in Settings to use GLM voice.", "请在设置中允许 Tide English 访问麦克风，以使用 GLM 语音。"),
            ("GLM voice audio could not start or continue. Check your microphone and audio route.", "GLM 语音无法启动或继续。请检查麦克风和音频输出设备。"),
            ("GLM voice did not confirm setup in time. Please try again.", "GLM 语音未能及时确认连接设置。请重试。"),
            ("GLM voice could not keep up with this connection. Start a new conversation.", "GLM 语音无法跟上当前连接。请开始新对话。"),
            ("Your GLM key must have the provider's id.secret format. Check it in Settings.", "你的 GLM 密钥必须采用提供方的 id.secret 格式。请在设置中检查。"),
            ("Your GLM key wasn’t accepted. Check it in Settings.", "你的 GLM 密钥未被接受。请在设置中检查。"),
            ("GLM billing or account limits need attention. Check your provider account.", "请检查 GLM 的计费或账户限额。请查看提供方账户。"),
            ("GLM is limiting requests. Wait briefly and try again.", "GLM 正在限制请求。请稍后重试。"),
            ("GLM native realtime access was denied. Check your account and start a new conversation.", "GLM 原生实时语音访问被拒绝。请检查账户后开始新对话。"),
            ("GLM voice connection was lost. Start a new conversation.", "GLM 语音连接已断开。请开始新对话。"),
            ("GLM returned an invalid voice response. Start a new conversation.", "GLM 返回了无效的语音响应。请开始新对话。"),
            ("GLM could not accept this voice request. Check the provider settings and start again.", "GLM 无法接受此语音请求。请检查提供方设置后重新开始。")
        ])
    }

    func testKnownGeminiVoiceRecoveryCopyUsesChinese() {
        assertChinese([
            ("Allow Tide English microphone access in Settings to use Gemini voice.", "请在设置中允许 Tide English 访问麦克风，以使用 Gemini 语音。"),
            ("Gemini voice audio could not start or continue. Check your microphone and audio route.", "Gemini 语音无法启动或继续。请检查麦克风和音频输出设备。"),
            ("Gemini voice settings or consent changed. Start a new conversation.", "Gemini 语音设置或授权已更改。请开始新对话。"),
            ("Gemini voice did not confirm setup in time. Your conversation is saved; please start again.", "Gemini 语音未能及时确认连接设置。你的对话已保存，请重新开始。"),
            ("Gemini voice could not keep up with this connection. Your conversation is saved; please start again.", "Gemini 语音无法跟上当前连接。你的对话已保存，请重新开始。"),
            ("Your Gemini key or account access wasn’t accepted. Check Google AI Studio and Settings.", "你的 Gemini 密钥或账户访问权限未被接受。请检查 Google AI Studio 和设置。"),
            ("Gemini returned HTTP 402: prepaid credits are unavailable. Check this key’s project and billing balance in Google AI Studio before starting again.", "Gemini 返回 HTTP 402：预付额度不可用。再次开始前，请在 Google AI Studio 检查此密钥的项目和计费余额。"),
            ("Gemini request or billing limits need attention. Check Google AI Studio, then try again.", "请检查 Gemini 的请求或计费限额。请查看 Google AI Studio 后重试。"),
            ("Gemini voice could not safely resume. Your conversation is saved; start a new conversation to continue.", "Gemini 语音无法安全恢复。你的对话已保存，请开始新对话以继续。"),
            ("Gemini native realtime is unavailable for this account.", "此账户无法使用 Gemini 原生实时语音。"),
            ("Gemini returned an invalid voice response. Your conversation is saved; start again.", "Gemini 返回了无效的语音响应。你的对话已保存，请重新开始。"),
            ("Gemini voice connection was lost. Your conversation is saved; start again.", "Gemini 语音连接已断开。你的对话已保存，请重新开始。")
        ])
    }

    func testMissingProviderKeyGuidancePreservesKnownProviderNames() {
        assertChinese([
            ("Add your OpenAI key in Settings to begin.", "请先在设置中添加 OpenAI 密钥。"),
            ("Add your DeepSeek key in Settings to begin.", "请先在设置中添加 DeepSeek 密钥。"),
            ("Add your GLM (BigModel) key in Settings to begin.", "请先在设置中添加 GLM (BigModel) 密钥。"),
            ("Add your Gemini key in Settings to begin.", "请先在设置中添加 Gemini 密钥。"),
            ("Add your Custom key in Settings to begin.", "请先在设置中添加 Custom 密钥。")
        ])
    }

    func testRecoveryTemplatesDoNotTranslateUnknownOrExtendedProviderErrors() {
        for input in [
            "Add your Unlisted Provider key in Settings to begin.",
            "Add your DeepSeek key in Settings to begin. Extra provider content",
            "Provider says: Add your Gemini key in Settings to begin.",
            "Add your Gemini\nkey in Settings to begin.",
            "GLM returned an invalid voice response. Start a new conversation. Details from provider",
            "The operation couldn’t be completed. (NSURLErrorDomain error -1009.)",
            "session.started", "gpt-live-1", "glm-realtime", "gemini-3.8-flash"
        ] {
            XCTAssertEqual(InterfaceText.string(input, language: .chinese), input)
        }
    }

    // These fixtures catch ignored/corrupt saved values and preference-order regressions.
    func testMissingAndCorruptThemeRestorePaper() {
        for saved in [nil, "", "ocean", "MIDNIGHT"] as [String?] {
            XCTAssertEqual(InterfaceConfiguration.restored(theme: saved, language: "english", preferredLanguages: []).theme, .paper)
        }
    }

    func testValidSavedThemeAndLanguageOverrideSystemPreferences() {
        XCTAssertEqual(InterfaceConfiguration.restored(theme: "midnight", language: "english", preferredLanguages: ["zh-Hans-CN"]), InterfaceConfiguration(theme: .midnight, language: .english))
        XCTAssertEqual(InterfaceConfiguration.restored(theme: "grove", language: "chinese", preferredLanguages: ["en-US"]), InterfaceConfiguration(theme: .grove, language: .chinese))
    }

    func testLanguageFollowsFirstSupportedSystemPreference() {
        let fixtures: [([String], InterfaceLanguage)] = [
            (["zh-Hans-CN", "en-US"], .chinese), (["zh-Hant-TW"], .chinese),
            (["en-GB", "zh-CN"], .english), (["fr-FR", "zh_CN", "en"], .chinese),
            (["ja", "EN_us", "zh"], .english), (["zh"], .chinese),
            (["zhish", "fr"], .english), ([], .english)
        ]
        for (preferences, expected) in fixtures {
            for saved in [nil, "", "unknown"] as [String?] {
                XCTAssertEqual(InterfaceConfiguration.restored(theme: nil, language: saved, preferredLanguages: preferences).language, expected, "\(preferences)")
            }
        }
    }

    func testChineseNavigationAndPresentationControls() {
        assertChinese([
            ("Talk", "对话"), ("Themes", "话题"), ("Words", "词汇"), ("Settings", "设置"),
            ("Model & API key", "模型与 API Key"), ("Done", "完成"),
            ("Appearance & language", "外观与语言"), ("Interface language", "界面语言"),
            ("Paper", "纸页"), ("Midnight", "夜读"), ("Grove", "林间"),
            ("Theme style", "主题风格"),
            ("Warm paper, quiet focus", "暖白纸页，专注练习"),
            ("Soft light for late practice", "柔和夜色，安心练习"),
            ("Fresh greens, a little calm", "清新草绿，慢慢开口")
        ])
    }

    func testInterruptionAlertTitleUsesChineseFunctionalCopy() {
        XCTAssertEqual(InterfaceText.string("A little interruption", language: .chinese), "提示")
    }

    func testEnglishIsExactPassThroughIncludingDynamicCopy() {
        for input in ["Talk", "Settings", "15 minutes", "Gemini couldn’t complete the request (HTTP 503). Please try again.", "你好\nA café ☕", ""] {
            XCTAssertEqual(InterfaceText.string(input, language: .english), input)
        }
    }

    func testUnknownLearningAndProtocolContentRemainUntouched() {
        for input in ["I like coffee.", "我喜欢喝咖啡。", "こんにちは", "Talk about Settings with me.", "My story: 15 minutes", "gpt-live-1", "deepseek-flash", "session.started", "https://api.deepseek.com", "en", "zh-Hans", "OpenAI", "Gemini", "Tide English"] {
            XCTAssertEqual(InterfaceText.string(input, language: .chinese), input)
        }
    }

    func testNumericTemplatesRetainTheirValues() {
        assertChinese([
            ("5 minutes", "5 分钟"), ("60 minutes", "60 分钟"), ("Ending in 9s", "9 秒后结束"),
            ("Ending in 12s\nReply to continue", "12 秒后结束\n回复以继续"),
            ("Step 2 of 2", "第 2 步，共 2 步"), ("2 of 3 recall bars", "回忆强度 2 格，共 3 格"),
            ("4 of 27", "第 4 个，共 27 个"),
            ("8 independent uses · Last seen Oct 13, 2026", "8 次独立使用 · 最近出现：Oct 13, 2026")
        ])
    }

    func testDynamicLanguageAndProviderValuesStayVerbatim() {
        assertChinese([
            ("Reply in Norwegian or another language", "用挪威语或其他语言回复"),
            ("Little by little · Mandarin", "日积月累 · Mandarin"),
            ("GLM (BigModel) bills your account for usage.", "GLM (BigModel) 会向你的账户收取使用费用。"),
            ("Key removed. Add a key before talking with DeepSeek.", "密钥已移除。与 DeepSeek 对话前请先添加密钥。"),
            ("DeepSeek is temporarily unavailable. Please try again shortly.", "DeepSeek 暂时不可用。请稍后重试。"),
            ("Gemini couldn’t complete the request (HTTP 503). Please try again.", "Gemini 无法完成请求（HTTP 503）。请重试。")
        ])
    }

    func testProviderReferenceIsRetainedWithoutExposingOrRewritingItsValue() {
        XCTAssertEqual(InterfaceText.string("Your DeepSeek key wasn’t accepted. Check or replace it here.\n\nReference: req_fixture-42", language: .chinese), "你的 DeepSeek 密钥未被接受。请在此检查或更换。\n\n参考编号：req_fixture-42")
        let unknown = "A provider-authored message.\n\nReference: req_fixture-42"
        XCTAssertEqual(InterfaceText.string(unknown, language: .chinese), unknown)
    }

    func testTemplatesRequireWholeFunctionalMessageAndValidNumbers() {
        for input in ["15 minutes later I went home", "Say: Ending in 9s", "-4 minutes", "five minutes", "Step 2 of 2\nmy story", "OpenAI bills your account for usage. Extra provider content", "Ending in 9s\nReply to continue\nMore", "3 of 3 recall bars\n"] {
            XCTAssertEqual(InterfaceText.string(input, language: .chinese), input)
        }
    }

    func testOnboardingAndPrivacyFunctionalCopy() {
        assertChinese([
            ("Agree and continue", "同意并继续"), ("I’m 18 or older", "我已年满 18 周岁"),
            ("What would you\nlike to speak?", "你想练习\n哪种语言？"), ("Subtitle language", "字幕语言"),
            ("Before we talk.", "开始对话前。"), ("Withdraw permission", "撤回授权"),
            ("AI processing is off. Your saved words and conversations remain available on this iPhone.", "AI 处理已关闭。你仍可在此 iPhone 上查看已保存的词汇和对话。"),
            ("Any active conversation will end. Your saved learning history stays on this iPhone. This does not undo processing already completed by your model provider.", "正在进行的对话将结束。已保存的学习记录会保留在此 iPhone 上。模型提供方已完成的处理无法撤销。")
        ])
    }

    func testProviderConsentPreservesRecipientEndpointAndModelVoiceIdentity() {
        let input = "With your permission, Tide English sends selected conversation text and learning context to DeepSeek at https://api.deepseek.com for conversations, meanings and learning assessment. Voice recognition stays on this iPhone; recognised text goes to the selected model and replies use system reading. Your own key connects directly. Provider retention and billing rules apply. You can withdraw permission in Settings → AI processing."
        XCTAssertEqual(InterfaceText.string(input, language: .chinese), "经你授权，Tide English 会将选定的对话文本和学习上下文发送至 DeepSeek（https://api.deepseek.com），用于对话、释义和学习评估。语音识别在此 iPhone 上进行；识别后的文本会发送至所选模型，回复由系统朗读。你的密钥直接连接提供方。提供方的数据保留和计费规则适用。你可在设置 → AI 处理中撤回授权。")
        assertChinese([("Native live voice uses gpt-live-1.", "原生实时语音使用 gpt-live-1。")])
    }

    func testModelEditorFunctionalCopyAndValidationGuidance() {
        assertChinese([
            ("Provider", "提供方"), ("Chat model", "对话模型"), ("HTTPS API base URL", "HTTPS API 基础 URL"),
            ("Saved on this iPhone", "已保存在此 iPhone 上"), ("No key saved", "未保存密钥"),
            ("Save model settings", "保存模型设置"), ("Model settings saved.", "模型设置已保存。"),
            ("End this conversation before changing model settings.", "请先结束本次对话，再更改模型设置。"),
            ("Enter a nonempty API key without spaces or control characters.", "请输入非空 API Key，且不含空格或控制字符。")
        ])
    }

    func testLearningDataAndRecallUI() {
        assertChinese([
            ("Past conversations", "历史对话"), ("Learning backup & data", "学习备份与数据"),
            ("Export learning backup", "导出学习备份"), ("Import learning backup", "导入学习备份"),
            ("Delete this conversation and its learning evidence?", "删除此对话及其学习记录？"),
            ("Your backup has been imported.", "备份已导入。"), ("Fragile", "初步记忆"),
            ("Growing", "逐渐熟悉"), ("Steady", "稳定掌握"), ("Tap to reveal meaning", "轻点查看释义"),
            ("Correct a misheard phrase. Learning evidence from the old wording will be removed; the original remains in your backup history.", "修正识别有误的语句。旧文本的学习记录将被移除；原文仍保留在备份历史中。")
        ])
    }

    func testCallStatusesAndAppAuthoredSpeechErrors() {
        assertChinese([
            ("Ready when you are", "准备好了就开始"), ("Getting comfortable…", "正在准备…"),
            ("Tide English is speaking", "Tide English 正在说话"), ("I’m listening", "我在听"),
            ("Take your time", "慢慢来"), ("Saving our conversation…", "正在保存对话…"),
            ("Mute microphone", "麦克风静音"), ("Unmute microphone", "取消麦克风静音"),
            ("Type a reply", "输入回复"), ("Start a conversation before sending your reply.", "请先开始对话，再发送回复。"),
            ("On-device speech is ready.", "设备端语音识别已就绪。"),
            ("No system reading voice is available for this language. Your text conversation still works.", "此语言没有可用的系统朗读声音。你仍可使用文本对话。")
        ])
    }

    func testBuiltInTopicBrowsingLabelsAreFunctionalCopy() {
        assertChinese([
            ("Everyday", "日常生活"), ("Connection", "人际交流"), ("Local life", "当地生活"),
            ("A coffee?", "喝杯咖啡？"), ("Something warm, please", "来杯热饮"),
            ("The weekend", "周末时光"), ("Tell me about yours", "聊聊你的周末"),
            ("Something to talk about", "值得聊聊的话题")
        ])
        let instruction = "You work in a cosy café. Help the learner order, then chat naturally."
        XCTAssertEqual(InterfaceText.string(instruction, language: .chinese), instruction)
    }

    func testTemplateInsertionsRemainLiteralEvenIfTheyResemblePlaceholders() {
        assertChinese([("Reply in {2} or another language", "用 {2} 或其他语言回复")])
    }

    func testKeyFooterTranslatesBillingClauseAndPreservesProvider() {
        assertChinese([
            ("Your key stays in this iPhone’s Keychain and is sent only to the selected provider. DeepSeek bills your account for usage. Each provider and custom endpoint keeps its own key.", "密钥保存在此 iPhone 的钥匙串中，仅发送至所选提供方。使用时，DeepSeek 会向你的账户收费。每个提供方和自定义端点分别保存自己的密钥。"),
            ("Your key stays in this iPhone’s Keychain and is sent only to the selected provider. Google bills your Gemini account for usage. Each provider and custom endpoint keeps its own key.", "密钥保存在此 iPhone 的钥匙串中，仅发送至所选提供方。使用时，Google 会向你的 Gemini 账户收费。每个提供方和自定义端点分别保存自己的密钥。")
        ])
    }

    func testLearningLanguageSelectionsTranslateKnownNamesAndVarieties() {
        assertChinese([
            ("Norwegian · Bokmål", "挪威语 · 书面挪威语"),
            ("Spanish · Spain", "西班牙语 · 西班牙"),
            ("English · International", "英语 · 国际通用"),
            ("French · France", "法语 · 法国"),
            ("German · Germany", "德语 · 德国"),
            ("Italian · Italy", "意大利语 · 意大利"),
            ("Portuguese · Brazil", "葡萄牙语 · 巴西"),
            ("Mandarin Chinese · Mainland China", "汉语普通话 · 中国大陆"),
            ("Serbian · Serbia", "塞尔维亚语 · 塞尔维亚"),
            ("Greek · Greece", "希腊语 · 希腊"),
            ("Tagalog (Filipino) · Philippines", "他加禄语（菲律宾语） · 菲律宾"),
            ("Dutch · Netherlands", "荷兰语 · 荷兰"),
            ("Russian · Standard", "俄语 · 标准语")
        ])
    }

    func testKnownLanguageTalkHeadingsUseChineseFunctionalCopy() {
        assertChinese([
            ("A little everyday Norwegian", "练习日常挪威语"),
            ("A little everyday Spanish", "练习日常西班牙语"),
            ("A little everyday English", "练习日常英语"),
            ("A little everyday French", "练习日常法语"),
            ("A little everyday German", "练习日常德语"),
            ("A little everyday Italian", "练习日常意大利语"),
            ("A little everyday Portuguese", "练习日常葡萄牙语"),
            ("A little everyday Mandarin Chinese", "练习日常汉语普通话"),
            ("A little everyday Serbian", "练习日常塞尔维亚语"),
            ("A little everyday Greek", "练习日常希腊语"),
            ("A little everyday Tagalog (Filipino)", "练习日常他加禄语（菲律宾语）"),
            ("A little everyday Dutch", "练习日常荷兰语"),
            ("A little everyday Russian", "练习日常俄语")
        ])
    }

    func testMeaningLanguageSelectionsUseChineseDisplayNames() {
        assertChinese([
            ("English", "英语"), ("French", "法语"), ("German", "德语"),
            ("Spanish", "西班牙语"), ("Norwegian", "挪威语"), ("Portuguese", "葡萄牙语"),
            ("Italian", "意大利语"), ("Chinese (Simplified)", "简体中文"),
            ("Polish", "波兰语"), ("Arabic", "阿拉伯语"), ("Ukrainian", "乌克兰语"),
            ("Serbian (Latin)", "塞尔维亚语（拉丁字母）"), ("Greek", "希腊语"),
            ("Tagalog (Filipino)", "他加禄语（菲律宾语）"), ("Dutch", "荷兰语"), ("Russian", "俄语")
        ])
        XCTAssertEqual(InterfaceText.string("English", language: .english), "English")
        XCTAssertEqual(InterfaceText.string("A little everyday an unknown language", language: .chinese), "A little everyday an unknown language")
    }

    func testKnownTopicPlaceholdersTranslateWithoutChangingArbitraryContent() {
        assertChinese([
            ("Design, space, life in Norway…", "设计、太空、挪威生活…"),
            ("Food, travel, music, life in Spain…", "美食、旅行、音乐、西班牙生活…"),
            ("Travel, films, work, everyday life…", "旅行、电影、工作、日常生活…"),
            ("Food, cinema, travel, life in France…", "美食、电影、旅行、法国生活…"),
            ("Food, travel, music, life in Germany…", "美食、旅行、音乐、德国生活…"),
            ("Food, cinema, travel, life in Italy…", "美食、电影、旅行、意大利生活…"),
            ("Food, music, travel, life in Brazil…", "美食、音乐、旅行、巴西生活…"),
            ("Food, travel, films, everyday life…", "美食、旅行、电影、日常生活…"),
            ("Food, music, travel, life in Serbia…", "美食、音乐、旅行、塞尔维亚生活…"),
            ("Food, music, travel, life in Greece…", "美食、音乐、旅行、希腊生活…"),
            ("Food, travel, music, life in the Philippines…", "美食、旅行、音乐、菲律宾生活…"),
            ("Food, cycling, travel, everyday life…", "美食、骑行、旅行、日常生活…"),
            ("Food, music, travel, everyday life…", "美食、音乐、旅行、日常生活…")
        ])
        XCTAssertEqual(InterfaceText.string("Food, music, and my own story", language: .chinese), "Food, music, and my own story")
    }

    func testIntegrationProgressAndAccessibilityNoticesUseChinese() {
        assertChinese([
            ("Checking that for you…", "正在帮你确认…"),
            ("Automatic scrolling paused", "自动滚动已暂停"),
            ("Checking Gemini", "正在检查 Gemini"),
            ("A short connection check is running. No microphone audio is captured.", "正在进行简短的连接检查，不会采集麦克风音频。")
        ])
    }

    func testPinyinVisibilityControlsUseChineseFunctionalLabels() {
        assertChinese([("Hide pinyin", "隐藏拼音"), ("Show pinyin", "显示拼音")])
    }

    func testKnownLanguageNamesTranslateInsideFunctionalDisplayContexts() {
        assertChinese([
            ("Little by little · Norwegian", "日积月累 · 挪威语"),
            ("Reply in Norwegian or another language", "用挪威语或其他语言回复"),
            ("Learning language, Norwegian · Bokmål", "学习语言，挪威语 · 书面挪威语"),
            ("Tide English speaks Norwegian. Choose the language you read most easily for meanings.", "Tide English 使用挪威语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Norwegian word or English meaning.", "请尝试其他挪威语词汇或英文释义。"),
            ("Little by little · Spanish", "日积月累 · 西班牙语"),
            ("Reply in Spanish or another language", "用西班牙语或其他语言回复"),
            ("Learning language, Spanish · Spain", "学习语言，西班牙语 · 西班牙"),
            ("Tide English speaks Spanish. Choose the language you read most easily for meanings.", "Tide English 使用西班牙语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Spanish word or English meaning.", "请尝试其他西班牙语词汇或英文释义。"),
            ("Little by little · English", "日积月累 · 英语"),
            ("Reply in English or another language", "用英语或其他语言回复"),
            ("Learning language, English · International", "学习语言，英语 · 国际通用"),
            ("Tide English speaks English. Choose the language you read most easily for meanings.", "Tide English 使用英语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another English word or English meaning.", "请尝试其他英语词汇或英文释义。"),
            ("Little by little · French", "日积月累 · 法语"),
            ("Reply in French or another language", "用法语或其他语言回复"),
            ("Learning language, French · France", "学习语言，法语 · 法国"),
            ("Tide English speaks French. Choose the language you read most easily for meanings.", "Tide English 使用法语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another French word or English meaning.", "请尝试其他法语词汇或英文释义。"),
            ("Little by little · German", "日积月累 · 德语"),
            ("Reply in German or another language", "用德语或其他语言回复"),
            ("Learning language, German · Germany", "学习语言，德语 · 德国"),
            ("Tide English speaks German. Choose the language you read most easily for meanings.", "Tide English 使用德语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another German word or English meaning.", "请尝试其他德语词汇或英文释义。"),
            ("Little by little · Italian", "日积月累 · 意大利语"),
            ("Reply in Italian or another language", "用意大利语或其他语言回复"),
            ("Learning language, Italian · Italy", "学习语言，意大利语 · 意大利"),
            ("Tide English speaks Italian. Choose the language you read most easily for meanings.", "Tide English 使用意大利语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Italian word or English meaning.", "请尝试其他意大利语词汇或英文释义。"),
            ("Little by little · Portuguese", "日积月累 · 葡萄牙语"),
            ("Reply in Portuguese or another language", "用葡萄牙语或其他语言回复"),
            ("Learning language, Portuguese · Brazil", "学习语言，葡萄牙语 · 巴西"),
            ("Tide English speaks Portuguese. Choose the language you read most easily for meanings.", "Tide English 使用葡萄牙语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Portuguese word or English meaning.", "请尝试其他葡萄牙语词汇或英文释义。"),
            ("Little by little · Mandarin Chinese", "日积月累 · 汉语普通话"),
            ("Reply in Mandarin Chinese or another language", "用汉语普通话或其他语言回复"),
            ("Learning language, Mandarin Chinese · Mainland China", "学习语言，汉语普通话 · 中国大陆"),
            ("Tide English speaks Mandarin Chinese. Choose the language you read most easily for meanings.", "Tide English 使用汉语普通话对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Mandarin Chinese word or English meaning.", "请尝试其他汉语普通话词汇或英文释义。"),
            ("Little by little · Serbian", "日积月累 · 塞尔维亚语"),
            ("Reply in Serbian or another language", "用塞尔维亚语或其他语言回复"),
            ("Learning language, Serbian · Serbia", "学习语言，塞尔维亚语 · 塞尔维亚"),
            ("Tide English speaks Serbian. Choose the language you read most easily for meanings.", "Tide English 使用塞尔维亚语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Serbian word or English meaning.", "请尝试其他塞尔维亚语词汇或英文释义。"),
            ("Little by little · Greek", "日积月累 · 希腊语"),
            ("Reply in Greek or another language", "用希腊语或其他语言回复"),
            ("Learning language, Greek · Greece", "学习语言，希腊语 · 希腊"),
            ("Tide English speaks Greek. Choose the language you read most easily for meanings.", "Tide English 使用希腊语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Greek word or English meaning.", "请尝试其他希腊语词汇或英文释义。"),
            ("Little by little · Tagalog (Filipino)", "日积月累 · 他加禄语（菲律宾语）"),
            ("Reply in Tagalog (Filipino) or another language", "用他加禄语（菲律宾语）或其他语言回复"),
            ("Learning language, Tagalog (Filipino) · Philippines", "学习语言，他加禄语（菲律宾语） · 菲律宾"),
            ("Tide English speaks Tagalog (Filipino). Choose the language you read most easily for meanings.", "Tide English 使用他加禄语（菲律宾语）对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Tagalog (Filipino) word or English meaning.", "请尝试其他他加禄语（菲律宾语）词汇或英文释义。"),
            ("Little by little · Dutch", "日积月累 · 荷兰语"),
            ("Reply in Dutch or another language", "用荷兰语或其他语言回复"),
            ("Learning language, Dutch · Netherlands", "学习语言，荷兰语 · 荷兰"),
            ("Tide English speaks Dutch. Choose the language you read most easily for meanings.", "Tide English 使用荷兰语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Dutch word or English meaning.", "请尝试其他荷兰语词汇或英文释义。"),
            ("Little by little · Russian", "日积月累 · 俄语"),
            ("Reply in Russian or another language", "用俄语或其他语言回复"),
            ("Learning language, Russian · Standard", "学习语言，俄语 · 标准语"),
            ("Tide English speaks Russian. Choose the language you read most easily for meanings.", "Tide English 使用俄语对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another Russian word or English meaning.", "请尝试其他俄语词汇或英文释义。"),
        ])
    }

    func testUnknownLanguageContextValuesRemainVerbatim() {
        assertChinese([
            ("Reply in FutureLanguage-X or another language", "用 FutureLanguage-X 或其他语言回复"),
            ("Little by little · FutureLanguage-X", "日积月累 · FutureLanguage-X"),
            ("Learning language, FutureLanguage-X · Variant", "学习语言，FutureLanguage-X · Variant"),
            ("Tide English speaks FutureLanguage-X. Choose the language you read most easily for meanings.", "Tide English 使用 FutureLanguage-X 对话。请选择你最容易阅读的语言来查看释义。"),
            ("Try another FutureLanguage-X word or English meaning.", "请尝试其他 FutureLanguage-X 词汇或英文释义。")
        ])
        XCTAssertEqual(InterfaceText.string("A learner said: Reply in English or another language", language: .chinese), "A learner said: Reply in English or another language")
    }

    private func assertChinese(_ fixtures: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in fixtures {
            XCTAssertEqual(InterfaceText.string(input, language: .chinese), expected, input, file: file, line: line)
        }
    }
}
