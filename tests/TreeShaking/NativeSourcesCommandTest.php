<?php

use Illuminate\Support\Facades\Artisan;
use Native\Mobile\UI\NativeUIServiceProvider;
use Orchestra\Testbench\TestCase;

uses(TestCase::class);

function nativeSourcesProviders($app): array
{
    return [NativeUIServiceProvider::class];
}

function decodeNativeSourcesOutput(): array
{
    $output = trim(Artisan::output());
    $json = json_decode($output, true);

    expect($json)->toBeArray("native_sources stdout was not JSON: {$output}");

    return $json;
}

function allPlatformFiles(string $platform): array
{
    $ext = $platform === 'ios' ? 'swift' : 'kt';
    $dir = dirname(__DIR__, 2)."/resources/{$platform}";

    return array_values(array_map('basename', glob("{$dir}/*.{$ext}") ?: []));
}

beforeEach(function () {
    $this->app->register(NativeUIServiceProvider::class);

    $views = base_path('resources/views');
    if (is_dir($views)) {
        foreach (glob($views.'/*.blade.php') ?: [] as $file) {
            @unlink($file);
        }
    }
});

it('accepts the extra options core passes and prints JSON for android', function () {
    config(['native-ui.tree_shaking.mode' => 'all']);

    $exit = Artisan::call('nativephp:native-ui:native-sources', [
        '--platform' => 'android',
        '--build-path' => '/tmp/build',
        '--plugin-path' => dirname(__DIR__, 2),
        '--app-id' => 'com.example.app',
        '--config' => '{}',
        '--plugins' => '[]',
    ]);

    expect($exit)->toBe(0);

    $files = decodeNativeSourcesOutput();
    $expected = allPlatformFiles('android');

    expect($files)->toEqualCanonicalizing($expected)
        ->and($files)->toContain('ButtonRenderer.kt')
        ->and($files)->toContain('ContainerRenderers.kt');
});

it('in all mode lists every iOS source file', function () {
    config(['native-ui.tree_shaking.mode' => 'all']);

    Artisan::call('nativephp:native-ui:native-sources', ['--platform' => 'ios']);

    expect(decodeNativeSourcesOutput())->toEqualCanonicalizing(allPlatformFiles('ios'));
});

it('in auto mode lists only files for used components plus shared utilities', function () {
    config([
        'native-ui.tree_shaking.enabled' => true,
        'native-ui.tree_shaking.mode' => 'auto',
        'native-ui.tree_shaking.include_all_on_uncertainty' => true,
    ]);

    $views = base_path('resources/views');
    if (! is_dir($views)) {
        mkdir($views, 0755, true);
    }
    file_put_contents("{$views}/welcome.blade.php", <<<'BLADE'
<native:button label="Go" />
<native:text>Hello</native:text>
<native:column>
    <native:image src="logo.png" />
    <native:outlined-text-input />
</native:column>
BLADE);

    Artisan::call('nativephp:native-ui:native-sources', ['--platform' => 'android']);

    $files = decodeNativeSourcesOutput();
    $all = allPlatformFiles('android');

    expect($files)->toContain('ButtonRenderer.kt')
        ->and($files)->toContain('TextRenderer.kt')
        ->and($files)->toContain('ContainerRenderers.kt')
        ->and($files)->toContain('ImageRenderer.kt')
        ->and($files)->toContain('OutlinedTextInputRenderer.kt')
        ->and($files)->not->toContain('WebviewRenderer.kt')
        ->and(count($files))->toBeLessThan(count($all));
});

it('in manual mode uses the configured component list', function () {
    config([
        'native-ui.tree_shaking.enabled' => true,
        'native-ui.tree_shaking.mode' => 'manual',
        'native-ui.tree_shaking.components' => ['button'],
    ]);

    Artisan::call('nativephp:native-ui:native-sources', ['--platform' => 'android']);

    $files = decodeNativeSourcesOutput();

    expect($files)->toContain('ButtonRenderer.kt')
        ->and($files)->not->toContain('WebviewRenderer.kt');
});

it('falls back to all files when detection is uncertain', function () {
    config([
        'native-ui.tree_shaking.enabled' => true,
        'native-ui.tree_shaking.mode' => 'auto',
        'native-ui.tree_shaking.include_all_on_uncertainty' => true,
    ]);

    $views = base_path('resources/views');
    if (! is_dir($views)) {
        mkdir($views, 0755, true);
    }
    file_put_contents("{$views}/dynamic.blade.php", '<native:{{ $type }} />');

    Artisan::call('nativephp:native-ui:native-sources', ['--platform' => 'android']);

    expect(decodeNativeSourcesOutput())->toEqualCanonicalizing(allPlatformFiles('android'));
});

it('prints the full list and exits 0 for an invalid platform rather than failing the build', function () {
    $exit = Artisan::call('nativephp:native-ui:native-sources', ['--platform' => 'windows']);

    expect($exit)->toBe(0)
        ->and(decodeNativeSourcesOutput())->toEqualCanonicalizing(allPlatformFiles('android'));
});
