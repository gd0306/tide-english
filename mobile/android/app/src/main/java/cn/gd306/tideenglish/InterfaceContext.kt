package cn.gd306.tideenglish

import android.content.Context
import android.content.res.Configuration
import androidx.annotation.StringRes
import java.util.Locale

/** Activity toasts and service notifications use the same explicit language as Compose. */
internal fun Context.interfaceString(@StringRes id: Int, vararg arguments: Any): String {
    val chinese = applicationContext.getSharedPreferences("tide.presentation.v1", Context.MODE_PRIVATE)
        .getString("language", "ENGLISH") == "CHINESE"
    val localized = applicationContext.createConfigurationContext(Configuration(resources.configuration).apply {
        setLocale(Locale.forLanguageTag(if (chinese) "zh" else "en"))
    })
    return localized.getString(id, *arguments)
}
