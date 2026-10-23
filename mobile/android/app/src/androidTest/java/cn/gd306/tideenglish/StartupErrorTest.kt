package cn.gd306.tideenglish

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import cn.gd306.tideenglish.core.Preferences
import cn.gd306.tideenglish.network.HostedFailure
import cn.gd306.tideenglish.network.ManagedAccountConfiguration
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StartupErrorTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private lateinit var vm: TideEnglishViewModel
    private lateinit var account: AccountViewModel
    private lateinit var preferences: Preferences
    private var configuration: ManagedAccountConfiguration? = null

    @Before fun prepare() {
        vm = compose.awaitHistoryLoaded()
        compose.runOnIdle {
            assertEquals("cn.gd306.tideenglish.android.uitest", compose.activity.packageName)
            account = ViewModelProvider(compose.activity)[AccountViewModel::class.java]
            configuration = account.configuration
            // Enable only the account UI. The isolated app has no account controller or credentials.
            AccountViewModel::class.java.getDeclaredField("configuration").apply { isAccessible = true }
                .set(account, requireNotNull(ManagedAccountConfiguration.parse("https://offline.invalid", "123-offline.apps.googleusercontent.com")))
            preferences = vm.archive.preferences
            vm.updatePreferences(preferences.copy(hasOnboarded = true, aiConsentVersion = 1))
        }
    }
    @After fun restore() {
        if (!::vm.isInitialized || !::preferences.isInitialized) return
        compose.runOnIdle {
            vm.dismissError()
            vm.updatePreferences(preferences)
            AccountViewModel::class.java.getDeclaredField("configuration").apply { isAccessible = true }.set(account, configuration)
        }
    }
    private fun fail(error: Throwable) = compose.runOnIdle {
        TideEnglishViewModel::class.java.getDeclaredMethod("presentError", Throwable::class.java, Int::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(vm, error, R.string.error_voice_connect_failed)
    }
    @Test fun legacyHostedSignInFailureCanBeDismissedWithoutEnablingManagedAccounts() {
        fail(HostedFailure.Http(401, "sign_in_required", reference = "0123abcdef45"))
        compose.onNodeWithText(compose.activity.getString(R.string.hosted_sign_in_again), substring = true).assertIsDisplayed()
        compose.onNodeWithText("0123abcdef45", substring = true).assertIsDisplayed()
        compose.onNodeWithText(compose.activity.getString(R.string.error_go_to_settings)).assertDoesNotExist()
        compose.onNodeWithText(compose.activity.getString(R.string.account_title)).assertDoesNotExist()
        compose.onNodeWithTag("account-google").assertDoesNotExist()
        compose.onNodeWithText(compose.activity.getString(R.string.common_ok)).performClick()
        compose.runOnIdle { assertNull(vm.error); assertFalse(vm.errorNeedsAccountSignIn); assertFalse(vm.errorNeedsKeySetup) }
    }
    @Test fun ordinaryServerFailureKeepsSingleDismissActionAndSafeReference() {
        fail(HostedFailure.Http(500, "service_unavailable", reference = "0123abcdef45"))
        compose.onNodeWithText(compose.activity.getString(R.string.hosted_request_failed), substring = true).assertIsDisplayed()
        compose.onNodeWithText("0123abcdef45", substring = true).assertIsDisplayed()
        compose.onNodeWithText(compose.activity.getString(R.string.account_title)).assertDoesNotExist()
        compose.onNodeWithText(compose.activity.getString(R.string.common_ok)).performClick()
        compose.runOnIdle { assertNull(vm.error); assertFalse(vm.errorNeedsAccountSignIn) }
    }
}
