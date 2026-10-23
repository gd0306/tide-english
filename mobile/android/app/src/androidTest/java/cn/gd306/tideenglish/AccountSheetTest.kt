package cn.gd306.tideenglish

import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.ClipboardManager
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import cn.gd306.tideenglish.core.AccountState
import cn.gd306.tideenglish.core.AccountNotice
import cn.gd306.tideenglish.core.ConversationProvider
import cn.gd306.tideenglish.core.MinuteBalance
import cn.gd306.tideenglish.ui.AccountSheet
import cn.gd306.tideenglish.ui.TideEnglishTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class AccountSheetTest {
    @get:Rule val compose = createComposeRule()
    private fun capture(name: String) {
        compose.waitForIdle()
        val image = InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: error("Screenshot unavailable")
        val directory = File(context.filesDir, "settings-review").apply { mkdirs() }
        File(directory, "$name.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    @Test fun unavailableGoogleDoesNotLaunchAndExplainsGuestAccess() {
        var signIns = 0
        compose.setContent { TideEnglishTheme {
            AccountSheet(AccountState(), {}, { signIns++ }, {}, {}, {})
        } }
        compose.onNodeWithTag("account-google").assertIsNotEnabled()
        assertEquals(0, signIns)
        compose.onNodeWithText("Make yourself at home.").assertIsDisplayed()
        compose.onNodeWithText("You can keep using Tide English without an account.", substring = true).assertExists()
    }
    @Test fun accountShowsMinutesAndDeletionRequiresConfirmation() {
        var deletions = 0
        val state = AccountState(googleAvailable = true, accountID = "synthetic-account", email = "preview@example.test",
            minutes = MinuteBalance("milliseconds", "connected-conversation-time", 1_800_000, 0, 1_800_000))
        compose.setContent { TideEnglishTheme { AccountSheet(state, {}, {}, {}, { deletions++ }, {},
            provider = ConversationProvider.HOSTED_MINUTES) } }
        compose.onNodeWithTag("account-minute-balance").assertTextEquals("30 min 0 sec")
        compose.onNodeWithText(context.getString(R.string.account_provider_google)).assertIsDisplayed()
        capture("09-member-account")
        compose.onNodeWithText(context.getString(R.string.account_delete_action)).performScrollTo().performClick()
        assertEquals(0, deletions)
        compose.onNodeWithText("Delete your Tide English account", substring = true).assertIsDisplayed()
        compose.onNodeWithTag("account-confirm-delete").performClick()
        compose.runOnIdle { assertEquals(1, deletions) }
    }
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val member = AccountState(accountID = "12345678-1234-1234-1234-123456789012", googleAvailable = true,
        minutes = MinuteBalance("milliseconds", "connected-conversation-time", 5_000, 0, 5_000))

    @Test fun finalSecondsAreVisibleAndAnUnavailableStoreDoesNotOfferPurchases() {
        compose.setContent { TideEnglishTheme { AccountSheet(member, {}, {}, {}, {}, {},
            provider = ConversationProvider.HOSTED_MINUTES) } }
        compose.onNodeWithTag("account-minute-balance").assertTextEquals("0 min 5 sec")
        compose.onNodeWithTag("account-buy-minutes").assertDoesNotExist()
        compose.onNodeWithTag("account-conversation-source").assertDoesNotExist()
    }

    @Test fun personalKeyAccountHidesMinutesAndAccessChoiceAndBlocksActionsDuringAConversation() {
        val running = mutableStateOf(false)
        val provider = mutableStateOf(ConversationProvider.PERSONAL_KEY)
        compose.setContent { TideEnglishTheme {
            AccountSheet(member, {}, {}, {}, {}, {}, provider = provider.value,
                conversationRunning = running.value, onBuyMinutes = {})
        } }
        compose.runOnIdle { assertEquals(ConversationProvider.PERSONAL_KEY, provider.value) }
        compose.onNodeWithTag("account-conversation-source").assertDoesNotExist()
        compose.onNodeWithTag("account-minute-balance").assertDoesNotExist()
        compose.onNodeWithTag("account-buy-minutes").assertDoesNotExist()
        compose.onNodeWithTag("account-check-purchases").assertIsEnabled()
        capture("10-personal-key-account")
        compose.runOnIdle { running.value = true }
        compose.onNodeWithTag("account-check-purchases").assertIsNotEnabled()
        compose.onNodeWithTag("account-sign-out").assertDoesNotExist()
    }

    @Test fun accountTransitionDisablesAnotherSignInOrPurchase() {
        var purchases = 0
        compose.setContent { TideEnglishTheme {
            AccountSheet(member, {}, {}, {}, {}, {}, transitionBusy = true,
                provider = ConversationProvider.HOSTED_MINUTES, onBuyMinutes = { purchases++ })
        } }
        compose.onNodeWithTag("account-buy-minutes").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithText(context.getString(R.string.account_sign_out)).assertDoesNotExist()
        compose.runOnIdle { assertEquals(0, purchases) }
    }

    @Test fun blockedDeletionOpensOnlyAnExplicitSupportDraftWithoutAccountData() {
        var deletions = 0
        val opened = mutableListOf<String>()
        val uri = object : UriHandler { override fun openUri(uri: String) { opened += uri } }
        compose.setContent { CompositionLocalProvider(LocalUriHandler provides uri) { TideEnglishTheme {
            AccountSheet(member.copy(email = "private-member@example.test", notice = AccountNotice.BILLING_UNRESOLVED),
                {}, {}, {}, { deletions++ }, {})
        } } }
        compose.onNodeWithTag("account-deletion-support").performScrollTo().performClick()
        compose.onNodeWithText("1215742191@qq.com").assertIsDisplayed()
        compose.runOnIdle { assertTrue(opened.isEmpty()); assertEquals(0, deletions) }
        compose.onNodeWithTag("account-deletion-email").performClick()
        compose.runOnIdle {
            assertEquals(listOf("mailto:1215742191@qq.com?subject=Tide%20English%20account%20deletion%20request"), opened)
            assertEquals(0, deletions)
        }
        compose.onNodeWithTag("account-deletion-request").assertExists()
        compose.onNodeWithText(context.getString(R.string.account_deleted)).assertDoesNotExist()
        compose.onNodeWithTag("account-deletion-web").performScrollTo().performClick()
        compose.runOnIdle { assertEquals("https://tide-english.example/support/#delete-account", opened.last()) }
    }

    @Test fun noEmailOrBrowserAppKeepsACopyableContactAndDoesNotClaimSubmission() {
        val clipboard = object : ClipboardManager {
            var value: AnnotatedString? = null
            override fun getText(): AnnotatedString? = value
            override fun setText(annotatedString: AnnotatedString) { value = annotatedString }
        }
        val uri = object : UriHandler {
            override fun openUri(uri: String) { throw IllegalArgumentException("No activity found") }
        }
        compose.setContent { CompositionLocalProvider(LocalUriHandler provides uri, LocalClipboardManager provides clipboard) { TideEnglishTheme {
            AccountSheet(member.copy(notice = AccountNotice.APPLE_DELETION), {}, {}, {}, {}, {})
        } } }
        compose.onNodeWithTag("account-deletion-support").performScrollTo().performClick()
        compose.onNodeWithTag("account-deletion-email").performClick()
        compose.onNodeWithTag("account-deletion-open-failed").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("account-deletion-web").performScrollTo().performClick()
        compose.onNodeWithTag("account-deletion-open-failed").assertExists()
        compose.onNodeWithTag("account-deletion-copy-email").performScrollTo().performClick()
        compose.runOnIdle { assertEquals("1215742191@qq.com", clipboard.value?.text) }
        compose.onNodeWithText(context.getString(R.string.account_deletion_email_copied)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.account_deleted)).assertDoesNotExist()
    }

    @Test fun deletionSupportCanBeRequestedBeforeAnAutomaticAttemptAndClosesOnAccountChange() {
        var deletions = 0
        val state = mutableStateOf(member)
        compose.setContent { TideEnglishTheme { AccountSheet(state.value, {}, {}, {}, { deletions++ }, {}) } }
        compose.onNodeWithText(context.getString(R.string.account_delete_action)).performScrollTo().performClick()
        compose.onNodeWithTag("account-request-deletion").performClick()
        compose.onNodeWithTag("account-deletion-request").assertExists()
        compose.onNodeWithTag("account-confirm-delete").assertDoesNotExist()
        compose.runOnIdle { assertEquals(0, deletions); state.value = AccountState(googleAvailable = true) }
        compose.onNodeWithTag("account-deletion-request").assertDoesNotExist()
        compose.onNodeWithTag("account-deletion-support").assertDoesNotExist()
    }

    @Test fun anEmptyAccountStillUsesConfirmedAutomaticDeletion() {
        var deletions = 0
        compose.setContent { TideEnglishTheme {
            AccountSheet(member.copy(minutes = MinuteBalance("milliseconds", "connected-conversation-time", 0, 0, 0)),
                {}, {}, {}, { deletions++ }, {})
        } }
        compose.onNodeWithText(context.getString(R.string.account_delete_action)).performScrollTo().performClick()
        compose.runOnIdle { assertEquals(0, deletions) }
        compose.onNodeWithTag("account-confirm-delete").performClick()
        compose.runOnIdle { assertEquals(1, deletions) }
        compose.onNodeWithTag("account-deletion-request").assertDoesNotExist()
    }
}
