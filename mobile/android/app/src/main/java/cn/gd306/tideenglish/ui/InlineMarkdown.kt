package cn.gd306.tideenglish.ui

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import cn.gd306.tideenglish.core.SourceLink

private val INLINE_MARKDOWN = Regex("""\[([^\]]+)]\(([^)\s]+)\)|\*\*(.+?)\*\*""")

fun inlineMarkdown(text: String, linkColor: androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color(0xFF445548)): AnnotatedString = buildAnnotatedString {
    var cursor = 0
    for (match in INLINE_MARKDOWN.findAll(text)) {
        append(text, cursor, match.range.first)
        val (label, url, bold) = match.destructured
        val safeUrl = SourceLink(label, url).safeUrl()
        when {
            bold.isNotEmpty() -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(bold) }
            safeUrl == null -> append(label)
            else -> withLink(LinkAnnotation.Url(safeUrl, TextLinkStyles(SpanStyle(color = linkColor)))) { append(label) }
        }
        cursor = match.range.last + 1
    }
    append(text, cursor, text.length)
}
