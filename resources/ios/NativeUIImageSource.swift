import SwiftUI
import UIKit

/// Where an image `src` actually points.
///
/// `src` reads like a web URL to whoever authored it, but SwiftUI has to know
/// whether to decode a file off disk or go out to the network — `AsyncImage` /
/// `URLSession` can't load `file://` or bare filesystem paths at all.
///
/// Shared by every renderer that loads an image (the `<native:image>` element,
/// the list-item avatar / thumbnail slots) so a path means the same thing
/// wherever it's written.
enum NativeUIImageSource {
    /// A file on this device — load it through `NativeUIImageCache`.
    case local(path: String)
    /// A remote URL — stream through `AsyncImage`.
    case remote(url: URL)
    /// Empty, or a string that isn't a usable URL.
    case unresolvable

    /// Resolution rules, in order:
    /// - `file://…` URLs and absolute `/…` paths are device files — camera
    ///   captures, gallery picks, anything the app already holds a real path
    ///   for.
    /// - Anything else carrying a URL scheme (`https:`, `data:`) is remote.
    /// - Whatever is left is RELATIVE, which is what a web developer writes for
    ///   an asset shipped with the app, so it resolves against the Laravel
    ///   app's `public/` directory on device. Note the asymmetry with the web,
    ///   where a leading `/` is document-root-relative — here it stays an
    ///   absolute device path, since that's the only way to reach a captured
    ///   photo.
    static func resolve(_ src: String) -> NativeUIImageSource {
        if src.isEmpty {
            return .unresolvable
        }
        if src.hasPrefix("file://") {
            return .local(path: URL(string: src)?.path ?? String(src.dropFirst("file://".count)))
        }
        if src.hasPrefix("/") {
            return .local(path: src)
        }
        if let url = URL(string: src), url.scheme != nil {
            return .remote(url: url)
        }

        let relative = src.hasPrefix("./") ? String(src.dropFirst(2)) : src

        return .local(path: AppUpdateManager.shared.getAppPath() + "/public/" + relative)
    }
}

/// Decoded-image cache for local files.
///
/// `UIImage(contentsOfFile:)` re-reads the file on every call and SwiftUI
/// re-evaluates `body` freely, so a list scrolling through local thumbnails
/// would pay that cost per visible row, per evaluation, on the main thread.
/// Remote images get `URLCache` for free via `AsyncImage`; this is the
/// local-file equivalent. (Android needs no counterpart — Coil memory-caches
/// by model already.)
///
/// Keyed on path + modification date + size, so overwriting a file in place —
/// re-taking an avatar to the same path, an update replacing a `public/`
/// asset — serves the new bytes instead of a stale image.
enum NativeUIImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // ~4 full-screen 3x images, or several hundred list thumbnails.
        // NSCache also purges itself under memory pressure.
        cache.totalCostLimit = 64 * 1024 * 1024

        return cache
    }()

    static func image(atPath path: String) -> UIImage? {
        guard let key = cacheKey(for: path) else {
            return nil
        }
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: cost(of: image))

        return image
    }

    /// nil when the file doesn't exist, which costs one `stat` and caches
    /// nothing — an asset that only appears later still loads when it does.
    private static func cacheKey(for path: String) -> NSString? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int else {
            return nil
        }

        return "\(path)|\(modified.timeIntervalSince1970)|\(size)" as NSString
    }

    /// Decoded footprint from metadata alone — reaching for `cgImage` here
    /// would defeat UIKit's lazy decode.
    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale) * 4
    }
}

/// Avatar / thumbnail image for list rows: fills its frame, showing
/// `placeholder` while a remote image loads and when the source doesn't
/// resolve. Callers supply their own frame and clip shape.
struct NativeUIRowImage<Placeholder: View>: View {
    private let src: String
    private let placeholder: () -> Placeholder

    init(src: String, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.src = src
        self.placeholder = placeholder
    }

    var body: some View {
        switch NativeUIImageSource.resolve(src) {
        case .local(let path):
            if let uiImage = NativeUIImageCache.image(atPath: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        case .remote(let url):
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholder()
            }
        case .unresolvable:
            placeholder()
        }
    }
}
