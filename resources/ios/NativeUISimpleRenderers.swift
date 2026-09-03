import SwiftUI
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
        switch NativeUIImageSource.resolve(src) {
        case .local(let path):
            // Local device file — camera capture, gallery selection, or an
            // asset shipped in the app's `public/` directory.
            // `AsyncImage`/`URLSession` can't load `file://` or bare
            // filesystem paths, so decode directly with UIImage (cached, and
            // HEIC/HEIF handled transparently — UIImage decodes them natively).
            if let uiImage = NativeUIImageCache.image(atPath: path) {
                tinted(Image(uiImage: uiImage), contentMode: contentMode, tintArgb: tintArgb, cornerRadius: cornerRadius)
            } else {
                Color.clear
            }
        case .remote(let url):
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
        case .unresolvable:
            Color.clear
        }
    }

    @ViewBuilder
    private func tinted(_ image: Image, contentMode: ContentMode, tintArgb: Int, cornerRadius: CGFloat) -> some View {
        let img = image
            .resizable()
            .aspectRatio(contentMode: contentMode)
        let styled = Group {
            if tintArgb != 0 {
                img.foregroundStyle(Color(argb: tintArgb))
            } else {
                img
            }
        }

        // `.fill` (cover/fill) spans the whole frame, so the frame-level
        // rounded clip from NodeStyleModifier already rounds the visible
        // pixels. `.fit` (contain/scale-down/none) letterboxes the image
        // inside the frame, leaving the frame's rounded corners out in the
        // transparent margin — so round the fitted image itself. Mirrors
        // ClipRadiusModifier (RoundedRectangle; rounded-full → 9999 clamps
        // to a capsule).
        if contentMode == .fit && cornerRadius > 0 {
            styled.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            styled
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

    private func resolveContentMode(_ fit: Int) -> ContentMode {
        switch fit {
        case 2: return .fill
        case 3: return .fill
        default: return .fit
        }
    }
}

struct NativeUIEmptyRenderer: View {
    let node: NativeUINode
    var body: some View {
        EmptyView()
    }
}
