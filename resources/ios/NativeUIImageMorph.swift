import SwiftUI
import UIKit

/// Where each image with a `ref` is drawn, so a modal can grow a picture
/// out of one (`morph-from`) and into another (`morph-to`) as it opens,
/// and back as it closes (see NativeUIModalRenderer).
///
/// An image reports once it has something to draw: the rect its pixels
/// cover in window points, with the transforms around it applied, and
/// the picture itself. That's the fitted rect for `fit="contain"`, and the
/// frame for the fits that fill it, so a copy drawn with aspect fill
/// across a rect moving between two reports matches both ends. Reports
/// are kept out of SwiftUI's change tracking: an image moving under a
/// finger reports every frame, and nothing redraws because of it.
@MainActor
final class NativeUIImageMorph: ObservableObject {
    static let shared = NativeUIImageMorph()

    private init() {}

    struct Drawn {
        /// The rect the image's pixels cover, in window points.
        let rect: CGRect
        let image: Image
        /// The corner radius it's clipped to.
        let radius: CGFloat
    }

    private var drawn: [String: Drawn] = [:]

    /// Waiting for an image to report, by ref.
    private var waiting: [String: [(Drawn) -> Void]] = [:]

    /// Refs whose images draw nothing while a copy of them is in flight.
    @Published private(set) var hidden: Set<String> = []

    func report(_ ref: String, _ entry: Drawn) {
        drawn[ref] = entry
        for done in waiting.removeValue(forKey: ref) ?? [] {
            done(entry)
        }
    }

    func forget(_ ref: String) {
        drawn.removeValue(forKey: ref)
    }

    /// Where `ref` is drawn, if any of it is on screen.
    func onScreen(_ ref: String) -> Drawn? {
        guard !ref.isEmpty, let entry = drawn[ref], !entry.rect.isEmpty else { return nil }
        return entry.rect.intersects(Self.screen) ? entry : nil
    }

    /// Hands over where `ref` is drawn as soon as it has reported, or nil
    /// once `timeout` passes without it.
    func whenDrawn(_ ref: String, timeout: TimeInterval, _ done: @escaping (Drawn?) -> Void) {
        if let entry = onScreen(ref) {
            done(entry)
            return
        }
        var answered = false
        waiting[ref, default: []].append { entry in
            guard !answered else { return }
            answered = true
            done(entry)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            guard !answered else { return }
            answered = true
            done(nil)
        }
    }

    func hide(_ refs: [String]) {
        hidden.formUnion(refs.filter { !$0.isEmpty })
    }

    func show(_ refs: [String]) {
        hidden.subtract(refs)
    }

    private static var screen: CGRect {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.bounds ?? UIScreen.main.bounds
    }
}

/// Reports a `ref`'d image's drawn rect (see NativeUIImageMorph). Applied
/// to the view that covers exactly the image's pixels.
struct NativeUIImageMorphReport: ViewModifier {
    let ref: String
    let image: Image
    let radius: CGFloat

    func body(content: Content) -> some View {
        if ref.isEmpty {
            content
        } else {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                    // rounded-full sends a huge radius; past half the shorter
                    // side it's a circle anyway, and a copy that shrinks from
                    // one should start rounding off straight away.
                    let rounded = min(radius, min(rect.width, rect.height) / 2)
                    NativeUIImageMorph.shared.report(ref, .init(rect: rect, image: image, radius: rounded))
                }
                .onDisappear { NativeUIImageMorph.shared.forget(ref) }
        }
    }
}

/// Hides a `ref`'d image while a copy of it is in flight.
struct NativeUIImageMorphHide: ViewModifier {
    let ref: String

    func body(content: Content) -> some View {
        if ref.isEmpty {
            content
        } else {
            content.modifier(Hiding(ref: ref))
        }
    }

    private struct Hiding: ViewModifier {
        let ref: String
        @ObservedObject private var morph = NativeUIImageMorph.shared

        func body(content: Content) -> some View {
            content.opacity(morph.hidden.contains(ref) ? 0 : 1)
        }
    }
}

/// A picture on its way between two drawn rects, drawn over the modal.
struct NativeUIImageFlight: Identifiable {
    let id = UUID()
    let from: NativeUIImageMorph.Drawn
    let to: NativeUIImageMorph.Drawn
    /// The image to draw: the larger of the two decodes where there is one.
    let image: Image
    let duration: TimeInterval
    /// Run once the copy is over `to`.
    let landed: () -> Void
}

/// Draws a flight in window points, over whatever it's laid over, and
/// sets off for `to` once it has drawn at `from`. Starting from its own
/// appearance rather than from whoever made it means the first frame is
/// always at the start, however the modal's own updates fall. Takes no
/// touches.
struct NativeUIImageFlightView: View {
    let flight: NativeUIImageFlight

    @State private var there = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let end = there ? flight.to : flight.from
            flight.image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: end.rect.width, height: end.rect.height)
                .clipShape(RoundedRectangle(cornerRadius: end.radius))
                .position(x: end.rect.midX - origin.x, y: end.rect.midY - origin.y)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.smooth(duration: flight.duration)) {
                there = true
            } completion: {
                flight.landed()
            }
        }
    }
}
