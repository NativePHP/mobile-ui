<?php

it('uses the field color as the placeholder fallback while preserving explicit overrides', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');

    expect($source)
        ->toContain('let resolvedPlaceholderColor = placeholderColor ?? contentColor.opacity(0.6)')
        ->toContain('Text(placeholder).foregroundColor(resolvedPlaceholderColor)')
        ->not->toContain('UIColor.placeholderText');
});

it('uses the resolved placeholder color for secure, revealed, selected, and multiline inputs', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');
    preg_match_all('/(?:SecureField|TextField)\(placeholder, [^\n]+/', $source, $fields);

    expect($fields[0])->toHaveCount(4);

    foreach ($fields[0] as $field) {
        expect($field)->toContain('prompt: prompt');
    }

    expect($source)->toMatch('/if text\.isEmpty && !placeholder\.isEmpty\s*\{\s*Text\(placeholder\)\s*\.foregroundStyle\(resolvedPlaceholderColor\)/');
});
