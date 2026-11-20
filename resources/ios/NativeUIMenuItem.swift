import SwiftUI
import UIKit

/// One row of a `:menu`, `:context-menu` or `:trailing-menu`: a
/// `top_bar_action` child of a pressable, button or list item. Android's
/// `renderAttachedMenuItem` draws the same rows.
///
/// A row is a Button with a label and an optional icon, or a Divider. It can
/// also carry:
///
/// - `image`: a picture, such as an account's avatar, drawn in place of the
///   icon. A remote URL, a device path or a path in the app's `public/`, as
///   for `<native:image>`. The icon shows until the picture has loaded, and
///   stays if it fails, so give a row both.
/// - `image_shape`: `circle` (the default) or `rounded`, a square with
///   rounded corners.
/// - `checked`: a tick beside the row, as on the option a menu has picked.
///   It's a Toggle, so iOS draws the tick where its own menus do.
///
/// A menu is a UIMenu underneath, which draws a snapshot of each row's image
/// and can't load or clip one itself. So `NativeUIMenuImages` fetches the
/// pictures as soon as whatever opens the menu is on screen (see
/// `nativeUIMenuImages`), and hands the rows ready-made images, already cut
/// to their shape.
struct NativeUIMenuItem: View {
    let item: NativeUINode
    @ObservedObject private var images = NativeUIMenuImages.shared

    var body: some View {
        if item.props.getBool("divider") {
            Divider()
        } else {
            let isDestructive = item.props.getBool("destructive")
            if item.props.getBool("checked") {
                Toggle(isOn: Binding(get: { true }, set: { _ in press() })) {
                    label
                }
            } else {
                Button(role: isDestructive ? .destructive : nil) {
                    press()
                } label: {
                    label
                }
                .tint(isDestructive ? .red : nil)
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        let text = item.props.getString("label", default: "")
        let icon = item.props.getString("icon", default: "")
        if let picture = images.image(for: item) {
            Label {
                Text(text)
            } icon: {
                Image(uiImage: picture).renderingMode(.original)
            }
        } else if !icon.isEmpty {
            Label { Text(text) } icon: { NativeIcon.image(icon) }
        } else {
            Text(text)
        }
    }

    private func press() {
        if item.onPress != 0 {
            NativeElementBridge.sendPressEvent(item.onPress, nodeId: item.id)
        }
    }
}

extension View {
    /// Fetches the pictures of a menu's rows while this view, the thing that
    /// opens the menu, is on screen, so they're ready by the time it opens.
    func nativeUIMenuImages(_ items: [NativeUINode]) -> some View {
        let wanted = items.compactMap(NativeUIMenuImages.Request.init)

        return task(id: wanted) {
            NativeUIMenuImages.shared.fetch(wanted)
        }
    }
}

/// The pictures menu rows show, cut to their shapes and sized for a menu.
/// Kept in memory for as long as the app runs. A picture that fails to load
/// isn't kept, so it's tried again the next time its menu comes on screen.
@MainActor
final class NativeUIMenuImages: ObservableObject {
    static let shared = NativeUIMenuImages()

    /// The size a menu draws a row's icon at.
    static let side: CGFloat = 24

    struct Request: Hashable, Sendable {
        let src: String
        let rounded: Bool

        init?(_ item: NativeUINode) {
            let src = item.props.getString("image", default: "")
            if item.props.getBool("divider") || src.isEmpty {
                return nil
            }
            self.src = src
            self.rounded = item.props.getString("image_shape", default: "circle") == "rounded"
        }
    }

    @Published private var images: [Request: UIImage] = [:]
    private var loading: Set<Request> = []

    func image(for item: NativeUINode) -> UIImage? {
        Request(item).flatMap { images[$0] }
    }

    func fetch(_ requests: [Request]) {
        for request in requests where images[request] == nil && !loading.contains(request) {
            loading.insert(request)
            Task {
                let picture = await Self.load(request)
                loading.remove(request)
                if let picture {
                    images[request] = picture
                }
            }
        }
    }

    private static func load(_ request: Request) async -> UIImage? {
        let scale: CGFloat = 3 // sharp on every screen, and tiny at this size
        let pixels = CGSize(width: side * scale, height: side * scale)
        let source: UIImage?

        switch NativeUIImageSource.resolve(request.src) {
        case .local(let path):
            source = await NativeUIImageCache.load(atPath: path, filling: pixels)
        case .remote(let url):
            let data = try? await URLSession.shared.data(from: url).0
            source = data.flatMap { UIImage(data: $0) }
        case .unresolvable:
            source = nil
        }

        guard let source, source.size.width > 0, source.size.height > 0 else {
            return nil
        }

        return cut(source, rounded: request.rounded, scale: scale)
    }

    /// Draws the picture filling a `side` square, as `object-cover` would,
    /// inside a circle or a rounded square. The menu draws it as it is, in
    /// its own colours.
    private static func cut(_ source: UIImage, rounded: Bool, scale: CGFloat) -> UIImage {
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let fill = max(side / source.size.width, side / source.size.height)
        let drawn = CGSize(width: source.size.width * fill, height: source.size.height * fill)
        let origin = CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)

        let picture = UIGraphicsImageRenderer(size: bounds.size, format: format).image { _ in
            let shape = rounded
                ? UIBezierPath(roundedRect: bounds, cornerRadius: side * 0.2)
                : UIBezierPath(ovalIn: bounds)
            shape.addClip()
            source.draw(in: CGRect(origin: origin, size: drawn))
        }

        return picture.withRenderingMode(.alwaysOriginal)
    }
}
