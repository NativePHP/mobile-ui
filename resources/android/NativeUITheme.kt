package com.nativephp.plugins.native_ui

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import org.json.JSONObject

/**
 * One coherent set of theme tokens (light OR dark). Renderers read the
 * active tokens via [LocalNativeUITheme].
 *
 * The PHP side (`Native\Mobile\UI\Theme::merge([...])`) is the source of
 * truth; tokens arrive over the bridge via `NativeUI.Theme.Set`.
 */
data class NativeUITokens(
    // Colors
    val primary:          Color,
    val onPrimary:        Color,
    val secondary:        Color,
    val onSecondary:      Color,
    val surface:          Color,
    val onSurface:        Color,
    val background:       Color,
    val onBackground:     Color,
    val surfaceVariant:   Color,
    val onSurfaceVariant: Color,
    val outline:          Color,
    val destructive:      Color,
    val onDestructive:    Color,
    val accent:           Color,
    val onAccent:         Color,

    // Radii
    val radiusSm:   Dp,
    val radiusMd:   Dp,
    val radiusLg:   Dp,
    val radiusFull: Dp,

    // Typography
    val fontSm:     TextUnit,
    val fontMd:     TextUnit,
    val fontLg:     TextUnit,
    val fontXl:     TextUnit,
    val fontFamily: String,
) {
    companion object {
        /**
         * Fallback matches `config/native-ui.php` defaults. Used before PHP
         * has pushed an initial theme — keeps components renderable during
         * bootstrap.
         */
        val fallback = NativeUITokens(
            primary          = parseHex("#0F766E"),
            onPrimary        = parseHex("#FFFFFF"),
            secondary        = parseHex("#64748B"),
            onSecondary      = parseHex("#FFFFFF"),
            surface          = parseHex("#FFFFFF"),
            onSurface        = parseHex("#0F172A"),
            background       = parseHex("#F8FAFC"),
            onBackground     = parseHex("#0F172A"),
            surfaceVariant   = parseHex("#F1F5F9"),
            onSurfaceVariant = parseHex("#475569"),
            outline          = parseHex("#CBD5E1"),
            destructive      = parseHex("#DC2626"),
            onDestructive    = parseHex("#FFFFFF"),
            accent           = parseHex("#FB923C"),
            onAccent         = parseHex("#FFFFFF"),
            radiusSm = 4.dp, radiusMd = 8.dp, radiusLg = 16.dp, radiusFull = 9999.dp,
            fontSm = 14.sp, fontMd = 16.sp, fontLg = 20.sp, fontXl = 24.sp,
            fontFamily = "System",
        )
    }
}

/**
 * Process-wide theme store. Observable via `mutableStateOf` so Compose
 * re-composes when the PHP side pushes an update.
 */
object NativeUITheme {
    var light by mutableStateOf(NativeUITokens.fallback)
        private set
    var dark by mutableStateOf(NativeUITokens.fallback)
        private set

