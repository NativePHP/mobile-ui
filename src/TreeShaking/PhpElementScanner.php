<?php

namespace Native\Mobile\UI\TreeShaking;

/**
 * Scans PHP files for mobile-ui Element class usage.
 *
 * Detects:
 *   - use Native\Mobile\UI\Elements\Button;
 *   - Button::make() (after use import)
 *   - Native\Mobile\UI\Elements\Button::make()
 *   - NativeElementCollector::leaf('button', [...])
 *   - NativeElementCollector::open('column', [...])
 *
 * Returns uncertain when:
 *   - Variables used as element types: ::leaf($var, ...)
 *   - String concatenation in component names
 *   - Reflection-based instantiation
 */
class PhpElementScanner
{
    protected array $uncertaintyPatterns = [
        // Variable element types
        '/NativeElementCollector::(leaf|open)\s*\(\s*\$/',
        '/ElementCollector::(leaf|open)\s*\(\s*\$/',

        // Reflection/dynamic instantiation
        '/app\(\)->make\s*\(\s*\$/',
        '/resolve\s*\(\s*\$.*Element/',
        '/new\s+\$/',

        // Config-driven (rare but possible)
        '/config\s*\(["\'][^"\']*component/',
    ];

    public function scan(array $files): array
    {
        $components = [];
        $uncertain = false;

        foreach ($files as $file) {
            if (! is_readable($file)) {
                continue;
            }

            $content = file_get_contents($file);

            // Check for uncertainty patterns first
            if ($this->hasUncertainty($content)) {
                $uncertain = true;
                continue;
            }

            // Extract component usage
            $components = array_merge($components, $this->extractFromElementApi($content));
            $components = array_merge($components, $this->extractFromCollector($content));
        }

        return [
            'components' => array_values(array_unique($components)),
            'uncertain' => $uncertain,
        ];
    }

    protected function hasUncertainty(string $content): bool
    {
        foreach ($this->uncertaintyPatterns as $pattern) {
            if (preg_match($pattern, $content)) {
                return true;
            }
        }

        return false;
    }

    protected function extractFromElementApi(string $content): array
    {
        $components = [];

        // Pattern 1: use statements
        // use Native\Mobile\UI\Elements\Button;
        // use Native\Mobile\Edge\Elements\Column;
        if (preg_match_all(
            '/use\s+Native\\\\Mobile\\\\(?:UI|Edge)\\\\Elements\\\\([A-Z][a-zA-Z]*);/',
            $content,
            $matches
        )) {
            foreach ($matches[1] as $className) {
                $components[] = $this->classNameToType($className);
            }
        }

        // Pattern 2: Fully-qualified static calls
        // Native\Mobile\UI\Elements\Button::make()
        if (preg_match_all(
            '/Native\\\\Mobile\\\\(?:UI|Edge)\\\\Elements\\\\([A-Z][a-zA-Z]*)::/',
            $content,
            $matches
        )) {
            foreach ($matches[1] as $className) {
                $components[] = $this->classNameToType($className);
            }
        }

        return $components;
    }

    protected function extractFromCollector(string $content): array
    {
        $components = [];

        // NativeElementCollector::leaf('button', [...])
        // NativeElementCollector::open('column', [...])
        if (preg_match_all(
            '/NativeElementCollector::(leaf|open)\s*\(\s*["\']([a-z_]+)["\']/',
            $content,
            $matches
        )) {
            $components = array_merge($components, $matches[2]);
        }

        // Short alias if used
        if (preg_match_all(
            '/ElementCollector::(leaf|open)\s*\(\s*["\']([a-z_]+)["\']/',
            $content,
            $matches
        )) {
            $components = array_merge($components, $matches[2]);
        }

        return $components;
    }

    protected function classNameToType(string $className): string
    {
        // Convert PascalCase class names to snake_case types
        // Button -> button
        // OutlinedTextInput -> outlined_text_input
        // NativeList -> native_list

        $type = preg_replace('/([A-Z])/', '_$1', $className);
        $type = trim($type, '_');

        return strtolower($type);
    }
}
