import SwiftUI
import UIKit

/// Where an image `src` actually points.
///
/// `src` reads like a web URL to whoever authored it, but SwiftUI has to know
/// whether to decode a file off disk or go out to the network — `URLSession`
/// can't load `file://` or bare filesystem paths at all.
///
/// Shared by every renderer that loads an image (the `<native:image>` element,
/// the list-item avatar / thumbnail slots) so a path means the same thing
/// wherever it's written.
enum NativeUIImageSource {
    /// A file on this device — load it through `NativeUIImageCache`.
    case local(path: String)
    /// A remote URL — download it through `NativeUIRemoteImageCache`.
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
/// SwiftUI re-evaluates `body` freely, so whatever a row does to draw a local
/// image it does per visible row, per evaluation, on the main thread. So the
/// main thread only ever looks in memory here: `image(atPath:)` is a lookup
/// by path. Checking the file, reading it and decoding it all happen in
/// `load(atPath:)`, off the main thread. Android works the same way: Coil
/// keys a file by its path and decodes it on an IO thread. `NativeUIRemoteImageCache`
/// is the remote equivalent.
///
/// Each entry remembers the file's modification date and size, and `load`
/// compares them before trusting it. `NativeUILocalImage` calls `load` each
/// time an image appears, so overwriting a file in place (re-taking an avatar
/// to the same path, an update replacing a `public/` asset) shows the new
/// bytes the next time the image comes on screen.
///
/// Images are decoded at the size they're drawn, not the file's size, as
/// Coil does: a 2400x1600 photo in a 318x212 pt frame is decoded at 954x636
/// pixels, about a sixth of the memory. There's one entry per path. A file
/// drawn at two sizes keeps the bigger decode, which serves the smaller frame
/// too.
enum NativeUIImageCache {
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        // ~5 full-screen 3x images, a couple of dozen photos in list rows,
        // or about a thousand avatars. NSCache also purges itself under
        // memory pressure.
        cache.totalCostLimit = 64 * 1024 * 1024

        return cache
    }()

    /// Loads in progress, so rows showing the same file share one read.
    @MainActor private static var loads: [String: Load] = [:]

    /// The decoded image for `path` if it's in memory, at whatever size it
    /// was decoded. Never touches the disk.
    static func image(atPath path: String) -> UIImage? {
        cache.object(forKey: path as NSString)?.image
    }

    /// The image at `path`, decoded big enough to fill `pixels` (or at the
    /// file's own size, if that's smaller). Checked against the file and
    /// decoded off the main thread when it's new, has changed, or was last
    /// decoded too small. nil when the file doesn't exist or isn't an image.
    /// Nothing is cached then, so a file that appears later loads the next
    /// time its image appears.
    @MainActor
    static func load(atPath path: String, filling pixels: CGSize) async -> UIImage? {
        let load = loads[path].flatMap { $0.fills(pixels) ? $0 : nil } ?? start(path, filling: pixels)
        load.waiting += 1

        let outcome = await withTaskCancellationHandler {
            await load.task.value
        } onCancel: {
            Task { @MainActor in load.leave() }
        }

        if loads[path] === load {
            loads[path] = nil
        }

        let key = path as NSString
        switch outcome {
        case .current(let entry):
            let cached = cache.object(forKey: key)
            if let cached, cached !== entry, cached.stamp == entry.stamp, cached.fills(entry.pixels) {
                // Another load decoded the same bytes at least as big.
                return cached.image
            }
            if cached !== entry {
                cache.setObject(entry, forKey: key, cost: entry.cost)
            }

            return entry.image
        case .missing:
            cache.removeObject(forKey: key)

            return nil
        case .cancelled:
            return nil
        }
    }

    @MainActor
    private static func start(_ path: String, filling pixels: CGSize) -> Load {
        let known = cache.object(forKey: path as NSString)
        let load = Load(path: path, pixels: pixels, task: Task.detached(priority: .userInitiated) {
            read(path, filling: pixels, known: known)
        })
        loads[path] = load

        return load
    }