    /**
     * Apply an effective token set from PHP. The [parameters] map is the
     * decoded JSON from `Theme::all()` — light + dark blocks plus radii and
     * typography scalars.
     */
    fun apply(parameters: Map<String, Any?>) {
        // Android's bridge layer leaves nested JSON objects as org.json.JSONObject
        // rather than converting them to Map<String, Any> (unlike iOS's Foundation
        // JSONSerialization). Use asMap() to accept either representation.
        val lightMap = asMap(parameters["light"])
        val darkMap  = asMap(parameters["dark"])

        val radiusSm   = numDp(parameters["radius-sm"],   NativeUITokens.fallback.radiusSm)
        val radiusMd   = numDp(parameters["radius-md"],   NativeUITokens.fallback.radiusMd)
        val radiusLg   = numDp(parameters["radius-lg"],   NativeUITokens.fallback.radiusLg)
        val radiusFull = numDp(parameters["radius-full"], NativeUITokens.fallback.radiusFull)

        val fontSm     = numSp(parameters["font-sm"],     NativeUITokens.fallback.fontSm)
        val fontMd     = numSp(parameters["font-md"],     NativeUITokens.fallback.fontMd)
        val fontLg     = numSp(parameters["font-lg"],     NativeUITokens.fallback.fontLg)
        val fontXl     = numSp(parameters["font-xl"],     NativeUITokens.fallback.fontXl)
        val fontFamily = (parameters["font-family"] as? String) ?: NativeUITokens.fallback.fontFamily

        val lightTokens = tokensFrom(
            lightMap, NativeUITokens.fallback,
            radiusSm, radiusMd, radiusLg, radiusFull,
            fontSm, fontMd, fontLg, fontXl, fontFamily
        )
        val darkTokens = tokensFrom(
            darkMap, lightTokens,
            radiusSm, radiusMd, radiusLg, radiusFull,
            fontSm, fontMd, fontLg, fontXl, fontFamily
        )

        // `mutableStateOf` notifies observers on every assignment — even when
        // the new value equals the old one. PHP pushes the theme on every
        // service-provider boot (each request) so unguarded assignment would
        // force every observer to recompose on every Livewire event. Skip
        // the write when tokens haven't actually changed.
        if (lightTokens != light) light = lightTokens
        if (darkTokens  != dark)  dark  = darkTokens
    }

    private fun tokensFrom(
        map: Map<String, Any?>,
        fb: NativeUITokens,
        radiusSm: Dp, radiusMd: Dp, radiusLg: Dp, radiusFull: Dp,
        fontSm: TextUnit, fontMd: TextUnit, fontLg: TextUnit, fontXl: TextUnit,
        fontFamily: String,
    ): NativeUITokens = NativeUITokens(
        primary          = color(map["primary"],            fb.primary),
        onPrimary        = color(map["on-primary"],         fb.onPrimary),
        secondary        = color(map["secondary"],          fb.secondary),
        onSecondary      = color(map["on-secondary"],       fb.onSecondary),
        surface          = color(map["surface"],            fb.surface),
        onSurface        = color(map["on-surface"],         fb.onSurface),
        background       = color(map["background"],         fb.background),
        onBackground     = color(map["on-background"],      fb.onBackground),
        surfaceVariant   = color(map["surface-variant"],    fb.surfaceVariant),
        onSurfaceVariant = color(map["on-surface-variant"], fb.onSurfaceVariant),
        outline          = color(map["outline"],            fb.outline),
        destructive      = color(map["destructive"],        fb.destructive),
        onDestructive    = color(map["on-destructive"],     fb.onDestructive),
        accent           = color(map["accent"],             fb.accent),
        onAccent         = color(map["on-accent"],          fb.onAccent),
        radiusSm = radiusSm, radiusMd = radiusMd, radiusLg = radiusLg, radiusFull = radiusFull,
        fontSm = fontSm, fontMd = fontMd, fontLg = fontLg, fontXl = fontXl,
        fontFamily = fontFamily,
    )
}

/**
 * Composition local exposing the *active* token set. Renderers read this
 * instead of touching [NativeUITheme] directly so Compose can track
 * dependencies and recompose when tokens change.
 */
val LocalNativeUITheme = compositionLocalOf { NativeUITokens.fallback }

/**
 * Derive a Material 3 [ColorScheme] from these plugin tokens.
 *
 * Native chrome on Android (TopAppBar, Scaffold, BottomNav, SideDrawer,
 * any vanilla M3 control) reads from `MaterialTheme.colorScheme.*`, while
 * per-component plugin renderers read from [LocalNativeUITheme]. Without
 * a bridge between the two, chrome stays on M3's baseline (lavender /
 * deep-purple) even after PHP pushes a custom theme via `Theme::merge`.
 *
 * Mapping notes:
 *   - `accent` → M3's `tertiary` slot (closest semantic match).
 *   - `destructive` → M3's `error` slot.
 *   - Container/inverse/scrim slots have no plugin equivalent; we leave
 *     them at M3's baseline (via `[lightColorScheme] / [darkColorScheme]`)
 *     so newly-introduced M3 widgets that depend on them keep working.
 *   - `surfaceTint = primary` so elevation tinting follows the brand.
 *
 * Call from a `@Composable` context that already knows the active mode
 * (system or PHP-overridden). The token instance itself doesn't carry a
 * light/dark flag — it's just one coherent palette.
 */
