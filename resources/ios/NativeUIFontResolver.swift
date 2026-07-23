import SwiftUI
import UIKit
import CoreGraphics
import CoreText

/// Resolves a custom-font token (a font file's basename, e.g. "Inter-Bold")
/// to a usable SwiftUI `Font`. Fonts are bundled into the app's Resources by
/// this plugin's `copy_assets` hook (`CopyFontsCommand`); here we look one up,
/// register it with CoreText on first use, and read its PostScript name — the
/// name `Font.custom(_:)` actually needs, which frequently differs from the
/// filename.
///
/// Results (including "no such font") are cached, so repeated renders don't
/// re-hit the filesystem. A token that resolves to nil lets callers fall back
/// to the system font.
enum NativeUIFontResolver {

    // token → PostScript name. A cached `.some(nil)` records "looked up,
    // not found" so misses aren't retried every frame.
    private static var cache: [String: String?] = [:]
    // PostScript name → whether CoreText can apply a REAL italic trait.
    private static var italicTraitCache: [String: Bool] = [:]
    private static let lock = NSLock()

    /// Slant for synthesized obliques: tan(14°), matching Android's fake
    /// italic (`textSkewX = -0.25`) so a single-style font leans the same
    /// amount on both platforms.
    private static let obliqueSkew: CGFloat = 0.25

    /// Semantic aliases from the theme payload's `fonts` map (e.g.
    /// "accent" → "DynaPuff-Regular"). Consulted before file lookup, so any
    /// font token — element `font=`, chrome props, the app default — may be
    /// an alias. Set by `NativeUITheme.apply()`.
    static var aliases: [String: String] = [:]

    private static let extensions = ["ttf", "otf", "ttc"]

    /// A SwiftUI `Font` for a bundled token at `size`, or nil to fall back.
    /// `size` is used as-is (callers pass an already-Dynamic-Type-scaled value).
    ///
    /// With `italic`, a font whose family has a real italic face is returned
    /// upright — the caller's `Text.italic()` / `Font.italic()` selects the
    /// true face via the trait. A single-style font (no italic face) gets a
    /// synthesized oblique here instead, because SwiftUI's trait path silently
    /// renders such fonts upright while Android fakes the slant — the exact
    /// cross-platform mismatch this resolves.
    static func font(_ token: String, size: CGFloat, italic: Bool = false) -> Font? {
        guard let name = postScriptName(for: token) else { return nil }

        if italic, !supportsItalicTrait(name) {
            let matrix = CGAffineTransform(a: 1, b: 0, c: obliqueSkew, d: 1, tx: 0, ty: 0)
            let descriptor = UIFontDescriptor(name: name, matrix: matrix)
            return Font(UIFont(descriptor: descriptor, size: size))
        }

        return Font.custom(name, size: size)
    }

    /// Whether CoreText can produce a genuinely italic face for this
    /// PostScript name. `CTFontCreateCopyWithSymbolicTraits` returns nil when
    /// the family has nothing to satisfy the trait — the case where SwiftUI's
    /// `.italic()` becomes a silent no-op.
    private static func supportsItalicTrait(_ postScriptName: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if let cached = italicTraitCache[postScriptName] {
            return cached
        }

        let base = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        let supported = CTFontCreateCopyWithSymbolicTraits(base, 0, nil, .italicTrait, .italicTrait) != nil
        italicTraitCache[postScriptName] = supported

        return supported
    }

    /// Extra `.lineSpacing` needed to hit a Tailwind `leading` target for the
    /// given font. `px` (line_height_px) is absolute; `mult` (line_height) is a
    /// multiplier of `fontSize`. SwiftUI's `Text` only exposes `.lineSpacing`
    /// (space beyond the font's natural line box), so we return
    /// `target − naturalLineHeight`, measured against the ACTUAL font (custom
    /// or system) so tall custom fonts aren't over-spaced. Increasing leading
    /// is exact; tightening below the natural line height is limited by SwiftUI.
    /// Returns 0 (SwiftUI default) when no leading is requested.
    static func lineSpacing(px: Float, mult: Float, fontSize: CGFloat, fontName: String) -> CGFloat {
        let target: CGFloat = px > 0 ? CGFloat(px) : (mult > 0 ? CGFloat(mult) * fontSize : 0)
        guard target > 0 else { return 0 }

        let natural: CGFloat = {
            if !fontName.isEmpty,
               let ps = postScriptName(for: fontName),
               let uiFont = UIFont(name: ps, size: fontSize) {
                return uiFont.lineHeight
            }
            return UIFont.systemFont(ofSize: fontSize).lineHeight
        }()

        return target - natural
    }

    /// PostScript name for a bundled token, registering it on first use.
    /// The token may be a semantic alias (`fonts` map in the theme config);
    /// caching keys on the RESOLVED file token so a runtime re-alias never
    /// serves a stale mapping.
    static func postScriptName(for token: String) -> String? {
        let token = aliases[token] ?? token

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[token] {
            return cached
        }

        let resolved = resolve(token)
        cache[token] = resolved

        return resolved
    }

    private static func resolve(_ token: String) -> String? {
        guard let url = bundleURL(for: token) else { return nil }

        // Register with CoreText so the font is addressable by name. Already
        // registered (e.g. also listed in Info.plist UIAppFonts) is fine.
        var cfError: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError) {
            if let error = cfError?.takeUnretainedValue(),
               CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue {
                return nil
            }
        }

        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider),
              let postScriptName = cgFont.postScriptName as String? else {
            return nil
        }

        return postScriptName
    }

    /// Look the token up in the bundle — copied flat into Resources, with a
    /// `fonts/` subdirectory fallback in case the bundle preserves structure.
    private static func bundleURL(for token: String) -> URL? {
        for ext in extensions {
            if let url = Bundle.main.url(forResource: token, withExtension: ext) {
                return url
            }
            if let url = Bundle.main.url(forResource: token, withExtension: ext, subdirectory: "fonts") {
                return url
            }
        }

        return nil
    }
}
