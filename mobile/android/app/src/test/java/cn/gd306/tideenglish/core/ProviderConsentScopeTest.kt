package cn.gd306.tideenglish.core

import org.junit.Assert.*
import org.junit.Test

class ProviderConsentScopeTest {
    @Test fun consentIsSpecificToSupplierModelAndRecipient() {
        val openAI = ProviderConfiguration(ModelProvider.OPENAI)
        assertEquals(ProviderConsentScope.key(openAI), ProviderConsentScope.key(openAI.copy()))
        assertNotEquals(ProviderConsentScope.key(openAI), ProviderConsentScope.key(openAI.copy(model = "other-model")))
        assertNotEquals(ProviderConsentScope.key(openAI), ProviderConsentScope.key(ProviderConfiguration(ModelProvider.DEEPSEEK)))
        val custom = ProviderConfiguration(ModelProvider.CUSTOM, "model", "https://one.example/v1")
        assertNotEquals(ProviderConsentScope.key(custom), ProviderConsentScope.key(custom.copy(baseURL = "https://two.example/v1")))
    }

    @Test fun normalizedRecipientsHaveTheSameConsentScope() {
        val first = ProviderConfiguration(ModelProvider.CUSTOM, "model", "https://ONE.example:443/v1/")
        assertEquals(ProviderConsentScope.key(first), ProviderConsentScope.key(first.copy(baseURL = "https://one.example/v1")))
    }

    @Test fun legacyConsentOnlyMigratesToTheOriginalOpenAIConfiguration() {
        assertTrue(ProviderConsentScope.canMigrateLegacy(ProviderConfiguration(ModelProvider.OPENAI)))
        assertFalse(ProviderConsentScope.canMigrateLegacy(ProviderConfiguration(ModelProvider.GEMINI)))
        assertFalse(ProviderConsentScope.canMigrateLegacy(ProviderConfiguration(ModelProvider.OPENAI).copy(model = "other-model")))
    }
}
