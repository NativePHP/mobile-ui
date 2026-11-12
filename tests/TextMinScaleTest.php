<?php

/**
 * `min-scale` lets text that is too wide for its lines shrink, down to that
 * share of its font size, before it truncates. Core's text element sends it
 * as the `min_scale` prop; 1 (the default) never shrinks.
 */
it('shrinks the leaf and the composed iOS text down to min_scale', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextRenderer.swift');

    expect($source)
        ->toContain('let minScale = CGFloat(p.getFloat("min_scale", default: 1))')
        ->toMatch('/\.lineLimit\(maxLines > 0 \? maxLines : nil\)\s*(\/\/[^\n]*\s*)*\.minimumScaleFactor\(minScale\)/')
        ->toMatch('/\.lineLimit\(maxLines > 0 \? maxLines : nil\)\s*(\/\/[^\n]*\s*)*\.minimumScaleFactor\(CGFloat\(p\.getFloat\("min_scale", default: 1\)\)\)/');
});

it('auto-sizes plain Android text between min_scale of its size and its size', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/TextRenderer.kt');

    expect($source)
        ->toContain('import androidx.compose.foundation.text.TextAutoSize')
        ->toContain('val minScale = p.getFloat("min_scale", 1f)')
        ->toContain('autoSize = if (minScale < 1f) TextAutoSize.StepBased(minFontSize = (fontSize * minScale).sp, maxFontSize = fontSize.sp) else null');
});
