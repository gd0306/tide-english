package cn.gd306.tideenglish.ui

import android.view.WindowManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import cn.gd306.tideenglish.ui.tidePluralStringResource as pluralStringResource
import cn.gd306.tideenglish.ui.tideStringResource as stringResource
import androidx.compose.ui.semantics.password
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogWindowProvider
import cn.gd306.tideenglish.TideEnglishViewModel
import cn.gd306.tideenglish.R
import cn.gd306.tideenglish.core.LanguageRegistry
import cn.gd306.tideenglish.core.MeaningLanguages
import cn.gd306.tideenglish.core.MinuteBalanceTime
import cn.gd306.tideenglish.core.Passage
import cn.gd306.tideenglish.core.SessionRecord
import cn.gd306.tideenglish.core.Speaker
import cn.gd306.tideenglish.core.UsageSummary
import cn.gd306.tideenglish.core.ProviderFailureKind
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(vm: TideEnglishViewModel, onExport: () -> Unit, onImport: () -> Unit, onReviewConsent: () -> Unit,
                   onAccount: (() -> Unit)? = null, accountSummary: String? = null,
                   focusAdvanced: Boolean = false, onDismiss: () -> Unit = {}) {
    TideDialogAppearance()
    var page by rememberSaveable { mutableStateOf("main") }
    var keyDialog by rememberSaveable { mutableStateOf(false) }
    var deleteAll by rememberSaveable { mutableStateOf(false) }
    var permissionDetails by rememberSaveable { mutableStateOf(false) }
    var revokeConsent by rememberSaveable { mutableStateOf(false) }
    var notices by rememberSaveable { mutableStateOf(false) }
    var history by rememberSaveable { mutableStateOf(false) }
    var transcript by remember { mutableStateOf<SessionRecord?>(null) }
    var deleteSession by remember { mutableStateOf<SessionRecord?>(null) }
    val listState = rememberLazyListState()
    androidx.compose.runtime.LaunchedEffect(focusAdvanced) {
        if (focusAdvanced) listState.scrollToItem(0)
    }
    val prefs = vm.archive.preferences
    val uriHandler = LocalUriHandler.current
    val context = LocalContext.current
    val version = remember(context) { context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty() }
    fun open(url: String) { runCatching { uriHandler.openUri(url) } }

    Column(Modifier.fillMaxSize()) {
        val title = when (page) {
            "interests" -> stringResource(R.string.settings_interests_label)
            "data" -> stringResource(R.string.settings_learning_data)
            "about" -> stringResource(R.string.settings_about)
            else -> stringResource(R.string.settings_navigation_title)
        }
        SettingsSheetHeader(title, onDismiss = { if (page == "main") onDismiss() else page = "main" },
            actionLabel = if (page == "main") R.string.settings_done else R.string.settings_back)
        LazyColumn(Modifier.weight(1f).testTag("settings-screen"), state = listState,
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp)) {
            when (page) {
                "main" -> {
                    item {
                        SettingsGroup {
                            SettingsRow(uiText("Model & API key", "模型与 API 密钥"), vm.modelConfiguration.provider.displayName + " · " + vm.modelConfiguration.model,
                                enabled = !vm.isRunning, chevron = true, modifier = Modifier.testTag("model-api-settings"), onClick = { keyDialog = true })
                        }
                    }
                    item {
                        val presentation = LocalPresentationStore.current
                        SettingsGroup(uiText("Appearance & language", "外观与界面语言")) {
                            SettingsChoiceRow(uiText("Theme", "主题"), presentation.value.theme.name.lowercase().replaceFirstChar { it.uppercase() }, presentation.value.theme.name,
                                InterfaceTheme.entries.map { it.name to it.name.lowercase().replaceFirstChar { c -> c.uppercase() } }, "interface-theme", true) {
                                presentation.update(presentation.value.copy(theme = InterfaceTheme.valueOf(it)))
                            }
                            SettingsDivider()
                            SettingsChoiceRow(uiText("Interface language", "界面语言"), if (presentation.value.language == InterfaceLanguage.CHINESE) "中文" else "English", presentation.value.language.name,
                                listOf("ENGLISH" to "English", "CHINESE" to "中文"), "interface-language", true) {
                                presentation.update(presentation.value.copy(language = InterfaceLanguage.valueOf(it)))
                            }
                        }
                    }
                    item {
                        SettingsGroup {
                            Row(Modifier.fillMaxWidth().heightIn(min = 68.dp)
                                .testTag("email-account-settings")
                                .clickable(enabled = onAccount != null && !vm.isRunning) { onAccount?.invoke() }
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                TideEnglishOrb(modifier = Modifier.size(38.dp), active = false)
                                Column(Modifier.weight(1f)) {
                                    Text(stringResource(R.string.account_title), style = MaterialTheme.typography.bodyLarge)
                                    Text(accountSummary ?: stringResource(R.string.settings_sign_in_optional),
                                        style = MaterialTheme.typography.bodySmall, color = TideEnglishColors.Secondary)
                                }
                                TideEnglishIcon(TideEnglishSymbol.ChevronRight, Modifier.size(13.dp), color = TideEnglishColors.Secondary)
                            }
                        }
                    }
                    item {
                        SettingsGroup(stringResource(R.string.settings_your_learning),
                            stringResource(if (vm.isRunning) R.string.settings_language_running_footer else R.string.settings_language_footer)) {
                            SettingsChoiceRow(stringResource(R.string.settings_learning_language), vm.language.settingsTitle, vm.language.id,
                                LanguageRegistry.all.map { it.id to it.settingsTitle }, "settings-learning-language", !vm.isRunning, vm::selectLanguage)
                            SettingsDivider()
                            SettingsMeaningSwitch(prefs.meaningVisible, vm::toggleMeaning)
                            SettingsDivider()
                            SettingsChoiceRow(stringResource(R.string.settings_meaning_language), prefs.meaningLanguage, prefs.meaningLanguage,
                                MeaningLanguages.all.map { it to it }, "settings-meaning-language", !vm.isRunning) {
                                vm.updatePreferences(prefs.copy(meaningLanguage = it))
                            }
                            SettingsDivider()
                            SettingsRow(stringResource(R.string.settings_interests_label), prefs.interests.take(24),
                                enabled = !vm.isRunning, chevron = true, modifier = Modifier.testTag("settings-interests"),
                                onClick = { page = "interests" })
                            Text(stringResource(R.string.settings_corrections_note), style = MaterialTheme.typography.bodySmall,
                                color = TideEnglishColors.Secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp))
                        }
                    }
                    item {
                        SettingsGroup(stringResource(R.string.settings_section_conversation),
                            stringResource(R.string.settings_session_limit_note)) {
                            val limits = (listOf(5, 10, 15, 20, 30, 60) + prefs.sessionMinutes).distinct().sorted()
                            SettingsChoiceRow(stringResource(R.string.settings_conversation_limit), stringResource(R.string.settings_limit_minutes, prefs.sessionMinutes),
                                prefs.sessionMinutes.toString(), limits.map { it.toString() to stringResource(R.string.settings_limit_minutes, it) },
                                "settings-conversation-limit", !vm.isRunning) { vm.updatePreferences(prefs.copy(sessionMinutes = it.toInt())) }
                        }
                    }
                    item {
                        SettingsGroup(stringResource(R.string.settings_your_data)) {
                            SettingsRow(stringResource(R.string.settings_learning_data), symbol = SettingsSymbol.HISTORY,
                                chevron = true, modifier = Modifier.testTag("settings-data"), onClick = { page = "data" })
                        }
                    }
                    item {
                        SettingsGroup(stringResource(R.string.settings_section_help_privacy)) {
                            SettingsRow(stringResource(R.string.common_contact_support), onClick = { open("https://tide-english.example/support/") })
                            SettingsDivider()
                            SettingsRow(stringResource(R.string.common_privacy_policy), onClick = { open("https://tide-english.example/privacy/") })
                            SettingsDivider()
                            SettingsRow(stringResource(R.string.common_terms_of_use), onClick = { open("https://tide-english.example/terms/") })
                            SettingsDivider()
                            SettingsRow(stringResource(R.string.settings_about), chevron = true,
                                modifier = Modifier.testTag("settings-about"), onClick = { page = "about" })
                        }
                    }
                }
                "interests" -> item {
                    SettingsGroup(footer = stringResource(R.string.settings_interests_note)) {
                        BasicTextField(value = prefs.interests,
                            onValueChange = { vm.updatePreferences(prefs.copy(interests = it.take(500))) },
                            enabled = !vm.isRunning,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(color = TideEnglishColors.Ink),
                            cursorBrush = SolidColor(TideEnglishColors.Secondary), minLines = 3, maxLines = 10,
                            modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp)
                                .padding(16.dp).testTag("settings-interests-input"),
                            decorationBox = { field ->
                                if (prefs.interests.isEmpty()) Text(stringResource(R.string.settings_interests_placeholder),
                                    color = TideEnglishColors.Secondary.copy(alpha = .7f))
                                field()
                            })
                    }
                }
                "data" -> item {
                    SettingsGroup(footer = stringResource(R.string.settings_backup_footer)) {
                        SettingsRow(stringResource(R.string.settings_export_backup), enabled = !vm.isRunning,
                            symbol = SettingsSymbol.EXPORT, onClick = onExport)
                        SettingsDivider()
                        SettingsRow(stringResource(R.string.settings_import_backup), enabled = !vm.isRunning,
                            symbol = SettingsSymbol.IMPORT, onClick = onImport)
                        SettingsDivider()
                        SettingsRow(stringResource(R.string.history_section_title), chevron = true,
                            modifier = Modifier.testTag("settings-history"), onClick = { history = true })
                        SettingsDivider()
                        SettingsRow(stringResource(R.string.settings_delete_all_data), enabled = !vm.isRunning,
                            tint = TideEnglishColors.Red, onClick = { deleteAll = true })
                    }
                }
                "about" -> item {
                    SettingsGroup {
                        Text(stringResource(R.string.settings_app_version_footer, version),
                            style = MaterialTheme.typography.bodySmall, color = TideEnglishColors.Secondary,
                            modifier = Modifier.padding(16.dp))
                        SettingsDivider()
                        SettingsRow(stringResource(R.string.settings_section_ai_permission), chevron = true,
                            modifier = Modifier.testTag("settings-ai-permission"), onClick = { permissionDetails = true })
                        SettingsDivider()
                        SettingsRow(uiText("Selected provider", "所选服务商"), vm.modelConfiguration.provider.displayName)
                        Text(vm.modelConfiguration.baseURL, style = MaterialTheme.typography.bodySmall,
                            color = TideEnglishColors.Secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                        Text(stringResource(R.string.settings_data_use_footer), style = MaterialTheme.typography.bodySmall,
                            color = TideEnglishColors.Secondary, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
                        SettingsDivider()
                        SettingsRow(stringResource(R.string.settings_open_source_notices), chevron = true,
                            onClick = { notices = true })
                    }
                }
            }
        }
    }
    if (keyDialog) ModelConfigurationDialog(vm, onDismiss = { keyDialog = false })
    if (notices) NoticesDialog(onDismiss = { notices = false })
    if (history) SettingsHistorySheet(vm, onDismiss = { history = false }, onSelect = { transcript = it }, onDelete = { deleteSession = it })
    if (permissionDetails) AlertDialog(onDismissRequest = { permissionDetails = false },
        title = { Text(stringResource(R.string.settings_section_ai_permission)) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(if (prefs.aiConsentVersion == AI_CONSENT_VERSION) R.string.settings_ai_consent_accepted else R.string.settings_ai_consent_not_accepted),
                style = MaterialTheme.typography.titleSmall)
            Text(stringResource(R.string.settings_ai_permission_summary), color = TideEnglishColors.Secondary)
        } },
        confirmButton = {
            if (prefs.aiConsentVersion == AI_CONSENT_VERSION) TideEnglishTextButton(onClick = { permissionDetails = false; revokeConsent = true },
                enabled = !vm.isRunning, modifier = Modifier.testTag("revoke-ai-consent")) {
                Text(stringResource(R.string.settings_revoke_consent_button), color = TideEnglishColors.Red)
            } else TideEnglishTextButton(onClick = { permissionDetails = false; onReviewConsent() },
                enabled = !vm.isRunning, modifier = Modifier.testTag("review-ai-consent")) { Text(stringResource(R.string.settings_review_consent_button)) }
        }, dismissButton = { TideEnglishTextButton(onClick = { permissionDetails = false }) { Text(stringResource(R.string.common_close)) } })
    if (deleteAll) ConfirmDialog(stringResource(R.string.settings_delete_all_confirm_title), stringResource(R.string.settings_delete_all_confirm_message), stringResource(R.string.settings_delete_all_confirm_button), {
        vm.deleteLearningData(); deleteAll = false
    }, { deleteAll = false })
    if (revokeConsent) ConfirmDialog(stringResource(R.string.settings_revoke_consent_confirm_title),
        stringResource(R.string.settings_revoke_consent_confirm_message), stringResource(R.string.settings_revoke_consent_button), {
            vm.updatePreferences(vm.archive.preferences.copy(aiConsentVersion = null)); revokeConsent = false
        }, { revokeConsent = false })
    deleteSession?.let { session -> ConfirmDialog(stringResource(R.string.history_delete_session_confirm_title), session.title, stringResource(R.string.common_delete), {
        vm.deleteSession(session.id); deleteSession = null
    }, { deleteSession = null }) }
    transcript?.let { TranscriptDialog(vm, it, onDismiss = { transcript = null }) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsHistorySheet(vm: TideEnglishViewModel, onDismiss: () -> Unit, onSelect: (SessionRecord) -> Unit, onDelete: (SessionRecord) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = TideEnglishColors.Cream,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxHeight(.9f)) {
            SettingsSheetHeader(stringResource(R.string.history_section_title), onDismiss)
            LazyColumn(Modifier.weight(1f).testTag("settings-history-list"), contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (vm.archive.sessions.isEmpty()) item {
                    Text(stringResource(R.string.history_empty), style = MaterialTheme.typography.bodyLarge, color = TideEnglishColors.Secondary,
                        modifier = Modifier.padding(16.dp))
                }
                items(vm.archive.sessions.sortedByDescending { it.startedAt }, key = { it.id }) { session ->
                    SettingsGroup {
                        Column(Modifier.fillMaxWidth().clickable { onSelect(session) }.padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            Text(session.title, style = MaterialTheme.typography.titleMedium)
                            Text("${LanguageRegistry.get(session.languageID)?.name ?: session.languageID} · ${formatDate(session.startedAt)}",
                                color = TideEnglishColors.Secondary, style = MaterialTheme.typography.bodySmall)
                        }
                        SettingsDivider()
                        SettingsRow(stringResource(R.string.common_delete), enabled = !vm.isRunning, tint = TideEnglishColors.Red, onClick = { onDelete(session) })
                    }
                }
            }
        }
    }
}

