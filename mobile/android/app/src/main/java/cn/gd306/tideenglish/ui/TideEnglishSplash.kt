package cn.gd306.tideenglish.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

/** Show the launch background only while local history loads, without a timed splash or extra orb. */
@Composable
fun TideEnglishStartup(loading: Boolean, content: @Composable () -> Unit) {
    var complete by rememberSaveable { mutableStateOf(!loading) }
    LaunchedEffect(loading) {
        if (!loading) complete = true
    }
    if (complete) content()
    else Box(Modifier.fillMaxSize().background(TideEnglishColors.Cream).testTag("startup-loading"))
}
