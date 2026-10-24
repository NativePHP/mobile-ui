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
///
/// Weights: a static font file holds ONE weight, so a requested weight is
/// met by picking a sibling file of the same family, named the way
/// `native:font` downloads them (`Inter-Regular`, `Inter-Medium`,
/// `Inter-SemiBold`, `Inter-Bold`, …). Android's resolver reads the same
/// convention. The family's `-Regular` face and a bare family name ("Inter")
/// both follow the requested weight; any other face ("Inter-Bold") names its
/// weight itself and is drawn as-is. A variable font (one file with a `wght`
/// axis) is drawn at the requested weight through that axis instead.
enum NativeUIFontResolver {

    // token → PostScript name. A cached `.some(nil)` records "looked up,
    // not found" so misses aren't retried every frame.
    private static var cache: [String: String?] = [:]
    // PostScript name → whether CoreText can apply a REAL italic trait.
    private static var italicTraitCache: [String: Bool] = [:]
    // "token#weight" → the file token that draws it.
    private static var weightedCache: [String: String] = [:]
    // PostScript name → its `wght` axis range, nil for a static font.
    private static var weightAxisCache: [String: ClosedRange<CGFloat>?] = [:]
    private static let lock = NSLock()

    /// Weight names a family's files carry after the last "-", in the CSS
    /// numeric weights they stand for.
    private static let weightSuffixes: [(suffix: String, value: Int)] = [
        ("Thin", 100), ("ExtraLight", 200), ("Light", 300), ("Regular", 400),
        ("Medium", 500), ("SemiBold", 600), ("Bold", 700), ("ExtraBold", 800),
        ("Black", 900),
    ]

