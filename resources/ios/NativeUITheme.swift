import SwiftUI
import UIKit

// MARK: - Theme Tokens

/// One coherent set of theme tokens (light OR dark). Exposed to SwiftUI
/// renderers via the `\.nativeUITheme` environment value.
///
/// The PHP side (`Native\Mobile\UI\Theme::merge([...])`) is the source of
/// truth. Tokens arrive over the bridge via `NativeUI.Theme.Set`.
struct NativeUITokens: Equatable {
    // Colors
    let primary: Color
    let onPrimary: Color
    let secondary: Color
    let onSecondary: Color
    let surface: Color
    let onSurface: Color
    let background: Color
    let onBackground: Color
    let surfaceVariant: Color
    let onSurfaceVariant: Color
    let outline: Color
    let destructive: Color
    let onDestructive: Color
    let accent: Color
    let onAccent: Color

    // Radii (points)
    let radiusSm: CGFloat
    let radiusMd: CGFloat
    let radiusLg: CGFloat
    let radiusFull: CGFloat

    // Typography
    let fontSm: CGFloat
    let fontMd: CGFloat
    let fontLg: CGFloat
    let fontXl: CGFloat
    let fontFamily: String

    /// Fallback matches `config/native-ui.php` defaults. Used before PHP has
    /// pushed an initial theme — keeps components renderable during bootstrap.
    static let fallback = NativeUITokens(
        primary:          Color(hex: "#0F766E"),
        onPrimary:        Color(hex: "#FFFFFF"),
        secondary:        Color(hex: "#475569"),
        onSecondary:      Color(hex: "#FFFFFF"),
        surface:          Color(hex: "#FFFFFF"),
        onSurface:        Color(hex: "#0F172A"),
        background:       Color(hex: "#F8FAFC"),
        onBackground:     Color(hex: "#0F172A"),
        surfaceVariant:   Color(hex: "#F1F5F9"),
        onSurfaceVariant: Color(hex: "#475569"),
        outline:          Color(hex: "#CBD5E1"),
        destructive:      Color(hex: "#B91C1C"),
        onDestructive:    Color(hex: "#FFFFFF"),
        accent:           Color(hex: "#C2410C"),
        onAccent:         Color(hex: "#FFFFFF"),
        radiusSm: 4, radiusMd: 8, radiusLg: 16, radiusFull: 9999,
        fontSm: 14, fontMd: 16, fontLg: 20, fontXl: 24,
        fontFamily: "System"
    )
}

// MARK: - Theme Store

/// Singleton holding the current effective theme tokens for both color schemes.
/// PHP pushes updates via `NativeUI.Theme.Set`; consumers pick the right scheme
/// via `resolve(for: colorScheme)`.
final class NativeUITheme: ObservableObject {
    static let shared = NativeUITheme()

    @Published private(set) var light: NativeUITokens = .fallback
    @Published private(set) var dark: NativeUITokens = .fallback

    private init() {}

    /// Pick the active token set based on the current system color scheme.
    func resolve(for scheme: ColorScheme) -> NativeUITokens {
        scheme == .dark ? dark : light
    }

