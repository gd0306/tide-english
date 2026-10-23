package cn.gd306.tideenglish.ui

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import cn.gd306.tideenglish.TideEnglishViewModel
import cn.gd306.tideenglish.core.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

internal class DefinitionStore private constructor(context: Context, private val generation: Long) {
    private val file = java.io.File(context.filesDir, "tide-vocabulary-definitions-v1.json")
    private var cache = VocabularyDefinitionCache()
    private var active = true
    private var initialized = false
    private val mutation = Mutex()
    private val loading = mutableStateMapOf<String, Boolean>()
    private val failures = mutableStateMapOf<String, Boolean>()
    fun isLoading(key: VocabularyDefinitionKey) = loading[key.encoded()] == true
    fun hasFailure(key: VocabularyDefinitionKey) = failures[key.encoded()] == true
    fun canLoad() = active && loading.size < 2
    fun beginLoading(key: VocabularyDefinitionKey): Boolean {
        if (!canLoad() || isLoading(key)) return false
        loading[key.encoded()] = true
        failures.remove(key.encoded())
        return true
    }
    fun finishLoading(key: VocabularyDefinitionKey, failed: Boolean) {
        loading.remove(key.encoded())
        if (active && failed) failures[key.encoded()] = true
    }
    var revision by mutableIntStateOf(0)
        private set
    var persistenceFailed by mutableStateOf(false)
        private set
    suspend fun initialize() = mutation.withLock {
        if (initialized) return@withLock
        val restored = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            synchronized(diskLock) {
                if (!active) return@synchronized null
                runCatching {
                    require(file.length() <= 4 * 1024 * 1024)
                    val text = android.util.AtomicFile(file).openRead().bufferedReader().use { it.readText() }
                    Json.decodeFromString<VocabularyDefinitionCache>(text).validated()
                }.getOrNull()
            }
        }
        if (active && restored != null) { cache = restored; revision++ }
        initialized = true
    }
    fun get(key: VocabularyDefinitionKey): VocabularyDefinition? { revision; return if (active) cache.get(key) else null }
    fun matches(key: VocabularyDefinitionKey, query: String): Boolean { revision; return active && cache.matches(key, query) }
    suspend fun put(key: VocabularyDefinitionKey, value: VocabularyDefinition) {
        initialize()
        mutation.withLock {
        if (!active) return@withLock
        cache.put(key, value); revision++
        // Serialize and persist away from the UI thread; later mutations wait for this snapshot.
        val snapshot = cache.copySnapshot()
        val saved = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            synchronized(diskLock) {
                if (!active) return@synchronized false
                runCatching {
                    val encoded = Json.encodeToString(snapshot).toByteArray()
                    require(encoded.size <= 4 * 1024 * 1024)
                    val atomic = android.util.AtomicFile(file)
                    val stream = atomic.startWrite()
                    try { stream.write(encoded); atomic.finishWrite(stream) }
                    catch (e: Exception) { atomic.failWrite(stream); throw e }
                }.isSuccess
            }
        }
        if (active) persistenceFailed = !saved
        }
    }
    companion object {
        private val diskLock = Any()
        private val stores = mutableMapOf<String, DefinitionStore>()
        fun shared(context: Context, generation: Long): DefinitionStore = synchronized(diskLock) {
            val path = context.filesDir.absolutePath
            val old = stores[path]
            if (old != null && old.generation == generation) old else {
                old?.active = false
                DefinitionStore(context.applicationContext, generation).also { stores[path] = it }
            }
        }
        /** Root calls this with delete-all to serialize deletion with in-flight disk writes. */
        fun clear(context: Context) = synchronized(diskLock) {
            stores.remove(context.filesDir.absolutePath)?.let { it.active = false; it.cache = VocabularyDefinitionCache(); it.revision++ }
            android.util.AtomicFile(java.io.File(context.filesDir, "tide-vocabulary-definitions-v1.json")).delete()
        }
    }
}
internal fun definitionKey(vm: TideEnglishViewModel, word: WordState) = VocabularyDefinitionKey(word.id, word.lemma, word.meaning,
    word.example.take(1200), vm.language.id, vm.archive.preferences.meaningLanguage, vm.modelConfiguration)

