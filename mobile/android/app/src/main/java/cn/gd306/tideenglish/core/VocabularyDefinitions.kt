package cn.gd306.tideenglish.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class VocabularyDefinition(val learningDefinition: String, val meaningDefinition: String) {
    fun validated(): VocabularyDefinition {
        require(listOf(learningDefinition, meaningDefinition).all { it.isNotBlank() && it.length <= 600 })
        return this
    }
}
@Serializable
data class VocabularyDefinitionKey(val wordID: String, val lemma: String, val sense: String, val example: String,
    val learningLanguage: String, val meaningLanguage: String, val configuration: ProviderConfiguration) {
    fun encoded(): String = Json.encodeToString(this)
}
/** Bounded auxiliary cache. Never part of learning exports; contains no credentials. */
@Serializable
data class VocabularyDefinitionCache(private val entries: LinkedHashMap<String, VocabularyDefinition> = linkedMapOf()) {
    fun copySnapshot(): VocabularyDefinitionCache = VocabularyDefinitionCache(LinkedHashMap(entries))
    fun get(key: VocabularyDefinitionKey): VocabularyDefinition? = entries[key.encoded()]
    fun put(key: VocabularyDefinitionKey, value: VocabularyDefinition) {
        value.validated()
        val encoded = key.encoded()
        require(encoded.length <= 20_000)
        entries.remove(encoded)
        entries[encoded] = value
        while (entries.size > 1000) entries.remove(entries.keys.first())
    }
    fun matches(key: VocabularyDefinitionKey, query: String): Boolean = get(key)?.let {
        it.learningDefinition.contains(query, true) || it.meaningDefinition.contains(query, true)
    } == true
    fun validated(): VocabularyDefinitionCache {
        require(entries.size <= 1000 && entries.keys.all { it.length <= 20_000 })
        entries.values.forEach { it.validated() }
        return this
    }
}