    /// Called by the bridge on every `Theme::merge()` from PHP. Parameters are
    /// the full effective theme (light + dark + radii + fonts), post-merge
    /// and post-dark-auto-derivation.
    func apply(_ parameters: [String: Any]) {
        let lightMap = parameters["light"] as? [String: Any] ?? [:]
        let darkMap  = parameters["dark"]  as? [String: Any] ?? [:]

        let radiusSm   = cgf(parameters["radius-sm"],   fallback: light.radiusSm)
        let radiusMd   = cgf(parameters["radius-md"],   fallback: light.radiusMd)
        let radiusLg   = cgf(parameters["radius-lg"],   fallback: light.radiusLg)
        let radiusFull = cgf(parameters["radius-full"], fallback: light.radiusFull)

        let fontSm     = cgf(parameters["font-sm"],     fallback: light.fontSm)
        let fontMd     = cgf(parameters["font-md"],     fallback: light.fontMd)
        let fontLg     = cgf(parameters["font-lg"],     fallback: light.fontLg)
        let fontXl     = cgf(parameters["font-xl"],     fallback: light.fontXl)
        let fontFamily = (parameters["font-family"] as? String) ?? light.fontFamily

        // Semantic font aliases (config `fonts` map) — handed to the resolver
        // so every token lookup (elements, chrome, the default above) accepts
        // an alias. Assigned before the token stores so any recomposition
        // triggered below already sees the fresh mapping.
        NativeUIFontResolver.aliases = (parameters["fonts"] as? [String: String]) ?? [:]

        func tokens(from map: [String: Any], fallbackTo: NativeUITokens) -> NativeUITokens {
            NativeUITokens(
                primary:          hex(map["primary"],            fallback: fallbackTo.primary),
                onPrimary:        hex(map["on-primary"],         fallback: fallbackTo.onPrimary),
                secondary:        hex(map["secondary"],          fallback: fallbackTo.secondary),
                onSecondary:      hex(map["on-secondary"],       fallback: fallbackTo.onSecondary),
                surface:          hex(map["surface"],            fallback: fallbackTo.surface),
                onSurface:        hex(map["on-surface"],         fallback: fallbackTo.onSurface),
                background:       hex(map["background"],         fallback: fallbackTo.background),
                onBackground:     hex(map["on-background"],      fallback: fallbackTo.onBackground),
                surfaceVariant:   hex(map["surface-variant"],    fallback: fallbackTo.surfaceVariant),
                onSurfaceVariant: hex(map["on-surface-variant"], fallback: fallbackTo.onSurfaceVariant),
                outline:          hex(map["outline"],            fallback: fallbackTo.outline),
                destructive:      hex(map["destructive"],        fallback: fallbackTo.destructive),
                onDestructive:    hex(map["on-destructive"],     fallback: fallbackTo.onDestructive),
                accent:           hex(map["accent"],             fallback: fallbackTo.accent),
                onAccent:         hex(map["on-accent"],          fallback: fallbackTo.onAccent),
                radiusSm: radiusSm, radiusMd: radiusMd, radiusLg: radiusLg, radiusFull: radiusFull,
                fontSm: fontSm, fontMd: fontMd, fontLg: fontLg, fontXl: fontXl,
                fontFamily: fontFamily
            )
        }

        let newLight = tokens(from: lightMap, fallbackTo: .fallback)
        let newDark  = tokens(from: darkMap,  fallbackTo: newLight)

        // `@Published` fires on every assignment — even when the new value
        // equals the old one. That would cause every observer (every Screen,
        // Button, TextInput…) to re-render on each bridge push, which PHP
        // sends on every service-provider boot (i.e. every request). Gate the
        // assignment on actual change to keep the observable stable.
        if newLight != self.light { self.light = newLight }
        if newDark  != self.dark  { self.dark  = newDark }

        applyChromeFont(fontFamily)
    }

    /// Font the SYSTEM-drawn navigation chrome. `navigationTitle` renders
    /// through UIKit's `UINavigationBar` and SwiftUI exposes no font API for
    /// it, so route the app-wide default font through the UIKit appearance
    /// proxy. Core doesn't configure `UINavigationBar` appearances itself, so
    /// this composes safely; bars pick it up on creation (theme lands at boot,
    /// before the first screen). Tab-bar labels are excluded — core's tabs
    /// renderer manages its own `UITabBarAppearance`.
    private func applyChromeFont(_ family: String) {
        if family.isEmpty || family == "System" {
            UINavigationBar.appearance().titleTextAttributes = nil
            UINavigationBar.appearance().largeTitleTextAttributes = nil
            return
        }

        guard let psName = NativeUIFontResolver.postScriptName(for: family) else { return }

        if let title = UIFont(name: psName, size: 17) {
            UINavigationBar.appearance().titleTextAttributes = [.font: title]
        }
        if let large = UIFont(name: psName, size: 34) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
        }
    }
}

// MARK: - Environment Propagation

private struct NativeUIThemeKey: EnvironmentKey {
    static let defaultValue: NativeUITokens = .fallback
}