    /// Runs off the main thread.
    private static func read(_ path: String, filling pixels: CGSize, known: Entry?) -> Outcome {
        if Task.isCancelled {
            return .cancelled
        }
        guard let stamp = Stamp(path: path) else {
            return .missing
        }
        if let known, known.stamp == stamp, known.fills(pixels) {
            return .current(known)
        }
        if Task.isCancelled {
            return .cancelled
        }
        // Reads the file but doesn't decode it. UIImage picks the file
        // (a name@3x.jpg beside name.jpg), its scale and its orientation.
        guard let file = UIImage(contentsOfFile: path) else {
            return .missing
        }

        return .current(decode(file, filling: pixels, stamp: stamp))
    }

    /// Decodes `file` at the smallest size that still fills `pixels`, or at
    /// its own size when it's no bigger than that. ImageIO scales while it
    /// decodes, so a big photo in a small frame is never in memory at full
    /// size. Filling rather than fitting means a contained image whose frame
    /// is a different shape can decode bigger than it's drawn, but never
    /// smaller, even when its frame isn't settled until the image arrives.
    ///
    /// UIImage decodes lazily, when it's first drawn, which is on the main
    /// thread. Both paths here hand back an image that's already decoded.
    private static func decode(_ file: UIImage, filling pixels: CGSize, stamp: Stamp) -> Entry {
        // Oriented, in pixels.
        let filePixels = CGSize(width: file.size.width * file.scale, height: file.size.height * file.scale)
        let fill = max(pixels.width / filePixels.width, pixels.height / filePixels.height)

        // The size has the file's own aspect ratio, so it reads the same
        // whether UIKit treats it as a box to fit, fill, or a longest side.
        if fill < 1,
           let thumbnail = file.preparingThumbnail(of: CGSize(width: (file.size.width * fill).rounded(.up), height: (file.size.height * fill).rounded(.up))),
           let cgImage = thumbnail.cgImage {
            // Drawn at the same size in points as the whole file would be,
            // so an image laid out at its natural size doesn't move.
            let scale = thumbnail.size.width * thumbnail.scale / file.size.width

            return Entry(image: UIImage(cgImage: cgImage, scale: scale, orientation: thumbnail.imageOrientation), stamp: stamp, isFullSize: false)
        }

        return Entry(image: file.preparingForDisplay() ?? file, stamp: stamp, isFullSize: true)
    }

    private enum Outcome {
        case current(Entry)
        case missing
        case cancelled
    }

    private final class Entry: @unchecked Sendable {
        let image: UIImage
        let stamp: Stamp
        /// Decoded at the file's own size, so there's nothing bigger to
        /// decode.
        let isFullSize: Bool

        init(image: UIImage, stamp: Stamp, isFullSize: Bool) {
            self.image = image
            self.stamp = stamp
            self.isFullSize = isFullSize
        }

        /// Decoded size in pixels, oriented as drawn.
        var pixels: CGSize {
            CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        }

        /// Whether this decode fills `target` without being scaled up. A
        /// pixel short is close enough: decoded sizes are rounded.
        func fills(_ target: CGSize) -> Bool {
            isFullSize || (pixels.width + 1 >= target.width && pixels.height + 1 >= target.height)
        }

        /// Decoded footprint, in bytes.
        var cost: Int {
            Int(pixels.width * pixels.height) * 4
        }
    }

    /// What a file looked like when it was read.
    private struct Stamp: Equatable {
        let modified: Date
        let size: Int

