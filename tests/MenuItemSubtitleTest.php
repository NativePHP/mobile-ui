<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Layouts\Builders\NavAction;

it('carries a menu row subtitle to the renderers', function () {
    $item = NavAction::make('post-as-simon')
        ->label('Simon')
        ->subtitle('@simon-hamp')
        ->icon('person')
        ->toElement();

    expect($item->toArray(new CallbackRegistry)['props'])->toMatchArray([
        'label' => 'Simon',
        'subtitle' => '@simon-hamp',
    ]);
});

it('leaves a menu row without a subtitle when it is empty', function (?string $subtitle) {
    $item = NavAction::make('post-as-simon')->label('Simon')->subtitle($subtitle)->toElement();

    expect($item->toArray(new CallbackRegistry)['props'])->not->toHaveKey('subtitle');
})->with([null, '']);

it('draws an iOS menu row subtitle as a second Text in every kind of row', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIMenuItem.swift');

    expect($source)
        ->toContain('item.props.getString("subtitle", default: "")')
        // The label, then the subtitle, then the picture or icon, side by
        // side, so the menu reads them as the row's title, subtitle and image.
        ->toMatch('/private var label: some View \{.*?Text\(text\)\s*if !subtitle\.isEmpty \{\s*Text\(subtitle\)\s*\}\s*if let picture = images\.image\(for: item\) \{\s*Image\(uiImage: picture\).*?\} else if !icon\.isEmpty \{\s*NativeIcon\.image\(icon\)\s*\}/s')
        // Ticked rows and plain rows both use it.
        ->toMatch('/Toggle\(isOn: .*?\) \{\s*label\s*\}/s')
        ->toMatch('/\} label: \{\s*label\s*\}/')
        // A menu drops a second Text nested in a Label's title, so the row
        // mustn't wrap its texts in a Label.
        ->not->toContain('Label {');
});

it('draws an Android menu row subtitle as a smaller line under the label', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ContainerRenderers.kt');
    $start = strpos($source, 'internal fun renderAttachedMenuItem');
    $row = substr($source, $start, strpos($source, 'object CanvasRenderer') - $start);

    expect($row)
        ->toContain('item.props.getString("subtitle", "")')
        ->toMatch('/if \(itemSubtitle\.isNotEmpty\(\)\) \{\s*Column\(modifier = Modifier\.weight\(1f\)\) \{\s*Text\(\s*itemLabel,.*?style = MaterialTheme\.typography\.bodyLarge,\s*\)\s*Text\(\s*itemSubtitle,\s*fontFamily = nuiDefaultFontFamily\(\),\s*color = MaterialTheme\.colorScheme\.onSurfaceVariant,\s*style = MaterialTheme\.typography\.bodyMedium,/s');
});
