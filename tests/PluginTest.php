<?php

beforeEach(function () {
    $this->pluginPath = dirname(__DIR__);
    $this->manifestPath = $this->pluginPath.'/nativephp.json';
});

describe('Plugin Manifest', function () {
    it('has a valid nativephp.json file', function () {
        expect(file_exists($this->manifestPath))->toBeTrue();

        $content = file_get_contents($this->manifestPath);
        $manifest = json_decode($content, true);

        expect(json_last_error())->toBe(JSON_ERROR_NONE);
    });

    it('has required fields', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        expect($manifest)->toHaveKeys(['namespace', 'components']);
        expect($manifest['namespace'])->toBe('NativeUI');
    });

    it('has valid components', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        expect($manifest['components'])->toBeArray()->not->toBeEmpty();

        foreach ($manifest['components'] as $component) {
            expect($component)->toHaveKeys(['type', 'element', 'blade']);
            // At least one platform renderer
            expect(
                ! empty($component['android_renderer']) || ! empty($component['ios_renderer'])
            )->toBeTrue();
        }
    });

    it('has button component', function () {
        $manifest = json_decode(file_get_contents($this->manifestPath), true);

        $button = collect($manifest['components'])->firstWhere('type', 'button');
        expect($button)->not->toBeNull();
        expect($button['element'])->toBe('Native\\Mobile\\UI\\Elements\\Button');
        expect($button['blade'])->toBe('Native\\Mobile\\UI\\Components\\Button');
        expect($button['android_renderer'])->not->toBeEmpty();
        expect($button['ios_renderer'])->not->toBeEmpty();
    });
});

describe('PHP Classes', function () {
    it('has Button Element class', function () {
        $file = $this->pluginPath.'/src/Elements/Button.php';
        expect(file_exists($file))->toBeTrue();

        $content = file_get_contents($file);
        expect($content)->toContain('extends Element');
        expect($content)->toContain("'button'");
        expect($content)->toContain('applyAttributes');
    });

    it('has Button Blade component class', function () {
        $file = $this->pluginPath.'/src/Components/Button.php';
        expect(file_exists($file))->toBeTrue();

        $content = file_get_contents($file);
        expect($content)->toContain('extends NativeBladeComponent');
        expect($content)->toContain("'button'");
    });

    it('has service provider', function () {
        $file = $this->pluginPath.'/src/NativeUIServiceProvider.php';
        expect(file_exists($file))->toBeTrue();
    });
});

describe('Native Renderers', function () {
    it('has Android Kotlin renderer', function () {
        $file = $this->pluginPath.'/resources/android/ButtonRenderer.kt';
        expect(file_exists($file))->toBeTrue();

        $content = file_get_contents($file);
        expect($content)->toContain('object ButtonRenderer');
        expect($content)->toContain('@Composable');
        expect($content)->toContain('fun Render(');
    });

    it('has iOS Swift renderer', function () {
        $file = $this->pluginPath.'/resources/ios/NativeUIButtonRenderer.swift';
        expect(file_exists($file))->toBeTrue();

        $content = file_get_contents($file);
        expect($content)->toContain('ButtonRenderer');
    });
});

describe('Composer Configuration', function () {
    it('has valid composer.json with nativephp-plugin type', function () {
        $composerPath = $this->pluginPath . '/composer.json';
        expect(file_exists($composerPath))->toBeTrue();

        $composer = json_decode(file_get_contents($composerPath), true);

        expect(json_last_error())->toBe(JSON_ERROR_NONE);
        expect($composer['type'])->toBe('nativephp-plugin');
    });
});
