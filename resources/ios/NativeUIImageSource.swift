import SwiftUI
import UIKit
import ImageIO

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
    /// A remote URL — download it through `NativeUIRemoteImageCache`, via
    /// `NativeUIRemoteImage`.
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
/// keys a file by its path and decodes it on an IO thread. Remote images go
/// through `NativeUIRemoteImageCache`, which decodes off the main thread too
/// but keeps their bytes on disk rather than decoded images in memory.
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

/// Downloaded and decoded remote images.
///
/// Bytes come through one `URLSession` with its own `URLCache` (2 MB in
/// memory, 50 MB on disk under Caches). The shared session `AsyncImage`
/// uses only has about 512 KB of memory and 10 MB of disk, so a grid of
/// product photos pushed itself out of it.
///
/// Image URLs are treated as immutable, the way Kingfisher, SDWebImage and
/// Coil (NativePHP on Android) treat them: once a response is on disk it's
/// used again without asking the server, even after its `max-age` has run
/// out. Plenty of image hosts send a short `max-age` and no ETag, and
/// honouring that refetched every photo a minute after it was first shown.
/// A response sent with `Cache-Control: no-store` is never written to disk,
/// so it's still downloaded every time. An image whose URL is reused for
/// changing content can ask for strict HTTP caching instead (`revalidate`),
/// which goes through URLSession's normal policy: fresh entries come from
/// disk, stale ones are revalidated or downloaded again.
///
/// Decoding is off the main thread, at the size the image is drawn. Each
/// view holds the image it's showing. Decoded images are otherwise kept only
/// in a small cache (4 MB, the last few card-sized images), so a screen
/// popped back to or a tab switched back to draws on its first frame rather
/// than flashing its placeholder while it decodes again from disk. A 16 MB
/// decoded cache cost about 30 MB of footprint on a measured shop journey,
/// and its second pass still missed it. Both the decoded cache and the
/// URLCache memory tier are emptied on a memory warning and when the app
/// goes to the background.
///
/// Every image waiting on the same URL shares one download, which is
/// cancelled only when none of them is waiting any more.
enum NativeUIRemoteImageCache {
    private static let memoryCapacity = 2 * 1024 * 1024

    private static let decodedCapacity = 4 * 1024 * 1024

    /// The last decode of each URL, costed by its decoded bytes.
    private static let decoded: NSCache<NSURL, Decoded> = {
        let cache = NSCache<NSURL, Decoded>()
        cache.totalCostLimit = decodedCapacity
        _ = trimmed

        return cache
    }()

    static let urlCache: URLCache = {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NativeUIImages", isDirectory: true)

        return URLCache(memoryCapacity: memoryCapacity, diskCapacity: 50 * 1024 * 1024, directory: directory)
    }()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = urlCache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        _ = trimmed

