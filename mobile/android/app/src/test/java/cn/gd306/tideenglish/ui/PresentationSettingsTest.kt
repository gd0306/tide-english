package cn.gd306.tideenglish.ui
import org.junit.Assert.*
import org.junit.Test
class PresentationSettingsTest {
    @Test fun corruptPreferencesRecoverIndependently() {
        assertEquals(PresentationSettings(InterfaceTheme.GROVE, InterfaceLanguage.ENGLISH), PresentationSettings.restored("GROVE", "unknown"))
        assertEquals(PresentationSettings(InterfaceTheme.PAPER, InterfaceLanguage.CHINESE), PresentationSettings.restored("unknown", "CHINESE"))
    }
    @Test fun explicitInterfaceLanguageDoesNotDependOnLearningLanguage() {
        assertEquals("zh", PresentationSettings.restored("MIDNIGHT", "CHINESE").language.tag)
        assertEquals("en", PresentationSettings.restored("GROVE", "ENGLISH").language.tag)
    }
}
