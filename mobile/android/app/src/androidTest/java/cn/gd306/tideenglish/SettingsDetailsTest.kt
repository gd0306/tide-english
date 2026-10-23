package cn.gd306.tideenglish

import androidx.compose.ui.test.*
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import cn.gd306.tideenglish.core.Preferences
import cn.gd306.tideenglish.core.ConversationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SettingsDetailsTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()
    private var originalPreferences = Preferences()
    private var originalProvider: ConversationProvider? = null
    private var preferencesCaptured = false

    @Before fun skipOnboarding() {
        compose.awaitHistoryLoaded()
        compose.runOnIdle {
            val vm = ViewModelProvider(compose.activity)[TideEnglishViewModel::class.java]
            originalPreferences = vm.archive.preferences.copy()
            originalProvider = vm.conversationProvider
            preferencesCaptured = true
            vm.updatePreferences(originalPreferences.copy(hasOnboarded = true))
        }
        compose.waitForIdle()
    }

    @After fun restorePreferences() {
        if (!preferencesCaptured) return
        compose.runOnIdle {
            val vm = ViewModelProvider(compose.activity)[TideEnglishViewModel::class.java]
            vm.updatePreferences(originalPreferences)
            originalProvider?.let(vm::selectConversationProvider)
        }
    }

    @Test fun personalSettingsExposeOneModelRouteWithoutCommercialSourceSelector() {
        compose.onNodeWithTag("tab-settings").performClick()
        compose.onNodeWithTag("model-api-settings").assertIsDisplayed().performClick()
        compose.onNodeWithTag("model-provider").assertIsDisplayed()
        compose.onNodeWithTag("api-key-input").assertIsDisplayed()
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithTag("settings-conversation-access").assertDoesNotExist()
        compose.onNodeWithTag("advanced-api-key").assertDoesNotExist()
    }

    @Test fun settingsMatchTheIphoneCorrectionsKeysAndVersionDetails() {
        val activity = compose.activity
        val version = activity.packageManager.getPackageInfo(activity.packageName, 0).versionName
        assertEquals(BuildConfig.VERSION_NAME, version)
        compose.onNodeWithTag("tab-settings").performClick()
        val settings = compose.onNodeWithTag("settings-screen")
        settings.performScrollToNode(hasText(activity.getString(R.string.settings_corrections_note)))
        settings.performScrollToNode(hasTestTag("model-api-settings"))
        compose.onNodeWithTag("model-api-settings").performClick()
        compose.onNodeWithTag("api-key-input").assertExists()
        compose.onNodeWithText(activity.getString(R.string.common_cancel)).performClick()
        settings.performScrollToNode(hasTestTag("settings-about"))
        compose.onNodeWithTag("settings-about").performClick()
        settings.performScrollToNode(hasText(activity.getString(R.string.settings_app_version_footer, version)))
    }
}