        return URLSession(configuration: configuration)
    }()

    /// Empties the decoded cache and the URLCache memory tier on a memory
    /// warning and when the app goes to the background. Setting the URLCache
    /// capacity to zero drops what's in memory and leaves the disk alone.
    /// Set up once, with whichever cache is used first.
    private static let trimmed: [NSObjectProtocol] = [
        UIApplication.didReceiveMemoryWarningNotification,
        UIApplication.didEnterBackgroundNotification,
    ].map { name in
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            decoded.removeAllObjects()
            urlCache.memoryCapacity = 0
            urlCache.memoryCapacity = memoryCapacity
        }
    }

    /// Downloads in progress, so images showing the same URL share one.
    @MainActor private static var downloads: [DownloadKey: Download] = [:]

    /// Decodes in progress, by URL and the size they fill.
    @MainActor private static var decodes: [String: Task<Decoded?, Never>] = [:]

    /// The last decode of `url` still in memory, and whether it fills
    /// `pixels` (zero before the first layout, which anything fills). Never
    /// touches the disk or network.
    @MainActor
    static func image(for url: URL, filling pixels: CGSize) -> (image: UIImage, fills: Bool)? {
        guard let entry = decoded.object(forKey: url as NSURL) else {
            return nil
        }
        let fills = entry.isFullSize
            || (pixels.width <= 0 && pixels.height <= 0)
            || (entry.pixels.width + 1 >= pixels.width && entry.pixels.height + 1 >= pixels.height)

        return (entry.image, fills)
    }

    /// The image at `url`, decoded big enough to fill `pixels` (or at its own
    /// size, if that's smaller). `revalidate` follows the server's HTTP
    /// caching instead of reusing whatever is on disk. Throws when the
    /// download fails or the bytes aren't an image, and `CancellationError`
    /// when the calling task is cancelled.
    @MainActor
    static func load(_ url: URL, filling pixels: CGSize, revalidate: Bool = false) async throws -> UIImage {
        let data = try await data(for: DownloadKey(url: url, revalidate: revalidate))
        try Task.checkCancellation()

        let key = "\(url.absoluteString)#\(pixels.width)x\(pixels.height)"
        let decode = decodes[key] ?? {
            let task = Task.detached(priority: .userInitiated) { decodeImage(data, filling: pixels) }
            decodes[key] = task

            return task
        }()
        let entry = await decode.value
        if decodes[key] == decode {
            decodes[key] = nil
        }
        guard let entry else {
            throw URLError(.cannotDecodeContentData)
        }
        // A full-screen photo would push out every card the cache holds.
        if entry.cost <= decodedCapacity / 2 {
            decoded.setObject(entry, forKey: url as NSURL, cost: entry.cost)
        }

        return entry.image
    }

    /// The bytes for `key`, through the shared download for it.
    @MainActor
    private static func data(for key: DownloadKey) async throws -> Data {
        let download: Download
        if let existing = downloads[key] {
            download = existing
        } else {
            download = Download(key: key)
            downloads[key] = download
            download.start()
        }
        let id = download.nextID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    download.join(id, continuation)
                }
            }
        } onCancel: {
            Task { @MainActor in download.leave(id) }
        }
    }

    /// Runs off the main thread.
    ///
    /// Unless `revalidate` is set, a successful response already on disk is
    /// used however old it is. `URLCache.cachedResponse(for:)` hands back
    /// stored responses whatever their freshness; it's URLSession's protocol
    /// policy that would have thrown an expired one away.
    nonisolated private static func fetch(_ key: DownloadKey) async throws -> Data {
        let request = URLRequest(url: key.url)
        if !key.revalidate, let cached = urlCache.cachedResponse(for: request) {
            if let http = cached.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return cached.data
            }
            // A cached error page would otherwise come back every time.
            urlCache.removeCachedResponse(for: request)
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            urlCache.removeCachedResponse(for: request)
            throw URLError(.badServerResponse)
        }

        return data
    }

    /// Decodes `data` at the smallest size that still fills `pixels`. Runs off
    /// the main thread.
    ///
    /// ImageIO thumbnails straight from the compressed bytes, so a big photo
    /// in a small frame is never in memory at full size. On the simulator a
    /// thumbnail costs more time per photo than a plain decode, so it's only
    /// used when the source is more than 1.5 times the size it's drawn at,
    /// where the memory it saves is worth it. Otherwise the whole image is
    /// decoded. Either way it comes back already decoded, so drawing it on
    /// the main thread doesn't decode it there. Animated images give their
    /// first frame, as `AsyncImage` did.
    nonisolated private static func decodeImage(_ data: Data, filling pixels: CGSize) -> Decoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber).map({ CGFloat($0.doubleValue) }),
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber).map({ CGFloat($0.doubleValue) }),
           width > 0, height > 0 {
            // EXIF orientations 5 to 8 turn the image on its side.
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let oriented = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
            let fill = max(pixels.width / oriented.width, pixels.height / oriented.height)

            if fill < 1 / 1.5 {
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: (max(oriented.width, oriented.height) * fill).rounded(.up),
                ] as CFDictionary
                if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                    // Drawn at the same size in points as the whole image
                    // would be (one point per pixel, as AsyncImage drew it),
                    // so an image laid out at its natural size doesn't move.
                    let scale = CGFloat(thumbnail.width) / oriented.width

                    return Decoded(image: UIImage(cgImage: thumbnail, scale: scale, orientation: .up), isFullSize: false)
                }
            }
        }

        guard let image = UIImage(data: data) else {
            return nil
        }

        return Decoded(image: image.preparingForDisplay() ?? image, isFullSize: true)
    }

    private final class Decoded: @unchecked Sendable {
        let image: UIImage
        /// Decoded at the image's own size, so there's nothing bigger to
        /// decode.
        let isFullSize: Bool

        init(image: UIImage, isFullSize: Bool) {
            self.image = image
            self.isFullSize = isFullSize
        }

        /// Decoded size in pixels, oriented as drawn.
        var pixels: CGSize {
            CGSize(width: (image.size.width * image.scale).rounded(), height: (image.size.height * image.scale).rounded())
        }

        /// Decoded footprint, in bytes.
        var cost: Int {
            Int(pixels.width * pixels.height) * 4
        }
    }

    /// A URL and how its cache is used. Strict and immutable loads of one URL
    /// don't share a download: an immutable one may be answered from disk.
    private struct DownloadKey: Hashable, Sendable {
        let url: URL
        let revalidate: Bool
    }

    /// One download, shared by every image waiting on its URL.
    ///
    /// When the last of them stops waiting, the request carries on for a
    /// moment before it's cancelled. A screen that re-renders while it loads
    /// rebuilds its images, and the new image asks for the same URL straight
    /// after the old one gave up: it joins this request rather than starting
    /// another. A fast scroll still cancels the rows it left behind.
    @MainActor
    private final class Download {
        let key: DownloadKey
        private var task: Task<Void, Never>?
        private var waiters: [Int: CheckedContinuation<Data, Error>] = [:]
        private var lastID = 0
        private var finished = false

        init(key: DownloadKey) {
            self.key = key
        }

        func start() {
            let key = key
            task = Task {
                let result: Result<Data, Error>
                do {
                    result = .success(try await NativeUIRemoteImageCache.fetch(key))
                } catch {
                    result = .failure(error)
                }
                self.finish(result)
            }
        }

        func nextID() -> Int {
            lastID += 1

            return lastID
        }

        func join(_ id: Int, _ continuation: CheckedContinuation<Data, Error>) {
            waiters[id] = continuation
        }

        func leave(_ id: Int) {
            guard let continuation = waiters.removeValue(forKey: id) else {
                return
            }
            continuation.resume(throwing: CancellationError())
            guard waiters.isEmpty else {
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard self.waiters.isEmpty, !self.finished else {
                    return
                }
                self.task?.cancel()
                self.forget()
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            finished = true
            forget()
            let waiting = waiters
            waiters = [:]
            for continuation in waiting.values {
                continuation.resume(with: result)
            }
        }

        private func forget() {
            if NativeUIRemoteImageCache.downloads[key] === self {
                NativeUIRemoteImageCache.downloads[key] = nil
            }
        }
    }
}

