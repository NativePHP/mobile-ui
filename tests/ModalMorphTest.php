<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\Modal;

it('carries a fade transition and the refs to morph between to the wire', function () {
    $modal = Modal::make();
    $modal->applyAttributes([
        'visible' => true,
        'transition' => 'fade',
        'morph-from' => 'thumb-7',
        'morph-to' => 'viewed-7',
    ]);

    expect($modal->getResolvedProps(new CallbackRegistry))
        ->toMatchArray([
            'visible' => true,
            'transition' => 'fade',
            'morph_from' => 'thumb-7',
            'morph_to' => 'viewed-7',
        ]);
});

it('leaves the slide up as it was', function () {
    $modal = Modal::make();
    $modal->applyAttributes(['visible' => true, 'transition' => 'slide']);

    expect($modal->getResolvedProps(new CallbackRegistry))
        ->not->toHaveKey('transition')
        ->not->toHaveKey('morph_from')
        ->not->toHaveKey('morph_to');
});

it('drops a morph ref that names nothing', function () {
    $props = Modal::make()->morphFrom('thumb-7')->morphFrom('')->morphTo('')->getResolvedProps(new CallbackRegistry);

    expect($props)->not->toHaveKey('morph_from')
        ->not->toHaveKey('morph_to');
});

it('fades on both platforms when it fades or morphs', function () {
    $ios = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIModalRenderer.swift');
    $android = file_get_contents(dirname(__DIR__).'/resources/android/ModalRenderer.kt');

    expect($ios)->toContain('node.props.getString("transition") == "fade" || !node.props.getString("morph_from").isEmpty')
        ->and($android)->toContain('node.props.getString("transition") == "fade" || node.props.getString("morph_from").isNotEmpty()');
});

it('reports where a ref\'d image is drawn on both platforms', function () {
    $ios = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUISimpleRenderers.swift');
    $android = file_get_contents(dirname(__DIR__).'/resources/android/ImageRenderer.kt');

    expect($ios)->toContain('NativeUIImageMorphReport(ref: ref, image: image, radius: cornerRadius)')
        ->toContain('.modifier(NativeUIImageMorphHide(ref: ref))')
        ->and($android)->toContain('NativeUIImageMorph.register(ref, morph)')
        ->toContain('NativeUIImageMorph.isHidden(ref)');
});
