package cn.gd306.tideenglish

import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import cn.gd306.tideenglish.ui.TideEnglishStartup
import cn.gd306.tideenglish.ui.TideEnglishTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TideEnglishSplashTest {
    @get:Rule val compose = createComposeRule()

    @Test fun localHistoryGatesContentAndCompletedStartupSurvivesRecreation() {
        val loading = mutableStateOf(true)
        val restoration = StateRestorationTester(compose)
        restoration.setContent { TideEnglishTheme {
            TideEnglishStartup(loading.value) {
                Text("Ready", Modifier.testTag("startup-content"))
            }
        } }
        compose.onNodeWithTag("startup-loading").assertIsDisplayed()
        compose.onNodeWithTag("tideenglish-splash-orb", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("startup-content").assertDoesNotExist()
        compose.runOnIdle { loading.value = false }
        compose.onNodeWithTag("startup-content").assertIsDisplayed()
        compose.onNodeWithTag("startup-loading").assertDoesNotExist()
        compose.runOnIdle { loading.value = true }
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("startup-content").assertIsDisplayed()
        compose.onNodeWithTag("startup-loading").assertDoesNotExist()
    }

    @Test fun readyHistoryShowsContentWithoutATimedSplash() {
        compose.mainClock.autoAdvance = false
        compose.setContent { TideEnglishTheme {
            TideEnglishStartup(loading = false) { Text("Ready", Modifier.testTag("startup-content")) }
        } }
        compose.onNodeWithTag("startup-content").assertIsDisplayed()
        compose.onNodeWithTag("startup-loading").assertDoesNotExist()
        compose.onNodeWithTag("tideenglish-splash-orb", useUnmergedTree = true).assertDoesNotExist()
    }
}
