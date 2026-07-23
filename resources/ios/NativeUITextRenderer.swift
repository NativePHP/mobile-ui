import SwiftUI

struct NativeUITextRenderer: View {
    let node: NativeUINode

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeStore = NativeUITheme.shared

    var body: some View {
        // A text node with child text runs composes them into ONE wrapping
        // attributed string (inline bold/colored runs, inline-code chips with a
        // background, syntax highlighting) instead of stacking each run as its
        // own block. A leaf text (no text children) keeps the original path
        // below — preserving Dynamic Type via `nuiScaledFont`.
        if node.children.contains(where: { $0.type == "text" }) {
            composedBody
        } else {
            leafBody
        }
    }

    @ViewBuilder
    private var leafBody: some View {
        let p = node.props
        let text = applyTransform(p.getString("text"), p.getInt("text_transform"))
        let fontSize = p.getFloat("font_size", default: 16)
        let fontWeight = resolveFontWeight(p.getInt("font_weight"))
        let fontDesign = resolveFontDesign(p.getInt("font_family"))
        let fontName = p.getString("font_name")
        let lightArgb = p.getColor("color", default: 0xFF000000)
        let darkArgb  = p.getColor("dark_color", default: 0)
        // Pick the dark hex when system is dark AND the theme class supplied
        // one (theme classes auto-emit a `dark` companion). Fall through to
        // the light value otherwise — matches NodeStyleModifier's bg/border
        // dark resolution semantics.
        let color: Int = (colorScheme == .dark && darkArgb != 0) ? darkArgb : lightArgb
        let textAlign = resolveTextAlign(p.getInt("text_align"))
        let maxLines = p.getInt("max_lines")
        let isItalic = p.getInt("font_style") == 1
        let isUnderline = p.getInt("underline") == 1
        let isStrikethrough = p.getInt("line_through") == 1
        let letterSpacingEm = p.getFloat("letter_spacing", default: 0)
        let lineSpacingValue = NativeUIFontResolver.lineSpacing(
            px: p.getFloat("line_height_px", default: 0),
            mult: p.getFloat("line_height", default: 0),
            fontSize: CGFloat(fontSize),
            fontName: fontName
        )

        if !text.isEmpty {
            // Style the `Text` itself (italic/underline/strikethrough on Text are
            // iOS 13+, keeping us below the iOS 16 View-level variants). Kerning
            // is iOS 16+, so it's guarded. The font itself is applied at the
            // View level via `nuiScaledFont` so it participates in Dynamic
            // Type; the Text-level decorations operate on that environment
            // font.
            let styledText: Text = {
                var t = Text(text)
                if isItalic { t = t.italic() }
                if isUnderline { t = t.underline() }
                if isStrikethrough { t = t.strikethrough() }
                if letterSpacingEm != 0, #available(iOS 16.0, *) {
                    t = t.kerning(CGFloat(letterSpacingEm) * CGFloat(fontSize))
                }
                return t
            }()

            styledText
                .nuiScaledFont(size: CGFloat(fontSize), weight: fontWeight, design: fontDesign, fontName: fontName.isEmpty ? nil : fontName, italic: isItalic)
                .lineSpacing(lineSpacingValue)
                .foregroundColor(Color(argb: color))
                .multilineTextAlignment(textAlign)
                .lineLimit(maxLines > 0 ? maxLines : nil)
                // `truncationMode` only applies when there IS a lineLimit; we
                // therefore skip it in the unlimited case so SwiftUI doesn't
                // decide (on some iOS versions) that our `.frame(maxWidth:)`
                // means "single line, truncate" rather than "wrap within."
                .modifier(TruncateIfLimited(maxLines: maxLines))
                // Fill available horizontal space so:
                //  (1) Text can wrap at the container width instead of using
                //      its intrinsic one-line width;
                //  (2) `multilineTextAlignment` has space to align within.
                .frame(maxWidth: .infinity, alignment: frameAlignment(from: p.getInt("text_align")))
                // Grow vertically to fit wrapped content. Without this, SwiftUI
                // sometimes collapses the Text to a single line when bounded
                // by `.frame(maxWidth:)`.
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Inline rich text (child runs → one AttributedString)

    /// Typographic context inherited down the run tree. A child run reads its
    /// own props, falling back to the inherited value for each field (CSS-like
    /// inheritance) — implemented by passing these as the `getX` defaults, so
    /// an unset prop transparently inherits. Decoration/background are NOT
    /// carried here; they're per-run (a chip's bg must not bleed to siblings).
    private struct RunContext {
        var fontSize: Float
        var fontWeightInt: Int
        var fontFamilyInt: Int
        var fontName: String
        var colorArgb: Int
        var darkColorArgb: Int
        var italic: Bool
        var letterSpacingEm: Float
        var textTransform: Int

        /// Root defaults — mirror the leaf path (16pt, regular, black, no dark
        /// override, no custom font, no decoration/kerning/transform).
        static let root = RunContext(
            fontSize: 16, fontWeightInt: 0, fontFamilyInt: 0, fontName: "",
            colorArgb: 0xFF000000, darkColorArgb: 0, italic: false,
            letterSpacingEm: 0, textTransform: 0
        )
    }

    @ViewBuilder
    private var composedBody: some View {
        let p = node.props
        let maxLines = p.getInt("max_lines")
        let composed = buildComposed()
        // Leading applies uniformly to the whole composed string; base it on
        // the node's own font size (the root run's size).
        let lineSpacingValue = NativeUIFontResolver.lineSpacing(
            px: p.getFloat("line_height_px", default: 0),
            mult: p.getFloat("line_height", default: 0),
            fontSize: CGFloat(p.getFloat("font_size", default: 16)),
            fontName: p.getString("font_name")
        )

        Text(composed)
            .lineSpacing(lineSpacingValue)
            .multilineTextAlignment(resolveTextAlign(p.getInt("text_align")))
            .lineLimit(maxLines > 0 ? maxLines : nil)
            .modifier(TruncateIfLimited(maxLines: maxLines))
            // Same fill + fixedSize policy as the leaf path so the composed
            // string wraps at the container width and grows vertically.
            .frame(maxWidth: .infinity, alignment: frameAlignment(from: p.getInt("text_align")))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Build the composed attributed string outside the `@ViewBuilder` — the
    /// in-out mutation of `appendRuns` is a `Void` statement and can't live in
    /// a builder body (it would be read as a view: "() cannot conform to View").
    private func buildComposed() -> AttributedString {
        var composed = AttributedString()
        appendRuns(into: &composed, node: node, inherited: .root)
        return composed
    }

    /// Walk a node, emitting one styled run for its own text (leaf, or the
    /// leading text before nested runs) then recursing into text children.
    private func appendRuns(into result: inout AttributedString, node: NativeUINode, inherited: RunContext) {
        let p = node.props

        // Resolve this level's effective context: own props over inherited.
        var ctx = inherited
        ctx.fontSize = p.getFloat("font_size", default: inherited.fontSize)
        ctx.fontWeightInt = p.getInt("font_weight", default: inherited.fontWeightInt)
        ctx.fontFamilyInt = p.getInt("font_family", default: inherited.fontFamilyInt)
        ctx.fontName = p.getString("font_name", default: inherited.fontName)
        ctx.colorArgb = p.getColor("color", default: inherited.colorArgb)
        ctx.darkColorArgb = p.getColor("dark_color", default: inherited.darkColorArgb)
        ctx.italic = p.getInt("font_style", default: inherited.italic ? 1 : 0) == 1
        ctx.letterSpacingEm = p.getFloat("letter_spacing", default: inherited.letterSpacingEm)
        ctx.textTransform = p.getInt("text_transform", default: inherited.textTransform)

        let ownText = p.getString("text")
        if !ownText.isEmpty {
            result += makeRun(ownText, node: node, ctx: ctx)
        }
        for child in node.children where child.type == "text" {
            appendRuns(into: &result, node: child, inherited: ctx)
        }
    }

    private func makeRun(_ text: String, node: NativeUINode, ctx: RunContext) -> AttributedString {
        var run = AttributedString(applyTransform(text, ctx.textTransform))

        let runWeight = resolveFontWeight(ctx.fontWeightInt)
        // Explicit run font first, then the app-wide theme default (only for
        // the default design — font-serif/font-mono win over the default),
        // then the system font. Mirrors NUIScaledFontModifier's resolution.
        var runFontName = ctx.fontName
        if runFontName.isEmpty, ctx.fontFamilyInt == 0 {
            let family = themeStore.resolve(for: colorScheme).fontFamily
            if !family.isEmpty, family != "System" { runFontName = family }
        }

        var font: Font
        if !runFontName.isEmpty,
           let custom = NativeUIFontResolver.font(runFontName, size: CGFloat(ctx.fontSize), italic: ctx.italic) {
            font = custom.weight(runWeight)
        } else {
            font = Font.system(
                size: CGFloat(ctx.fontSize),
                weight: runWeight,
                design: resolveFontDesign(ctx.fontFamilyInt)
            )
        }
        // Real italic faces (and the system font) take the trait here; a
        // single-style custom font already came back synthetically obliqued
        // from the resolver, on which `.italic()` is a harmless no-op.
        if ctx.italic, #available(iOS 16.0, *) { font = font.italic() }
        run.font = font

        // Foreground — dark hex wins when in dark mode and one was supplied.
        let fg = (colorScheme == .dark && ctx.darkColorArgb != 0) ? ctx.darkColorArgb : ctx.colorArgb
        run.foregroundColor = Color(argb: fg)

        // Run background = the inline-code chip. bg_color lives on style;
        // dark_bg_color on props (matches NodeStyleModifier's split). Per-run,
        // never inherited.
        let bgArgb = node.style?.bgColor ?? 0
        let darkBg = colorScheme == .dark ? node.props.getColor("dark_bg_color", default: 0) : 0
        let effectiveBg = darkBg != 0 ? darkBg : bgArgb
        if effectiveBg != 0 {
            run.backgroundColor = Color(argb: effectiveBg)
        }

        // `Text.LineStyle` (underline/strikethrough on AttributedString) is
        // iOS 16+, same tier as the leaf path's kerning guard. On iOS 15 an
        // inline run simply renders without the decoration.
        if #available(iOS 16.0, *) {
            if node.props.getInt("underline") == 1 { run.underlineStyle = .single }
            if node.props.getInt("line_through") == 1 { run.strikethroughStyle = .single }
        }
        if ctx.letterSpacingEm != 0 { run.kern = CGFloat(ctx.letterSpacingEm) * CGFloat(ctx.fontSize) }

        return run
    }

    private func resolveFontWeight(_ weight: Int) -> Font.Weight {
        switch weight {
        case 1: return .thin
        case 2: return .light
        case 3: return .regular
        case 4: return .medium
        case 5: return .semibold
        case 6: return .bold
        case 7: return .heavy
        default: return .regular
        }
    }

    private func resolveTextAlign(_ align: Int) -> TextAlignment {
        switch align {
        case 0: return .leading
        case 1: return .center
        case 2: return .trailing
        default: return .leading
        }
    }

    private func resolveFontDesign(_ family: Int) -> Font.Design {
        switch family {
        case 1: return .serif
        case 2: return .monospaced
        default: return .default
        }
    }

    /// Text transform: 1 = uppercase, 2 = lowercase, 3 = capitalize, else none.
    private func applyTransform(_ s: String, _ transform: Int) -> String {
        switch transform {
        case 1: return s.uppercased()
        case 2: return s.lowercased()
        case 3: return s.capitalized
        default: return s
        }
    }

    /// Map text-align int to SwiftUI `Alignment` for use with `.frame(alignment:)`.
    private func frameAlignment(from align: Int) -> Alignment {
        switch align {
        case 1: return .center
        case 2: return .trailing
        default: return .leading
        }
    }
}

/// Applies `.truncationMode(.tail)` only when a line limit is actually set.
/// Applying it with `lineLimit(nil)` can make some SwiftUI versions behave
/// as if a single-line limit were in effect, collapsing multi-line content
/// into one truncated line.
private struct TruncateIfLimited: ViewModifier {
    let maxLines: Int
    func body(content: Content) -> some View {
        if maxLines > 0 {
            content.truncationMode(.tail)
        } else {
            content
        }
    }
}
