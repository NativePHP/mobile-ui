import SwiftUI
import UIKit

struct NativeUIPressableRenderer: View {
    let node: NativeUINode
    var body: some View {
        // `:menu` and `:context-menu` items ride along as `top_bar_action`
        // children. They're for the menu only: laid out with the content,
        // each would take a share of the pressable's gap.
        let content = node.children.filter { $0.type != "top_bar_action" }
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
                NativeUIColumnRenderer(node: node, children: content)
                    .contentShape(Rectangle())
            }
        } else if node.props.getBool("has_context_menu") {
            // `:context-menu` attached — the same items, opened by a long
            // press. The tap stays core's `@press`. SwiftUI's context menu
            // lifts the pressable out of the screen and plays the haptic,
            // as a long press on a row does anywhere in iOS.
            let items = node.children.filter { $0.type == "top_bar_action" }
            NativeUIColumnRenderer(node: node, children: content)
                .contextMenu {
                    ForEach(items) { item in
                        pressableMenuItem(item)
                    }
                }
        } else {
            NativeUIColumnRenderer(node: node, children: content)
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
                Label { Text(label) } icon: { NativeIcon.image(icon) }
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle().fill(lineColor).frame(height: 1)
    }

    /// `border-*` colours the rule (`dark:border-*` in dark mode). Without
    /// one, a `bg-*` colour is the rule: NodeStyleModifier already paints the
    /// node's background (and its `dark:bg-*` variant) across this 1pt frame,
    /// so the line stays clear instead of covering it with the separator.
    /// Neither falls back to the system separator.
    private var lineColor: Color {
        let dark = colorScheme == .dark
        let darkBorder = dark ? node.props.getColor("dark_border_color", default: 0) : 0
        let borderArgb = darkBorder != 0 ? darkBorder : (node.style?.borderColor ?? 0)
        if borderArgb != 0 {
            return Color(argb: borderArgb)
        }

        let darkBg = dark ? node.props.getColor("dark_bg_color", default: 0) : 0
        if darkBg != 0 || (node.style?.bgColor ?? 0) != 0 {
            return .clear
        }

        return Color(uiColor: .separator)
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
        // No `fit` prop means no `object-*` class: contain, as on Android.
        let fit = ImageFit(rawValue: p.getInt("fit", default: ImageFit.contain.rawValue)) ?? .contain
        let tintArgb = p.getColor("tint_color", default: 0)
        let cornerRadius = CGFloat(node.style?.borderRadius ?? 0)
        let alt = p.getString("alt")

        if fit == .contain {
            // Contain (the default, object-contain, object-scale-down): the
            // image is letterboxed and never overflows, so render it directly.
            // Without an explicit height the resizable + `.aspectRatio(.fit)`
            // image self-sizes to its source's aspect ratio — i.e. a bare
            // `<image class="w-full">` lays out at its natural ratio like an
            // HTML <img>. Inside a definite frame, `.frame(maxWidth:maxHeight:)`
            // takes that whole frame and centers the letterboxed image, as
            // CSS's default `object-position` does; without it the node's own
            // frame leaves the image in its top-leading corner. Where the
            // proposal leaves a dimension open it takes the image's size, so
            // self-sizing is unchanged.
            imageContent(src: src, fit: fit, tintArgb: tintArgb, cornerRadius: cornerRadius)
                .modifier(ImageAltModifier(alt: alt))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Cover, fill and none (object-cover, object-fill, object-none):
            // the image fills its frame, is stretched to it, or keeps its own
            // size, and cover and none can draw past the frame, so clip to it.
            // `ImageFrameLayout` (applied in `tinted`) gives the image view the
            // frame's size and centers the image in it.
            imageContent(src: src, fit: fit, tintArgb: tintArgb, cornerRadius: cornerRadius)
                .clipped()
                .modifier(ImageAltModifier(alt: alt))
        }
    }

    @ViewBuilder
    private func imageContent(src: String, fit: ImageFit, tintArgb: Int, cornerRadius: CGFloat) -> some View {
        switch NativeUIImageSource.resolve(src) {
        case .local(let path):
            // Local device file — camera capture, gallery selection, or an
            // asset shipped in the app's `public/` directory.
            // `AsyncImage`/`URLSession` can't load `file://` or bare
            // filesystem paths, so decode with UIImage (cached, off the main
            // thread, at the size it's drawn, and HEIC/HEIF handled
            // transparently — UIImage decodes them natively). Until it
            // arrives, the clear placeholder takes the element's frame, so a
            // sized image doesn't move anything. None draws the image at its
            // own size, however small the frame, so it needs the whole file.
            NativeUILocalImage(path: path, fullSize: fit == .none) { uiImage in
                tinted(Image(uiImage: uiImage), fit: fit, tintArgb: tintArgb, cornerRadius: cornerRadius)
            } placeholder: {
                Color.clear
            }
        case .remote(let url):
            // Remote URL (http/https) — load asynchronously, and try again
            // if the download fails.
            NativeUIRemoteImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    tinted(image, fit: fit, tintArgb: tintArgb, cornerRadius: cornerRadius)
                case .failure:
                    Color.clear
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                @unknown default:
                    Color.clear
                }
            }
        case .unresolvable:
            Color.clear
        }
    }

    @ViewBuilder
    private func tinted(_ image: Image, fit: ImageFit, tintArgb: Int, cornerRadius: CGFloat) -> some View {
        let styled = Group {
            if tintArgb != 0 {
                sized(image, fit: fit).foregroundStyle(Color(argb: tintArgb))
            } else {
                sized(image, fit: fit)
            }
        }

        // Contain letterboxes the image inside the frame, leaving the frame's
        // rounded corners out in the transparent margin — so round the fitted
        // image itself. Mirrors ClipRadiusModifier (RoundedRectangle;
        // rounded-full → 9999 clamps to a capsule). Cover and fill span the
        // whole frame, so the frame-level rounded clip from NodeStyleModifier
        // already rounds the visible pixels, and none keeps its own size
        // inside that same clip, as on Android.
        if fit != .contain {
            ImageFrameLayout { styled }
        } else if cornerRadius > 0 {
            styled.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            styled
        }
    }

    /// Sizes the image for its fit, after CSS `object-fit`.
    @ViewBuilder
    private func sized(_ image: Image, fit: ImageFit) -> some View {
        switch fit {
        case .contain:
            image.resizable().aspectRatio(contentMode: .fit)
        case .cover:
            image.resizable().aspectRatio(contentMode: .fill)
        case .fill:
            // Stretched to the frame, whatever the image's own shape.
            image.resizable()
        case .none:
            // The image's own size in points: its pixel size for a plain
            // file, half or a third of it for an @2x or @3x file.
            image
        }
    }

    /// HTML `<img alt>` semantics for VoiceOver: an `alt` prop makes the
    /// image a labeled image element; no `alt` marks it decorative and hides
    /// it from the accessibility tree entirely.
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

    /// Wire values of the `fit` prop, matching PHP's `ImageFit` enum.
    private enum ImageFit: Int {
        case none = 0
        case contain = 1
        case cover = 2
        case fill = 3
    }

    /// Frames a cover, fill or none image. A definite frame is taken as is,
    /// with the image centered in it and free to overflow until `body`
    /// clips it. Sizing the view from the image instead let a higher-res
    /// decoded source report an intrinsic size larger than the frame, and
    /// the image painted beyond its declared frame onto siblings.
    ///
    /// A dimension the frame leaves open (`w-full` with no height in a list)
    /// comes from the image's aspect ratio, as contain and an HTML <img> do.
    /// With both open, as in a flex container's first unconstrained measure,
    /// it answers 10pt like an empty view, so a big photo's own size can't
    /// leak into the layout.
    private struct ImageFrameLayout: Layout {
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let natural = subviews.first?.sizeThatFits(.unspecified) ?? .zero
            let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }

            switch (width, height) {
            case let (width?, height?):
                return CGSize(width: width, height: height)
            case let (width?, nil) where natural.width > 0:
                return CGSize(width: width, height: width * natural.height / natural.width)
            case let (nil, height?) where natural.height > 0:
                return CGSize(width: height * natural.width / natural.height, height: height)
            default:
                return proposal.replacingUnspecifiedDimensions()
            }
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            subviews.first?.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}

struct NativeUIEmptyRenderer: View {
    let node: NativeUINode
    var body: some View {
        EmptyView()
    }
}
