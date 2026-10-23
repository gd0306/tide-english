package cn.gd306.tideenglish.network
import android.content.Context
import cn.gd306.tideenglish.core.ModelProvider
import cn.gd306.tideenglish.core.ProviderConfiguration
import kotlinx.serialization.json.Json
class ProviderConfigurationStore(context: Context) {
 private val preferences=context.applicationContext.getSharedPreferences("tide_provider_configuration",Context.MODE_PRIVATE)
 fun read():ProviderConfiguration {
  val saved=preferences.getString("selection",null) ?: return ProviderConfiguration()
  return runCatching { Json.decodeFromString<ProviderConfiguration>(saved) }.getOrElse { ProviderConfiguration(ModelProvider.CUSTOM) }
 }
 fun save(configuration:ProviderConfiguration) {
  check(preferences.edit().putString("selection",Json.encodeToString(ProviderConfiguration.serializer(),configuration.validated())).commit()) { "The provider selection couldn't be saved." }
 }
}