    /// OpenType `wght` axis tag, as CoreText's variation dictionaries key it.
    private static let weightAxisTag = 0x7767_6874

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
    /// `size` is used as-is (callers pass an already-Dynamic-Type-scaled value),
    /// so the font is built with `Font.custom(_:fixedSize:)`. The `size:` variant
    /// would scale relative to `.body` a SECOND time on top of the caller's
    /// `@ScaledMetric`, squaring the multiplier — invisible at the default text
    /// size (where it is 1.0) and roughly 1.8x at xxxLarge. The `UIFont` branch
    /// below is already non-scaling, and the system-font fallback in
    /// `NUIScaledFontModifier` uses fixed-size `.system(size:)` for the same
    /// reason.
    ///
    /// With `italic`, a font whose family has a real italic face is returned
    /// upright — the caller's `Text.italic()` / `Font.italic()` selects the
    /// true face via the trait. A single-style font (no italic face) gets a
    /// synthesized oblique here instead, because SwiftUI's trait path silently
    /// renders such fonts upright while Android fakes the slant — the exact
    /// cross-platform mismatch this resolves.
    ///
    /// Matrix-skewed glyphs lean PAST their advance widths, and SwiftUI's
    /// text renderer clips each line to those advances — so a line ENDING in
    /// an oblique run loses the top-right of its last glyph. Leaf text
    /// therefore skews at the view level instead (`obliqueTransform`); this
    /// font-level path remains for inline composed runs, where a per-view
    /// transform can't reach and mid-line runs hide the overhang naturally.
    ///
    /// `weight` picks the family's matching face (see the type comment), so
    /// callers must NOT chain `.weight()` onto the result: on a static face
    /// that makes SwiftUI drop the custom font for the system one.
    static func font(_ token: String, size: CGFloat, italic: Bool = false, weight: Font.Weight = .regular) -> Font? {
        guard let name = postScriptName(for: token, weight: weight) else { return nil }

        let oblique = italic && !supportsItalicTrait(name)
        let axisWeight = variableWeight(name, weight: weight)

        if oblique || axisWeight != nil {
            var attributes: [UIFontDescriptor.AttributeName: Any] = [.name: name]
            if oblique {
                attributes[.matrix] = CGAffineTransform(a: 1, b: 0, c: obliqueSkew, d: 1, tx: 0, ty: 0)
            }
            if let axisWeight {
                attributes[UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)] = [weightAxisTag: axisWeight]
            }

            return Font(UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size))
        }

        return Font.custom(name, fixedSize: size)
    }

    /// Whether an italic request for this token needs a synthesized oblique
    /// (custom font resolves, but its family has no real italic face).
    static func needsSyntheticOblique(_ token: String, weight: Font.Weight = .regular) -> Bool {
        guard let name = postScriptName(for: token, weight: weight) else { return false }

        return !supportsItalicTrait(name)
    }

    /// View-space skew for a synthetic oblique on LEAF text: the Text keeps
    /// its upright font (complete raster, nothing clipped) and the rendered
    /// view is slanted after the fact — the same draw-time model as Android's
    /// `textSkewX`. Anchored at the first baseline (`ascender` below the top
    /// in view coordinates, where y grows downward), so the baseline stays
    /// put and glyph tops lean right. On wrapped text later baselines sit
    /// lower and drift slightly left — the trade against the font-matrix
    /// path's hard clip at every line end.
    static func obliqueTransform(_ token: String, size: CGFloat, weight: Font.Weight = .regular) -> CGAffineTransform {
        let ascent: CGFloat = {
            if let name = postScriptName(for: token, weight: weight), let font = UIFont(name: name, size: size) {
                return font.ascender
            }
            return UIFont.systemFont(ofSize: size).ascender
        }()

        return CGAffineTransform(a: 1, b: 0, c: -obliqueSkew, d: 1, tx: obliqueSkew * ascent, ty: 0)
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
               let ps = postScriptName(for: fontName, weight: .regular),
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

    /// PostScript name of the face that draws `token` at `weight`.
    static func postScriptName(for token: String, weight: Font.Weight) -> String? {
        postScriptName(for: weightedToken(aliases[token] ?? token, weight: weight))
    }

    /// The file token that draws a (de-aliased) token at `weight`: a sibling
    /// face for a family's `-Regular` file or a bare family name, otherwise
    /// the token itself. A family missing the exact weight gets its nearest
    /// face, by the CSS font-matching order Compose also uses.
    static func weightedToken(_ token: String, weight: Font.Weight) -> String {
        let target = weightValue(weight)
        let key = "\(token)#\(target)"

        lock.lock()
        if let cached = weightedCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = pickWeightedToken(token, target: target)

        lock.lock()
        weightedCache[key] = resolved
        lock.unlock()

        return resolved
    }

    private static func pickWeightedToken(_ token: String, target: Int) -> String {
        let family: String
        if bundleURL(for: token) != nil {
            // A face that names its own weight ("Inter-Bold") stays put: an
            // unstyled element passes `.regular`, which must not turn it into
            // the family's Regular face.
            guard target != 400, token.hasSuffix("-Regular") else { return token }
            family = String(token.dropLast("-Regular".count))
        } else {
            family = token
        }

        let available = weightSuffixes.filter { bundleURL(for: "\(family)-\($0.suffix)") != nil }
        guard let best = nearestWeight(target, in: available.map(\.value)),
              let face = available.first(where: { $0.value == best }) else {
            return token
        }

        return "\(family)-\(face.suffix)"
    }

    /// CSS font matching (CSS Fonts 4, §5.2 step 4.c): for 400 try 500 next,
    /// for 500 try 400 next, then lighter weights for light targets and
    /// heavier ones for bold targets, before going the other way.
    static func nearestWeight(_ target: Int, in available: [Int]) -> Int? {
        if available.contains(target) { return target }

        let lighter = available.filter { $0 < target }.sorted(by: >)
        let heavier = available.filter { $0 > target }.sorted()

        switch target {
        case 400:
            if available.contains(500) { return 500 }
            return lighter.first ?? heavier.first
        case 500:
            if available.contains(400) { return 400 }
            return lighter.first ?? heavier.first
        case ..<400:
            return lighter.first ?? heavier.first
        default:
            return heavier.first ?? lighter.first
        }
    }

    static func weightValue(_ weight: Font.Weight) -> Int {
        switch weight {
        case .ultraLight: return 200
        case .thin: return 100
        case .light: return 300
        case .medium: return 500
        case .semibold: return 600
        case .bold: return 700
        case .heavy: return 800
        case .black: return 900
        default: return 400
        }
    }

    /// The `wght` axis value to draw a variable font at, or nil for a static
    /// font or a regular request (the font's own default instance).
    private static func variableWeight(_ postScriptName: String, weight: Font.Weight) -> CGFloat? {
        let target = weightValue(weight)
        guard target != 400, let range = weightAxis(postScriptName) else { return nil }

        return min(max(CGFloat(target), range.lowerBound), range.upperBound)
    }

    private static func weightAxis(_ postScriptName: String) -> ClosedRange<CGFloat>? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = weightAxisCache[postScriptName] {
            return cached
        }

        var range: ClosedRange<CGFloat>?
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        if let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] {
            for axis in axes where (axis[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.intValue == weightAxisTag {
                if let lower = (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue,
                   let upper = (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue,
                   lower <= upper {
                    range = CGFloat(lower)...CGFloat(upper)
                }
            }
        }
        weightAxisCache[postScriptName] = range

        return range
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
