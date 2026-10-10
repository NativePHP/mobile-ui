<?php

namespace Native\Mobile\UI\TreeShaking;

/**
 * Maps component types to native renderer files and resolves dependencies.
 *
 * Reads nativephp.json manifest to map components to Swift/Kotlin renderers,
 * scans renderer sources for transitive dependencies, and includes shared
 * utilities that all renderers need.
 */
class RendererMapper
{
    protected string $manifestPath;

    protected array $manifest;

    protected array $rendererDependenciesCache = [];

    public function __construct(string $manifestPath)
    {
        $this->manifestPath = $manifestPath;
        $this->manifest = $this->loadManifest();
    }

    public function getAllComponentTypes(): array
    {
        return array_column($this->manifest['components'] ?? [], 'type');
    }

    public function getFilesToCopy(array $componentTypes, string $platform): array
    {
        $files = [];

        // Always include shared/base files
        $files = array_merge($files, $this->getSharedFiles($platform));

        // Add renderer files for used components
        foreach ($componentTypes as $type) {
            $renderer = $this->getRendererName($type, $platform);

            if ($renderer === null) {
                continue;
            }

            $file = $this->rendererToFile($renderer, $platform);

            if ($file !== null) {
                $files[] = $file;
            }
        }

        // Resolve transitive dependencies
        $files = $this->resolveTransitiveDependencies($files, $platform);

        return array_values(array_unique($files));
    }

    protected function getSharedFiles(string $platform): array
    {
        // These files are always needed regardless of which components are used
        if ($platform === 'ios') {
            return [
                'NativeUITheme.swift',
                'NativeUIFontResolver.swift',
                'NativeUIDrawerHost.swift',
                'NativeUIFloatingOverlayHost.swift',
                'NativeUIBackgroundLayerHost.swift',
                'NativeUITransitionFunctions.swift',
                'NativeUIFillWidthHelper.swift',
                'NativeUINavRenderers.swift',
            ];
        }

        // Android
        return [
            'NativeUITheme.kt',
            'NativeUIFontResolver.kt',
            'NativeUIChromeInit.kt',
            'NativeLayoutDrawerHost.kt',
            'NativeFloatingOverlayHost.kt',
            'NativeUIBackgroundLayerHost.kt',
            'NativeUITransitionFunctions.kt',
            'TextInputShared.kt',
            'NativeUIImageSource.kt',
        ];
    }

    protected function getRendererName(string $componentType, string $platform): ?string
    {
        $key = $platform === 'ios' ? 'ios_renderer' : 'android_renderer';

        foreach ($this->manifest['components'] ?? [] as $component) {
            if ($component['type'] === $componentType) {
                return $component[$key] ?? null;
            }
        }

        return null;
    }

    protected function rendererToFile(string $renderer, string $platform): ?string
    {
        if ($platform === 'ios') {
            // iOS renderer: "NativeUIButtonRenderer" -> "NativeUIButtonRenderer.swift"
            return "{$renderer}.swift";
        }

        // Android renderer: "com.nativephp.plugins.native_ui.ui.ButtonRenderer"
        // -> "ButtonRenderer.kt" (take last segment)
        $parts = explode('.', $renderer);
        $className = end($parts);

        return "{$className}.kt";
    }

    protected function resolveTransitiveDependencies(array $files, string $platform): array
    {
        $resolver = new RendererDependencyResolver(
            dirname($this->manifestPath)."/resources/{$platform}",
            $platform
        );

        $allFiles = $files;

        foreach ($files as $file) {
            $deps = $resolver->getDependencies($file);
            $allFiles = array_merge($allFiles, $deps);
        }

        return array_values(array_unique($allFiles));
    }

    protected function loadManifest(): array
    {
        if (! file_exists($this->manifestPath)) {
            throw new \RuntimeException("Manifest not found: {$this->manifestPath}");
        }

        $content = file_get_contents($this->manifestPath);
        $manifest = json_decode($content, true);

        if ($manifest === null) {
            throw new \RuntimeException("Invalid JSON in manifest: {$this->manifestPath}");
        }

        return $manifest;
    }
}
