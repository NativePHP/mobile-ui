<?php

it('sizes an iOS multiline input from its text view, in whole lines of the text view\'s line height', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');

    expect($source)
        // A Text mirror lays a custom font out at a different line height to
        // the UITextView, so a field capped by one shows part of a line.
        ->not->toContain('Text(text + " ")')
        ->toContain('.frame(height: editorSize.height(minLines: lower, maxLines: upper,')
        ->toContain('.background(NativeUITextEditorSizer(size: $editorSize))')
        ->toMatch('/let shown = CGFloat\(min\(max\(lines, minLines\), maxLines\)\)\s*return shown \* lineHeight \+ \(shown - 1\) \* lineSpacing/')
        ->toContain('lineHeight: font.lineHeight');
});

it('takes the iOS multiline text view\'s own insets off, so nothing it scrolls shows outside the field', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');

    expect($source)
        ->toContain('tv.textContainerInset = .zero')
        ->toContain('tv.textContainer.lineFragmentPadding = 0')
        ->not->toContain('.padding(.vertical, -8)');
});
