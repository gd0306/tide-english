package cn.gd306.tideenglish.network

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import cn.gd306.tideenglish.core.EmailAccountFailure
import cn.gd306.tideenglish.core.EmailAccountException
import cn.gd306.tideenglish.core.EmailAccountSession
import cn.gd306.tideenglish.core.EmailAccountStorage
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Separate from learning exports and OpenAI keys; app backup excludes these preferences. */
class EmailAccountSessionStore(context: Context, scope: String) : EmailAccountStorage {
    private val preferences = context.applicationContext.getSharedPreferences("tide_email_session_v1", Context.MODE_PRIVATE)
    private val binding = "${context.packageName}|$scope|v1".toByteArray(Charsets.UTF_8)
    private val alias = "cn.gd306.tideenglish.tide.email.aes.v1"
    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun key(): SecretKey = (keyStore().getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance("AES", "AndroidKeyStore").run {
        init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).build())
        generateKey()
    }
    override suspend fun save(session: EmailAccountSession) = withContext(Dispatchers.IO) { access.withLock {
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()); updateAAD(binding) }
            val encrypted = cipher.doFinal(Json.encodeToString(session).toByteArray(Charsets.UTF_8))
            if (!preferences.edit().putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
                    .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP)).putBoolean("uncertain", false).commit()) throw EmailAccountException(EmailAccountFailure.SecureStorage)
        } catch (_: Exception) { throw EmailAccountException(EmailAccountFailure.SecureStorage) }
    } }
    override suspend fun read(): EmailAccountSession? = withContext(Dispatchers.IO) { access.withLock {
        try {
            val encoded = preferences.getString("ciphertext", null) ?: return@withLock null
            if (encoded.length > 4096) throw EmailAccountException(EmailAccountFailure.SecureStorage)
            val iv = preferences.getString("iv", null) ?: throw EmailAccountException(EmailAccountFailure.SecureStorage)
            if (iv.length > 64) throw EmailAccountException(EmailAccountFailure.SecureStorage)
            val storedKey = keyStore().getKey(alias, null) as? SecretKey ?: throw EmailAccountException(EmailAccountFailure.SecureStorage)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.DECRYPT_MODE, storedKey, GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)))
                updateAAD(binding)
            }
            Json.decodeFromString<EmailAccountSession>(cipher.doFinal(Base64.decode(encoded, Base64.NO_WRAP)).toString(Charsets.UTF_8))
        } catch (_: Exception) {
            remove(); null
        }
    } }
    override suspend fun markUncertain() = withContext(Dispatchers.IO) { access.withLock {
        if (!preferences.edit().putBoolean("uncertain", true).commit()) throw EmailAccountException(EmailAccountFailure.SecureStorage)
    } }
    override suspend fun isUncertain(): Boolean = withContext(Dispatchers.IO) { access.withLock { preferences.getBoolean("uncertain", false) } }
    override suspend fun clear() = withContext(Dispatchers.IO) { access.withLock { remove() } }
    private fun remove() {
        var failed = !preferences.edit().clear().commit()
        try { keyStore().deleteEntry(alias) } catch (_: Exception) { failed = true }
        if (failed) throw EmailAccountException(EmailAccountFailure.SecureStorage)
    }
    companion object {
        // Account sheet instances share this independent file/key.
        // A reader must never combine one save's ciphertext with another save's IV or erase its key.
        private val access = Mutex()
    }
}
