package cn.gd306.tideenglish.core
import org.junit.Assert.*
import org.junit.Test
class ProviderConfigurationTest {
 @Test fun customScopesNormalizeButNeverCrossRecipients() {
  val a=ProviderConfiguration(ModelProvider.CUSTOM,"chat","https://EXAMPLE.com:443/v1/").validated()
  assertEquals("https://example.com/v1",a.baseURL)
  assertEquals(a.credentialScope(),a.copy(baseURL="https://example.com/v1").credentialScope())
  assertNotEquals(a.credentialScope(),a.copy(baseURL="https://other.example/v1").credentialScope())
 }
 @Test fun rejectsAmbiguousEndpointsAndOfficialSubstitution() {
  listOf("http://example.com","https://key@example.com","https://example.com/a/../b","https://example.com/%2e","https://example.com?a=b","https://example.com//v1").forEach {
   assertThrows(IllegalArgumentException::class.java) { ProviderConfiguration(ModelProvider.CUSTOM,"chat",it).validated() }
  }
  assertThrows(IllegalArgumentException::class.java) { ProviderConfiguration(ModelProvider.OPENAI,baseURL="https://other.example").validated() }
 }
 @Test fun keepsLegacyOpenAIScopeAndValidatesCredentials() {
  assertEquals("tideenglish_openai_credentials",ProviderConfiguration(ModelProvider.OPENAI).credentialScope())
  assertEquals("key-value",ProviderConfiguration.validatedCredential(" key-value "))
  listOf("", "a b", "a\nb").forEach { assertThrows(IllegalArgumentException::class.java) { ProviderConfiguration.validatedCredential(it) } }
 }
 @Test fun searchCapabilitiesMatchSelectedProvider() {
  assertTrue(ProviderConfiguration(ModelProvider.OPENAI).supportsSearch)
  assertTrue(ProviderConfiguration(ModelProvider.GLM).supportsSearch)
  assertFalse(ProviderConfiguration(ModelProvider.DEEPSEEK).supportsSearch)
  assertFalse(ProviderConfiguration(ModelProvider.GEMINI).supportsSearch)
 }
}
