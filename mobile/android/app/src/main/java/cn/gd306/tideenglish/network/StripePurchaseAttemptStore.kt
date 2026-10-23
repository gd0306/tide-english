package cn.gd306.tideenglish.network

import android.content.Context
import cn.gd306.tideenglish.core.*
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Excluded from Android backup along with all app preferences. Contains no payment or login credentials. */
class StripePurchaseAttemptStore(context: Context, origin: String, environment: String) : StripePurchaseAttemptStorage {
    private val preferences = context.applicationContext.getSharedPreferences("tideenglish_stripe_attempts", Context.MODE_PRIVATE)
    private val namespace = MessageDigest.getInstance("SHA-256").digest("$origin|$environment".toByteArray())
        .joinToString("") { "%02x".format(it) }
    override suspend fun read(accountID: String): StripePurchaseAttempt? = withContext(Dispatchers.IO) {
        val value = preferences.getString("$namespace.$accountID", null) ?: return@withContext null
        try {
            if (value.length > 2048) throw MinuteCommerceFailure.InvalidResponse
            Json.decodeFromString<StripePurchaseAttempt>(value).also { if (it.accountID != accountID) throw MinuteCommerceFailure.InvalidResponse }
        } catch (_: Exception) { throw MinuteCommerceFailure.InvalidResponse }
    }
    override suspend fun save(attempt: StripePurchaseAttempt) = withContext(Dispatchers.IO) {
        if (!preferences.edit().putString("$namespace.${attempt.accountID}", Json.encodeToString(attempt)).commit())
            throw MinuteCommerceFailure.Unavailable
    }
    override suspend fun remove(accountID: String) = withContext(Dispatchers.IO) {
        if (!preferences.edit().remove("$namespace.$accountID").commit()) throw MinuteCommerceFailure.Unavailable
    }
}
