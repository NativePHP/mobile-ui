package com.nativephp.plugins.native_ui.ui

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import android.content.Context
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.argbToComposeColor

object TextRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        // A text node with child text runs composes them into ONE wrapping
        // AnnotatedString (inline bold/colored runs, inline-code chips via a
        // SpanStyle background). A leaf text keeps the original path below.
        if (node.children.any { it.type == "text" }) {
            RenderComposed(node, modifier)
        } else {
            RenderLeaf(node, modifier)
        }
    }

    @Composable
    private fun RenderLeaf(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val text = applyTransform(p.getString("text"), p.getInt("text_transform"))
        val fontSize = p.getFloat("font_size", 16f)
        val fontWeight = resolveFontWeight(p.getInt("font_weight"))
        val fontStyle = resolveFontStyle(p.getInt("font_style"))
        val fontName = p.getString("font_name")
        val customFamily = if (fontName.isNotEmpty()) NativeUIFontResolver.resolve(LocalContext.current, fontName) else null
        val fontFamily = customFamily
            ?: resolveFontFamily(p.getInt("font_family"))
            ?: nuiThemeDefaultFontFamily(LocalContext.current)
        val textDecoration = resolveDecoration(p.getInt("underline"), p.getInt("line_through"))
        val letterSpacingEm = p.getFloat("letter_spacing", 0f)
        val lineHeight = nuiLineHeightUnit(p.getFloat("line_height_px", 0f), p.getFloat("line_height", 0f), fontSize)
        val maxLines = p.getInt("max_lines")
        val textAlign = resolveTextAlign(p.getInt("text_align"))

        val isDark = NativeAppearanceState.isDark()
        val darkColor = if (isDark) p.getColor("dark_color", 0) else 0
        val textArgb = if (darkColor != 0) darkColor else p.getColor("color", 0xFF000000.toInt())
        Text(
            text = text,
            modifier = modifier,
            color = argbToComposeColor(textArgb),
            fontSize = fontSize.sp,
            fontWeight = fontWeight,
            fontStyle = fontStyle,
            textDecoration = textDecoration,
            letterSpacing = if (letterSpacingEm != 0f) letterSpacingEm.em else TextUnit.Unspecified,
            textAlign = textAlign,
            maxLines = if (maxLines > 0) maxLines else Int.MAX_VALUE,
            overflow = TextOverflow.Ellipsis,
            // Android adds extra "font padding" above/below glyphs by default,
            // which shifts text within its box — so it doesn't vertically center
            // against icons (e.g. the X engagement row) and reads looser than
            // iOS. Disable it and trim line-height padding so text hugs its
            // glyphs like iOS.
            // fontFamily lives here (not as a loose param) so it's guaranteed to
            // survive into the final TextStyle.
            style = TextStyle(
                fontFamily = fontFamily,
                lineHeight = lineHeight,
                platformStyle = PlatformTextStyle(includeFontPadding = false),
                lineHeightStyle = LineHeightStyle(
                    alignment = LineHeightStyle.Alignment.Center,
                    trim = LineHeightStyle.Trim.Both
                )
            )
        )
    }

    @Composable
    private fun RenderComposed(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val isDark = NativeAppearanceState.isDark()
        val maxLines = p.getInt("max_lines")
        // Leading applies to the whole string; base the multiplier on the
        // node's own font size (the root run's size).
        val lineHeight = nuiLineHeightUnit(p.getFloat("line_height_px", 0f), p.getFloat("line_height", 0f), p.getFloat("font_size", 16f))

        val ctx = LocalContext.current
        val annotated = buildAnnotatedString {
            appendTextRuns(node, RunCtx.Root, isDark, ctx)
        }

        Text(
            text = annotated,
            modifier = modifier,
            textAlign = resolveTextAlign(p.getInt("text_align")),
            maxLines = if (maxLines > 0) maxLines else Int.MAX_VALUE,
            overflow = TextOverflow.Ellipsis,
            // Same font-padding / line-height trim as the leaf path so composed
            // and plain text share vertical metrics.
            style = TextStyle(
                lineHeight = lineHeight,
                platformStyle = PlatformTextStyle(includeFontPadding = false),
                lineHeightStyle = LineHeightStyle(
                    alignment = LineHeightStyle.Alignment.Center,
                    trim = LineHeightStyle.Trim.Both
                )
            )
        )
    }
}

/**
 * Typographic context inherited down the run tree. A child run reads its own
 * props, falling back to the inherited value per field (CSS-like inheritance) —
 * implemented by passing these as the `getX` defaults, so an unset prop
 * transparently inherits. Decoration/background are NOT carried here; they're
 * per-run (a chip's background must not bleed onto siblings).
 */
