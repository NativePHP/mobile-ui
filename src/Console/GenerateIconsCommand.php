<?php

namespace Native\Mobile\UI\Console;

use Illuminate\Console\Command;

/**
 * Regenerate the icon enums (`App\Enums\Icons\Ios`, `App\Enums\Icons\Android`,
 * `App\Enums\Icons\AndroidOutlined`) from the JSON snapshots that ship with
 * the native-ui plugin.
 *
 *   php artisan native-ui:generate-icons                 # regenerate from local snapshots
 *   php artisan native-ui:generate-icons --refresh-material
 *       # fetch the latest Material catalog from Google's metadata
 *       # endpoint, update the local snapshot, then regenerate
 *
 * The SF Symbols catalog has no public web URL — Apple ships it as a
 * plist bundled with the SF Symbols.app. To refresh the SF snapshot,
 * extract symbol names from the app on a Mac and update
 * `vendor/nativephp/mobile-ui/resources/icons/sf-symbols.json` (or
 * publish the snapshots into your app first to own them).
 *
 * Output goes to your app at `app/Enums/Icons/`. The namespace is
 * `App\Enums\Icons` — change `--namespace` to write somewhere else.
 * Files survive `composer update` because they're in app-space, not
 * vendor.
 *
 * Generated files are overwritten in-place. Don't hand-edit the enum
 * cases — add to the JSON snapshot, regenerate.
 */
class GenerateIconsCommand extends Command
{
    protected $signature = 'native-ui:generate-icons
        {--refresh-material : Fetch latest Material catalog from Google before regenerating}
        {--output= : Override output directory (default: app/Enums/Icons)}
        {--namespace= : Override generated namespace (default: App\\Enums\\Icons)}';

    protected $description = 'Generate Ios / Android / AndroidOutlined icon enums into your app';

    private const MATERIAL_URL = 'https://fonts.google.com/metadata/icons';

    public function handle(): int
    {
        $iconsDir = $this->pluginResourcesPath('icons');
        $outputDir = $this->option('output') ?: app_path('Enums/Icons');
        $namespace = $this->option('namespace') ?: 'App\\Enums\\Icons';

        if (! is_dir($outputDir)) {
            mkdir($outputDir, 0755, recursive: true);
        }

        if ($this->option('refresh-material')) {
            $count = $this->refreshMaterial($iconsDir.'/material-icons.json');
            $this->info("Material catalog refreshed — {$count} symbols.");
        }

        $sf = $this->loadSymbols($iconsDir.'/sf-symbols.json');
        $material = $this->loadSymbols($iconsDir.'/material-icons.json');

        $this->writeEnum(
            file: $outputDir.'/Ios.php',
            namespace: $namespace,
            class: 'Ios',
            interface: 'IosSymbol',
            interfaceFqn: 'Native\\Mobile\\Icon\\IosSymbol',
            cases: $this->buildCases($sf, fn ($n) => $this->sfCaseName($n)),
            variant: null,
            blurb: 'SF Symbols (iOS).',
        );

        $materialCases = $this->buildCases($material, fn ($n) => $this->materialCaseName($n));
        $this->writeEnum(
            file: $outputDir.'/Android.php',
            namespace: $namespace,
            class: 'Android',
            interface: 'AndroidSymbol',
            interfaceFqn: 'Native\\Mobile\\Icon\\AndroidSymbol',
            cases: $materialCases,
            variant: 'filled',
            blurb: 'Material Icons — Filled variant (Android default).',
        );
        $this->writeEnum(
            file: $outputDir.'/AndroidOutlined.php',
            namespace: $namespace,
            class: 'AndroidOutlined',
            interface: 'AndroidSymbol',
            interfaceFqn: 'Native\\Mobile\\Icon\\AndroidSymbol',
            cases: $materialCases,
            variant: 'outlined',
            blurb: 'Material Icons — Outlined variant.',
        );

        $this->info(sprintf(
            'Generated Ios (%d cases) + Android (%d cases) + AndroidOutlined (%d cases).',
            count($sf),
            count($material),
            count($material),
        ));

        return self::SUCCESS;
    }

    /**
     * Read a snapshot JSON file. Expected schema: `{ "symbols": ["a", "b", ...] }`.
     *
     * @return string[]
     */
    private function loadSymbols(string $path): array
    {
        if (! is_file($path)) {
            $this->error("Snapshot not found: {$path}");
            exit(self::FAILURE);
        }
        $data = json_decode(file_get_contents($path), true, flags: JSON_THROW_ON_ERROR);
        $symbols = $data['symbols'] ?? [];
        if (! is_array($symbols) || empty($symbols)) {
            $this->error("Snapshot has no 'symbols' array: {$path}");
            exit(self::FAILURE);
        }

        return array_values(array_unique(array_filter($symbols, 'is_string')));
    }

