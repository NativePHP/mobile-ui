import SwiftUI
import SwiftDraw
import UIKit

struct NativeUIPressableRenderer: View {
    let node: NativeUINode
    var body: some View {
        if node.props.getBool("has_menu") {
            // `:menu` attribute attached — wrap the pressable's content
            // as a SwiftUI Menu's label. SwiftUI's Menu absorbs taps to
            // open the dropdown, so the @press handler is naturally
            // shadowed (matches the locked-in spec). On iOS 26+ the menu
            // gets Liquid Glass for free.
            let items = node.children.filter { $0.type == "top_bar_action" }
            Menu {
                ForEach(items) { item in
                    pressableMenuItem(item)
                }
            } label: {
                NativeUIColumnRenderer(node: node)
                    .contentShape(Rectangle())
            }
        } else {
            NativeUIColumnRenderer(node: node)
        }
    }
}

/// Render one menu item as either a Button or a Divider, mirroring the
/// `TopBarActionView` dropdown pattern from `NativeRootStackRenderer`.
@ViewBuilder
private func pressableMenuItem(_ item: NativeUINode) -> some View {
    if item.props.getBool("divider") {
        Divider()
    } else {
        let label = item.props.getString("label", default: "")
        let icon = item.props.getString("icon", default: "")
        let isDestructive = item.props.getBool("destructive")
        Button(role: isDestructive ? .destructive : nil) {
            if item.onPress != 0 {
                NativeElementBridge.sendPressEvent(item.onPress, nodeId: item.id)
            }
        } label: {
            if !icon.isEmpty {
                Label(label, systemImage: getIconForName(icon))
            } else {
                Text(label)
            }
        }
        .tint(isDestructive ? .red : nil)
    }
}

struct NativeUICanvasRenderer: View {
    let node: NativeUINode
    var body: some View {
        NativeUIColumnRenderer(node: node)
    }
}

struct NativeUISpacerRenderer: View {
    let node: NativeUINode
    var body: some View {
        // SwiftUI's `Spacer()` only expands inside SwiftUI's own HStack/VStack —
        // our FlexContainer is a custom Layout, so a real Spacer would size to
        // zero. Color.clear accepts whatever proposal FlexContainer gives it
        // (driven by the spacer node's flex_grow=1 default), so it claims the
        // remaining main-axis space and pushes siblings apart as expected.
        Color.clear
    }
}

struct NativeUIDividerRenderer: View {
    let node: NativeUINode
    var body: some View {
        let borderArgb = node.style?.borderColor ?? 0
        let color: Color = borderArgb != 0 ? Color(argb: borderArgb) : Color(uiColor: .separator)
        Rectangle().fill(color).frame(height: 1)
    }
}

struct NativeUIRectRenderer: View {
    let node: NativeUINode
    var body: some View {
        // Shape primitive — renders as a filled rectangle using node.style.bgColor.
        // Border radius / stroke come from NodeStyleModifier above, so this only
        // paints the fill. `.fill(.clear)` (previous behavior) produced an
        // invisible shape.
        let fillArgb = node.style?.bgColor ?? 0
        let fill = fillArgb != 0 ? Color(argb: fillArgb) : Color.clear
        Rectangle().fill(fill)
    }
}

struct NativeUICircleRenderer: View {
    let node: NativeUINode
    var body: some View {
        let fillArgb = node.style?.bgColor ?? 0
        let fill = fillArgb != 0 ? Color(argb: fillArgb) : Color.clear
        Circle().fill(fill)
    }
}

struct NativeUILineRenderer: View {
    let node: NativeUINode
    var body: some View {
        let borderArgb = node.style?.borderColor ?? 0
        let color: Color = borderArgb != 0 ? Color(argb: borderArgb) : Color(uiColor: .separator)
        let width = CGFloat(node.style?.borderWidth ?? 1)
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 100, y: 0))
        }
        .stroke(color, lineWidth: width)
    }
}

