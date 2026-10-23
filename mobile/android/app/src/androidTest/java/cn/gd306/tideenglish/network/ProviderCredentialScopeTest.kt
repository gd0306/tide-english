package cn.gd306.tideenglish.network

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import cn.gd306.tideenglish.core.ModelProvider
import cn.gd306.tideenglish.core.ProviderConfiguration
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProviderCredentialScopeTest {
    @Test fun customRecipientsHaveIndependentEncryptedCredentials() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        check(context.packageName.endsWith(".uitest")) { "Credential verification requires the isolated UI test app." }
        val id = UUID.randomUUID().toString()
        val first = ProviderConfiguration(ModelProvider.CUSTOM, "chat", "https://$id.example/first")
        val second = first.copy(baseURL = "https://$id.example/second")
        val one = CredentialStore(context, first)
        val two = CredentialStore(context, second)
        try {
            one.save("synthetic-key-one")
            two.save("synthetic-key-two")
            assertEquals("synthetic-key-one", CredentialStore(context, first).read())
            assertEquals("synthetic-key-two", CredentialStore(context, second).read())
            one.delete()
            assertNull(one.read())
            assertEquals("synthetic-key-two", two.read())
        } finally {
            one.delete()
            two.delete()
        }
    }
}
