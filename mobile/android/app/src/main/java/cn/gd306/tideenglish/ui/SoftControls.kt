package cn.gd306.tideenglish.ui

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import cn.gd306.tideenglish.ui.tideStringResource as stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cn.gd306.tideenglish.R

@Composable
fun SoftRoundButton(symbol: TideEnglishSymbol, description: String, onClick: () -> Unit, modifier: Modifier = Modifier,
                    diameter: Dp = 48.dp, tint: Color = TideEnglishColors.Surface.copy(alpha = .78f),
                    enabled: Boolean = true, filledIcon: Boolean = false) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) .94f else 1f, spring(stiffness = 600f), label = "button press")
    Box(modifier.size(diameter).graphicsLayer { scaleX = scale; scaleY = scale }
        .shadow(18.dp, CircleShape, ambientColor = TideEnglishColors.Secondary.copy(alpha = .05f), spotColor = TideEnglishColors.Secondary.copy(alpha = .08f))
        .background(tint, CircleShape).border(1.dp, TideEnglishColors.Surface.copy(alpha = .7f), CircleShape).clip(CircleShape)
        .clickable(enabled = enabled, role = Role.Button, interactionSource = interaction, indication = null, onClick = onClick),
        contentAlignment = Alignment.Center) {
        TideEnglishIcon(symbol, Modifier.size(23.dp), color = TideEnglishColors.Ink.copy(alpha = if (enabled) 1f else .4f),
            description = description, filled = filledIcon)
    }
}

@Composable
fun FloatingNavigation(selected: Int, onSelect: (Int) -> Unit) {
    val items = listOf(Triple(R.string.talk_tab_title, TideEnglishSymbol.Wave, "tab-talk"),
        Triple(R.string.topics_tab_title, TideEnglishSymbol.Themes, "tab-topics"),
        Triple(R.string.words_tab_title, TideEnglishSymbol.Words, "tab-words"))
    Box(Modifier.fillMaxWidth().navigationBarsPadding().padding(top = 8.dp, bottom = 12.dp), contentAlignment = Alignment.Center) {
        BoxWithConstraints(Modifier.widthIn(max = 304.dp).fillMaxWidth().height(66.dp).testTag("floating-navigation")
            .shadow(25.dp, CircleShape, ambientColor = TideEnglishColors.Secondary.copy(alpha = .08f), spotColor = TideEnglishColors.Secondary.copy(alpha = .10f))
            .background(TideEnglishColors.Surface.copy(alpha = .94f), CircleShape)
            .border(1.5.dp, TideEnglishColors.Surface.copy(alpha = .85f), CircleShape).padding(4.dp).selectableGroup()) {
            val width = maxWidth / 3
            val offset by animateDpAsState(width * selected, spring(dampingRatio = .88f, stiffness = 350f), label = "tab position")
            Box(Modifier.offset(x = offset).width(width).fillMaxHeight().background(TideEnglishColors.Peach, CircleShape))
            Row(Modifier.fillMaxSize()) {
                items.forEachIndexed { index, (title, symbol, tag) ->
                    Column(Modifier.weight(1f).fillMaxHeight().clip(CircleShape).testTag(tag)
                        .selectable(selected = selected == index, role = Role.Tab,
                            interactionSource = remember { MutableInteractionSource() }, indication = null,
                            onClick = { onSelect(index) }),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                        TideEnglishIcon(symbol, Modifier.size(24.dp), filled = true)
                        Text(stringResource(title), style = MaterialTheme.typography.labelSmall,
                            color = TideEnglishColors.Ink, modifier = Modifier.padding(top = 2.dp))
                    }
                }
            }
        }
    }
}

@Composable
fun TideEnglishTextField(value: String, onValueChange: (String) -> Unit, modifier: Modifier = Modifier,
                   label: @Composable (() -> Unit)? = null, supportingText: @Composable (() -> Unit)? = null, singleLine: Boolean = false, minLines: Int = 1,
                   maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
                   keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
                   visualTransformation: VisualTransformation = VisualTransformation.None,
                   enabled: Boolean = true) {
    OutlinedTextField(value, onValueChange, modifier, enabled = enabled, label = label, supportingText = supportingText,
        singleLine = singleLine, minLines = minLines, maxLines = maxLines,
        textStyle = MaterialTheme.typography.bodyLarge, shape = RoundedCornerShape(22.dp),
        keyboardOptions = keyboardOptions, visualTransformation = visualTransformation,
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = TideEnglishColors.Surface.copy(alpha = .90f), unfocusedContainerColor = TideEnglishColors.Surface.copy(alpha = .72f),
            focusedBorderColor = TideEnglishColors.Orange.copy(alpha = .7f), unfocusedBorderColor = TideEnglishColors.Surface,
            cursorColor = TideEnglishColors.Ink, focusedLabelColor = TideEnglishColors.Secondary,
            unfocusedLabelColor = TideEnglishColors.Secondary))
}

@Composable
fun TideEnglishSearchField(value: String, onValueChange: (String) -> Unit, placeholder: String) {
    OutlinedTextField(value, onValueChange, modifier = Modifier.fillMaxWidth(), singleLine = true,
        placeholder = { Text(placeholder, style = MaterialTheme.typography.bodyLarge) },
        leadingIcon = { TideEnglishIcon(TideEnglishSymbol.Search, Modifier.size(21.dp)) }, shape = CircleShape,
        textStyle = MaterialTheme.typography.bodyLarge,
        colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = TideEnglishColors.Surface.copy(alpha = .9f),
            unfocusedContainerColor = TideEnglishColors.Surface.copy(alpha = .75f), focusedBorderColor = TideEnglishColors.Orange.copy(alpha = .6f),
            unfocusedBorderColor = TideEnglishColors.Surface, cursorColor = TideEnglishColors.Ink, unfocusedPlaceholderColor = TideEnglishColors.Secondary))
}

@Composable
fun TideEnglishTextButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true,
                     content: @Composable RowScope.() -> Unit) {
    TextButton(onClick, modifier, enabled, colors = ButtonDefaults.textButtonColors(contentColor = TideEnglishColors.Ink), content = content)
}
