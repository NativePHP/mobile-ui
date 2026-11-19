import Foundation
import SwiftUI

/// What a registered pull-to-refresh indicator draws from.
struct NativeUIRefreshIndicatorScope {
    /// How far the list is pulled, from 0 at rest to 1 at the refresh
    /// threshold; 1 while refreshing.
    let progress: Double
    /// Whether the refresh the pull triggered is running.
    let isRefreshing: Bool
    /// The `refresh-indicator-options` the screen gave, decoded from JSON.
    let options: [String: Any]
}

/// Pull-to-refresh indicators other plugins provide, by the name a list's
/// `refresh-indicator` attribute gives. Register from the plugin's
/// `ios.init_function`, before the first render:
///
///     NativeUIRefreshIndicators.shared.register("lottie") { scope in AnyView(…) }
///
/// A list naming a registered indicator runs its own pull-to-refresh, since
/// `.refreshable` only shows the system spinner, and draws the indicator in
/// a 40pt square in the gap the pull opens above its rows. A list naming an
/// indicator nobody registered keeps `.refreshable`.
final class NativeUIRefreshIndicators {
    typealias Indicator = (NativeUIRefreshIndicatorScope) -> AnyView

    static let shared = NativeUIRefreshIndicators()

    private var indicators: [String: Indicator] = [:]
    private let lock = NSLock()

    func register(_ name: String, indicator: @escaping Indicator) {
        lock.lock(); defer { lock.unlock() }
        indicators[name] = indicator
    }

    func indicator(named name: String) -> Indicator? {
        lock.lock(); defer { lock.unlock() }
        return name.isEmpty ? nil : indicators[name]
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        indicators = [:]
    }
}

/// A list's `refresh_indicator_options`, a JSON object; none when missing or
/// malformed.
func decodeRefreshIndicatorOptions(_ json: String) -> [String: Any] {
    guard !json.isEmpty, let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}
