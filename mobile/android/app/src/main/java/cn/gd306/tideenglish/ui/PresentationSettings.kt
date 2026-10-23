package cn.gd306.tideenglish.ui

import android.content.Context
import android.content.res.Configuration
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import java.util.Locale

enum class InterfaceTheme { PAPER, MIDNIGHT, GROVE }
enum class InterfaceLanguage(val tag: String) { ENGLISH("en"), CHINESE("zh") }
data class PresentationSettings(val theme: InterfaceTheme = InterfaceTheme.PAPER, val language: InterfaceLanguage = InterfaceLanguage.ENGLISH) {
    companion object {
        fun restored(theme: String?, language: String?) = PresentationSettings(
            InterfaceTheme.entries.firstOrNull { it.name == theme } ?: InterfaceTheme.PAPER,
            InterfaceLanguage.entries.firstOrNull { it.name == language } ?: InterfaceLanguage.ENGLISH)
    }
}
class PresentationStore(context: Context) {
    private val prefs = context.getSharedPreferences("tide.presentation.v1", Context.MODE_PRIVATE)
    var value by mutableStateOf(PresentationSettings.restored(prefs.getString("theme", null), prefs.getString("language", null)))
        private set
    fun update(settings: PresentationSettings) {
        prefs.edit().putString("theme", settings.theme.name).putString("language", settings.language.name).apply()
        value = settings
    }
}
val LocalInterfaceLanguage = staticCompositionLocalOf { InterfaceLanguage.ENGLISH }
val LocalPresentationStore = staticCompositionLocalOf<PresentationStore> { error("Presentation store unavailable") }
@Composable
fun TidePresentation(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val store = remember(context.applicationContext) { PresentationStore(context.applicationContext) }
    val settings = store.value
    val activity = remember(context) {
        var current: Context? = context
        while (current is android.content.ContextWrapper && current !is android.app.Activity) current = current.baseContext
        current as? android.app.Activity
    }
    SideEffect {
        activity?.window?.let { window ->
            val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
            controller.isAppearanceLightStatusBars = settings.theme != InterfaceTheme.MIDNIGHT
            controller.isAppearanceLightNavigationBars = settings.theme != InterfaceTheme.MIDNIGHT
        }
    }
    val systemConfiguration = LocalConfiguration.current
    val localized = remember(context, systemConfiguration, settings.language) {
        context.createConfigurationContext(Configuration(systemConfiguration).apply { setLocale(Locale.forLanguageTag(settings.language.tag)) })
    }
    CompositionLocalProvider(LocalContext provides localized, LocalInterfaceLanguage provides settings.language, LocalInterfaceTheme provides settings.theme, LocalPresentationStore provides store) { content() }
}
@Composable
fun uiText(english: String, chinese: String): String = if (LocalInterfaceLanguage.current == InterfaceLanguage.CHINESE) chinese else english
