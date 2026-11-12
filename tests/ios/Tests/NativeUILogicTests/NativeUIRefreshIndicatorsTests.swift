import SwiftUI
import Testing
@testable import NativeUILogic

@Suite(.serialized) struct NativeUIRefreshIndicatorsTests {
    init() { NativeUIRefreshIndicators.shared.reset() }

    @Test func findsAnIndicatorByTheNameItWasRegisteredUnder() {
        NativeUIRefreshIndicators.shared.register("probe") { _ in AnyView(EmptyView()) }

        #expect(NativeUIRefreshIndicators.shared.indicator(named: "probe") != nil)
    }

    @Test func findsNoIndicatorNobodyRegistered() {
        NativeUIRefreshIndicators.shared.register("probe") { _ in AnyView(EmptyView()) }

        #expect(NativeUIRefreshIndicators.shared.indicator(named: "missing") == nil)
        #expect(NativeUIRefreshIndicators.shared.indicator(named: "") == nil)
    }

    @Test func handsTheIndicatorItsScope() {
        var seen: NativeUIRefreshIndicatorScope?
        NativeUIRefreshIndicators.shared.register("probe") { scope in
            seen = scope
            return AnyView(EmptyView())
        }

        let options = decodeRefreshIndicatorOptions(#"{"asset":"animations/splash.lottie","speed":1.5,"loop":true}"#)
        _ = NativeUIRefreshIndicators.shared.indicator(named: "probe")?(
            NativeUIRefreshIndicatorScope(progress: 0.5, isRefreshing: false, options: options)
        )

        #expect(seen?.progress == 0.5)
        #expect(seen?.isRefreshing == false)
        #expect(seen?.options["asset"] as? String == "animations/splash.lottie")
        #expect(seen?.options["speed"] as? Double == 1.5)
        #expect(seen?.options["loop"] as? Bool == true)
    }

    @Test func readsMissingOrMalformedOptionsAsNone() {
        #expect(decodeRefreshIndicatorOptions("").isEmpty)
        #expect(decodeRefreshIndicatorOptions("not json").isEmpty)
        #expect(decodeRefreshIndicatorOptions("[1,2]").isEmpty)
    }
}
