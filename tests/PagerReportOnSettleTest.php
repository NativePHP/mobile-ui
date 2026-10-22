<?php

it('only reports from the idle phase on iOS when reporting on settle', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)
        ->toContain('reportOnSettle: p.getBool("report_on_settle")')
        ->toMatch('/leading = page\s*(\/\/[^\n]*\s*)*if !reportOnSettle \{\s*report\(page\)\s*\}/')
        ->toMatch('/guard phase == \.idle else \{ return \}\s*report\(leading\)/');
});

it('counts a programmatic jump as known to PHP on iOS', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIPagerRenderer.swift');

    expect($source)->toMatch('/reported = \[page\]\s*lastReported = page\s*position = page/');
});

it('reports the settled page on Android when reporting on settle', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/PagerRenderer.kt');

    expect($source)
        ->toContain('val reportOnSettle = p.getBool("report_on_settle", false)')
        ->toContain('snapshotFlow { if (reportOnSettle) pagerState.settledPage else pagerState.currentPage }');
});

it('reports a page on Android only when it is news to PHP', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/PagerRenderer.kt');

    expect($source)
        ->toContain('var lastReported by remember { mutableIntStateOf(requestedPage) }')
        ->toMatch('/reported\.add\(requestedPage\)\s*lastReported = requestedPage\s*pagerState\.scrollToPage\(requestedPage\)/')
        ->toMatch('/if \(lastReported != index\) \{\s*lastReported = index\s*reported\.add\(index\)/');
});
