import Testing
@testable import NativeUILogic

@Suite struct NativeUIPullToRefreshTests {
    @Test func restsHiddenWithNoProgress() {
        let pull = NativeUIPullToRefresh()

        #expect(pull.progress == 0)
        #expect(pull.gap == 0)
        #expect(!pull.isRefreshing)
    }

    @Test func progressFollowsThePullUpToTheThreshold() {
        var pull = NativeUIPullToRefresh()
        pull.interactionChanged(interacting: true)

        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold / 2)
        #expect(pull.progress == 0.5)
        #expect(pull.gap == NativeUIPullToRefresh.threshold / 2)

        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold * 2)
        #expect(pull.progress == 1)
    }

    @Test func scrollingDownTheListIsNoPull() {
        var pull = NativeUIPullToRefresh()
        pull.scrolled(overscroll: -300)

        #expect(pull.progress == 0)
        #expect(pull.gap == 0)
    }

    @Test func releasingPastTheThresholdStartsARefresh() {
        var pull = NativeUIPullToRefresh()
        pull.interactionChanged(interacting: true)
        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold + 10)

        let started = pull.interactionChanged(interacting: false)
        #expect(started)
        #expect(pull.isRefreshing)
        #expect(pull.progress == 1)
    }

    @Test func releasingShortOfTheThresholdDoesNot() {
        var pull = NativeUIPullToRefresh()
        pull.interactionChanged(interacting: true)
        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold - 1)

        let started = pull.interactionChanged(interacting: false)
        #expect(!started)
        #expect(!pull.isRefreshing)
    }

    @Test func aBounceWithoutAFingerDoesNotRefresh() {
        var pull = NativeUIPullToRefresh()
        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold * 2)

        let started = pull.interactionChanged(interacting: false)
        #expect(!started)
        #expect(!pull.isRefreshing)
    }

    @Test func aPullDuringARefreshStartsNoOther() {
        var pull = NativeUIPullToRefresh()
        pull.interactionChanged(interacting: true)
        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold * 2)
        pull.interactionChanged(interacting: false)

        pull.interactionChanged(interacting: true)
        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold * 2)
        let startedAgain = pull.interactionChanged(interacting: false)
        #expect(!startedAgain)
        #expect(pull.isRefreshing)
    }

    @Test func theRefreshKeepsRoomAboveTheContentUntilItEnds() {
        var pull = NativeUIPullToRefresh()
        pull.interactionChanged(interacting: true)
        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold + 20)
        pull.interactionChanged(interacting: false)

        // The room shifts the content's top down by its height, so the same
        // spot reads that much less overscroll: the gap doesn't jump.
        #expect(pull.margin == NativeUIPullToRefresh.restHeight)
        pull.scrolled(overscroll: NativeUIPullToRefresh.threshold + 20 - NativeUIPullToRefresh.restHeight)
        #expect(pull.gap == NativeUIPullToRefresh.threshold + 20)

        pull.scrolled(overscroll: 0)
        #expect(pull.gap == NativeUIPullToRefresh.restHeight)

        pull.finishRefresh()
        #expect(!pull.isRefreshing)
        #expect(pull.margin == 0)
        #expect(pull.gap == 0)
    }

    @Test func theIndicatorDrawsInFromTheTopThenStaysNearIt() {
        var pull = NativeUIPullToRefresh()
        let size: Double = 40

        pull.scrolled(overscroll: 10)
        #expect(pull.indicatorTop(size: size) == 5 - 20)

        pull.scrolled(overscroll: NativeUIPullToRefresh.restHeight * 3)
        #expect(pull.indicatorTop(size: size) == NativeUIPullToRefresh.restHeight / 2 - 20)
    }
}