fun NativeUITokens.toMaterialColorScheme(isDark: Boolean = false): ColorScheme {
    val base = if (isDark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary          = primary,
        onPrimary        = onPrimary,
        secondary        = secondary,
        onSecondary      = onSecondary,
        tertiary         = accent,
        onTertiary       = onAccent,
        background       = background,
        onBackground     = onBackground,
        surface          = surface,
        onSurface        = onSurface,
        surfaceVariant   = surfaceVariant,
        onSurfaceVariant = onSurfaceVariant,
        outline          = outline,
        error            = destructive,
        onError          = onDestructive,
        surfaceTint      = primary,
        // M3's "surface container" tonal family. These back DropdownMenu,
        // NavigationBar/TabRow, sheets, and the watcher's loading indicator.
        // Left unmapped they keep lightColorScheme()'s baseline (a pinkish
        // neutral), which read as off-theme. Fold them onto the configured
        // surface tokens: the lower tiers track `surface`, the elevated tiers
        // track `surfaceVariant`, so anchored chrome stays on-palette.
        surfaceContainerLowest  = surface,
        surfaceContainerLow     = surface,
        surfaceContainer        = surface,
        surfaceContainerHigh    = surfaceVariant,
        surfaceContainerHighest = surfaceVariant,
        surfaceBright           = surface,
        surfaceDim              = surfaceVariant,
        inverseSurface          = onSurface,
        inverseOnSurface        = surface,
        inversePrimary          = primary,
    )
}

// ─── Parsing helpers ─────────────────────────────────────────────────────────

/// Accept either a real Map (iOS-style bridge payload) or a [JSONObject]
/// (Android bridge default for nested objects) and return a uniform
/// `Map<String, Any?>` for downstream consumption.
private fun asMap(any: Any?): Map<String, Any?> = when (any) {
    is Map<*, *> -> {
        @Suppress("UNCHECKED_CAST")
        (any as? Map<String, Any?>) ?: emptyMap()
    }
    is JSONObject -> {
        val out = mutableMapOf<String, Any?>()
        val keys = any.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            out[key] = if (any.isNull(key)) null else any.opt(key)
        }
        out
    }
    else -> emptyMap()
}

private fun color(any: Any?, fallback: Color): Color =
    (any as? String)?.takeIf { it.startsWith("#") }?.let(::parseHex) ?: fallback

private fun numDp(any: Any?, fallback: Dp): Dp = when (any) {
    is Int    -> any.dp
    is Long   -> any.toInt().dp
    is Double -> any.toFloat().dp
    is Float  -> any.dp
    is Number -> any.toFloat().dp
    else      -> fallback
}

private fun numSp(any: Any?, fallback: TextUnit): TextUnit = when (any) {
    is Int    -> any.sp
    is Long   -> any.toInt().sp
    is Double -> any.toFloat().sp
    is Float  -> any.sp
    is Number -> any.toFloat().sp
    else      -> fallback
}

/** Parse `#RRGGBB` or `#AARRGGBB` into a Compose [Color]. */
private fun parseHex(hex: String): Color {
    val clean = hex.removePrefix("#")
    val long = try { clean.toLong(16) } catch (_: NumberFormatException) { return Color.Black }
    val argb: Long = when (clean.length) {
        6 -> 0xFF000000L or long
        8 -> long
        else -> return Color.Black
    }
    return Color(
        alpha = ((argb shr 24) and 0xFF) / 255f,
        red   = ((argb shr 16) and 0xFF) / 255f,
        green = ((argb shr 8)  and 0xFF) / 255f,
        blue  = ( argb         and 0xFF) / 255f,
    )
}