struct NativeUIImageRenderer: View {
    let node: NativeUINode
    var body: some View {
        let p = node.props
        let src = p.getString("src")
        let fit = p.getInt("fit")
        let tintArgb = p.getColor("tint_color", default: 0)
        let contentMode = resolveContentMode(fit)
        let cornerRadius = CGFloat(node.style?.borderRadius ?? 0)
        let alt = p.getString("alt")

        if contentMode == .fill {
            // Cover / fill (object-cover, object-fill): the image fills its
            // frame and may overflow. With just
            // `image.resizable().aspectRatio(.fill).clipped()`, a higher-res
            // decoded source reports an intrinsic size larger than the frame,
            // the proposal-clamping path diverges between simulator and
            // device, and the image paints beyond its declared frame onto
            // siblings. Wrapping in `Color.clear.overlay { ... }` pins the
            // outer view to exactly the proposed frame; `.clipped()` then
            // crops the overflow. NOTE: this needs a definite height — supply
            // one via `h-*` or `aspect-*`, since Color.clear has no intrinsic
            // size and collapses in an unbounded (scroll-view) main axis.
            Color.clear
                .overlay(imageContent(src: src, contentMode: contentMode, tintArgb: tintArgb, cornerRadius: cornerRadius))
                .clipped()
                .modifier(ImageAltModifier(alt: alt))
        } else {
            // Fit (default / object-contain / scale-down / none): the image
            // is letterboxed and never overflows, so render it directly.
            // Without an explicit height the resizable + `.aspectRatio(.fit)`
            // image self-sizes to its source's aspect ratio — i.e. a bare
            // `<image class="w-full">` lays out at its natural ratio like an
            // HTML <img>. Within a definite frame it just letterboxes.
            imageContent(src: src, contentMode: contentMode, tintArgb: tintArgb, cornerRadius: cornerRadius)
                .modifier(ImageAltModifier(alt: alt))
        }
    }

    @ViewBuilder
    private func imageContent(src: String, contentMode: ContentMode, tintArgb: Int, cornerRadius: CGFloat) -> some View {
        if src.isEmpty {
            Color.clear
        } else if isSVGSource(src) {
            // Vectors never become bitmaps: SVGView draws through a Canvas and
            // stays sharp at any size, so an 8pt viewBox blown up to 96pt is
            // exact rather than an upscaled raster.
            NativeUISVGContent(src: src, contentMode: contentMode, tintArgb: tintArgb, cornerRadius: cornerRadius)
        } else if let path = localFilePath(for: src) {
            // Local device file — camera capture, gallery selection, etc.
            // `AsyncImage`/`URLSession` can't load `file://` or bare
            // filesystem paths, so decode directly with UIImage. Handles
            // HEIC/HEIF transparently (UIImage decodes them natively).
            if let uiImage = UIImage(contentsOfFile: path) {
                tinted(Image(uiImage: uiImage), contentMode: contentMode, tintArgb: tintArgb, cornerRadius: cornerRadius)
            } else {
                Color.clear
            }
        } else if let url = URL(string: src) {
            // Remote URL (http/https) — load asynchronously.
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    tinted(image, contentMode: contentMode, tintArgb: tintArgb, cornerRadius: cornerRadius)
                case .failure:
                    Color.clear
                case .empty:
                    ProgressView()
                @unknown default:
                    Color.clear
                }
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func tinted(_ image: Image, contentMode: ContentMode, tintArgb: Int, cornerRadius: CGFloat) -> some View {
        // `foregroundStyle` only recolours a template image. A UIImage decoded
        // from a file or a URL is `.original`, so the tint had nothing to act
        // on and was dropped silently.
        let source = tintArgb != 0 ? image.renderingMode(.template) : image

        source
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .modifier(ImageTintModifier(tintArgb: tintArgb))
            .modifier(FittedCornerModifier(contentMode: contentMode, cornerRadius: cornerRadius))
    }

}

/// Resolves `src` to a local filesystem path when it points at an on-device
/// file (`file://…` URL or an absolute `/…` path), or nil when it's a remote
/// URL that should go through AsyncImage.
private func localFilePath(for src: String) -> String? {
    if src.hasPrefix("file://") {
        return URL(string: src)?.path ?? String(src.dropFirst("file://".count))
    }
    if src.hasPrefix("/") {
        return src
    }
    return nil
}

/// Classifies `src` as SVG content, or nil when it isn't SVG. Inline markup
/// and data URIs are recognised by their prefix; files and remote URLs by
/// extension, since neither can be sniffed without reading them first.
/// Detection and loading share this one classification, so every source the
/// renderer routes to the SVG branch is one the loader knows how to fetch.
private enum SVGSource {
    case markup(String)
    case dataURI(String)
    case remote(URL)
    case localFile(String)
    case bundled(String)

