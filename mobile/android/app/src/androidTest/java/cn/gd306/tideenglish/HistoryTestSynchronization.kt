package cn.gd306.tideenglish

import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.rules.ActivityScenarioRule
import org.junit.Assert.assertNull

/** Compose idle alone does not wait for the archive's Dispatchers.IO read. */
internal fun AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>.awaitHistoryLoaded(): TideEnglishViewModel {
    val vm = runOnUiThread { ViewModelProvider(activity)[TideEnglishViewModel::class.java] }
    waitUntil(timeoutMillis = 10_000) { runOnUiThread { !vm.loadingHistory } }
    runOnIdle { assertNull("Test history must load before preferences are changed", vm.error) }
    return vm
}
