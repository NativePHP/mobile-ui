package com.nativephp.plugins.native_ui.ui

import android.content.Context
import android.content.res.AssetManager
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.nativephp.plugins.native_ui.NativeUITheme

// Tailwind `leading`: line_height_px is an absolute sp target; line_height is a
// unitless multiplier of the font size. Unspecified leaves Compose's default.
// Shared by the text / button / text-input renderers.
internal fun nuiLineHeightUnit(px: Float, mult: Float, fontSize: Float): TextUnit = when {
    px > 0f -> px.sp
    mult > 0f -> (mult * fontSize).sp
    else -> TextUnit.Unspecified
}

/**
 * App-wide default font from the theme's `font-family` token, or null when
 * unset / "System". Read inside composition: the theme store is backed by
 * `mutableStateOf`, so a PHP theme push recomposes consumers. The token is
 * identical for light and dark, so reading the light set suffices.
 *
 * Precedence at call sites: explicit `font_name` prop, then an explicit
 * `font-serif`/`font-mono` class, then this, then the system font.
 */
internal fun nuiThemeDefaultFontFamily(context: Context): FontFamily? {
    val family = NativeUITheme.light.fontFamily
    if (family.isEmpty() || family == "System") return null

    return NativeUIFontResolver.resolve(context, family)
}

/**
 * Composable sugar for [nuiThemeDefaultFontFamily] — grabs LocalContext so a
 * `Text(...)` site can just say `fontFamily = nuiDefaultFontFamily()`.
 */
@Composable
internal fun nuiDefaultFontFamily(): FontFamily? = nuiThemeDefaultFontFamily(LocalContext.current)

/**
 * Per-node font: an explicit `font_name` prop wins, then the app-wide theme
 * default, then null (system font).
 */
@Composable
internal fun nuiNodeFontFamily(name: String): FontFamily? =
    (if (name.isNotEmpty()) NativeUIFontResolver.resolve(LocalContext.current, name) else null)
        ?: nuiDefaultFontFamily()

/**
 * Material3 [Typography] carrying the app-wide default font on every text
 * style (sizes / weights / spacing untouched), or null when no default font
 * is configured. Fed to core chrome through NativeUIThemeProvider.typographyFor
 * so top bars, tab labels, and dropdowns render in the app's font.
 */
fun nuiThemeDefaultTypography(context: Context): Typography? {
    val family = nuiThemeDefaultFontFamily(context) ?: return null

    val base = Typography()
    return Typography(
        displayLarge = base.displayLarge.copy(fontFamily = family),
        displayMedium = base.displayMedium.copy(fontFamily = family),
        displaySmall = base.displaySmall.copy(fontFamily = family),
        headlineLarge = base.headlineLarge.copy(fontFamily = family),
        headlineMedium = base.headlineMedium.copy(fontFamily = family),
        headlineSmall = base.headlineSmall.copy(fontFamily = family),
        titleLarge = base.titleLarge.copy(fontFamily = family),
        titleMedium = base.titleMedium.copy(fontFamily = family),
        titleSmall = base.titleSmall.copy(fontFamily = family),
        bodyLarge = base.bodyLarge.copy(fontFamily = family),
        bodyMedium = base.bodyMedium.copy(fontFamily = family),
        bodySmall = base.bodySmall.copy(fontFamily = family),
        labelLarge = base.labelLarge.copy(fontFamily = family),
        labelMedium = base.labelMedium.copy(fontFamily = family),
        labelSmall = base.labelSmall.copy(fontFamily = family),
    )
}

/**
 * Resolves a custom-font token (a font file's basename, e.g. "Inter-Bold") to a
 * Compose [FontFamily] loaded from the app's `assets/fonts/`. Fonts land there
 * via this plugin's `copy_assets` hook (CopyFontsCommand).
 *
 * Results — including "no such font" — are cached, so repeated recompositions
 * don't re-hit the AssetManager. A token that resolves to null lets callers
 * fall back to the default family.
 */
object NativeUIFontResolver {

    // token -> FontFamily; a stored null means "looked up, not present".
    private val cache = HashMap<String, FontFamily?>()

    /**
     * Semantic aliases from the theme payload's `fonts` map (e.g.
     * "accent" -> "DynaPuff-Regular"). Consulted before file lookup, so any
     * font token — element `font=`, chrome props, the app default — may be
     * an alias. Set by [NativeUITheme.apply].
     */
    @Volatile
    var aliases: Map<String, String> = emptyMap()

    private val extensions = listOf("ttf", "otf", "ttc")

    @Synchronized
    fun resolve(context: Context, token: String): FontFamily? {
        // Alias hop first; cache keys on the RESOLVED file token so a
        // runtime re-alias never serves a stale mapping.
        val token = aliases[token] ?: token

        if (cache.containsKey(token)) {
            return cache[token]
        }

        val family = build(context.assets, token)
        cache[token] = family

        return family
    }

    private fun build(assets: AssetManager, token: String): FontFamily? {
        for (ext in extensions) {
            val path = "fonts/$token.$ext"
            if (!assetExists(assets, path)) {
                continue
            }

            return try {
                FontFamily(Font(path = path, assetManager = assets))
            } catch (e: Exception) {
                null
            }
        }

        return null
    }

    private fun assetExists(assets: AssetManager, path: String): Boolean {
        return try {
            assets.open(path).close()
            true
        } catch (e: Exception) {
            false
        }
    }
}
