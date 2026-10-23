package cn.gd306.tideenglish.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import cn.gd306.tideenglish.ui.tideStringResource as stringResource
import androidx.compose.ui.unit.dp
import cn.gd306.tideenglish.R

/** The iOS lookup flow: selected word, original sentence, then its contextual meaning. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun WordLookupSheet(word: String, sentence: String, languageID: String,
    explanation: String?, error: String?, loading: Boolean, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = TideEnglishColors.Cream,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().testTag("word-lookup-sheet")) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 26.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.talk_lookup_dialog_title), style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f))
                SoftRoundButton(TideEnglishSymbol.Close, stringResource(R.string.common_close), onDismiss,
                    modifier = Modifier.testTag("word-lookup-close"), diameter = 40.dp)
            }
            Column(Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState())
                .padding(28.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                Text(word, style = MaterialTheme.typography.headlineLarge, modifier = Modifier.testTag("word-lookup-word"))
                if (languageID == "zh") PinyinHelp(word)
                SelectionContainer {
                    Text(sentence, style = MaterialTheme.typography.titleLarge, color = TideEnglishColors.Secondary,
                        modifier = Modifier.testTag("word-lookup-sentence"))
                }
                when {
                    explanation != null -> SelectionContainer {
                        Text(explanation, style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.testTag("word-lookup-explanation"))
                    }
                    error != null -> Text(error, color = TideEnglishColors.Secondary, modifier = Modifier.testTag("word-lookup-error"))
                    loading -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Text(stringResource(R.string.talk_meaning_loading), color = TideEnglishColors.Secondary)
                    }
                }
            }
        }
    }
}
