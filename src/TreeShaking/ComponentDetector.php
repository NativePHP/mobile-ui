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
        $bladeDetector = new BladeComponentScanner();
        $result = $bladeDetector->scan($this->getBladeFiles());

        if ($result['uncertain']) {
            $hasUncertainty = true;
        }
        $components = array_merge($components, $result['components']);

        // Scan PHP files for Element class usage
        $phpDetector = new PhpElementScanner();
        $result = $phpDetector->scan($this->getPhpFiles());

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

        // Vendor PHP files (packages may use Element API)
        $vendorPath = $this->basePath.'/vendor';
        if (is_dir($vendorPath)) {
            // Only scan Livewire components and similar, not all vendor code
            $files = array_merge($files, $this->globRecursive($vendorPath, '*.php', [
                '*/livewire/*',
                '*/Http/Livewire/*',
            ]));
        }

        return $files;
    }

    protected function globRecursive(string $dir, string $pattern, array $pathFilters = []): array
    {
        if (! is_dir($dir)) {
            return [];
        }

        $iterator = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($dir, \RecursiveDirectoryIterator::SKIP_DOTS)
        );

        $files = [];
        foreach ($iterator as $file) {
            if (! $file->isFile()) {
                continue;
            }

            $path = $file->getPathname();

            // Apply path filters if specified
            if (! empty($pathFilters)) {
                $matched = false;
                foreach ($pathFilters as $filter) {
                    if (fnmatch($filter, $path)) {
                        $matched = true;
                        break;
                    }
                }
                if (! $matched) {
                    continue;
                }
            }

            if (fnmatch('*'.$pattern, basename($path))) {
                $files[] = $path;
            }
        }

        return $files;
    }
}
