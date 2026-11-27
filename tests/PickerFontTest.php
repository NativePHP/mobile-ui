<?php

it('draws an Android picker value in the theme font at the field text size', function (string $file) {
    $source = file_get_contents(dirname(__DIR__)."/resources/android/{$file}");

    expect($source)
        ->toContain('textStyle = LocalTextStyle.current.copy(color = theme.onSurface, fontFamily = nuiDefaultFontFamily())')
        ->not->toContain('textStyle = TextStyle(');
})->with([
    'DatePickerRenderer.kt',
    'SelectRenderer.kt',
]);
