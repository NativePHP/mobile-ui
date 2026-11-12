<?php

/**
 * Source contract of the pager's page context: the pages beside the one
 * showing stay composed (`beyondViewportPageCount = 1`), so a page needs
 * a way to know whether it is the page the pager is settled on before
 * anything on it — a list's `scroll_target` — acts on a bottom-tab
 * reselect. Pure source assertions in the ModalRendererTest style; the
 * plugin ships no JVM test environment, so the pager-state reads
 * themselves are proven on a device.
 */
test('provides the page context to every page of the pager', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/PagerRenderer.kt');

    // The context is provided around the whole page branch chain — a page
    // with a header, a page without one, a loading page, a placeholder —
    // not just the header branch LocalPagerHeader covers. A pager without
    // a header (a feed pager) is exactly the one that needs it.
    $provider = '/CompositionLocalProvider\(LocalPagerPage provides pageContext\) \{.*?'
        .'val child = pageByIndex\[index\].*?'
        .'if \(child != null && header != null\) \{.*?'
        .'LocalPagerHeader provides.*?'
        .'\} else if \(child != null\) \{\s*'
        .'NodeView\(node = child\).*?'
        .'\} else if \(hasMore && index >= count\) \{\s*'
        .'PagerLoadingPage\(\).*?'
        .'\} else \{\s*'
        .'PagerPlaceholder\(/s';

    expect(preg_match($provider, $source))->toBe(1)
        ->and($source)->toContain('val LocalPagerPage = compositionLocalOf<PagerPageContext?> { null }');
});

test('counts a page available only once the pager has settled on it', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/PagerRenderer.kt');

    // Conservative on purpose: targetPage alone commits as soon as a
    // swipe leans toward a page (so the page arriving would count as
    // available while still moving), currentPage alone still names the
    // page being left until the swipe passes halfway, and neither says
    // whether a settle is still running. All three together mean the
    // pager is at rest on this page, read live from the pager's own
    // state — never from a prop PHP sends, which is what lags the swipe.
    $predicate = '/fun isAvailable\(\): Boolean =\s*'
        .'!pagerState\.isScrollInProgress &&\s*'
        .'pagerState\.currentPage == page &&\s*'
        .'pagerState\.targetPage == page &&\s*'
        .'\(parent\?\.isAvailable\(\) \?: true\)/s';

    expect(preg_match($predicate, $source))->toBe(1)
        ->and(preg_match('/class PagerPageContext\(\s*val page: Int,\s*val pagerState: PagerState,\s*val parent: PagerPageContext\? = null,?\s*\)/s', $source))->toBe(1);
});

test('combines nested pagers through the parent context', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/PagerRenderer.kt');

    // A pager that is itself a page of a pager reads the outer context
    // at its own scope and threads it into each page's context, so a list
    // deep inside is available only while every pager around it is
    // settled on its page. The context is remembered per pager, page and
    // parent, so recomposition neither churns its identity nor leaves a
    // stale capture behind.
    expect($source)
        ->toContain('val parentPage = LocalPagerPage.current')
        ->toContain('remember(pagerState, index, parentPage) { PagerPageContext(index, pagerState, parentPage) }');
});
