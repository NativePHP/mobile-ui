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
        let outlineWidth = CGFloat(p.getFloat("text_outline", default: 0))
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
                if outlineWidth > 0, #available(iOS 18.0, *) {
                    // A single-style custom font's italic is a skew of the
                    // whole view (nuiScaledFont), which slants the outline too.
                    let name = effectiveFontName(fontName, family: p.getInt("font_family"))
                    let italic = isItalic && (name.isEmpty || !NativeUIFontResolver.needsSyntheticOblique(name))
                    t = t.customAttribute(NUITextOutline(
                        width: outlineWidth,
                        color: Color(argb: color),
                        text: text,
                        font: outlineFont(name: name, size: fontSize, weight: p.getInt("font_weight"), family: p.getInt("font_family"), italic: italic),
                        kern: CGFloat(letterSpacingEm) * CGFloat(fontSize)
                    ))
                }
                return t
            }()

            styledText
                .nuiScaledFont(size: CGFloat(fontSize), weight: fontWeight, design: fontDesign, fontName: fontName.isEmpty ? nil : fontName, italic: isItalic)
                .lineSpacing(lineSpacingValue)
                .foregroundColor(Color(argb: color))
                .modifier(NUIOutlinedText(width: outlineWidth))
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
        var outlineWidth: Float
        var pressCallbackId: Int
        var pressNodeId: Int

        /// Root defaults — mirror the leaf path (16pt, regular, black, no dark
        /// override, no custom font, no decoration/kerning/transform/outline).
        static let root = RunContext(
            fontSize: 16, fontWeightInt: 0, fontFamilyInt: 0, fontName: "",
            colorArgb: 0xFF000000, darkColorArgb: 0, italic: false,
            letterSpacingEm: 0, textTransform: 0, outlineWidth: 0, pressCallbackId: 0, pressNodeId: 0
        )
    }

    /// A stretch of the composed string: filled runs, or one outlined run.
    private struct ComposedStretch {
        var text = AttributedString()
        var outline: NUITextOutline?
    }

    @ViewBuilder
    private var composedBody: some View {
        let p = node.props
        let maxLines = p.getInt("max_lines")
        let stretches = buildComposed()
        let outlineWidth = stretches.compactMap(\.outline?.width).max() ?? 0
        // Leading applies uniformly to the whole composed string; base it on
        // the node's own font size (the root run's size).
        let lineSpacingValue = NativeUIFontResolver.lineSpacing(
            px: p.getFloat("line_height_px", default: 0),
            mult: p.getFloat("line_height", default: 0),
            fontSize: CGFloat(p.getFloat("font_size", default: 16)),
            fontName: p.getString("font_name")
        )

        composedText(stretches)
            .modifier(NUIOutlinedText(width: outlineWidth))
            .lineSpacing(lineSpacingValue)
            .multilineTextAlignment(resolveTextAlign(p.getInt("text_align")))
            .lineLimit(maxLines > 0 ? maxLines : nil)
            .modifier(TruncateIfLimited(maxLines: maxLines))
            // Same fill + fixedSize policy as the leaf path so the composed
            // string wraps at the container width and grows vertically.
            .frame(maxWidth: .infinity, alignment: frameAlignment(from: p.getInt("text_align")))
            .fixedSize(horizontal: false, vertical: true)
            // Taps on pressable runs arrive as our custom-scheme link;
            // every other URL keeps the system's own behaviour.
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "nativephp-press" else { return .systemAction }
                let parts = url.pathComponents.filter { $0 != "/" }
                if parts.count == 2, let cb = Int(parts[0]), let nodeId = Int(parts[1]), cb != 0 {
                    // Through the focus policy so a focused field's pending
                    // change reaches PHP before the press does (mobile-air #335).
                    KeyboardFocusPolicy.dispatchPress {
                        NativeElementBridge.sendPressEvent(cb, nodeId: nodeId)
                    }
                }
                return .handled
            })
    }

    /// Build the composed attributed string outside the `@ViewBuilder` — the
    /// in-out mutation of `appendRuns` is a `Void` statement and can't live in
    /// a builder body (it would be read as a view: "() cannot conform to View").
    private func buildComposed() -> [ComposedStretch] {
        var stretches: [ComposedStretch] = []
        appendRuns(into: &stretches, node: node, inherited: .root)
        return stretches
    }

    /// One `Text` for the whole string. Without outlined runs that's a single
    /// attributed string, as it always was. Outlined stretches are marked for
    /// NUIOutlineTextRenderer, which only reads a Text attribute, so then the
    /// stretches join as Texts instead.
    private func composedText(_ stretches: [ComposedStretch]) -> Text {
        guard #available(iOS 18.0, *), stretches.contains(where: { $0.outline != nil }) else {
            return Text(stretches.reduce(into: AttributedString()) { $0 += $1.text })
        }

        return stretches.reduce(Text(verbatim: "")) { composed, stretch in
            let piece = stretch.outline.map { Text(stretch.text).customAttribute($0) } ?? Text(stretch.text)

            return Text("\(composed)\(piece)")
        }
    }

    /// Walk a node, emitting one styled run for its own text (leaf, or the
    /// leading text before nested runs) then recursing into text children.
    private func appendRuns(into result: inout [ComposedStretch], node: NativeUINode, inherited: RunContext) {
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
        ctx.outlineWidth = p.getFloat("text_outline", default: inherited.outlineWidth)

        // The innermost @press wins for this run and its whole subtree,
        // matching the flat per-span links the Android renderer emits.
        if node.onPress != 0 {
            ctx.pressCallbackId = node.onPress
            ctx.pressNodeId = node.id
        }

        let ownText = p.getString("text")
        if !ownText.isEmpty {
            let run = makeRun(ownText, node: node, ctx: ctx)

            if ctx.outlineWidth > 0 {
                let fg = (colorScheme == .dark && ctx.darkColorArgb != 0) ? ctx.darkColorArgb : ctx.colorArgb
                let outline = NUITextOutline(
                    width: CGFloat(ctx.outlineWidth),
                    color: Color(argb: fg),
                    text: String(run.characters),
                    font: outlineFont(
                        name: effectiveFontName(ctx.fontName, family: ctx.fontFamilyInt),
                        size: ctx.fontSize, weight: ctx.fontWeightInt, family: ctx.fontFamilyInt, italic: ctx.italic
                    ),
                    kern: CGFloat(ctx.letterSpacingEm) * CGFloat(ctx.fontSize),
                    id: result.count
                )
                result.append(ComposedStretch(text: run, outline: outline))
            } else if let last = result.indices.last, result[last].outline == nil {
                result[last].text += run
            } else {
                result.append(ComposedStretch(text: run))
            }
        }
        for child in node.children where child.type == "text" {
            appendRuns(into: &result, node: child, inherited: ctx)
        }
    }

    private func makeRun(_ text: String, node: NativeUINode, ctx: RunContext) -> AttributedString {
        var run = AttributedString(applyTransform(text, ctx.textTransform))

        let runWeight = resolveFontWeight(ctx.fontWeightInt)
        let runFontName = effectiveFontName(ctx.fontName, family: ctx.fontFamilyInt)

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

        // A pressable run rides a custom-scheme link that composedBody's
        // OpenURLAction intercepts and forwards as an ordinary press,
        // so PHP sees the same dispatch a standalone tap sends.
        if ctx.pressCallbackId != 0 {
            run.link = URL(string: "nativephp-press://run/\(ctx.pressCallbackId)/\(ctx.pressNodeId)")
        }

        return run
    }

    /// Explicit font first, then the app-wide theme default (only for the
    /// default design — font-serif/font-mono win over the default). Empty
    /// means the system font. Mirrors NUIScaledFontModifier's resolution.
    private func effectiveFontName(_ name: String, family: Int) -> String {
        guard name.isEmpty, family == 0 else { return name }

        let themeFamily = themeStore.resolve(for: colorScheme).fontFamily
        return themeFamily == "System" ? "" : themeFamily
    }

    /// The Core Text font an outlined run's glyphs are stroked in, picked the
    /// way its SwiftUI font is: the bundled font when `name` resolves, else
    /// the system font. SwiftUI doesn't say which font it laid a run out in,
    /// so the renderer needs its own. `size` is the design size; the renderer
    /// scales to the run's laid-out size, which takes in Dynamic Type.
    private func outlineFont(name: String, size: Float, weight: Int, family: Int, italic: Bool) -> CTFont {
        if !name.isEmpty, let custom = NativeUIFontResolver.ctFont(name, size: CGFloat(size), italic: italic) {
            return custom
        }

        var descriptor = UIFont.systemFont(ofSize: CGFloat(size), weight: resolveSystemFontWeight(weight)).fontDescriptor
        if family == 1 { descriptor = descriptor.withDesign(.serif) ?? descriptor }
        if family == 2 { descriptor = descriptor.withDesign(.monospaced) ?? descriptor }
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) ?? descriptor }

        return UIFont(descriptor: descriptor, size: CGFloat(size)) as CTFont
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

    /// resolveFontWeight's weights, for UIKit.
    private func resolveSystemFontWeight(_ weight: Int) -> UIFont.Weight {
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

// MARK: - Outlined text (`text-outline`)

/// Marks text to draw hollow: the outline of its glyphs, `width` points wide
/// and centred on their edges like a CSS text stroke, in `color`.
/// NUIOutlineTextRenderer strokes the glyphs Core Text sets `text` in with
/// `font`, so the two have to be the text and font the run shows.
struct NUITextOutline: Hashable {
    var width: CGFloat
    var color: Color
    var text: String
    var font: CTFont
    var kern: CGFloat = 0
    /// Tells apart two outlined runs that are otherwise the same.
    var id = 0
}

@available(iOS 18.0, *)
extension NUITextOutline: TextAttribute {}

/// Draws text marked with NUITextOutline as outlines, and everything else as
/// usual. SwiftUI can't stroke text, and its layout doesn't say which glyphs
/// it placed, so each outlined run's text is set again with Core Text to get
/// the glyphs' paths. Those are stroked where SwiftUI placed each glyph, with
/// mitred corners like Android and the web.
@available(iOS 18.0, *)
struct NUIOutlineTextRenderer: TextRenderer {
    var width: CGFloat

    /// Android's and the web's default.
    private static let miterLimit: CGFloat = 4

    /// A sharp corner's miter can reach `miterLimit` half-widths past the glyph.
    var displayPadding: EdgeInsets {
        let reach = width / 2 * Self.miterLimit

        return EdgeInsets(top: reach, leading: reach, bottom: reach, trailing: reach)
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        // Where each outlined run's text starts in the layout. A run that
        // wraps is split over lines, and this finds its first character.
        var starts: [NUITextOutline: Text.Layout.CharacterIndex] = [:]
        for line in layout {
            for run in line {
                if let outline = run[NUITextOutline.self], let first = run.characterIndices.min() {
                    starts[outline] = min(starts[outline] ?? first, first)
                }
            }
        }

        var glyphSets: [NUITextOutline: OutlineGlyphs] = [:]
        for line in layout {
            for run in line {
                guard let outline = run[NUITextOutline.self], let start = starts[outline] else {
                    ctx.draw(run)
                    continue
                }

                let glyphs = glyphSets[outline] ?? OutlineGlyphs(outline)
                glyphSets[outline] = glyphs
                stroke(run, outline: outline, glyphs: glyphs, start: start, in: &ctx)
            }
        }
    }

    private func stroke(_ run: Text.Layout.Run, outline: NUITextOutline, glyphs: OutlineGlyphs, start: Text.Layout.CharacterIndex, in ctx: inout GraphicsContext) {
        let path = CGMutablePath()

        for slice in run {
            guard let index = slice.characterIndices.min(),
                  let glyph = glyphs[glyphs.first + start.distance(to: index)],
                  let shape = glyph.path(ascent: run.typographicBounds.ascent, at: slice.typographicBounds.origin) else {
                // No outline to draw (an emoji, say): draw the glyph as it is.
                ctx.draw(slice)
                continue
            }

            path.addPath(shape)
        }

        ctx.stroke(
            Path(path),
            with: .color(outline.color),
            style: StrokeStyle(lineWidth: outline.width, lineJoin: .miter, miterLimit: Self.miterLimit)
        )
    }
}

/// The glyphs Core Text sets an outlined run's text in, by the UTF-16 offset
/// of the character each one starts at, as SwiftUI's character indices count.
@available(iOS 18.0, *)
private struct OutlineGlyphs {
    struct Glyph {
        var id: CGGlyph
        var font: CTFont

        /// The glyph's path at the run's size, on the baseline at `origin`.
        /// SwiftUI may have sized the font for Dynamic Type, so the size
        /// comes from the run's ascent. Glyphs can be built from overlapping
        /// shapes (SF's are), which a stroke would show inside the letter, so
        /// the overlaps are merged away first.
        func path(ascent: CGFloat, at origin: CGPoint) -> CGPath? {
            let scale = ascent / CTFontGetAscent(font)
            let sized = abs(scale - 1) < 0.001 ? font : CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * scale, nil, nil)
            var placement = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origin.x, ty: origin.y)

            return CTFontCreatePathForGlyph(sized, id, &placement)?.normalized()
        }
    }

    private var glyphs: [Int: Glyph] = [:]
    /// The first offset with a glyph, which lines up with the run's first
    /// character index in SwiftUI's layout.
    private(set) var first = 0

    init(_ outline: NUITextOutline) {
        var attributes: [NSAttributedString.Key: Any] = [.font: outline.font]
        if outline.kern != 0 { attributes[.kern] = outline.kern }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: outline.text, attributes: attributes))

        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var ids = [CGGlyph](repeating: 0, count: count)
            var offsets = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &ids)
            CTRunGetStringIndices(run, CFRange(), &offsets)
            // Fallback fonts (for characters `font` lacks) are per run.
            let runFont = (CTRunGetAttributes(run) as? [NSAttributedString.Key: Any])?[.font]
            let font = runFont.map { $0 as! CTFont } ?? outline.font

            for (id, offset) in zip(ids, offsets) where glyphs[offset] == nil {
                glyphs[offset] = Glyph(id: id, font: font)
            }
        }

        first = glyphs.keys.min() ?? 0
    }

    subscript(offset: Int) -> Glyph? {
        glyphs[offset]
    }
}

/// Draws a Text's outlined runs (`text-outline`) through
/// NUIOutlineTextRenderer when it has any. Before iOS 18 they draw filled.
struct NUIOutlinedText: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        if width > 0, #available(iOS 18.0, *) {
            content.textRenderer(NUIOutlineTextRenderer(width: width))
        } else {
            content
        }
    }
}
