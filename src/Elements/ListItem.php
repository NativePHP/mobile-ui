<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\Edge\Layouts\Builders\NavAction;
use Native\Mobile\Icon\AndroidSymbol;
use Native\Mobile\Icon\IconResolver;
use Native\Mobile\Icon\IosSymbol;
use Native\Mobile\UI\Concerns\ResolvesColorValues;

class ListItem extends Element
{
    use ResolvesColorValues;

    protected string $type = 'list_item';

    protected array $listItemProps = [];

    protected ?string $leadingChangeCallback = null;

    protected ?string $trailingChangeCallback = null;

    protected ?string $trailingPressCallback = null;

    protected ?string $swipeDeleteCallback = null;

    /** @var array<int, array{method:string,label:string,icon?:string,tint?:string,role?:string}> */
    protected array $leadingActions = [];

    /** @var array<int, array{method:string,label:string,icon?:string,tint?:string,role?:string}> */
    protected array $trailingActions = [];

    /**
     * Small status badges drawn in the trailing area (right-aligned).
     * Stacked horizontally. Each badge: an icon (string / Ios enum /
     * Android enum) plus an optional color hex.
     *
     * @var array<int, array{icon?:string,ios?:mixed,android?:mixed,color?:string}>
     */
    protected array $trailingBadges = [];

