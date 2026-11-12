<?php

it('draws an Android picker value in the theme font', function (string $file) {
    $source = file_get_contents(dirname(__DIR__)."/resources/android/{$file}");

    expect($source)
        ->toContain('textStyle = TextStyle(color = theme.onSurface, fontFamily = nuiDefaultFontFamily())')
        ->not->toContain('textStyle = TextStyle(color = theme.onSurface),');
})->with([
    'DatePickerRenderer.kt',
    'SelectRenderer.kt',
]);
