package com.nativephp.plugins.native_ui.ui

import android.content.Context
import com.nativephp.mobile.bridge.PHPBridge

/**
 * Shared `src` resolution for every renderer that loads an image — the
 * `<native:image>` element and the list-item avatar / thumbnail slots — so a
 * path means the same thing wherever it's written.
 */

/**
 * `src` reads like a web URL to whoever authored it, but Coil needs something
 * it can actually fetch off this device.
 *
 * Left untouched: anything carrying a scheme (`https:`, `file:`, `content:`,
 * `data:`, `android.resource:`) and anything absolute — camera captures and
 * gallery picks arrive as absolute filesystem paths.
 *
 * A RELATIVE path is what a web developer writes for an asset shipped with the
 * app, so it resolves against the Laravel app's `public/` directory on device:
 * `img/logo.png` → `<laravel>/public/img/logo.png`. Note the asymmetry with the
 * web, where a leading `/` is document-root-relative — here it stays an
 * absolute device path, since that's the only way to reach a captured photo.
 */
internal fun nuiResolveImageSrc(src: String, context: Context): String {
    if (src.isEmpty() || src.startsWith("/") || SCHEME.containsMatchIn(src)) {
        return src
    }

    return "${PHPBridge(context).getLaravelPath()}/public/${src.removePrefix("./")}"
}

/** Leading URI scheme per RFC 3986 — `https:`, `file:`, `android.resource:`. */
private val SCHEME = Regex("^[a-zA-Z][a-zA-Z0-9+.-]*:")