    public static function make(string $headline = ''): static
    {
        $el = new static;
        if ($headline !== '') {
            $el->listItemProps['headline'] = $headline;
        }

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['headline'])) {
            $this->listItemProps['headline'] = $attrs['headline'];
        }
        if (isset($attrs['supporting'])) {
            $this->supporting($attrs['supporting']);
        }
        if (isset($attrs['overline'])) {
            $this->overline($attrs['overline']);
        }

        // Leading content — type-based attributes
        // Leading icon accepts an optional cross-platform string plus
        // typed iOS / Android overrides — same shape as HasPlatformIcon
        // builders. The trio is collapsed via IconResolver inside
        // `leadingIcon()`.
        if (isset($attrs['leadingIcon']) || isset($attrs['leadingIconIos']) || isset($attrs['leadingIconAndroid'])) {
            $this->leadingIcon(
                $attrs['leadingIcon'] ?? null,
                $attrs['leadingIconIos'] ?? null,
                $attrs['leadingIconAndroid'] ?? null,
            );
        }
        if (isset($attrs['leadingAvatar'])) {
            $this->leadingAvatar($attrs['leadingAvatar']);
        }
        if (isset($attrs['leadingMonogram'])) {
            $this->leadingMonogram($attrs['leadingMonogram'], $attrs['leadingMonogramColor'] ?? null);
        }
        if (isset($attrs['leadingIconBgColor'])) {
            $this->leadingIconBackgroundColor($attrs['leadingIconBgColor']);
        }
        if (isset($attrs['leadingImage'])) {
            $this->leadingImage($attrs['leadingImage']);
        }
        if (isset($attrs['leadingCheckbox'])) {
            $this->leadingCheckbox((bool) $attrs['leadingCheckbox']);
        }
        if (isset($attrs['leadingRadio'])) {
            $this->leadingRadio((bool) $attrs['leadingRadio']);
        }

        // Trailing content — type-based attributes
        // Trailing icon — same typed-icon API as leadingIcon.
        if (isset($attrs['trailingIcon']) || isset($attrs['trailingIconIos']) || isset($attrs['trailingIconAndroid'])) {
            $this->trailingIcon(
                $attrs['trailingIcon'] ?? null,
                $attrs['trailingIconIos'] ?? null,
                $attrs['trailingIconAndroid'] ?? null,
            );
        }
        if (isset($attrs['trailingText'])) {
            $this->trailingText($attrs['trailingText']);
        }
        if (isset($attrs['trailingCheckbox'])) {
            $this->trailingCheckbox((bool) $attrs['trailingCheckbox']);
        }
        if (isset($attrs['trailingSwitch'])) {
            $this->trailingSwitch((bool) $attrs['trailingSwitch']);
        }
        if (isset($attrs['trailingIconButton'])) {
            $this->trailingIconButton($attrs['trailingIconButton']);
        }
        if (isset($attrs['trailing-a11y-label']) || isset($attrs['trailingA11yLabel'])) {
            $this->trailingA11yLabel($attrs['trailing-a11y-label'] ?? $attrs['trailingA11yLabel']);
        }

        // Optional `:trailing-menu` attribute attaches a tap-to-open menu
        // to the row's trailing slot. The renderer wraps the existing
        // trailing icon button in a Menu (iOS) / DropdownMenu (Android).
        // Combine with `trailingIconButton="ellipsis"` to control the
        // glyph; if unset the renderer picks a sensible default.
        //
        // The Blade precompiler keeps attribute names verbatim, so a
        // kebab-case Blade attr (`:trailing-menu`) lands as
        // `$attrs['trailing-menu']`. Accept both spellings, matching the
        // pattern used elsewhere (`a11y-label` / `a11yLabel`, etc.).
        $trailingMenu = $attrs['trailing-menu'] ?? $attrs['trailingMenu'] ?? null;
        if (is_array($trailingMenu) && ! empty($trailingMenu)) {
            foreach ($trailingMenu as $item) {
                if ($item instanceof NavAction) {
                    $this->addChild($item->toElement());
                } elseif ($item instanceof Element) {
                    $this->addChild($item);
                }
            }
            $this->listItemProps['has_trailing_menu'] = true;
            // Default trailing slot to icon_button if the dev didn't
            // specify one, so there's something to anchor the menu to.
            // Use `ellipsis` — valid SF symbol, and Android's IconHelper
            // aliases it to `more_horiz` so both platforms get a glyph.
            if (! isset($this->listItemProps['trailing_type'])) {
                $this->listItemProps['trailing_type'] = 'icon_button';
                $this->listItemProps['trailing_value'] = 'ellipsis';
            }
        }

        // Color attributes
        if (isset($attrs['headlineColor'])) {
            $this->headlineColor($attrs['headlineColor']);
        }
        if (isset($attrs['supportingColor'])) {
            $this->supportingColor($attrs['supportingColor']);
        }
        if (isset($attrs['overlineColor'])) {
            $this->overlineColor($attrs['overlineColor']);
        }
        if (isset($attrs['containerColor'])) {
            $this->containerColor($attrs['containerColor']);
        }
        if (isset($attrs['leadingIconColor'])) {
            $this->leadingIconColor($attrs['leadingIconColor']);
        }
        if (isset($attrs['trailingIconColor'])) {
            $this->trailingIconColor($attrs['trailingIconColor']);
        }
        if (isset($attrs['trailingTextColor'])) {
            $this->trailingTextColor($attrs['trailingTextColor']);
        }

        // Elevation
        if (isset($attrs['tonalElevation'])) {
            $this->tonalElevation((float) $attrs['tonalElevation']);
        }
        if (isset($attrs['shadowElevation'])) {
            $this->shadowElevation((float) $attrs['shadowElevation']);
        }

        // Disabled
        if (isset($attrs['disabled'])) {
            $this->disabled((bool) $attrs['disabled']);
        }

        // Swipe actions — legacy single-action API
        if (isset($attrs['on-swipe-delete']) || isset($attrs['onSwipeDelete'])) {
            $this->onSwipeDelete($attrs['on-swipe-delete'] ?? $attrs['onSwipeDelete']);
        }

        // Leading / trailing control change callbacks (checkbox, radio,
        // switch). Both spellings, matching `on-swipe-delete` above.
        if (isset($attrs['on-leading-change']) || isset($attrs['onLeadingChange'])) {
            $this->onLeadingChange($attrs['on-leading-change'] ?? $attrs['onLeadingChange']);
        }
        if (isset($attrs['on-trailing-change']) || isset($attrs['onTrailingChange'])) {
            $this->onTrailingChange($attrs['on-trailing-change'] ?? $attrs['onTrailingChange']);
        }

        // Swipe actions — new structured multi-action API. Each entry
        // is `['method' => …, 'label' => …, 'icon' => …, 'tint' => …,
        // 'role' => …]`. Both arrays support 1+ actions.
        if (isset($attrs['leading-actions']) && is_array($attrs['leading-actions'])) {
            $this->leadingActions($attrs['leading-actions']);
        }
        if (isset($attrs['trailing-actions']) && is_array($attrs['trailing-actions'])) {
            $this->trailingActions($attrs['trailing-actions']);
        }

        // Stacked status badges (e.g. flag + pin both visible at once).
        if (isset($attrs['trailing-badges']) && is_array($attrs['trailing-badges'])) {
            $this->trailingBadges($attrs['trailing-badges']);
        }

        $this->applyA11yAttributes($attrs);
    }

    /**
     * Set the list of small badges drawn in the trailing area. Each
     * entry: `['icon' => 'flag', 'ios' => Ios::FlagFill, 'android' =>
     * Android::Flag, 'color' => '#EF4444']`. Icons resolve via
     * `IconResolver`. When set, replaces the single `trailingIcon`
     * slot — the renderer draws all badges in a small HStack.
     *
     * @param  array<int, array<string, mixed>>  $badges
     */
    public function trailingBadges(array $badges): static
    {
        $this->trailingBadges = array_values($badges);

        return $this;
    }

    public function onSwipeDelete(string $method): static
    {
        $this->swipeDeleteCallback = $method;

        return $this;
    }

    /**
     * Actions revealed on a leading-edge (left→right) swipe.
     *
     * Each entry: `['method' => 'archive', 'label' => 'Archive',
     * 'icon' => 'archivebox', 'tint' => '#10B981', 'role' => '']`.
     * iOS renders via `.swipeActions(edge: .leading)`; Android via a
     * custom swipe-to-reveal composable mirroring the same behavior.
     *
     * @param  array<int, array<string, string>>  $actions
     */
    public function leadingActions(array $actions): static
    {
        $this->leadingActions = array_values($actions);

        return $this;
    }

    /**
     * Actions revealed on a trailing-edge (right→left) swipe.
     * Same shape as `leadingActions`. Setting `role => 'destructive'`
     * on an action gives it the red destructive treatment.
     *
     * @param  array<int, array<string, string>>  $actions
     */
    public function trailingActions(array $actions): static
    {
        $this->trailingActions = array_values($actions);

        return $this;
    }

    // ── Text content ─────────────────────────────────

    public function supporting(string $text): static
    {
        $this->listItemProps['supporting'] = $text;

        return $this;
    }

    public function overline(string $text): static
    {
        $this->listItemProps['overline'] = $text;

        return $this;
    }

    // ── Leading content ──────────────────────────────

    public function leadingIcon(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        $r = IconResolver::resolve($name, $ios, $android);
        if ($r['icon'] !== null) {
            $this->listItemProps['leading_type'] = 'icon';
            $this->listItemProps['leading_value'] = $r['icon'];
            $this->listItemProps['leading_icon'] = $r['icon'];
            if ($r['variant'] !== null) {
                $this->listItemProps['leading_icon_variant'] = $r['variant'];
            }
        }

        return $this;
    }

    public function leadingAvatar(string $url): static
    {
        $this->listItemProps['leading_type'] = 'avatar';
        $this->listItemProps['leading_value'] = $url;

        return $this;
    }

    public function leadingMonogram(string $initials, ?string $color = null): static
    {
        $this->listItemProps['leading_type'] = 'monogram';
        $this->listItemProps['leading_value'] = substr($initials, 0, 2);
        if ($color !== null) {
            $this->listItemProps['leading_monogram_color'] = $this->resolveColorValue($color);
        }

        return $this;
    }

    public function leadingImage(string $url): static
    {
        $this->listItemProps['leading_type'] = 'image';
        $this->listItemProps['leading_value'] = $url;

        return $this;
    }

    /**
     * Render the leading icon inside a filled circle of this color (with a
     * white glyph), instead of a bare tinted glyph. Pairs with
     * `leadingIcon` — gives the "icon tile" look without a monogram.
     */
    public function leadingIconBackgroundColor(string $color): static
    {
        $this->listItemProps['leading_icon_bg_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function leadingCheckbox(bool $checked = false): static
    {
        $this->listItemProps['leading_type'] = 'checkbox';
        $this->listItemProps['leading_checked'] = $checked;

        return $this;
    }

    public function leadingRadio(bool $selected = false): static
    {
        $this->listItemProps['leading_type'] = 'radio';
        $this->listItemProps['leading_checked'] = $selected;

        return $this;
    }

    // ── Trailing content ─────────────────────────────

    public function trailingIcon(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        $r = IconResolver::resolve($name, $ios, $android);
        if ($r['icon'] !== null) {
            $this->listItemProps['trailing_type'] = 'icon';
            $this->listItemProps['trailing_value'] = $r['icon'];
            $this->listItemProps['trailing_icon'] = $r['icon'];
            if ($r['variant'] !== null) {
                $this->listItemProps['trailing_icon_variant'] = $r['variant'];
            }
        }

        return $this;
    }

    public function trailingText(string $text): static
    {
        $this->listItemProps['trailing_type'] = 'text';
        $this->listItemProps['trailing_value'] = $text;

        return $this;
    }

    public function trailingCheckbox(bool $checked = false): static
    {
        $this->listItemProps['trailing_type'] = 'checkbox';
        $this->listItemProps['trailing_checked'] = $checked;

        return $this;
    }

    public function trailingSwitch(bool $checked = false): static
    {
        $this->listItemProps['trailing_type'] = 'switch';
        $this->listItemProps['trailing_checked'] = $checked;

        return $this;
    }

    public function trailingIconButton(
        ?string $name = null,
        IosSymbol|string|null $ios = null,
        AndroidSymbol|string|null $android = null,
    ): static {
        $r = IconResolver::resolve($name, $ios, $android);
        if ($r['icon'] !== null) {
            $this->listItemProps['trailing_type'] = 'icon_button';
            $this->listItemProps['trailing_value'] = $r['icon'];
            if ($r['variant'] !== null) {
                $this->listItemProps['trailing_icon_variant'] = $r['variant'];
            }
        }

        return $this;
    }

    /**
     * Screen-reader label for the trailing icon button. Icon buttons have
     * no visible text, so without this VoiceOver / TalkBack announce
     * nothing useful. Stored as `trailing_a11y_label` alongside the other
     * `trailing_*` props; iOS applies it as the button's
     * `accessibilityLabel`, Android as its `contentDescription`.
     */
    public function trailingA11yLabel(string $value): static
    {
        $this->listItemProps['trailing_a11y_label'] = $value;

        return $this;
    }

    // ── Callbacks ────────────────────────────────────

    public function onLeadingChange(string $method): static
    {
        $this->leadingChangeCallback = $method;

        return $this;
    }

    public function onTrailingChange(string $method): static
    {
        $this->trailingChangeCallback = $method;

        return $this;
    }

    public function onTrailingPress(string $method): static
    {
        $this->trailingPressCallback = $method;

        return $this;
    }

    // ── Styling ──────────────────────────────────────

    public function headlineColor(string $color): static
    {
        $this->listItemProps['headline_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function supportingColor(string $color): static
    {
        $this->listItemProps['supporting_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function overlineColor(string $color): static
    {
        $this->listItemProps['overline_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function containerColor(string $color): static
    {
        $this->listItemProps['container_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function leadingIconColor(string $color): static
    {
        $this->listItemProps['leading_icon_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function trailingIconColor(string $color): static
    {
        $this->listItemProps['trailing_icon_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function trailingTextColor(string $color): static
    {
        $this->listItemProps['trailing_text_color'] = $this->resolveColorValue($color);

        return $this;
    }

    public function tonalElevation(float $dp): static
    {
        $this->listItemProps['tonal_elevation'] = $dp;

        return $this;
    }

    public function shadowElevation(float $dp): static
    {
        $this->listItemProps['shadow_elevation'] = $dp;

        return $this;
    }

    public function disabled(bool $disabled = true): static
    {
        $this->listItemProps['disabled'] = $disabled;

        return $this;
    }

    // ── Resolution ───────────────────────────────────

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->listItemProps;

        if ($this->leadingChangeCallback !== null) {
            $props['on_leading_change'] = $registry->register($this->leadingChangeCallback);
        }
        if ($this->trailingChangeCallback !== null) {
            $props['on_trailing_change'] = $registry->register($this->trailingChangeCallback);
        }
        if ($this->trailingPressCallback !== null) {
            $props['on_trailing_press'] = $registry->register($this->trailingPressCallback);
        }
        if ($this->swipeDeleteCallback !== null) {
            $props['on_swipe_delete'] = $registry->register($this->swipeDeleteCallback);
        }

        // Multi-action swipe arrays — register each method, then emit
        // a JSON-encoded string per edge for the native renderer to
        // parse. Format: `[{"cb":42,"label":"Archive","icon":"archivebox","tint":"#10B981","role":""}, …]`
        if (! empty($this->leadingActions)) {
            $props['leading_actions_json'] = $this->serializeActions($this->leadingActions, $registry);
        }
        if (! empty($this->trailingActions)) {
            $props['trailing_actions_json'] = $this->serializeActions($this->trailingActions, $registry);
        }

        if (! empty($this->trailingBadges)) {
            $props['trailing_badges_json'] = $this->serializeBadges($this->trailingBadges);
        }

        return $props;
    }

    /**
     * Serialize trailing-badge specs. Resolves the typed icon via
     * IconResolver so the native side gets the platform-correct name
     * (and Material variant when applicable).
     *
     * @param  array<int, array<string, mixed>>  $badges
     */
    private function serializeBadges(array $badges): string
    {
        $out = [];
        foreach ($badges as $badge) {
            $resolved = IconResolver::resolve(
                $badge['icon'] ?? null,
                $badge['ios'] ?? null,
                $badge['android'] ?? null,
            );
            if (empty($resolved['icon'])) {
                continue;
            }
            $color = $badge['color'] ?? '';
            $out[] = [
                'icon' => $resolved['icon'],
                'icon_variant' => $resolved['variant'] ?? '',
                'color' => $color === '' ? '' : $this->resolveColorValue($color),
            ];
        }

        return json_encode($out);
    }

    /**
     * Serialize a swipe-action list to a JSON string for the wire.
     *
     * Each input action may carry a cross-platform `icon` string AND/OR
     * a typed `ios` (IosSymbol enum) / `android` (AndroidSymbol enum)
     * override. `IconResolver::resolve` chooses the right one for the
     * current platform — same logic as `HasPlatformIcon` builders so
     * the icon API is consistent across the framework.
     *
     * On Android, when the android override is an `AndroidSymbol`
     * enum case, the chosen variant (filled vs outlined) flows
     * through as `icon_variant` so the renderer picks the right font.
     *
     * @param  array<int, array<string, mixed>>  $actions
     */
    private function serializeActions(array $actions, CallbackRegistry $registry): string
    {
        $out = [];
        foreach ($actions as $action) {
            if (empty($action['method'])) {
                continue;
            }

            $resolved = IconResolver::resolve(
                $action['icon'] ?? null,
                $action['ios'] ?? null,
                $action['android'] ?? null,
            );

            $tint = $action['tint'] ?? '';
            $out[] = [
                'cb' => $registry->register($action['method']),
                'label' => $action['label'] ?? '',
                'icon' => $resolved['icon'] ?? '',
                'icon_variant' => $resolved['variant'] ?? '',
                'tint' => $tint === '' ? '' : $this->resolveColorValue($tint),
                'role' => $action['role'] ?? '',
            ];
        }

        return json_encode($out);
    }
}