        init?(path: String) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? Int else {
                return nil
            }
            self.modified = modified
            self.size = size
        }
    }

    /// One read of a file, shared by every image waiting on it that it's big
    /// enough for. Cancelled when all of them have gone, so a fast scroll
    /// doesn't leave a queue of decodes for rows already off screen.
    @MainActor
    private final class Load {
        let path: String
        /// What it was started to fill.
        let pixels: CGSize
        let task: Task<Outcome, Never>
        var waiting = 0

        init(path: String, pixels: CGSize, task: Task<Outcome, Never>) {
            self.path = path
            self.pixels = pixels
            self.task = task
        }

        func fills(_ target: CGSize) -> Bool {
            pixels.width >= target.width && pixels.height >= target.height
        }

        func leave() {
            waiting -= 1
            guard waiting == 0 else {
                return
            }
            task.cancel()
            if NativeUIImageCache.loads[path] === self {
                NativeUIImageCache.loads[path] = nil
            }
        }
    }
}

/// A local file drawn through `NativeUIImageCache` without touching the disk
/// on the main thread. An image already in memory draws straight away;
/// otherwise `placeholder` holds its place while the file loads. Give the
/// placeholder the image's frame so nothing moves when the image arrives.
///
/// The file is decoded at the size this view is laid out at, which it
/// measures without changing: the placeholder's size before the image
/// arrives, the image's after. If it's laid out bigger later, a bigger
/// decode replaces the image, which keeps drawing until then. `fullSize`
/// decodes the whole file instead, for an image drawn at its own size
/// rather than its frame's (`object-none`).
struct NativeUILocalImage<Content: View, Placeholder: View>: View {
    private let path: String
    private let fullSize: Bool
    private let content: (UIImage) -> Content
    private let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale

    /// What the last load gave, held so an image the cache drops while it's
    /// on screen keeps drawing.
    @State private var loaded: (path: String, image: UIImage)?

    /// Laid-out size in points. Zero until the first layout.
    @State private var size: CGSize = .zero

    init(path: String, fullSize: Bool = false, @ViewBuilder content: @escaping (UIImage) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.path = path
        self.fullSize = fullSize
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        let request = Request(path: path, size: fullSize ? CGSize(width: CGFloat.infinity, height: .infinity) : size, scale: displayScale)

        // A ZStack rather than a Group: a Group would hand `.task` to each
        // branch, so swapping in the image would start a second load.
        ZStack {
            if let image = NativeUIImageCache.image(atPath: path) ?? held {
                content(image)
            } else {
                placeholder()
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: request) {
            // Nothing to fill before the first layout, and nothing drawn at
            // zero size.
            guard request.pixels.width > 0 || request.pixels.height > 0 else {
                return
            }
            let image = await NativeUIImageCache.load(atPath: path, filling: request.pixels)
            if !Task.isCancelled, image !== held {
                loaded = image.map { (path, $0) }
            }
        }
    }

    /// The file and the pixels it has to fill. Whole pixels, so a size that
    /// moves by a fraction of one doesn't start another load.
    private struct Request: Equatable {
        let path: String
        let pixels: CGSize

        init(path: String, size: CGSize, scale: CGFloat) {
            self.path = path
            self.pixels = CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
        }
    }

    private var held: UIImage? {
        loaded?.path == path ? loaded?.image : nil
    }
}

/// Decoded remote images in memory, and the downloads in flight.
///
/// `AsyncImage` keeps neither: each one starts its own download, and a
/// download that fails leaves it on its failure phase for good. That includes
/// one cancelled because the view was recreated mid-download, which a screen
/// that re-renders while its images load (a poll, a list update) does all the
/// time, so images on such a screen can stay blank until it's rebuilt. Here a
/// download belongs to the cache rather than to a view, so a recreated view
/// waits on the same one; a download that fails for a reason that can pass
/// (no connection, a timeout, a 5xx) is tried again a couple of times; and an
/// image that failed starts over the next time it comes on screen. The bytes
/// still go through the shared `URLCache`, as with `AsyncImage`.
enum NativeUIRemoteImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024

