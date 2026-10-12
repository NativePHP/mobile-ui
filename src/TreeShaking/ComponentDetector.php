<?php

namespace Native\Mobile\UI\TreeShaking;

/**
 * Detects which mobile-ui components are used in an application.
 *
 * Scans:
 *   - Blade templates for <native:*> and <x-native::*> syntax
 *   - PHP files for Element class usage (use statements, static calls)
 *   - PHP files for NativeElementCollector::leaf/open string literals
 *
 * Returns ['*'] when uncertainty is detected (dynamic component names, etc.).
 */
class ComponentDetector
{
    protected string $basePath;

    public function __construct(string $basePath)
    {
        $this->basePath = $basePath;
    }

    public function detect(): array
    {
        $components = [];
        $hasUncertainty = false;

        // Scan Blade templates
        $bladeDetector = new BladeComponentScanner;
        $bladeFiles = $this->getBladeFiles();

        // Check for unreadable marker
        if (in_array('*UNREADABLE*', $bladeFiles, true)) {
            return ['*'];
        }

        $result = $bladeDetector->scan($bladeFiles);

        if ($result['uncertain']) {
            $hasUncertainty = true;
        }
        $components = array_merge($components, $result['components']);

        // Scan PHP files for Element class usage
        $phpDetector = new PhpElementScanner;
        $phpFiles = $this->getPhpFiles();

        // Check for unreadable marker
        if (in_array('*UNREADABLE*', $phpFiles, true)) {
            return ['*'];
        }

        $result = $phpDetector->scan($phpFiles);

        if ($result['uncertain']) {
            $hasUncertainty = true;
        }
        $components = array_merge($components, $result['components']);

        // Return special '*' marker if uncertainty detected
        if ($hasUncertainty) {
            return ['*'];
        }

        return array_values(array_unique($components));
    }

    protected function getBladeFiles(): array
    {
        $files = [];

        // App views
        $appViews = $this->basePath.'/resources/views';
        if (is_dir($appViews)) {
            $files = array_merge($files, $this->globRecursive($appViews, '*.blade.php'));
        }

        // Vendor views (packages may use components)
        $vendorViews = $this->basePath.'/vendor';
        if (is_dir($vendorViews)) {
            $files = array_merge($files, $this->globRecursive($vendorViews, '*.blade.php'));
        }

        return $files;
    }

    protected function getPhpFiles(): array
    {
        $files = [];

        // App PHP files
        $appPath = $this->basePath.'/app';
        if (is_dir($appPath)) {
            $files = array_merge($files, $this->globRecursive($appPath, '*.php'));
        }

        // Vendor PHP: only files that actually mention Native UI / Edge.
        // Scanning every vendor file would treat `new $class` in Carbon etc.
        // as tree-shaking uncertainty and fall back to bundling everything.
        $vendorPath = $this->basePath.'/vendor';
        if (is_dir($vendorPath)) {
            foreach ($this->globRecursive($vendorPath, '*.php') as $file) {
                $content = @file_get_contents($file);
                if (is_string($content) && $this->looksLikeNativeUiPhp($content)) {
                    $files[] = $file;
                }
            }
        }

        return $files;
    }

    protected function globRecursive(string $dir, string $pattern): array
    {
        if (! is_dir($dir)) {
            return [];
        }

        try {
            $iterator = new \RecursiveIteratorIterator(
                new \RecursiveDirectoryIterator($dir, \RecursiveDirectoryIterator::SKIP_DOTS),
                \RecursiveIteratorIterator::LEAVES_ONLY,
                \RecursiveIteratorIterator::CATCH_GET_CHILD
            );
        } catch (\UnexpectedValueException $e) {
            // Directory not readable - fail safe and include everything
            return ['*UNREADABLE*'];
        }

        $files = [];
        foreach ($iterator as $file) {
            try {
                if (! $file->isFile()) {
                    continue;
                }

                $path = $file->getPathname();

                if ($this->shouldSkipPath($path)) {
                    continue;
                }

                if (fnmatch($pattern, $file->getFilename())) {
                    $files[] = $path;
                }
            } catch (\UnexpectedValueException $e) {
                // File not readable - fail safe and include everything
                return ['*UNREADABLE*'];
            }
        }

        return $files;
    }

    /**
     * Skip test fixtures and VCS metadata. Scanning package test suites
     * (e.g. vendor/nativephp/mobile/tests) would pick up example tags and
     * `new $class` uncertainty patterns that are not part of the app.
     */
    protected function shouldSkipPath(string $path): bool
    {
        $normalized = str_replace('\\', '/', $path);

        foreach ([
            '/tests/',
            '/Tests/',
            '/test/',
            '/phpunit/',
            '/.git/',
            '/node_modules/',
            '/vendor/bin/',
        ] as $skip) {
            if (str_contains($normalized, $skip)) {
                return true;
            }
        }

        return false;
    }

    protected function looksLikeNativeUiPhp(string $content): bool
    {
        return str_contains($content, 'Native\\Mobile\\UI')
            || str_contains($content, 'Native\\Mobile\\Edge')
            || str_contains($content, 'NativeElementCollector')
            || str_contains($content, '<native:');
    }
}
