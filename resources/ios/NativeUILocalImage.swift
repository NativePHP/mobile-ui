import Foundation

/// Shared resolver for image sources that point at a file on the device
/// rather than a remote URL.
///
/// `AsyncImage` / `URLSession` cannot load `file://` URLs or bare filesystem
/// paths, so every renderer that accepts an image source has to decide
/// between decoding with `UIImage(contentsOfFile:)` and going through the
/// async loader. The `<image>` element and a list row's leading slots all
/// need that decision, so it lives here instead of being duplicated.
enum NativeUILocalImage {
    /// The local filesystem path for `src` (a `file://…` URL or an absolute
    /// `/…` path), or nil when `src` is a remote URL that should go through
    /// `AsyncImage`.
    static func path(for src: String) -> String? {
        if src.hasPrefix("file://") {
            return URL(string: src)?.path ?? String(src.dropFirst("file://".count))
        }
        if src.hasPrefix("/") {
            return src
        }
        return nil
    }
}
