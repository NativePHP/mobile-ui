<?php

use Native\Mobile\UI\TreeShaking\RendererMapper;

beforeEach(function () {
    $this->testManifest = createTestManifest();
});

it('maps component types to iOS renderer files', function () {
    $mapper = new RendererMapper($this->testManifest);

    $files = $mapper->getFilesToCopy(['button', 'text'], 'ios');

    expect($files)->toContain('NativeUIButtonRenderer.swift')
        ->and($files)->toContain('NativeUITextRenderer.swift');
});

it('maps component types to Android renderer files', function () {
    $mapper = new RendererMapper($this->testManifest);

    $files = $mapper->getFilesToCopy(['button', 'text'], 'android');

    expect($files)->toContain('ButtonRenderer.kt')
        ->and($files)->toContain('TextRenderer.kt');
});

it('always includes shared iOS files', function () {
    $mapper = new RendererMapper($this->testManifest);

    $files = $mapper->getFilesToCopy(['button'], 'ios');

    expect($files)->toContain('NativeUITheme.swift')
        ->and($files)->toContain('NativeUIFontResolver.swift')
        ->and($files)->toContain('NativeUIDrawerHost.swift')
        ->and($files)->toContain('NativeUITransitionFunctions.swift');
});

it('always includes shared Android files', function () {
    $mapper = new RendererMapper($this->testManifest);

    $files = $mapper->getFilesToCopy(['button'], 'android');

    expect($files)->toContain('NativeUITheme.kt')
        ->and($files)->toContain('NativeUIThemeFunctions.kt')
        ->and($files)->toContain('NativeUIFontResolver.kt')
        ->and($files)->toContain('NativeUIChromeInit.kt')
        ->and($files)->toContain('TextInputShared.kt');
});

it('returns unique files when components share renderers', function () {
    $mapper = new RendererMapper($this->testManifest);

    $files = $mapper->getFilesToCopy(['button', 'button', 'text'], 'ios');

    $buttonCount = count(array_filter($files, fn ($f) => $f === 'NativeUIButtonRenderer.swift'));

    expect($buttonCount)->toBe(1);
});

it('gets all component types from manifest', function () {
    $mapper = new RendererMapper($this->testManifest);

    $types = $mapper->getAllComponentTypes();

    expect($types)->toContain('button')
        ->and($types)->toContain('text')
        ->and($types)->toContain('column');
});

it('handles missing component gracefully', function () {
    $mapper = new RendererMapper($this->testManifest);

    $files = $mapper->getFilesToCopy(['nonexistent_component'], 'ios');

    // Should still include shared files
    expect($files)->toContain('NativeUITheme.swift');
});

it('throws exception for missing manifest', function () {
    expect(fn () => new RendererMapper('/nonexistent/path/manifest.json'))
        ->toThrow(RuntimeException::class, 'Manifest not found');
});

it('maps combined Android renderers to the file that defines them', function () {
    $mapper = new RendererMapper(dirname(__DIR__, 2).'/nativephp.json');

    $files = $mapper->getFilesToCopy(['column', 'spacer', 'top_bar'], 'android');

    expect($files)->toContain('ContainerRenderers.kt')
        ->and($files)->toContain('SimpleRenderers.kt')
        ->and($files)->toContain('NavRenderers.kt')
        ->and($files)->not->toContain('ColumnRenderer.kt')
        ->and($files)->not->toContain('SpacerRenderer.kt')
        ->and($files)->not->toContain('TopBarRenderer.kt');
});

it('maps combined iOS renderers to the file that defines them', function () {
    $mapper = new RendererMapper(dirname(__DIR__, 2).'/nativephp.json');

    $files = $mapper->getFilesToCopy(['image', 'pressable', 'top_bar'], 'ios');

    expect($files)->toContain('NativeUISimpleRenderers.swift')
        ->and($files)->toContain('NativeUINavRenderers.swift')
        ->and($files)->not->toContain('NativeUIImageRenderer.swift')
        ->and($files)->not->toContain('NativeUIPressableRenderer.swift');
});

it('throws exception for invalid JSON manifest', function () {
    $invalidManifest = tempnam(sys_get_temp_dir(), 'manifest_');
    file_put_contents($invalidManifest, '{ invalid json');

    expect(fn () => new RendererMapper($invalidManifest))
        ->toThrow(RuntimeException::class, 'Invalid JSON');

    @unlink($invalidManifest);
});

// Helper to create a test manifest
function createTestManifest(): string
{
    $manifest = [
        'components' => [
            [
                'type' => 'button',
                'ios_renderer' => 'NativeUIButtonRenderer',
                'android_renderer' => 'com.nativephp.plugins.native_ui.ui.ButtonRenderer',
            ],
            [
                'type' => 'text',
                'ios_renderer' => 'NativeUITextRenderer',
                'android_renderer' => 'com.nativephp.plugins.native_ui.ui.TextRenderer',
            ],
            [
                'type' => 'column',
                'ios_renderer' => 'NativeUIColumnRenderer',
                'android_renderer' => 'com.nativephp.plugins.native_ui.ui.ColumnRenderer',
            ],
        ],
    ];

    $file = tempnam(sys_get_temp_dir(), 'manifest_');
    file_put_contents($file, json_encode($manifest));
    register_shutdown_function(fn () => @unlink($file));

    return $file;
}
