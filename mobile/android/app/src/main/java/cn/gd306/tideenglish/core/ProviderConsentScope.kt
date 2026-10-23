package cn.gd306.tideenglish.core

import java.security.MessageDigest

/** Permission follows the exact supplier, model and normalized recipient. Never includes keys. */
object ProviderConsentScope {
    fun key(configuration: ProviderConfiguration): String {
        val c = configuration.validated()
        return MessageDigest.getInstance("SHA-256")
            .digest("${c.provider.name}\n${c.model}\n${c.baseURL}".toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    fun canMigrateLegacy(configuration: ProviderConfiguration): Boolean =
        configuration == ProviderConfiguration(ModelProvider.OPENAI)
}
