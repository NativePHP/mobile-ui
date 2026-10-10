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

        // Vendor PHP files - scan ALL (packages may use Element API anywhere)
        $vendorPath = $this->basePath.'/vendor';
        if (is_dir($vendorPath)) {
            $files = array_merge($files, $this->globRecursive($vendorPath, '*.php'));
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

                if (fnmatch('*'.$pattern, basename($file->getFilename()))) {
                    $files[] = $file->getPathname();
                }
            } catch (\UnexpectedValueException $e) {
                // File not readable - fail safe and include everything
                return ['*UNREADABLE*'];
            }
        }

        return $files;
    }
}
