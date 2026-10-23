package cn.gd306.tideenglish

import android.content.Context
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import cn.gd306.tideenglish.core.ModelProvider
import cn.gd306.tideenglish.core.Preferences
import cn.gd306.tideenglish.core.ProviderConfiguration
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the real personal Settings entry. No key is saved and no provider call is made. */
@RunWith(AndroidJUnit4::class)
class TideSettingsFlowTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private lateinit var vm: TideEnglishViewModel
    private lateinit var originalPreferences: Preferences
    private lateinit var originalModel: ProviderConfiguration
    private var originalTheme: String? = null
    private var originalLanguage: String? = null
    @Before fun prepare() {
        vm = compose.awaitHistoryLoaded()
        assertEquals("cn.gd306.tideenglish.android.uitest", compose.activity.packageName)
        val presentation = compose.activity.getSharedPreferences("tide.presentation.v1", Context.MODE_PRIVATE)
        originalTheme = presentation.getString("theme", null)
        originalLanguage = presentation.getString("language", null)
        presentation.edit().putString("theme", "PAPER").putString("language", "ENGLISH").commit()
        compose.runOnIdle {
            originalPreferences = vm.archive.preferences.copy()
            originalModel = vm.modelConfiguration
            vm.updateModelConfiguration(ProviderConfiguration())
            vm.updatePreferences(originalPreferences.copy(hasOnboarded = true, aiConsentVersion = 1))
        }
        compose.activityRule.scenario.recreate()
        compose.awaitHistoryLoaded()
        compose.onNodeWithTag("tab-settings").performClick()
    }
    @After fun restore() {
        if (::originalPreferences.isInitialized) compose.runOnIdle {
            vm.updateModelConfiguration(originalModel)
            vm.updatePreferences(originalPreferences)
        }
        compose.activity.getSharedPreferences("tide.presentation.v1", Context.MODE_PRIVATE).edit()
            .putString("theme", originalTheme).putString("language", originalLanguage).commit()
    }
    @Test fun selectedProviderChangesModelAndRevokesPriorConsentThroughSingleRoute() {
        compose.onNodeWithTag("model-api-settings").assertIsDisplayed().performClick()
        compose.onNodeWithTag("model-provider").performClick()
        compose.onNodeWithTag("model-provider-DEEPSEEK").performClick()
        compose.onNodeWithTag("model-name").assertTextContains(ModelProvider.DEEPSEEK.defaultModel)
        compose.onNodeWithTag("model-config-save").performClick()
        compose.onNodeWithTag("api-key-input").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(ModelProvider.DEEPSEEK, vm.modelConfiguration.provider)
            assertEquals(ModelProvider.DEEPSEEK.defaultModel, vm.modelConfiguration.model)
            assertNull(vm.archive.preferences.aiConsentVersion)
        }
        compose.onNodeWithTag("settings-conversation-access").assertDoesNotExist()
        compose.onNodeWithTag("advanced-api-key").assertDoesNotExist()
    }
    @Test fun explicitChineseAndGrovePersistWithoutChangingLearningOrMeaningLanguages() {
        val learning = vm.archive.preferences.learningLanguageID
        val meaning = vm.archive.preferences.meaningLanguage
        compose.onNodeWithTag("interface-language").performClick()
        compose.onNodeWithTag("interface-language-CHINESE").performClick()
        compose.onNodeWithText("模型与 API 密钥").assertIsDisplayed()
        compose.onNodeWithText("设置").assertIsDisplayed()
        compose.onNodeWithText("完成").assertIsDisplayed()
        compose.onNodeWithText("学习语言").assertIsDisplayed()
        compose.onNodeWithTag("interface-theme").performClick()
        compose.onNodeWithTag("interface-theme-GROVE").performClick()
        compose.activityRule.scenario.recreate()
        compose.awaitHistoryLoaded()
        compose.onNodeWithTag("model-api-settings").assertIsDisplayed()
        compose.onNodeWithText("模型与 API 密钥").assertIsDisplayed()
        compose.onNodeWithText("设置").assertIsDisplayed()
        compose.onNodeWithText("完成").assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(learning, vm.archive.preferences.learningLanguageID)
            assertEquals(meaning, vm.archive.preferences.meaningLanguage)
            val prefs = compose.activity.getSharedPreferences("tide.presentation.v1", Context.MODE_PRIVATE)
            assertEquals("CHINESE", prefs.getString("language", null))
            assertEquals("GROVE", prefs.getString("theme", null))
        }
        compose.onNodeWithTag("interface-language").performClick()
        compose.onNodeWithTag("interface-language-ENGLISH").performClick()
        compose.onNodeWithText("Model & API key").assertIsDisplayed()
    }
}