        return cache
    }()

    /// Downloads in progress, so views showing the same URL share one.
    @MainActor private static var loads: [URL: Task<UIImage?, Never>] = [:]

    /// The waits before the second and third tries.
    private static let retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1500)]

    /// The decoded image for `url` if it's in memory. Never touches the
    /// network.
    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// The image at `url`, downloaded once however many views wait on it. nil
    /// when every try failed. Nothing is cached then, so the next call tries
    /// again.
    @MainActor
    static func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) {
            return cached
        }

        let task = loads[url] ?? start(url)
        let image = await task.value

        if loads[url] == task {
            loads[url] = nil
        }

        return image
    }

    /// Not cancelled when the view that asked goes away, so a view recreated
    /// mid-download picks the download up instead of losing it.
    @MainActor
    private static func start(_ url: URL) -> Task<UIImage?, Never> {
        let task = Task.detached(priority: .userInitiated) {
            await fetch(url)
        }
        loads[url] = task

        return task
    }

    /// Runs off the main thread.
    private static func fetch(_ url: URL) async -> UIImage? {
        for attempt in 0...retryDelays.count {
            if attempt > 0 {
                try? await Task.sleep(for: retryDelays[attempt - 1])
            }

            switch await download(url) {
            case .image(let image):
                cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.scale * image.size.height * image.scale) * 4)

                return image
            case .permanent:
                return nil
            case .transient:
                continue
            }
        }

        return nil
    }

    private enum Download {
        case image(UIImage)
        /// Might work on another try: no connection, a timeout, a 408, 429 or 5xx.
        case transient
        /// Won't: a 404 and the like, or bytes that aren't an image.
        case permanent
    }

    private static func download(_ url: URL) async -> Download {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            return .transient
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500 ? .transient : .permanent
        }
        guard let image = UIImage(data: data) else {
            return .permanent
        }

        // Decoded here rather than on the main thread when it's first drawn.
        return .image(image.preparingForDisplay() ?? image)
    }
}

/// A remote image drawn through `NativeUIRemoteImageCache`. An image already
/// in memory draws straight away; otherwise `placeholder` holds its place,
/// told whether the download failed. A failed image tries again the next time
/// it comes on screen.
struct NativeUIRemoteImage<Content: View, Placeholder: View>: View {
    private let url: URL
    private let content: (UIImage) -> Content
    private let placeholder: (_ failed: Bool) -> Placeholder

    /// What the last load gave, held so an image the cache drops while it's
    /// on screen keeps drawing.
    @State private var loaded: (url: URL, image: UIImage)?

    @State private var failed: URL?

    init(url: URL, @ViewBuilder content: @escaping (UIImage) -> Content, @ViewBuilder placeholder: @escaping (_ failed: Bool) -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        // A ZStack rather than a Group, as in NativeUILocalImage: a Group
        // would hand `.task` to each branch.
        ZStack {
            if let image = NativeUIRemoteImageCache.image(for: url) ?? held {
                content(image)
            } else {
                placeholder(failed == url)
            }
        }
        .task(id: url) {
            let image = await NativeUIRemoteImageCache.load(url)
            if Task.isCancelled {
                return
            }
            if let image {
                loaded = (url, image)
                failed = nil
            } else {
                failed = url
            }
        }
    }

    private var held: UIImage? {
        loaded?.url == url ? loaded?.image : nil
    }
}

/// Avatar / thumbnail image for list rows: fills its frame, showing
/// `placeholder` while the image loads and when the source doesn't resolve.
/// Callers supply their own frame and clip shape.
struct NativeUIRowImage<Placeholder: View>: View {
    private let src: String
    private let contentMode: ContentMode
    private let placeholder: () -> Placeholder

    init(src: String, contentMode: ContentMode = .fill, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.src = src
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        switch NativeUIImageSource.resolve(src) {
        case .local(let path):
            NativeUILocalImage(path: path) { uiImage in
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } placeholder: {
                placeholder()
            }
        case .remote(let url):
            NativeUIRemoteImage(url: url) { uiImage in
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } placeholder: { _ in
                placeholder()
            }
        case .unresolvable:
            placeholder()
        }
    }
}
