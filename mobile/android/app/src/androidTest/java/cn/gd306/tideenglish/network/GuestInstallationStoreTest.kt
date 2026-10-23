package cn.gd306.tideenglish.network

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import cn.gd306.tideenglish.core.*
import java.security.KeyStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GuestInstallationStoreTest {
    @Test fun guestIdentityAndTransferTicketSurviveRecreationWithoutEnteringMemberStorage() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("cn.gd306.tideenglish.android.uitest", context.packageName)
        val origin = "https://guest.example.test/"
        val store = GuestInstallationStore(context, origin)
        val members = AccountSessionStore(context, origin)
        val member = AccountSession("22222222-2222-4222-8222-222222222222", "m".repeat(43), System.currentTimeMillis() + 86_400_000)
        val guest = AccountSession("11111111-1111-4111-8111-111111111111", "g".repeat(43), System.currentTimeMillis() + 86_400_000)
        val value = GuestInstallation("i".repeat(43), guest, member.accountID)
        try {
            store.save(value); members.save(member)
            assertEquals(value, GuestInstallationStore(context, origin).read())
            assertEquals(member, members.read())
            val raw = context.getSharedPreferences("tideenglish_guest_installation", Context.MODE_PRIVATE).all.values.joinToString()
            listOf(value.installationToken, guest.accessToken, guest.accountID, member.accountID).forEach { assertFalse(raw.contains(it)) }
            members.clear(); assertEquals(value, store.read())
        } finally { members.clear(); cleanup(context) }
    }
    @Test fun wrongOriginAndCipherCorruptionFailClosedWithoutReplacingInstallation() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("cn.gd306.tideenglish.android.uitest", context.packageName)
        val store = GuestInstallationStore(context, "https://guest.example.test/")
        val value = GuestInstallation("i".repeat(43))
        try {
            store.save(value)
            try { GuestInstallationStore(context, "https://other.example.test/").read(); fail("cross-origin identity") }
            catch (_: AccountFailure.SecureStorage) { }
            assertEquals(value, store.read())
            context.getSharedPreferences("tideenglish_guest_installation", Context.MODE_PRIVATE).edit().putString("ciphertext", "invalid").commit()
            try { store.read(); fail("corruption treated as fresh install") } catch (_: AccountFailure.SecureStorage) { }
        } finally { cleanup(context) }
    }
    private fun cleanup(context: Context) {
        context.getSharedPreferences("tideenglish_guest_installation", Context.MODE_PRIVATE).edit().clear().commit()
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry("cn.gd306.tideenglish.guest.aes") }
    }
}
