<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Elements\BottomSheet;

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('bottom-sheet', BottomSheet::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function bottomSheetProps(array $attrs): array
{
    NativeElementCollector::open('bottom-sheet', $attrs);
    NativeElementCollector::close();

    return NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'] ?? [];
}

it('draws the handle over the content when asked', function (mixed $value) {
    expect(bottomSheetProps(['handle-over-content' => $value])['handle_over_content'])->toBeTrue();
})->with([true, 'true', '1']);

it('leaves the handle in its own strip by default', function () {
    expect(bottomSheetProps([]))->not->toHaveKey('handle_over_content')
        ->and(bottomSheetProps(['handleOverContent' => false])['handle_over_content'])->toBeFalse();
});