@Composable
internal fun VocabularyDefinitions(vm: TideEnglishViewModel, word: WordState, store: DefinitionStore, compact: Boolean = false) {
    val key = definitionKey(vm, word)
    val value = store.get(key) ?: if (key.learningLanguage == "en" && key.meaningLanguage == "English")
        VocabularyDefinition(word.meaning, word.meaning).takeIf { word.meaning.isNotBlank() && word.meaning.length <= 600 } else null
    val loading = store.isLoading(key)
    val failed = store.hasFailure(key)
    val scope = rememberCoroutineScope()
    val allowed = vm.archive.preferences.aiConsentVersion == AI_CONSENT_VERSION && vm.hasKey && !vm.isRunning
    fun load() {
        if (!allowed || !store.beginLoading(key)) return
        scope.launch(start = kotlinx.coroutines.CoroutineStart.UNDISPATCHED) {
            var requestFailed = false
            try {
                store.initialize()
                if (store.get(key) != null) return@launch
                val source = Json.encodeToString(mapOf("lemma" to word.lemma, "englishReferenceSense" to word.meaning, "example" to word.example.take(1200)))
                val dataGeneration = vm.learningDataGeneration
                val result = vm.fetchVocabularyDefinition(source, vm.language.name, key.meaningLanguage).validated()
                if (key == definitionKey(vm, word) && dataGeneration == vm.learningDataGeneration) store.put(key, result)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { requestFailed = true }
            finally { store.finishLoading(key, requestFailed) }
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("vocabulary-definitions")) {
        VocabularyDefinitionText(vm.language.name, key.meaningLanguage, value, word.meaning, compact)
        if (value != null && store.persistenceFailed) Text(uiText("Definitions are available but could not be saved for next time.", "释义目前可用，但无法保存供下次使用。"), style = MaterialTheme.typography.bodySmall)
        if (value == null) {
            if (!compact || loading || failed || !allowed) Text(when {
                loading -> uiText("Loading definitions…", "正在加载释义…")
                failed -> uiText("Definitions unavailable. Saved words remain available offline.", "暂时无法加载释义。已保存词汇仍可离线浏览。")
                !allowed -> uiText("Add an API key and allow AI in Settings to load definitions.", "请在设置中添加 API 密钥并允许 AI，以加载释义。")
                else -> uiText("Load both definitions for these languages.", "加载这两种语言的释义。")
            }, style = MaterialTheme.typography.bodySmall)
            TideEnglishTextButton(onClick = ::load, enabled = allowed && !loading && store.canLoad()) { Text(if (failed) uiText("Retry", "重试") else uiText("Load definitions", "加载释义")) }
        }
    }
}


/** App labels surround provider-authored definitions without translating the learning content. */
@Composable
internal fun VocabularyDefinitionText(learningLanguage: String, meaningLanguage: String,
    value: VocabularyDefinition?, englishReference: String, compact: Boolean = false) {
    val body = if (compact) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium
    Text(uiText("Learning definition", "学习语言释义") + " · " + learningLanguage, style = MaterialTheme.typography.labelSmall, color = TideEnglishColors.Secondary)
    Text(value?.learningDefinition ?: "—", style = body)
    Text(uiText("Meaning definition", "释义语言解释") + " · " + meaningLanguage, style = MaterialTheme.typography.labelSmall, color = TideEnglishColors.Secondary)
    Text(value?.meaningDefinition ?: "—", style = body)
    if (value == null && englishReference.isNotBlank()) {
        Text(uiText("English reference", "英语参考释义") + " · English", style = MaterialTheme.typography.labelSmall, color = TideEnglishColors.Secondary)
        Text(englishReference, style = body)
    }
}