/// A remote image drawn through `NativeUIRemoteImageCache`. Callers get an
/// `AsyncImagePhase`, as they did from `AsyncImage`: `.empty` while it
/// loads, `.success` with the image, `.failure` once it has run out of tries.
/// An image still in the small decoded cache draws on the first frame.
///
/// The image is decoded at the size this view is laid out at, measured the
/// way `NativeUILocalImage` measures it. `fullSize` decodes the whole image
/// instead, for an image drawn at its own size (`object-none`). `revalidate`
/// follows the server's HTTP caching rather than reusing what's on disk.
///
/// A failed download is tried again after 0.5 s and then 1.5 s. After that
/// the image stays failed until it next comes on screen. A load cancelled
/// because this view went away or changed its request isn't tried again
/// from here: the view that replaces it starts its own, and joins the
/// download if it's still running.
struct NativeUIRemoteImage<Content: View>: View {
    // Computed: a generic type can't have a stored static.
    private static var retryDelays: [Duration] { [.milliseconds(500), .milliseconds(1500)] }

    private let url: URL
    private let fullSize: Bool
    private let revalidate: Bool
    private let content: (AsyncImagePhase) -> Content

    @Environment(\.displayScale) private var displayScale

    /// What the last load gave. Kept while a new size loads, so the image
    /// doesn't drop back to its placeholder when its frame changes.
    @State private var loaded: (url: URL, image: UIImage)?

    /// The error once the image has run out of tries.
    @State private var failure: (url: URL, error: Error)?

    /// Laid-out size in points. Zero until the first layout.
    @State private var size: CGSize = .zero

    init(url: URL, fullSize: Bool = false, revalidate: Bool = false, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.fullSize = fullSize
        self.revalidate = revalidate
        self.content = content
    }

    var body: some View {
        let request = Request(url: url, size: fullSize ? CGSize(width: CGFloat.infinity, height: .infinity) : size, scale: displayScale)

        // A ZStack rather than a Group: a Group would hand `.task` to each
        // branch, so swapping in the image would start a second load.
        ZStack {
            content(phase)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: request) {
            // Nothing to fill before the first layout.
            guard request.pixels.width > 0 || request.pixels.height > 0 else {
                return
            }
            if !revalidate {
                if let held, Self.fills(held, request.pixels) {
                    return
                }
                if let cached = NativeUIRemoteImageCache.image(for: url, filling: request.pixels), cached.fills {
                    loaded = (url, cached.image)

                    return
                }
            }
            failure = nil
            var failures = 0
            while !Task.isCancelled {
                do {
                    let image = try await NativeUIRemoteImageCache.load(url, filling: request.pixels, revalidate: revalidate)
                    if !Task.isCancelled {
                        loaded = (url, image)
                    }

                    return
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    if failures == Self.retryDelays.count {
                        failure = (url, error)

                        return
                    }
                    try? await Task.sleep(for: Self.retryDelays[failures])
                    failures += 1
                }
            }
        }
    }

    /// What this view holds, or else the last decode in memory, so a view
    /// rebuilt on screen draws on its first frame. A strict (`revalidate`)
    /// image still loads after showing it.
    private var phase: AsyncImagePhase {
        if let image = held ?? NativeUIRemoteImageCache.image(for: url, filling: .zero)?.image {
            return .success(Image(uiImage: image))
        }
        if let failure, failure.url == url {
            return .failure(failure.error)
        }

        return .empty
    }

    /// Whether `image` fills `pixels` without being scaled up. A pixel short
    /// is close enough: decoded sizes are rounded.
    private static func fills(_ image: UIImage, _ pixels: CGSize) -> Bool {
        image.size.width * image.scale + 1 >= pixels.width && image.size.height * image.scale + 1 >= pixels.height
    }

    /// The URL and the pixels it has to fill. Whole pixels, so a size that
    /// moves by a fraction of one doesn't start another load.
    private struct Request: Equatable {
        let url: URL
        let pixels: CGSize

        init(url: URL, size: CGSize, scale: CGFloat) {
            self.url = url
            self.pixels = CGSize(width: (size.width * scale).rounded(.up), height: (size.height * scale).rounded(.up))
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
            NativeUIRemoteImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder()
                }
            }
        case .unresolvable:
            placeholder()
        }
    }
}
