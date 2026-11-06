<?php

namespace Native\Mobile\UI\TreeShaking;

/**
 * Scans renderer source files for references to other renderers.
 *
 * Example: ButtonGroupRenderer may reference ButtonRenderer,
 * so if ButtonGroup is used, Button's renderer must also be included.
 */
class RendererDependencyResolver
{
    protected string $sourcePath;

    protected string $platform;

    protected array $cache = [];

    public function __construct(string $sourcePath, string $platform)
    {
        $this->sourcePath = $sourcePath;
        $this->platform = $platform;
    }

    public function getDependencies(string $file): array
    {
        if (isset($this->cache[$file])) {
            return $this->cache[$file];
        }

        $filePath = $this->sourcePath.'/'.$file;

        if (! file_exists($filePath)) {
            $this->cache[$file] = [];

            return [];
        }

        $content = file_get_contents($filePath);
        $deps = $this->extractDependencies($content, $file);

        $this->cache[$file] = $deps;

        return $deps;
    }

    protected function extractDependencies(string $content, string $currentFile): array
    {
        $deps = [];

        if ($this->platform === 'ios') {
            // Instantiations / calls: NativeUIButtonRenderer(...)
            // Ignore struct/enum/class/protocol/extension declarations.
            if (preg_match_all('/\b(NativeUI[A-Z][a-zA-Z]+Renderer)\s*\(/', $content, $matches, PREG_OFFSET_CAPTURE)) {
                foreach ($matches[1] as [$renderer, $offset]) {
                    if ($this->isTypeDeclaration($content, $offset)) {
                        continue;
                    }
                    $deps[] = "{$renderer}.swift";
                }
            }
        } else {
            // Android calls: ButtonRenderer(...)
            if (preg_match_all('/\b([A-Z][a-zA-Z]+Renderer)\s*\(/', $content, $matches, PREG_OFFSET_CAPTURE)) {
                foreach ($matches[1] as [$renderer, $offset]) {
                    if ($renderer === 'Renderer' || $this->isTypeDeclaration($content, $offset)) {
                        continue;
                    }
                    $deps[] = "{$renderer}.kt";
                }
            }

            // Import statements: com.nativephp.plugins.native_ui.ui.ButtonRenderer
            if (preg_match_all(
                '/import\s+com\.nativephp\.plugins\.native_ui\.ui\.([A-Z][a-zA-Z]+)/',
                $content,
                $matches
            )) {
                foreach ($matches[1] as $className) {
                    $deps[] = "{$className}.kt";
                }
            }
        }

        $deps = array_filter($deps, fn ($dep) => $dep !== $currentFile);

        return array_values(array_unique($deps));
    }

    /**
     * True when the match at $offset is a type/function declaration, not a use.
     */
    protected function isTypeDeclaration(string $content, int $offset): bool
    {
        $before = substr($content, max(0, $offset - 24), min(24, $offset));

        return (bool) preg_match('/\b(struct|enum|class|protocol|extension|object|fun)\s+$/', $before);
    }
}
