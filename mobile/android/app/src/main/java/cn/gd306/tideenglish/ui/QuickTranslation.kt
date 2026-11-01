package cn.gd306.tideenglish.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import android.content.ClipData
import cn.gd306.tideenglish.TideEnglishViewModel
import cn.gd306.tideenglish.errorMessageRes
import cn.gd306.tideenglish.core.*
import kotlinx.coroutines.launch

@Stable
internal class QuickTranslationState(
    source: MutableState<String>, target: MutableState<String>, input: MutableState<String>,
    val translator: QuickTranslationController,
) {
    var source by source
    var target by target
    var input by input
    var revision by mutableIntStateOf(0)
}

/** Owned by WordsScreen, so scrolling the lazy list never cancels or resends a translation. */
@Composable
internal fun rememberQuickTranslationState(vm: TideEnglishViewModel): QuickTranslationState {
    val initialSource = QuickTranslationRequest.sourceLanguage(vm.language)
    val source = rememberSaveable(vm.language.id) { mutableStateOf(initialSource) }
    val target = rememberSaveable(vm.language.id) { mutableStateOf(vm.archive.preferences.meaningLanguage.let {
        if (it == initialSource) { if (it == "English") "Chinese (Simplified)" else "English" } else it
    }) }
    val input = rememberSaveable(vm.language.id) { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val translator = remember(vm, vm.language.id) { QuickTranslationController(scope, translate = vm::quickTranslate) }
    val state = remember(translator) { QuickTranslationState(source, target, input, translator) }
    DisposableEffect(state) {
        translator.onChange = { state.revision++ }
        onDispose { translator.onChange = null; translator.reset() }
    }
    val allowed = translationAllowed(vm)
    val request = QuickTranslationRequest(state.input, state.source, state.target)
    LaunchedEffect(request, allowed, vm.modelConfiguration, vm.learningDataGeneration) {
        translator.reset()
        if (allowed) translator.update(request)
    }
    return state
}

private fun translationAllowed(vm: TideEnglishViewModel) = vm.archive.preferences.aiConsentVersion == AI_CONSENT_VERSION && vm.hasKey &&
    vm.conversationProvider == ConversationProvider.PERSONAL_KEY && !vm.isRunning

@Composable
internal fun QuickTranslation(vm: TideEnglishViewModel, state: QuickTranslationState) {
    val translator = state.translator
    state.revision // Observe the controller's page-local state.
    val allowed = translationAllowed(vm)
    val request = QuickTranslationRequest(state.input, state.source, state.target)
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboard.current
    val swapLabel = uiText("Swap languages", "交换语言")
    val copyLabel = uiText("Copy translation", "复制译文")
    Surface(shape = RoundedCornerShape(20.dp), color = TideEnglishColors.Surface) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(uiText("Quick translation", "便捷翻译"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TranslationLanguageMenu(state.source, uiText("Source language", "源语言"), "translation-source", Modifier.weight(1f)) { state.source = it }
                TextButton(onClick = {
                    val output = translator.text
                    val previous = state.source; state.source = state.target; state.target = previous
                    if (output.isNotEmpty()) state.input = output
                    translator.reset()
                }, modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).testTag("translation-swap").semantics { contentDescription = swapLabel },
                    contentPadding = PaddingValues(4.dp)) { Text("⇄", style = MaterialTheme.typography.titleLarge) }
                TranslationLanguageMenu(state.target, uiText("Target language", "目标语言"), "translation-target", Modifier.weight(1f)) { state.target = it }
            }
            OutlinedTextField(state.input, { state.input = it }, label = { Text(uiText("Enter text", "输入文字")) },
                minLines = 3, maxLines = 5, isError = state.input.length > 2000, modifier = Modifier.fillMaxWidth().testTag("translation-input"))
            Surface(color = TideEnglishColors.Sage.copy(alpha = .6f), shape = RoundedCornerShape(12.dp)) {
                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(uiText("Translation", "译文"), style = MaterialTheme.typography.labelSmall, modifier = Modifier.weight(1f))
                        if (translator.isLoading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                        if (translator.text.isNotEmpty()) TextButton(onClick = {
                            scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(copyLabel, translator.text))) }
                        }, modifier = Modifier.testTag("translation-copy")) { Text(uiText("Copy", "复制")) }
                    }
                    SelectionContainer {
                        Text(translator.text.ifEmpty { uiText("Your translation appears here.", "译文将显示在这里。") },
                            color = if (translator.text.isEmpty()) TideEnglishColors.Secondary else TideEnglishColors.Ink,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 42.dp).testTag("translation-output"))
                    }
                }
            }
            if (state.input.length > 2000) Text(uiText("Keep text within 2,000 characters.", "请输入不超过 2,000 个字符的文字。"), style = MaterialTheme.typography.bodySmall)
            translator.error?.let {
                val resource = errorMessageRes(it)
                Text(if (resource != 0) tideStringResource(resource) else uiText("Couldn’t translate. Check your connection and try again.", "翻译失败，请检查网络后重试。"),
                    style = MaterialTheme.typography.bodySmall, modifier = Modifier.testTag("translation-error"))
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { state.input = ""; translator.reset() }, enabled = state.input.isNotEmpty(), modifier = Modifier.testTag("translation-clear")) { Text(uiText("Clear", "清空")) }
                Button(onClick = { translator.update(request, immediately = true) }, enabled = allowed && request.isValid && !translator.isLoading,
                    modifier = Modifier.testTag("translation-submit")) { Text(if (translator.error != null) uiText("Retry", "重试") else uiText("Translate", "翻译")) }
            }
            Text(when {
                vm.isRunning -> uiText("End the conversation to use quick translation.", "结束对话后即可使用便捷翻译。")
                !allowed -> uiText("Add your API key and allow AI in Settings to translate.", "请在设置中选择自己的 API 密钥并允许 AI 翻译。")
                else -> uiText("Uses your selected model and API key.", "使用你已选择的模型和 API 密钥。")
            }, style = MaterialTheme.typography.bodySmall, color = TideEnglishColors.Secondary)
        }
    }
}

@Composable
private fun TranslationLanguageMenu(value: String, label: String, tag: String, modifier: Modifier, select: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    // Keep the language names consistent with Settings; localize the two default choices.
    @Composable fun name(language: String): String = when (language) {
        "English" -> uiText("English", "英语")
        "Chinese (Simplified)" -> uiText("Chinese (Simplified)", "简体中文")
        else -> language
    }
    Box(modifier) {
        OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag(tag).semantics { contentDescription = label },
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 10.dp), shape = RoundedCornerShape(10.dp)) {
            Text(name(value), modifier = Modifier.weight(1f)); Text("⌄")
        }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            MeaningLanguages.all.forEach { language -> DropdownMenuItem(text = { Text(name(language)) }, onClick = { expanded = false; select(language) }) }
        }
    }
}
