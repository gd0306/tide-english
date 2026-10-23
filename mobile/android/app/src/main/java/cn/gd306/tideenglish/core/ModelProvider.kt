package cn.gd306.tideenglish.core

import java.net.URI
import java.security.MessageDigest
import kotlinx.serialization.Serializable

@Serializable
enum class ModelProvider(val displayName: String, val defaultModel: String, val defaultBaseURL: String) {
 OPENAI("OpenAI","gpt-6-luna","https://api.openai.com/v1"),
 DEEPSEEK("DeepSeek","deepseek-flash","https://api.deepseek.com"),
 GLM("GLM (BigModel)","glm-4.7-flash","https://open.bigmodel.cn/api/paas/v4"),
 GEMINI("Gemini","gemini-3.8-flash","https://generativelanguage.googleapis.com/v1beta/openai"),
 CUSTOM("Custom","","")
}

@Serializable
data class ProviderConfiguration(val provider: ModelProvider = ModelProvider.OPENAI,
 val model: String = provider.defaultModel, val baseURL: String = provider.defaultBaseURL) {
 val supportsSearch: Boolean get() = provider == ModelProvider.OPENAI || provider == ModelProvider.GLM
 fun validated(): ProviderConfiguration {
  require(model.length in 1..128 && Regex("[A-Za-z0-9][A-Za-z0-9._:/-]*").matches(model)) { "Enter a valid chat model ID." }
  require(baseURL.length in 1..2048 && baseURL.all { it.code in 33..126 } && !baseURL.contains('\\') && !baseURL.contains('%')) { "Enter a valid HTTPS API endpoint." }
  val uri=try { URI(baseURL) } catch (_:Exception) { throw IllegalArgumentException("Enter a valid HTTPS API endpoint.") }
  require(uri.scheme.equals("https",true) && !uri.host.isNullOrEmpty() && uri.rawUserInfo==null && uri.rawQuery==null && uri.rawFragment==null && (uri.port==-1 || uri.port in 1..65535) && !uri.path.contains("//") && uri.path.split('/').none { it=="." || it==".." }) { "Enter an HTTPS API endpoint without credentials, query, fragment or relative paths." }
  val normalized=URI("https",null,uri.host.lowercase(),if(uri.port==443) -1 else uri.port,uri.path.trimEnd('/'),null,null).toASCIIString()
  require(provider==ModelProvider.CUSTOM || normalized==provider.defaultBaseURL) { "Use the official endpoint or select Custom." }
  return copy(baseURL=normalized)
 }
 fun credentialScope(): String {
  val c=validated()
  return if(provider==ModelProvider.OPENAI) "tideenglish_openai_credentials" else if(provider==ModelProvider.CUSTOM) {
   "tideenglish_custom_"+MessageDigest.getInstance("SHA-256").digest(c.baseURL.toByteArray()).joinToString("") { "%02x".format(it) }
  } else "tideenglish_${provider.name.lowercase()}_credentials"
 }
 companion object {
  fun validatedCredential(key:String):String {
   val value=key.trim(' ')
   require(value.length in 1..4096 && value.all { it.code in 33..126 }) { "Enter a nonempty API key without spaces or control characters." }
   return value
  }
 }
}
