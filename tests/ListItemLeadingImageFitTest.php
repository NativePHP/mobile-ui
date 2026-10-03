<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\ListItem;

function leadingImageProps(ListItem $item): array
{
    return $item->toArray(new CallbackRegistry)['props'];
}

it('crops to the square by default', function () {
    $item = new ListItem;
    $item->applyAttributes(['headline' => 'Row', 'leadingImage' => 'https://example.com/a.png']);

    expect(leadingImageProps($item))->not->toHaveKey('leading_image_fit');
});

it('resolves the fit attribute in both spellings', function (string $attribute) {
    $item = new ListItem;
    $item->applyAttributes(['headline' => 'Row', 'leadingImage' => 'https://example.com/a.png', $attribute => 'contain']);

    expect(leadingImageProps($item)['leading_image_fit'])->toBe('contain');
})->with(['leadingImageFit', 'leading-image-fit']);

it('ignores an empty fit', function () {
    expect(leadingImageProps(ListItem::make()->leadingImage('https://example.com/a.png', '')))
        ->not->toHaveKey('leading_image_fit');
});

it('is settable fluently', function () {
    expect(leadingImageProps(ListItem::make()->leadingImage('https://example.com/a.png', 'contain'))['leading_image_fit'])
        ->toBe('contain');
});
