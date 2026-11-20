<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Layouts\Builders\NavAction;

it('carries a menu row picture, its shape and its tick to the renderers', function () {
    $item = NavAction::make('post-as-nativephp')
        ->label('NativePHP')
        ->icon('building')
        ->image('https://avatars.githubusercontent.com/u/1?v=4')
        ->toElement()
        ->setProp('image_shape', 'rounded')
        ->setProp('checked', true);

    $props = $item->toArray(new CallbackRegistry)['props'];

    expect($props)
        ->toMatchArray([
            'image' => 'https://avatars.githubusercontent.com/u/1?v=4',
            'image_shape' => 'rounded',
            'checked' => true,
        ]);
});

it('draws every iOS menu row with the shared row', function () {
    $ios = dirname(__DIR__).'/resources/ios';

    foreach (['NativeUISimpleRenderers.swift', 'NativeUIButtonRenderer.swift', 'NativeUIListItemRenderer.swift'] as $file) {
        $source = file_get_contents("{$ios}/{$file}");

        expect($source)
            ->toContain('NativeUIMenuItem(item: item)')
            ->toContain('.nativeUIMenuImages(')
            ->not->toMatch('/private func (pressable|button|listItem)MenuItem/');
    }
});

it('gives an iOS menu row its picture, cut to shape, and a tick when checked', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIMenuItem.swift');

    expect($source)
        ->toContain('item.props.getString("image", default: "")')
        ->toContain('item.props.getString("image_shape", default: "circle") == "rounded"')
        ->toContain('if item.props.getBool("checked") {')
        ->toContain('Toggle(isOn: Binding(get: { true }, set: { _ in press() }))')
        ->toContain('UIBezierPath(ovalIn: bounds)')
        ->toContain('UIBezierPath(roundedRect: bounds, cornerRadius: side * 0.2)')
        ->toContain('picture.withRenderingMode(.alwaysOriginal)')
        // The icon stands in until the picture has loaded.
        ->toMatch('/if let picture = images\.image\(for: item\) \{.*?\} else if !icon\.isEmpty \{/s');
});

it('gives an Android menu row its picture, cut to shape, and a tick when checked', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/android/ContainerRenderers.kt');
    $start = strpos($source, 'internal fun renderAttachedMenuItem');
    $row = substr($source, $start, strpos($source, 'object CanvasRenderer') - $start);

    expect($row)
        ->toContain('item.props.getString("image", "")')
        ->toContain('item.props.getString("image_shape", "circle") == "rounded"')
        ->toContain('.clip(if (roundedImage) RoundedCornerShape(5.dp) else CircleShape)')
        ->toContain('loading = { icon() },')
        ->toContain('error = { icon() },')
        ->toMatch('/if \(isChecked\) \{\s*MaterialIcon\(\s*name = "check",/');
});
