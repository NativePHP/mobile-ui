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
/// SwiftUI re-evaluates `body` freely, so whatever a row does to draw a local
/// image it does per visible row, per evaluation, on the main thread. So the
/// main thread only ever looks in memory here: `image(atPath:)` is a lookup
/// by path. Checking the file, reading it and decoding it all happen in
/// `load(atPath:)`, off the main thread. Android works the same way: Coil
/// keys a file by its path and decodes it on an IO thread. Remote images get
/// `URLCache` via `AsyncImage`; this is the local-file equivalent.
///
/// Each entry remembers the file's modification date and size, and `load`
/// compares them before trusting it. `NativeUILocalImage` calls `load` each
/// time an image appears, so overwriting a file in place (re-taking an avatar
/// to the same path, an update replacing a `public/` asset) shows the new
/// bytes the next time the image comes on screen.
enum NativeUIImageCache {
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        // ~4 full-screen 3x images, or several hundred list thumbnails.
        // NSCache also purges itself under memory pressure.
        cache.totalCostLimit = 64 * 1024 * 1024

        return cache
    }()

    /// Loads in progress, so rows showing the same file share one read.
    @MainActor private static var loads: [String: Load] = [:]

    /// The decoded image for `path` if it's in memory. Never touches the disk.
    static func image(atPath path: String) -> UIImage? {
        cache.object(forKey: path as NSString)?.image
    }

    /// The image at `path`, checked against the file and decoded off the main
    /// thread when it's new or has changed. nil when the file doesn't exist
    /// or isn't an image. Nothing is cached then, so a file that appears
    /// later loads the next time its image appears.
    @MainActor
    static func load(atPath path: String) async -> UIImage? {
        let load = loads[path] ?? start(path)
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
            if cache.object(forKey: key) !== entry {
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
    private static func start(_ path: String) -> Load {
        let known = cache.object(forKey: path as NSString)
        let load = Load(path: path, task: Task.detached(priority: .userInitiated) {
            read(path, known: known)
        })
        loads[path] = load

        return load
    }

    /// Runs off the main thread.
    private static func read(_ path: String, known: Entry?) -> Outcome {
        if Task.isCancelled {
            return .cancelled
        }
        guard let stamp = Stamp(path: path) else {
            return .missing
        }
        if let known, known.stamp == stamp {
            return .current(known)
        }
        if Task.isCancelled {
            return .cancelled
        }
        guard let image = UIImage(contentsOfFile: path) else {
            return .missing
        }

        // UIImage decodes lazily, when it's first drawn, which is on the
        // main thread. Decode here instead.
        return .current(Entry(image: image.preparingForDisplay() ?? image, stamp: stamp))
    }

    private enum Outcome {
        case current(Entry)
        case missing
        case cancelled
    }

    private final class Entry: @unchecked Sendable {
        let image: UIImage
        let stamp: Stamp

        init(image: UIImage, stamp: Stamp) {
            self.image = image
            self.stamp = stamp
        }

        /// Decoded footprint, in bytes.
        var cost: Int {
            Int(image.size.width * image.scale * image.size.height * image.scale) * 4
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

    /// One read of a file, shared by every image waiting on it. Cancelled
    /// when all of them have gone, so a fast scroll doesn't leave a queue of
    /// decodes for rows already off screen.
    @MainActor
    private final class Load {
        let path: String
        let task: Task<Outcome, Never>
        var waiting = 0

        init(path: String, task: Task<Outcome, Never>) {
            self.path = path
            self.task = task
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
struct NativeUILocalImage<Content: View, Placeholder: View>: View {
    private let path: String
    private let content: (UIImage) -> Content
    private let placeholder: () -> Placeholder

    /// What the last load gave, held so an image the cache drops while it's
    /// on screen keeps drawing.
    @State private var loaded: (path: String, image: UIImage)?

    init(path: String, @ViewBuilder content: @escaping (UIImage) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.path = path
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        // A ZStack rather than a Group: a Group would hand `.task` to each
        // branch, so swapping in the image would start a second load.
        ZStack {
            if let image = NativeUIImageCache.image(atPath: path) ?? held {
                content(image)
            } else {
                placeholder()
            }
        }
        .task(id: path) {
            let image = await NativeUIImageCache.load(atPath: path)
            if !Task.isCancelled, image !== held {
                loaded = image.map { (path, $0) }
            }
        }
    }

    private var held: UIImage? {
        loaded?.path == path ? loaded?.image : nil
    }
}

/// Avatar / thumbnail image for list rows: fills its frame, showing
/// `placeholder` while the image loads and when the source doesn't resolve.
/// Callers supply their own frame and clip shape.
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
            NativeUILocalImage(path: path) { uiImage in
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } placeholder: {
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
