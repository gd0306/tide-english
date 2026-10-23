package cn.gd306.tideenglish.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.background
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import cn.gd306.tideenglish.ui.tideStringResource as stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import cn.gd306.tideenglish.TideEnglishViewModel
import cn.gd306.tideenglish.R
import cn.gd306.tideenglish.core.CloudAction
import cn.gd306.tideenglish.core.AccountState
import cn.gd306.tideenglish.AccountViewModel
import cn.gd306.tideenglish.MinutePurchaseViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TideEnglishApp(
    vm: TideEnglishViewModel,
    onEmailAccount: (() -> Unit)? = null,
    emailAccountSummary: String? = null,
    microphoneMessage: String?,
    onRequestMicrophone: () -> Unit,
    onOpenAppSettings: (() -> Unit)?,
    onExport: () -> Unit,
    onImport: () -> Unit,
    account: AccountViewModel? = null,
    onGoogleSignIn: () -> Unit = {},
    onSignOut: () -> Unit = {},
    onDeleteAccount: () -> Unit = {},
    accountTransitionBusy: Boolean = false,
    purchases: MinutePurchaseViewModel? = null,
    onBuyMinutes: (String, Int) -> Unit = { _, _ -> },
) {
    val reportState by vm.reportState.collectAsStateWithLifecycle()
    val accountState = account?.state?.collectAsStateWithLifecycle()?.value
    val prefs = vm.archive.preferences
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var showConsent by rememberSaveable { mutableStateOf(false) }
    var showAccount by rememberSaveable { mutableStateOf(false) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var focusAdvanced by rememberSaveable { mutableStateOf(false) }
    var showMinutes by rememberSaveable { mutableStateOf(false) }
    BackHandler(enabled = tab != 0 && !showSettings && !showAccount && !showMinutes) { tab = 0 }
    fun perform(action: CloudAction) {
        when (action) {
            CloudAction.StartVoice -> if (!vm.needsMinuteAccess()) onRequestMicrophone()
            is CloudAction.SendTyped -> vm.sendTyped(action.text)
            is CloudAction.Lookup -> vm.lookup(action.word, action.sentence)
            is CloudAction.CurrentTopic -> vm.currentTopic(action.query)
            CloudAction.Help -> vm.help()
        }
    }
    fun withConsent(action: CloudAction) {
        if (vm.archive.preferences.aiConsentVersion == AI_CONSENT_VERSION) perform(action)
        else {
            vm.pendingCloudAction = action
            showConsent = true
        }
    }

    TidePresentation { TideEnglishTheme {
        Surface(Modifier.fillMaxSize(), color = TideEnglishColors.Cream) {
            if (vm.loadingHistory) {
                Box(Modifier.fillMaxSize().testTag("history-loading"))
            } else if (!prefs.hasOnboarded) {
                OnboardingScreen(prefs.learningLanguageID, prefs.meaningLanguage) { language, meaning ->
                    vm.selectLanguage(language)
                    vm.updatePreferences(
                        vm.archive.preferences.copy(
                            learningLanguageID = language,
                            meaningLanguage = meaning,
                            meaningVisible = true,
                            hasOnboarded = true,
                            aiConsentVersion = null,
                        ),
                    )
                    vm.pendingCloudAction = null
                    showConsent = true
                }
            } else {
                Scaffold(
                    containerColor = TideEnglishColors.Cream,
                    contentWindowInsets = WindowInsets(0, 0, 0, 0),
                    topBar = {
                        Row(
                            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(horizontal = 20.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Brand()
                            Spacer(Modifier.weight(1f))
                            SoftRoundButton(TideEnglishSymbol.Settings, stringResource(R.string.settings_tab_title),
                                onClick = { showSettings = true }, modifier = Modifier.testTag("tab-settings"), diameter = 44.dp)
                        }
                    },
                ) { padding ->
                    Box(Modifier.fillMaxSize().padding(padding)) {
                    Column(Modifier.fillMaxSize().then(if (tab == 0) Modifier.padding(bottom =
                        90.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()) else Modifier)) {
                        when (tab) {
                            0 -> TalkScreen(
                                vm = vm,
                                onOpenAdvanced = { focusAdvanced = true; showSettings = true },
                                onOpenAccount = { onEmailAccount?.invoke() },
                                microphoneMessage = microphoneMessage,
                                onMicrophone = { withConsent(CloudAction.StartVoice) },
                                onOpenAppSettings = onOpenAppSettings,
                                onSendTyped = { text -> withConsent(CloudAction.SendTyped(text)) },
                                onLookup = { word, sentence -> withConsent(CloudAction.Lookup(word, sentence)) },
                                onHelp = { withConsent(CloudAction.Help) },
                            )
                            1 -> TopicsScreen(
                                vm,
                                onChoose = { tab = 0 },
                                onCurrentTopic = { query -> withConsent(CloudAction.CurrentTopic(query)) },
                            )
                            2 -> WordsScreen(vm)
                        }
                    }
                    Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(108.dp)
                        .background(Brush.verticalGradient(listOf(Color.Transparent, TideEnglishColors.Cream.copy(alpha = .92f)))))
                    Box(Modifier.align(Alignment.BottomCenter)) { FloatingNavigation(tab) { tab = it } }
                    }
                }
            }

            if (showSettings) {
                ModalBottomSheet(onDismissRequest = { showSettings = false; focusAdvanced = false }, containerColor = TideEnglishColors.Cream,
                    sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
                    Column(Modifier.fillMaxHeight(.94f)) {
                        SettingsScreen(vm, onExport, onImport, onReviewConsent = {
                            vm.pendingCloudAction = null; showConsent = true
                        }, onAccount = {
                            onEmailAccount?.invoke()
                        }, accountSummary = emailAccountSummary, focusAdvanced = focusAdvanced,
                            onDismiss = { showSettings = false; focusAdvanced = false })
                    }
                }
            }

            if (showConsent) AIConsentDialog(configuration = vm.modelConfiguration,
                onAgree = {
                    vm.updatePreferences(vm.archive.preferences.copy(aiConsentVersion = AI_CONSENT_VERSION))
                    showConsent = false
                    val action = vm.pendingCloudAction
                    vm.pendingCloudAction = null
                    action?.let(::perform)
                },
                onDecline = {
                    showConsent = false
                    vm.pendingCloudAction = null
                },
            )

            reportState.selection?.let { selected ->
                androidx.compose.runtime.key(reportState.generation) {
                    ReportConversationSheet(selected.excerpt, selected.languageID, reportState.available,
                        reportState.delivery, vm::submitReport, vm::dismissReport,
                        LocalInterfaceLanguage.current.tag)
                }
            }

            vm.error?.let { message ->
                AlertDialog(
                    onDismissRequest = vm::dismissError,
                    title = { Text(stringResource(R.string.error_dialog_title)) },
                    text = { Text(message) },
                    confirmButton = { TideEnglishTextButton(onClick = vm::dismissError) { Text(stringResource(R.string.common_ok)) } },
                    dismissButton = if (vm.errorNeedsKeySetup) ({
                        TideEnglishTextButton(onClick = { vm.dismissError(); showSettings = true }) { Text(stringResource(R.string.error_go_to_settings)) }
                    }) else null,
                )
            }
        }
    }
}
}
