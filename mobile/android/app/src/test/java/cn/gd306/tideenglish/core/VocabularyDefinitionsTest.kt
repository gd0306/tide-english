package cn.gd306.tideenglish.core

import org.junit.Assert.*
import org.junit.Test
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class VocabularyDefinitionsTest {
    private val key = VocabularyDefinitionKey("one", "bank", "river edge", "Beside the bank", "en", "Chinese (Simplified)", ProviderConfiguration())
    private val definition = VocabularyDefinition("The land beside a river", "河岸")
    @Test fun cacheNeverLeaksAcrossMeaningLanguageModelEndpointOrWordSource() {
        val cache = VocabularyDefinitionCache()
        cache.put(key, definition)
        assertEquals(definition, cache.get(key))
        listOf(key.copy(meaningLanguage="Italian"), key.copy(learningLanguage="es"), key.copy(example="The savings bank"),
            key.copy(configuration=key.configuration.copy(model="another-model")),
            key.copy(configuration=ProviderConfiguration(ModelProvider.CUSTOM,"model","https://example.com/v1"))).forEach {
            assertNull(cache.get(it))
        }
    }
    @Test fun savedDefinitionsRemainSearchableAfterSerialization() {
        val cache = VocabularyDefinitionCache()
        cache.put(key, definition)
        val restored = Json.decodeFromString<VocabularyDefinitionCache>(Json.encodeToString(cache)).validated()
        assertTrue(restored.matches(key, "河岸"))
        assertTrue(restored.matches(key, "RIVER"))
        assertFalse(restored.matches(key, "money"))
    }
    @Test fun incompleteDefinitionsAreNotCached() {
        val cache = VocabularyDefinitionCache()
        assertThrows(IllegalArgumentException::class.java) { cache.put(key, VocabularyDefinition("valid", " ")) }
        assertThrows(IllegalArgumentException::class.java) { cache.put(key, VocabularyDefinition("x".repeat(601), "valid")) }
        assertNull(cache.get(key))
    }
    @Test fun diskSnapshotDoesNotChangeDuringLaterCacheWrites() {
        val cache = VocabularyDefinitionCache()
        cache.put(key, definition)
        val snapshot = cache.copySnapshot()
        cache.put(key.copy(lemma="later"), definition)
        assertNull(snapshot.get(key.copy(lemma="later")))
        assertEquals(definition, snapshot.get(key))
    }
    @Test fun tupleEncodingPreventsSeparatorAliases() {
        assertNotEquals(key.copy(lemma="a|b",sense="c").encoded(), key.copy(lemma="a",sense="b|c").encoded())
    }
}