    init?(_ src: String) {
        let trimmed = src.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("<svg") || trimmed.hasPrefix("<?xml") {
            self = .markup(trimmed)
            return
        }
        if trimmed.hasPrefix("data:image/svg+xml") {
            self = .dataURI(trimmed)
            return
        }

        let path = URL(string: trimmed)?.path ?? trimmed
        guard (path as NSString).pathExtension.lowercased() == "svg" else {
            return nil
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"), let url = URL(string: trimmed) {
            self = .remote(url)
            return
        }
        if let filePath = localFilePath(for: trimmed) {
            self = .localFile(filePath)
            return
        }
        self = .bundled(trimmed)
    }
}

private func isSVGSource(_ src: String) -> Bool {
    SVGSource(src) != nil
}

/// Parses an SVG source off the main actor, then draws it with the same tint
/// and corner treatment as a raster image. Parsing is a `task(id:)` rather
/// than a computed value because a remote source has to be fetched.
private struct NativeUISVGContent: View {
    let src: String
    let contentMode: ContentMode
    let tintArgb: Int
    let cornerRadius: CGFloat

    @State private var svg: SVG?

    var body: some View {
        Group {
            if let svg {
                SVGView(svg: svg)
                    .renderingMode(tintArgb != 0 ? .template : .original)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                // Covers "still loading" and "failed to parse" alike, matching
                // the raster branch's empty result for an undecodable source.
                Color.clear
            }
        }
        .modifier(ImageTintModifier(tintArgb: tintArgb))
        .modifier(FittedCornerModifier(contentMode: contentMode, cornerRadius: cornerRadius))
        .task(id: src) {
            svg = await Self.parse(src)
        }
    }

    private static func parse(_ src: String) async -> SVG? {
        guard let source = SVGSource(src) else { return nil }

        switch source {
        case .markup(let xml):
            return SVG(xml: xml)
        case .dataURI(let uri):
            guard let data = decodeDataURI(uri) else { return nil }
            return SVG(data: data)
        case .remote(let url):
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return SVG(data: data)
        case .localFile(let path):
            return SVG(fileURL: URL(fileURLWithPath: path))
        case .bundled(let name):
            return SVG(named: name, in: .main)
        }
    }

    /// RFC 2397: the payload is base64 when the media type carries the marker,
    /// and percent-encoded text otherwise.
    private static func decodeDataURI(_ src: String) -> Data? {
        let parts = src.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let payload = String(parts[1])

        if parts[0].contains("base64") {
            return Data(base64Encoded: payload)
        }

        return payload.removingPercentEncoding?.data(using: .utf8)
    }
}

/// Maps the `fit` ordinal to a SwiftUI content mode.
private func resolveContentMode(_ fit: Int) -> ContentMode {
    switch fit {
    case 2: return .fill
    case 3: return .fill
    default: return .fit
    }
}

/// HTML `<img alt>` semantics for VoiceOver: an `alt` prop makes the image a
/// labeled image element; no `alt` marks it decorative and hides it from the
/// accessibility tree entirely.
private struct ImageAltModifier: ViewModifier {
    let alt: String
    func body(content: Content) -> some View {
        if alt.isEmpty {
            content.accessibilityHidden(true)
        } else {
            content
                .accessibilityLabel(alt)
                .accessibilityAddTraits(.isImage)
        }
    }
}

private struct ImageTintModifier: ViewModifier {
    let tintArgb: Int
    func body(content: Content) -> some View {
        if tintArgb != 0 {
            content.foregroundStyle(Color(argb: tintArgb))
        } else {
            content
        }
    }
}

/// `.fill` (cover/fill) spans the whole frame, so the frame-level rounded clip
/// from NodeStyleModifier already rounds the visible pixels. `.fit`
/// (contain/scale-down/none) letterboxes the content inside the frame, leaving
/// the frame's rounded corners out in the transparent margin — so round the
/// fitted content itself. Mirrors ClipRadiusModifier (RoundedRectangle;
/// rounded-full → 9999 clamps to a capsule).
private struct FittedCornerModifier: ViewModifier {
    let contentMode: ContentMode
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        if contentMode == .fit && cornerRadius > 0 {
            content.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
        }
    }
}

struct NativeUIEmptyRenderer: View {
    let node: NativeUINode
    var body: some View {
        EmptyView()
    }
}