@Composable
private fun ConfirmDialog(title: String, message: String, confirm: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TideEnglishTextButton(onClick = onConfirm) { Text(confirm, color = TideEnglishColors.Red) } },
        dismissButton = { TideEnglishTextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
    )
}

@Composable
fun TranscriptDialog(vm: TideEnglishViewModel, session: SessionRecord, onDismiss: () -> Unit) {
    var correcting by remember { mutableStateOf<Passage?>(null) }
    val liveSession = vm.archive.sessions.firstOrNull { it.id == session.id }
        ?: vm.session?.takeIf { it.id == session.id }
        ?: session
    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = RoundedCornerShape(28.dp), color = TideEnglishColors.Surface) {
            LazyColumn(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                item {
                    Text(liveSession.title, style = MaterialTheme.typography.headlineMedium)
                    Text("${formatDate(liveSession.startedAt)} · ${pluralStringResource(R.plurals.history_passages_count, liveSession.passages.size, liveSession.passages.size)}", color = TideEnglishColors.Secondary)
                }
                items(liveSession.passages, key = { it.id }) { passage ->
                    Column(
                        Modifier.fillMaxWidth().background(
                            if (passage.speaker == Speaker.user) TideEnglishColors.SurfaceBright else TideEnglishColors.Peach,
                            RoundedCornerShape(18.dp),
                        ).padding(15.dp),
                        verticalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(if (passage.speaker == Speaker.user) R.string.history_speaker_you else R.string.history_speaker_tideenglish),
                                style = MaterialTheme.typography.labelSmall, color = TideEnglishColors.Secondary, modifier = Modifier.weight(1f))
                            if (passage.speaker == Speaker.assistant && passage.text.isNotBlank()) {
                                ReportUtteranceAction(onClick = {
                                    vm.reportUtterance(liveSession.id, passage.id)
                                    onDismiss()
                                }, modifier = Modifier.testTag("report-history-${passage.id}"))
                            }
                        }
                        SelectionContainer { Text(passage.text) }
                        if (liveSession.languageID == "zh") PinyinHelp(passage.text)
                        if (passage.speaker == Speaker.user && !vm.isRunning) TideEnglishTextButton(onClick = { correcting = passage }) { Text(stringResource(R.string.history_edit_passage_button)) }
                    }
                }
                liveSession.topics.flatMap { it.sources }.filter { it.safeUrl() != null }.takeIf { it.isNotEmpty() }?.let { sources ->
                    item { Text(stringResource(R.string.history_saved_sources), fontWeight = FontWeight.SemiBold) }
                    items(sources) { source ->
                        val uriHandler = LocalUriHandler.current
                        Text("↗ ${source.title}", color = TideEnglishColors.Orange, modifier = Modifier.clickable { source.safeUrl()?.let(uriHandler::openUri) }.padding(vertical = 6.dp))
                    }
                }
                item { TideEnglishTextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.common_close)) } }
            }
        }
    }
    correcting?.let { passage -> CorrectionDialog(passage, onSave = {
        vm.correctPassage(liveSession.id, passage.id, it); correcting = null
    }, onDismiss = { correcting = null }) }
}

@Composable
private fun CorrectionDialog(passage: Passage, onSave: (String) -> Unit, onDismiss: () -> Unit) {
    var text by rememberSaveable(passage.id) { mutableStateOf(passage.text) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.history_correction_dialog_title)) },
        text = { TideEnglishTextField(text, { text = it.take(10_000) }, minLines = 3, maxLines = 9) },
        confirmButton = { Button(onClick = { onSave(text.trim()) }, enabled = text.isNotBlank()) { Text(stringResource(R.string.common_save)) } },
        dismissButton = { TideEnglishTextButton(onClick = onDismiss) { Text(stringResource(R.string.common_cancel)) } },
    )
}