    /**
     * Build deduplicated [caseName => rawValue] pairs, sorted by case name.
     *
     * @param  string[]  $symbols
     * @param  callable(string):string  $caseFn
     * @return array<string, string>
     */
    private function buildCases(array $symbols, callable $caseFn): array
    {
        $cases = [];
        foreach ($symbols as $raw) {
            $case = $caseFn($raw);
            if ($case === '') {
                continue;
            }
            // First-write-wins on collision so deterministic ordering matches
            // the source file order (helpful when chasing diffs after a refresh).
            $cases[$case] ??= $raw;
        }
        ksort($cases);

        return $cases;
    }

    /**
     * SF Symbol name → PascalCase enum case.
     *
     *   bell.slash                   → BellSlash
     *   square.and.arrow.up          → SquareAndArrowUp
     *   arrow.uturn.backward         → ArrowUturnBackward
     *   1.brakesignal                → Symbol1Brakesignal
     */
    private function sfCaseName(string $name): string
    {
        return $this->escapePhpIdentifier($this->toPascal(preg_split('/[._-]/', $name)));
    }

    /**
     * Material ligature name → PascalCase enum case.
     *
     *   notifications_off            → NotificationsOff
     *   shopping_cart                → ShoppingCart
     *   class                        → SymbolClass  (PHP reserves bare `class`)
     *   123                          → Symbol123
     */
    private function materialCaseName(string $name): string
    {
        return $this->escapePhpIdentifier($this->toPascal(preg_split('/[_-]/', $name)));
    }

    /**
     * @param  string[]  $parts
     */
    private function toPascal(array $parts): string
    {
        return implode('', array_map(fn ($p) => ucfirst($p), $parts));
    }

    /**
     * Disambiguate identifiers that PHP reserves or rejects as class
     * constants / enum case names. Currently the only outright rejection
     * is `class` (reserved for `::class`). Digits-first cases get the
     * same `Symbol`-prefix treatment so the rule is uniform.
     */
    private function escapePhpIdentifier(string $name): string
    {
        if ($name === '') {
            return $name;
        }
        if (ctype_digit($name[0])) {
            return 'Symbol'.$name;
        }
        if (strcasecmp($name, 'class') === 0) {
            return 'SymbolClass';
        }

        return $name;
    }

    /**
     * @param  array<string, string>  $cases
     */
    private function writeEnum(
        string $file,
        string $namespace,
        string $class,
        string $interface,
        string $interfaceFqn,
        array $cases,
        ?string $variant,
        string $blurb,
    ): void {
        $lines = ['<?php', '', "namespace {$namespace};", '', "use {$interfaceFqn};", '', '/**', " * {$blurb}", ' *', ' * GENERATED FILE — do not hand-edit.', ' * Run `php artisan native-ui:generate-icons` to regenerate from', ' * `resources/icons/*.json` snapshots.', ' */', "enum {$class}: string implements {$interface}", '{'];

        if ($variant !== null) {
            $lines[] = '    public function variant(): string';
            $lines[] = '    {';
            $lines[] = "        return '{$variant}';";
            $lines[] = '    }';
            $lines[] = '';
        }

        foreach ($cases as $case => $value) {
            $lines[] = "    case {$case} = '{$value}';";
        }

        $lines[] = '}';
        $lines[] = '';

        file_put_contents($file, implode("\n", $lines));
        $this->line("  wrote {$file}");
    }

    /**
     * Fetch Google's Material Icons metadata, extract just the icon names,
     * and overwrite the local snapshot.
     */
    private function refreshMaterial(string $path): int
    {
        $this->line('Fetching Material catalog from Google…');
        $body = @file_get_contents(self::MATERIAL_URL);
        if ($body === false) {
            $this->error('Failed to fetch '.self::MATERIAL_URL);
            exit(self::FAILURE);
        }
        // Google prefixes the JSON with `)]}'` as an XSS guard — strip it.
        $body = preg_replace('/^\)\]\}\'\s*/', '', $body);
        $data = json_decode($body, true);
        if (! is_array($data) || ! isset($data['icons']) || ! is_array($data['icons'])) {
            $this->error('Unexpected metadata shape from Google.');
            exit(self::FAILURE);
        }

        $names = array_values(array_unique(array_filter(
            array_map(fn ($icon) => $icon['name'] ?? null, $data['icons']),
            'is_string',
        )));
        sort($names);

        $snapshot = [
            '_meta' => [
                'source' => 'Auto-fetched from '.self::MATERIAL_URL,
                'format' => 'Material Icons font ligature names (snake_case). Same name renders in both Filled and Outlined fonts.',
                'updated' => date('Y-m-d'),
            ],
            'symbols' => $names,
        ];
        file_put_contents($path, json_encode($snapshot, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)."\n");

        return count($names);
    }

    private function pluginResourcesPath(string $sub = ''): string
    {
        return dirname(__DIR__, 2).'/resources'.($sub === '' ? '' : '/'.$sub);
    }
}
