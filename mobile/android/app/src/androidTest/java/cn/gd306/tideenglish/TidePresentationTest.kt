package cn.gd306.tideenglish

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.material3.Text
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import cn.gd306.tideenglish.core.ModelProvider
import cn.gd306.tideenglish.core.ProviderConfiguration
import cn.gd306.tideenglish.ui.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TidePresentationTest {
    @get:Rule val compose = createComposeRule()
    @Test fun explicitChineseLabelsApplyUnderMidnightTheme() {
        compose.setContent {
            CompositionLocalProvider(LocalInterfaceLanguage provides InterfaceLanguage.CHINESE, LocalInterfaceTheme provides InterfaceTheme.MIDNIGHT) {
                TideEnglishTheme { Text(uiText("Model & API key", "模型与 API 密钥")) }
            }
        }
        compose.onNodeWithText("模型与 API 密钥").assertIsDisplayed()
        compose.onNodeWithText("Model & API key").assertDoesNotExist()
    }
    @Test fun definitionRequestsAreDeduplicatedAndBoundedWithoutNetwork() {
        val context = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        org.junit.Assert.assertEquals("cn.gd306.tideenglish.android.uitest", context.packageName)
        val store = DefinitionStore.shared(context, 987654L)
        val first = cn.gd306.tideenglish.core.VocabularyDefinitionKey("one", "bank", "river edge", "Beside a river", "es", "Chinese (Simplified)", ProviderConfiguration())
        try {
            org.junit.Assert.assertTrue(store.beginLoading(first))
            org.junit.Assert.assertFalse(store.beginLoading(first))
            org.junit.Assert.assertTrue(store.beginLoading(first.copy(wordID = "two")))
            org.junit.Assert.assertFalse(store.beginLoading(first.copy(wordID = "three")))
            store.finishLoading(first, failed = true)
            org.junit.Assert.assertTrue(store.hasFailure(first))
            org.junit.Assert.assertTrue(store.beginLoading(first))
            org.junit.Assert.assertFalse(store.hasFailure(first))
        } finally { DefinitionStore.clear(context) }
    }
    @Test fun cachedWordCardShowsBothDefinitionsWithActualLanguageLabels() {
        compose.setContent {
            TideEnglishTheme {
                androidx.compose.foundation.layout.Column {
                    VocabularyDefinitionText("Spanish", "Chinese (Simplified)",
                        cn.gd306.tideenglish.core.VocabularyDefinition("La tierra junto a un río", "河岸"), "English reference sense", compact = true)
                }
            }
        }
        compose.onNodeWithText("Learning definition · Spanish").assertIsDisplayed()
        compose.onNodeWithText("Meaning definition · Chinese (Simplified)").assertIsDisplayed()
        compose.onNodeWithText("La tierra junto a un río").assertIsDisplayed()
        compose.onNodeWithText("河岸").assertIsDisplayed()
        compose.onNodeWithText("English reference sense").assertDoesNotExist()
    }
    @Test fun missingDefinitionsLabelEnglishReferenceWithoutMisidentifyingItsLanguage() {
        compose.setContent {
            TideEnglishTheme {
                androidx.compose.foundation.layout.Column {
                    VocabularyDefinitionText("Spanish", "Chinese (Simplified)", null, "The land beside a river", compact = true)
                }
            }
        }
        compose.onNodeWithText("English reference · English").assertIsDisplayed()
        compose.onNodeWithText("The land beside a river").assertIsDisplayed()
        compose.onNodeWithText("Learning definition · Spanish").assertIsDisplayed()
        compose.onNodeWithText("Meaning definition · Chinese (Simplified)").assertIsDisplayed()
    }
    @Test fun consentIdentifiesActualProviderModelAndRecipient() {
        compose.setContent {
            TideEnglishTheme {
                AIConsentDialog({}, {}, ProviderConfiguration(ModelProvider.DEEPSEEK, "deepseek-flash", ModelProvider.DEEPSEEK.defaultBaseURL))
            }
        }
        compose.onNodeWithText("DeepSeek", substring = true).assertExists()
        compose.onNodeWithText("https://api.deepseek.com", substring = true).assertExists()
        compose.onNodeWithText("deepseek-flash", substring = true).assertExists()
    }
}
