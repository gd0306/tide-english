package cn.gd306.tideenglish.ui

import android.content.res.Configuration
import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import java.util.Locale

/** Native dialog compositions replace LocalContext, but inherit our explicit interface language. */
@Composable
private fun interfaceResources(): android.content.res.Resources {
    val context = LocalContext.current.applicationContext
    val configuration = LocalConfiguration.current
    val language = LocalInterfaceLanguage.current
    return remember(context, configuration, language) {
        context.createConfigurationContext(Configuration(configuration).apply {
            setLocale(Locale.forLanguageTag(language.tag))
        }).resources
    }
}

@Composable
fun tideStringResource(@StringRes id: Int, vararg formatArgs: Any): String =
    interfaceResources().getString(id, *formatArgs)

@Composable
fun tidePluralStringResource(@PluralsRes id: Int, quantity: Int, vararg formatArgs: Any): String =
    interfaceResources().getQuantityString(id, quantity, *formatArgs)

/** ModalBottomSheet owns another window, so update its system-bar contrast as well. */
@Composable
internal fun TideDialogAppearance() {
    val view = LocalView.current
    val window = (view.parent as? DialogWindowProvider)?.window ?: return
    val dark = LocalInterfaceTheme.current == InterfaceTheme.MIDNIGHT
    val background = TideEnglishColors.Cream.toArgb()
    SideEffect {
        androidx.core.view.WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        }
        @Suppress("DEPRECATION")
        run { window.navigationBarColor = background }
        if (android.os.Build.VERSION.SDK_INT >= 29) window.isNavigationBarContrastEnforced = false
    }
}
