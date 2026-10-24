package com.nativephp.plugins.native_ui.ui

import android.content.Context
import android.content.res.AssetManager
import android.os.Build
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.nativephp.plugins.native_ui.NativeUITheme
import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream

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
        val path = assetPath(assets, token) ?: return buildWeighted(assets, token)

        // A family's Regular file follows `font-*` weights like a bare family
        // name does: its bundled siblings join it ("Inter-Regular" +
        // `font-bold` draws Inter-Bold, not a faked bold). Any other face
        // ("Inter-Bold") names its weight and stays a single file.
        if (token.endsWith("-Regular")) {
            val siblings = weightedFonts(assets, token.removeSuffix("-Regular"))
            if (siblings.size > 1) {
                return fontFamilyOf(siblings.map { (siblingPath, weight) -> Font(path = siblingPath, assetManager = assets, weight = weight) })
            }
        }

        return variableFamily(assets, path)
            ?: fontFamilyOf(listOf(Font(path = path, assetManager = assets)))
    }

    /**
     * A family name with no file of its own ("Roboto") picks up every weight
     * file bundled for it ("Roboto-Regular", "Roboto-Bold", …) as ONE family,
     * so `font-bold` / `font-semibold` select the real cut instead of Compose
     * faking bold from a single regular file.
     */
    private fun buildWeighted(assets: AssetManager, family: String): FontFamily? {
        val fonts = weightedFonts(assets, family)
        if (fonts.isEmpty()) {
            return null
        }

        if (fonts.size == 1) {
            variableFamily(assets, fonts[0].first)?.let { return it }
        }

        return fontFamilyOf(fonts.map { (path, weight) -> Font(path = path, assetManager = assets, weight = weight) })
    }

    /** Bundled `<family>-<Weight>` files, lightest first. */
    private fun weightedFonts(assets: AssetManager, family: String): List<Pair<String, FontWeight>> =
        weightSuffixes.mapNotNull { (suffix, weight) ->
            assetPath(assets, "$family-$suffix")?.let { it to weight }
        }

    /**
     * A variable font (one file with a `wght` axis) as one face per weight,
     * each drawn at that point on the axis — so `font-*` classes move along
     * the axis instead of Compose faking bold from the default instance.
     * Regular keeps the font's own default instance, like iOS.
     */
    private fun variableFamily(assets: AssetManager, path: String): FontFamily? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return null
        }

        val axis = try {
            assets.open(path).use { readWeightAxis(it) }
        } catch (e: Exception) {
            null
        } ?: return null

        return fontFamilyOf((1..9).map { step ->
            val weight = FontWeight(step * 100)
            if (weight == FontWeight.Normal) {
                Font(path = path, assetManager = assets, weight = weight)
            } else {
                val value = (step * 100f).coerceIn(axis.start, axis.endInclusive)
                Font(
                    path = path,
                    assetManager = assets,
                    weight = weight,
                    variationSettings = FontVariation.Settings(FontVariation.weight(value.toInt())),
                )
            }
        })
    }

    private fun fontFamilyOf(fonts: List<Font>): FontFamily? = try {
        FontFamily(fonts)
    } catch (e: Exception) {
        null
    }

    private fun assetPath(assets: AssetManager, token: String): String? =
        extensions.map { "fonts/$token.$it" }.firstOrNull { assetExists(assets, it) }

    private val weightSuffixes = listOf(
        "Thin" to FontWeight.Thin,
        "ExtraLight" to FontWeight.ExtraLight,
        "Light" to FontWeight.Light,
        "Regular" to FontWeight.Normal,
        "Medium" to FontWeight.Medium,
        "SemiBold" to FontWeight.SemiBold,
        "Bold" to FontWeight.Bold,
        "ExtraBold" to FontWeight.ExtraBold,
        "Black" to FontWeight.Black,
    )

    private fun assetExists(assets: AssetManager, path: String): Boolean {
        return try {
            assets.open(path).close()
            true
        } catch (e: Exception) {
            false
        }
    }
}

/**
 * The `wght` axis range of a variable font, or null for a static font (no
 * `fvar` table), a collection (`.ttc`), or a font without a weight axis.
 * Reads only the sfnt table directory and the `fvar` axis records.
 */
internal fun readWeightAxis(input: InputStream): ClosedFloatingPointRange<Float>? {
    val data = DataInputStream(input.buffered())
    try {
        if (data.readInt() == TAG_TTCF) {
            return null
        }

        val numTables = data.readUnsignedShort()
        data.skipFully(6)

        var fvarOffset = -1L
        repeat(numTables) {
            val tag = data.readInt()
            data.skipFully(4)
            val offset = data.readInt().toLong() and 0xFFFFFFFFL
            data.skipFully(4)
            if (tag == TAG_FVAR) {
                fvarOffset = offset
            }
        }

        val directoryEnd = 12L + 16L * numTables
        if (fvarOffset < directoryEnd) {
            return null
        }
        data.skipFully(fvarOffset - directoryEnd)

        data.skipFully(4) // major + minor version
        val axesArrayOffset = data.readUnsignedShort()
        data.skipFully(2) // reserved
        val axisCount = data.readUnsignedShort()
        val axisSize = data.readUnsignedShort()
        if (axesArrayOffset < 12 || axisSize < 16) {
            return null
        }
        data.skipFully(axesArrayOffset - 12L)

        repeat(axisCount) {
            val tag = data.readInt()
            val min = data.readInt() / 65536f
            data.skipFully(4) // default
            val max = data.readInt() / 65536f
            data.skipFully(axisSize - 16L)
            if (tag == TAG_WGHT && min <= max) {
                return min..max
            }
        }
    } catch (e: EOFException) {
        return null
    }

    return null
}

private const val TAG_TTCF = 0x74746366 // 'ttcf'
private const val TAG_FVAR = 0x66766172 // 'fvar'
private const val TAG_WGHT = 0x77676874 // 'wght'

private fun DataInputStream.skipFully(count: Long) {
    var remaining = count
    while (remaining > 0) {
        val skipped = skip(remaining)
        if (skipped <= 0) {
            if (read() < 0) throw EOFException()
            remaining--
        } else {
            remaining -= skipped
        }
    }
}

private fun DataInputStream.skipFully(count: Int) = skipFully(count.toLong())
