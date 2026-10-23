package cn.gd306.tideenglish

import androidx.compose.ui.test.*
import androidx.compose.runtime.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import cn.gd306.tideenglish.ui.TideEnglishTheme
import cn.gd306.tideenglish.ui.TypedReplySheet
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TypedReplySheetTest {
    @get:Rule val compose = createComposeRule()
    @Test fun replyCanBeEnteredAndSentFromTheSheetWithoutLosingTheActionToTheKeyboard() {
        var sent: String? = null
        var dismissed = false
        val successes = mutableIntStateOf(0)
        compose.setContent { TideEnglishTheme { TypedReplySheet("Spanish", false, { sent = it }, { dismissed = true }, completedSends = successes.intValue) } }
        compose.onNodeWithTag("typed-reply-input").assertIsFocused().performTextInput("  Me gustaría un café.  ")
        compose.onNodeWithTag("typed-reply-send").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals("Me gustaría un café.", sent); assertFalse(dismissed); successes.intValue++ }
        compose.waitForIdle()
        compose.runOnIdle { assertTrue(dismissed) }
    }

    @Test fun failureKeepsDraftAndSendActionReachable() {
        val failure = mutableStateOf<String?>(null)
        var dismissed = false
        compose.setContent { TideEnglishTheme { TypedReplySheet("Spanish", false, { failure.value = "Connection lost. Try again." },
            { dismissed = true }, error = failure.value) } }
        compose.onNodeWithTag("typed-reply-input").performTextInput("Quiero un café.")
        compose.onNodeWithTag("typed-reply-send").performClick()
        compose.onNodeWithTag("typed-reply-error").assertIsDisplayed()
        compose.onNodeWithTag("typed-reply-input").assertTextContains("Quiero un café.")
        compose.onNodeWithTag("typed-reply-send").assertIsDisplayed().assertIsEnabled()
        compose.runOnIdle { assertFalse(dismissed) }
    }
}