extension EnvironmentValues {
    /// Active theme tokens for the current color scheme. Renderers read this
    /// instead of going through `NativeUITheme.shared` directly so SwiftUI can
    /// track dependencies and update components when tokens change.
    var nativeUITheme: NativeUITokens {
        get { self[NativeUIThemeKey.self] }
        set { self[NativeUIThemeKey.self] = newValue }
    }
}

// MARK: - Parsing helpers

private func hex(_ any: Any?, fallback: Color) -> Color {
    guard let s = any as? String, s.hasPrefix("#") else { return fallback }
    return Color(hex: s)
}

private func cgf(_ any: Any?, fallback: CGFloat) -> CGFloat {
    if let n = any as? CGFloat { return n }
    if let n = any as? Double { return CGFloat(n) }
    if let n = any as? Int { return CGFloat(n) }
    if let n = any as? NSNumber { return CGFloat(truncating: n) }
    return fallback
}

// MARK: - Accessibility helpers

/// Renders a fixed design-point font size through Dynamic Type so text tracks
/// the user's preferred content size. `@ScaledMetric` scales the base size
/// relative to `.body`, matching how UIFontMetrics scales custom fonts.
struct NUIScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let fontName: String?
    private let italic: Bool

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, fontName: String?, italic: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.design = design
        self.fontName = fontName
        self.italic = italic
    }

    @ObservedObject private var themeStore = NativeUITheme.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // A resolvable custom font wins; the weight still applies (SwiftUI
        // selects/synthesizes it within the family). Unknown names — or none —
        // fall back to the system font unchanged. `size` is already Dynamic-
        // Type-scaled by `@ScaledMetric`, so the custom font uses it as-is.
        // `italic` only matters for single-style custom fonts: the font stays
        // upright (so SwiftUI rasterizes the full glyphs — a matrix-skewed
        // font leans past its advances and gets clipped at line ends) and the
        // rendered view is slanted instead. Real italic faces and the system
        // font get the trait from the caller's `Text.italic()`.
        if let name = effectiveFontName, let custom = NativeUIFontResolver.font(name, size: size) {
            if italic, NativeUIFontResolver.needsSyntheticOblique(name) {
                content.font(custom.weight(weight))
                    .transformEffect(NativeUIFontResolver.obliqueTransform(name, size: size))
            } else {
                content.font(custom.weight(weight))
            }
        } else {
            content.font(.system(size: size, weight: weight, design: design))
        }
    }

    /// Explicit per-element font first; otherwise the app-wide default from
    /// the theme's `font-family` token — but only for the default design, so
    /// explicit `font-serif` / `font-mono` classes still win over the default.
    private var effectiveFontName: String? {
        if let fontName { return fontName }
        guard design == .default else { return nil }

        let family = themeStore.resolve(for: colorScheme).fontFamily
        return (family.isEmpty || family == "System") ? nil : family
    }
}

extension View {
    /// Dynamic-Type-aware replacement for `.font(.system(size:weight:design:))`.
    /// Use this for all text (and glyph icons rendered as text) so type scales
    /// with the user's accessibility settings. Pass `fontName` (a bundled font
    /// token) to render in a custom font, falling back to the system font when
    /// it can't be resolved.
    func nuiScaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default, fontName: String? = nil, italic: Bool = false) -> some View {
        modifier(NUIScaledFontModifier(size: size, weight: weight, design: design, fontName: fontName, italic: italic))
    }

    /// Ensures a minimum 44×44pt hit target (Apple HIG) without changing the
    /// visual size of the content. Apply to small tappable controls.
    func nuiMinTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

extension Color {
    /// Construct from `#RRGGBB` or `#AARRGGBB` hex string. Falls back to black
    /// on malformed input.
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        s = s.uppercased()

        var argb: UInt64 = 0xFF000000
        if s.count == 6, let rgb = UInt64(s, radix: 16) {
            argb = 0xFF000000 | rgb
        } else if s.count == 8, let full = UInt64(s, radix: 16) {
            argb = full
        }

        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >>  8) & 0xFF) / 255.0
        let b = Double((argb >>  0) & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
