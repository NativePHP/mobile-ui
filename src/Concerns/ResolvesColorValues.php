<?php

namespace Native\Mobile\UI\Concerns;

use Native\Mobile\Edge\TailwindParser;

/**
 * Shared authoring-layer color grammar for element color props.
 *
 * Element color setters accept the same inputs as theme config tokens —
 * Tailwind palette names (`red-300`), opacity modifiers (`red-300/20`,
 * `#8B5CF6/50`), and CSS hex with alpha (`#8B5CF680`) — resolved to the
 * wire-format hex the native ColorParsers expect (#RRGGBB / #AARRGGBB).
 * Unrecognized strings pass through untouched so the native side's own
 * fallbacks still apply. See TailwindParser::resolveColorValue for the
 * full grammar.
 */
trait ResolvesColorValues
{
    protected function resolveColorValue(string $value): string
    {
        // Guards against a core version that predates the shared resolver.
        if (! method_exists(TailwindParser::class, 'resolveColorValue')) {
            return $value;
        }

        return TailwindParser::resolveColorValue($value) ?? $value;
    }
}