private data class RunCtx(
    val fontSize: Float,
    val fontWeightInt: Int,
    val fontFamilyInt: Int,
    val fontName: String,
    val colorArgb: Int,
    val darkColorArgb: Int,
    val italic: Boolean,
    val letterSpacingEm: Float,
    val textTransform: Int,
) {
    companion object {
        // Root defaults — mirror the leaf path (16sp, normal, black, no dark
        // override, no custom font, no decoration/letter-spacing/transform).
        val Root = RunCtx(16f, 0, 0, "", 0xFF000000.toInt(), 0, false, 0f, 0)
    }
}

/**
 * Walk a node, emitting one styled span for its own text (leaf, or the leading
 * text before nested runs) then recursing into text children.
 */
private fun AnnotatedString.Builder.appendTextRuns(node: NativeUINode, inherited: RunCtx, isDark: Boolean, context: Context) {
    val p = node.props

    // Resolve this level's effective context: own props over inherited.
    val ctx = RunCtx(
        fontSize = p.getFloat("font_size", inherited.fontSize),
        fontWeightInt = p.getInt("font_weight", inherited.fontWeightInt),
        fontFamilyInt = p.getInt("font_family", inherited.fontFamilyInt),
        fontName = p.getString("font_name", inherited.fontName),
        colorArgb = p.getColor("color", inherited.colorArgb),
        darkColorArgb = p.getColor("dark_color", inherited.darkColorArgb),
        italic = p.getInt("font_style", if (inherited.italic) 1 else 0) == 1,
        letterSpacingEm = p.getFloat("letter_spacing", inherited.letterSpacingEm),
        textTransform = p.getInt("text_transform", inherited.textTransform),
    )

    val ownText = applyTransform(p.getString("text"), ctx.textTransform)
    if (ownText.isNotEmpty()) {
        val fg = if (isDark && ctx.darkColorArgb != 0) ctx.darkColorArgb else ctx.colorArgb
        // Run background = the inline-code chip. bg_color lives on style;
        // dark_bg_color on props (matches NodeModifiers' split). Per-run.
        val bgArgb = node.style?.bgColor ?: 0
        val darkBg = if (isDark) p.getColor("dark_bg_color", 0) else 0
        val effectiveBg = if (darkBg != 0) darkBg else bgArgb

        val span = SpanStyle(
            color = argbToComposeColor(fg),
            fontSize = ctx.fontSize.sp,
            fontWeight = resolveFontWeight(ctx.fontWeightInt),
            fontStyle = if (ctx.italic) FontStyle.Italic else FontStyle.Normal,
            fontFamily = (if (ctx.fontName.isNotEmpty()) NativeUIFontResolver.resolve(context, ctx.fontName) else null)
                ?: resolveFontFamily(ctx.fontFamilyInt)
                ?: nuiThemeDefaultFontFamily(context),
            letterSpacing = if (ctx.letterSpacingEm != 0f) ctx.letterSpacingEm.em else TextUnit.Unspecified,
            textDecoration = resolveDecoration(p.getInt("underline"), p.getInt("line_through")),
            background = if (effectiveBg != 0) argbToComposeColor(effectiveBg) else Color.Unspecified,
        )
        withStyle(span) { append(ownText) }
    }

    node.children.filter { it.type == "text" }.forEach { child ->
        appendTextRuns(child, ctx, isDark, context)
    }
}

private fun resolveFontWeight(weight: Int): FontWeight {
    return when (weight) {
        1 -> FontWeight.Thin
        2 -> FontWeight.Light
        3 -> FontWeight.Normal
        4 -> FontWeight.Medium
        5 -> FontWeight.SemiBold
        6 -> FontWeight.Bold
        7 -> FontWeight.ExtraBold
        else -> FontWeight.Normal
    }
}

private fun resolveFontStyle(style: Int): FontStyle {
    return if (style == 1) FontStyle.Italic else FontStyle.Normal
}

// 0/absent = default (sans); only override for serif/mono so a custom default
// font isn't clobbered.
private fun resolveFontFamily(family: Int): FontFamily? = when (family) {
    1 -> FontFamily.Serif
    2 -> FontFamily.Monospace
    else -> null
}

private fun resolveDecoration(underline: Int, lineThrough: Int): TextDecoration? {
    val decos = buildList {
        if (underline == 1) add(TextDecoration.Underline)
        if (lineThrough == 1) add(TextDecoration.LineThrough)
    }
    return if (decos.isEmpty()) null else TextDecoration.combine(decos)
}

// 1 = uppercase, 2 = lowercase, 3 = capitalize (first letter of each word).
private fun applyTransform(s: String, transform: Int): String = when (transform) {
    1 -> s.uppercase()
    2 -> s.lowercase()
    3 -> s.split(" ").joinToString(" ") { w -> w.replaceFirstChar { it.uppercaseChar() } }
    else -> s
}

private fun resolveTextAlign(align: Int): TextAlign {
    return when (align) {
        0 -> TextAlign.Start
        1 -> TextAlign.Center
        2 -> TextAlign.End
        else -> TextAlign.Start
    }
}