<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Layouts\Builders\NavAction;

it('carries a menu row subtitle to the renderers', function () {
    $item = NavAction::make('post-as-simon')
        ->label('Simon')
        ->icon('person')
        ->toElement()
        ->setProp('subtitle', '@simon-hamp');

    $props = $item->toArray(new CallbackRegistry)['props'];

    expect($props)->toMatchArray([
        'label' => 'Simon',
        'subtitle' => '@simon-hamp',
    ]);
});

it('draws an iOS menu row subtitle as a second Text in every kind of row', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIMenuItem.swift');

    expect($source)
        ->toContain('item.props.getString("subtitle", default: "")')
        ->toMatch('/private func title\(_ text: String\) -> some View \{\s*let subtitle = .*?\s*Text\(text\)\s*if !subtitle\.isEmpty \{\s*Text\(subtitle\)\s*\}/s')
        // The picture row, the icon row and the plain row all use it.
        ->toMatch('/Label \{\s*title\(text\)\s*\} icon: \{\s*Image\(uiImage: picture\)/')
        ->toContain('Label { title(text) } icon: { NativeIcon.image(icon) }')
        ->toMatch('/\} else \{\s*title\(text\)\s*\}/')
        ->not->toMatch('/Label \{\s*Text\(text\)/');
});

it('draws an Android menu row subtitle as a smaller line under the label', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ContainerRenderers.kt');
    $start = strpos($source, 'internal fun renderAttachedMenuItem');
    $row = substr($source, $start, strpos($source, 'object CanvasRenderer') - $start);

    expect($row)
        ->toContain('item.props.getString("subtitle", "")')
        ->toMatch('/if \(itemSubtitle\.isNotEmpty\(\)\) \{\s*Column\(modifier = Modifier\.weight\(1f\)\) \{\s*Text\(\s*itemLabel,.*?style = MaterialTheme\.typography\.bodyLarge,\s*\)\s*Text\(\s*itemSubtitle,\s*fontFamily = nuiDefaultFontFamily\(\),\s*color = MaterialTheme\.colorScheme\.onSurfaceVariant,\s*style = MaterialTheme\.typography\.bodyMedium,/s');
});
