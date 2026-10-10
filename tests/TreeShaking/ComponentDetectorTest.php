<?php

use Native\Mobile\UI\TreeShaking\ComponentDetector;

it('detects components from both Blade and PHP files', function () {
    $tempDir = createTempAppStructure([
        'resources/views/welcome.blade.php' => '<native:button label="Click" />',
        'app/Livewire/Counter.php' => <<<'PHP'
<?php
use Native\Mobile\UI\Elements\Text;
class Counter {
    public function render() {
        return Text::make('Count: 5');
    }
}
PHP,
    ]);

    $detector = new ComponentDetector($tempDir);
    $components = $detector->detect();

    expect($components)->toContain('button')
        ->and($components)->toContain('text');
});

it('returns special marker on uncertainty', function () {
    $tempDir = createTempAppStructure([
        'resources/views/dynamic.blade.php' => '<native:{{ $type }} />',
    ]);

    $detector = new ComponentDetector($tempDir);
    $components = $detector->detect();

    expect($components)->toBe(['*']);
});

it('returns unique components across all files', function () {
    $tempDir = createTempAppStructure([
        'resources/views/page1.blade.php' => '<native:button /><native:text />',
        'resources/views/page2.blade.php' => '<native:button /><native:column />',
        'app/MyComponent.php' => '<?php use Native\Mobile\UI\Elements\Button;',
    ]);

    $detector = new ComponentDetector($tempDir);
    $components = $detector->detect();

    expect($components)->toHaveCount(3)
        ->and($components)->toContain('button')
        ->and($components)->toContain('text')
        ->and($components)->toContain('column');
});

it('scans vendor directories for packages using components', function () {
    $tempDir = createTempAppStructure([
        'vendor/my-package/src/Components/Livewire/MyWidget.php' => <<<'PHP'
<?php
namespace MyPackage\Livewire;
use Native\Mobile\UI\Elements\Badge;
class MyWidget {}
PHP,
    ]);

    $detector = new ComponentDetector($tempDir);
    $components = $detector->detect();

    expect($components)->toContain('badge');
});

it('handles missing directories gracefully', function () {
    $tempDir = sys_get_temp_dir().'/nonexistent_'.uniqid();

    $detector = new ComponentDetector($tempDir);
    $components = $detector->detect();

    expect($components)->toBeArray();
});

// Helper to create temporary app structure
function createTempAppStructure(array $files): string
{
    $dir = sys_get_temp_dir().'/app_test_'.uniqid();

    foreach ($files as $path => $content) {
        $fullPath = "{$dir}/{$path}";
        $dirPath = dirname($fullPath);

        if (! is_dir($dirPath)) {
            mkdir($dirPath, 0755, true);
        }

        file_put_contents($fullPath, $content);
    }

    register_shutdown_function(function () use ($dir) {
        if (is_dir($dir)) {
            $iterator = new RecursiveIteratorIterator(
                new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS),
                RecursiveIteratorIterator::CHILD_FIRST
            );

            foreach ($iterator as $file) {
                if ($file->isDir()) {
                    rmdir($file->getRealPath());
                } else {
                    unlink($file->getRealPath());
                }
            }

            rmdir($dir);
        }
    });

    return $dir;
}
