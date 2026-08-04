package com.nativephp.plugins.native_ui

import android.content.Context
import androidx.compose.ui.platform.LocalContext
import com.nativephp.mobile.ui.NativeUIThemeProvider
import com.nativephp.mobile.ui.nativerender.NativeRootHostRegistry
import com.nativephp.plugins.native_ui.ui.NativeFloatingOverlayHost
import com.nativephp.plugins.native_ui.ui.NativeLayoutDrawerHost
import com.nativephp.plugins.native_ui.ui.NativeUIBackgroundLayerHost
import com.nativephp.plugins.native_ui.ui.NativeUIFontResolver
import com.nativephp.plugins.native_ui.ui.nuiThemeDefaultTypography

/**
 * Init function invoked by the generated `PluginBridgeFunctionRegistration` in
 * `onCreate` (before the first composition). Wires native-ui into core's seams:
 * registers the layout-drawer root host, and supplies the app's Material3
 * ColorScheme from native-ui's PHP-driven theme tokens. Declared in the plugin
 * manifest under `android.init_function`.
 *
 * The `context` parameter is supplied by the generated call site
 * (`registerNativeUIChrome(context)`); the font resolver captures its
 * application context for asset-backed font loading.
 */
fun registerNativeUIChrome(context: Context) {
    NativeRootHostRegistry.register("native-ui.drawer", consumes = "native_drawer") { root, content ->
        val drawerNode = root.children.firstOrNull { it.type == "native_drawer" }
        NativeLayoutDrawerHost(drawerNode = drawerNode, content = content)
    }

    NativeRootHostRegistry.register("native-ui.floating-overlay", consumes = "floating_overlay") { root, content ->
        val overlayNode = root.children.firstOrNull { it.type == "floating_overlay" }
        NativeFloatingOverlayHost(overlayNode = overlayNode, content = content)
    }

    NativeRootHostRegistry.register("native-ui.background-layer", consumes = "background_layer") { root, content ->
        val layerNode = root.children.firstOrNull { it.type == "background_layer" }
        NativeUIBackgroundLayerHost(
            layerNode = layerNode,
            hostedByChrome = root.type == "native_root_tabs",
            content = content,
        )
    }

    // Supply the app's color scheme from native-ui's theme tokens. The lambda
    // reads NativeUITheme.{light,dark} (Compose snapshot state) when invoked
    // during composition, so PHP-side Theme::merge updates stay reactive.
    NativeUIThemeProvider.colorSchemeFor = { isDark ->
        (if (isDark) NativeUITheme.dark else NativeUITheme.light).toMaterialColorScheme(isDark)
    }

    // Supply the app's typography when a default font is configured (the
    // theme's `font-family` token). Every Material text style keeps its size /
    // weight / spacing and swaps only the family, so core chrome — top bar
    // titles, tab labels, dropdowns — renders in the app's font. Returns null
    // (Material defaults) when the token is "System".
    NativeUIThemeProvider.typographyFor = {
        nuiThemeDefaultTypography(LocalContext.current)
    }

    // Resolve chrome font tokens (per-layout / per-bar `font_name` props on
    // the root sentinels) for core's chrome renderers. Captures the
    // application context — asset-backed fonts don't need an activity.
    val appContext = context.applicationContext
    NativeUIThemeProvider.fontFamilyResolver = { name ->
        NativeUIFontResolver.resolve(appContext, name)
    }
}
