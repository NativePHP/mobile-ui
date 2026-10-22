<?php

namespace Native\Mobile\UI\Elements;

use Illuminate\Support\Str;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\UI\Concerns\ResolvesColorValues;
use Native\Mobile\UI\Theme;

/**
 * Full-screen snap pager — the TikTok / Reels / Shorts feed. Each page
 * fills the container; a swipe settles on exactly one page. Vertical by
 * default, `horizontal` for a stories-style strip.
 *
 * The children are the pages. For a feed, ship only a window of them and
 * tell the pager where that window sits:
 *
 *   <native:pager :count="$loaded" :page="$page" :from="$from" :to="$to"
 *                has-more on-page-change="onPagerPage">
 *       ... one {{ '@' }}include('feed.page', ['index' => $i]) per $i in $from..$to,
 *           each rooted at <stack :native:key="'page-'.$i"> ...
 *   </native:pager>
 *
 * Key the root of every page with `native:key` (an id that does not depend
 * on the page's slot in the window). The window slides by one on every
 * swipe, so an unkeyed page gets a new positional node id at each render
 * and native rebuilds its whole subtree — a video surface restarts from
 * zero one round-trip after the swipe settles. A bare `key` attribute is
 * NOT the same thing and is silently ignored.
 *
 * Native lays out `count` logical pages and shows a placeholder for any
 * page outside `[from..to]`. `count` is how many items are loaded SO FAR,
 * not a total — a feed has none; grow it as batches arrive and the pager
 * grows in place. With `has-more` native appends a loading page after the
 * last item; settling on it reports `index === count`. Pair with the
 * `HasPagerWindow` trait — native fires `on_page_change(int $index)` after
 * each swipe settles and the next render emits the pages around it.
 *
 * Native reports the page as soon as it becomes the nearest one during a
 * swipe (not once the scroll rests), so PHP's round-trip overlaps the
 * animation. That suits a media feed, where the next page's video should
 * start loading early. A screen whose frame is heavy can stutter when that
 * frame lands mid-swipe; `report-on-settle` waits until the scroll rests.
 * Native keeps the pager position across re-renders; `page` only moves the
 * pager when PHP sends an index native never reported (a programmatic
 * jump) — echoes of earlier reports are ignored.
 *
 * `placeholders` gives every loaded page an image to show before it is
 * shipped (see placeholders()).
 *
 * `tabs` draws a row of tabs above the pages, one label per page:
 *
 *   <native:pager horizontal :tabs="['Following', 'Latest', 'Trending']"
 *                 :page="$page" on-page-change="showPage"
 *                 on-tab-reselect="scrollToTop">
 *
 * Native owns the row. Its indicator follows the swipe frame by frame, the
 * label under it switches as the swipe passes halfway, and a tap scrolls
 * the pager to that page, all without PHP. The page change is reported as
 * usual once the pager gets there. A tap on the tab already showing calls
 * `on-tab-reselect` instead, with the index, so the page can go back to
 * its top. `tabs-scrollable` makes the tabs as wide as their labels in a
 * row that scrolls, keeping the current one in view; by default they share
 * the row equally. Colours default to the theme (`on-surface`,
 * `on-surface-variant`, `primary`, `outline-variant`), and the `tab-*`
 * attributes override them per pager, since the row sits on whatever the
 * pages are (light labels over a video feed, say).
 *
 * The page index rides the tab-change transport, so a single feed is
 * capped at 32,767 pages per screen.
 */
class Pager extends Element
{
    use ResolvesColorValues;

    protected string $type = 'pager';

    /** @var array<string, mixed> */
    protected array $pagerProps = [];

    protected ?string $pageCallback = null;

    protected ?string $tabReselectCallback = null;

    public static function make(Element ...$children): static
    {
        $el = new static;
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['count'])) {
            $this->count((int) $attrs['count']);
        }
        if (isset($attrs['page'])) {
            $this->page((int) $attrs['page']);
        }
        $from = $attrs['window_from'] ?? $attrs['windowFrom'] ?? $attrs['from'] ?? null;
        if ($from !== null) {
            $this->pagerProps['window_from'] = (int) $from;
        }
        $to = $attrs['window_to'] ?? $attrs['windowTo'] ?? $attrs['to'] ?? null;
        if ($to !== null) {
            $this->pagerProps['window_to'] = (int) $to;
        }
        if (isset($attrs['horizontal'])) {
            $this->horizontal(filter_var($attrs['horizontal'], FILTER_VALIDATE_BOOLEAN));
        }
        $more = $attrs['has_more'] ?? $attrs['hasMore'] ?? $attrs['has-more'] ?? null;
        if ($more !== null) {
            $this->hasMore(filter_var($more, FILTER_VALIDATE_BOOLEAN));
        }
        if (isset($attrs['placeholders']) && is_array($attrs['placeholders'])) {
            $this->placeholders($attrs['placeholders']);
        }
        $settle = $attrs['report_on_settle'] ?? $attrs['reportOnSettle'] ?? $attrs['report-on-settle'] ?? null;
        if ($settle !== null) {
            $this->reportOnSettle(filter_var($settle, FILTER_VALIDATE_BOOLEAN));
        }
        $cb = $attrs['on_page_change'] ?? $attrs['onPageChange'] ?? $attrs['on-page-change'] ?? null;
        if ($cb !== null) {
            $this->onPageChange($cb);
        }

        $this->applyTabAttributes($attrs);

        $this->applyA11yAttributes($attrs);
    }

    /** Items loaded so far. Defaults to the number of inline children. */
    public function count(int $count): static
    {
        $this->pagerProps['count'] = max(0, $count);

        return $this;
    }

    /** Page the pager should show; see the class doc for when it moves. */
    public function page(int $index): static
    {
        $this->pagerProps['page'] = max(0, $index);

        return $this;
    }

    public function horizontal(bool $value = true): static
    {
        $this->pagerProps['horizontal'] = $value;

        return $this;
    }

    /**
     * Append a loading page after the last loaded item. The user can pull
     * into it while the next batch is fetched; settling there reports
     * `index === count`.
     */
    public function hasMore(bool $value = true): static
    {
        $this->pagerProps['has_more'] = $value;

        return $this;
    }

    /**
     * One image URL per page index (empty string for none), for every
     * loaded item — not just the shipped window. A page PHP hasn't shipped
     * yet shows its image instead of nothing, so scrolling faster than the
     * round-trip lands on a still rather than a blank. Twenty URLs is a
     * trivial payload; the images are fetched and cached natively.
     *
     * @param  array<int, string|null>  $urls
     */
    public function placeholders(array $urls): static
    {
        $this->pagerProps['placeholders'] = array_map(fn ($u) => (string) ($u ?? ''), array_values($urls));

        return $this;
    }

    /**
     * Report the page once the scroll comes to rest, instead of as soon as
     * it becomes the nearest one mid-swipe. Use it when the render a page
     * change causes is big enough to drop frames if it lands during the
     * swipe animation.
     */
    public function reportOnSettle(bool $value = true): static
    {
        $this->pagerProps['report_on_settle'] = $value;

        return $this;
    }

    public function onPageChange(string $method): static
    {
        $this->pageCallback = $method;

        return $this;
    }

    /**
     * One tab per page, drawn natively above the pages. Each is a label, or
     * `['label' => ..., 'a11y-label' => ...]` when the label read out should
     * say more than the one shown.
     *
     * @param  array<int, string|array{label?: string, a11y-label?: string, a11y_label?: string, a11yLabel?: string}>  $tabs
     */
    public function tabs(array $tabs): static
    {
        $labels = [];
        $a11yLabels = [];

        foreach (array_values($tabs) as $tab) {
            if (is_array($tab)) {
                $labels[] = (string) ($tab['label'] ?? '');
                $a11yLabels[] = (string) ($tab['a11y-label'] ?? $tab['a11y_label'] ?? $tab['a11yLabel'] ?? '');
            } else {
                $labels[] = (string) $tab;
                $a11yLabels[] = '';
            }
        }

        $this->pagerProps['tabs'] = $labels;

        if (array_filter($a11yLabels) !== []) {
            $this->pagerProps['tab_a11y_labels'] = $a11yLabels;
        } else {
            unset($this->pagerProps['tab_a11y_labels']);
        }

        return $this;
    }

    /**
     * Tabs as wide as their labels, in a row that scrolls sideways and keeps
     * the current tab in view. By default the tabs share the row equally.
     */
    public function tabsScrollable(bool $value = true): static
    {
        $this->pagerProps['tabs_scrollable'] = $value;

        return $this;
    }

    /**
     * Called with `(int $index)` when the tab already showing is tapped,
     * the usual cue to scroll that page back to its top.
     */
    public function onTabReselect(string $method): static
    {
        $this->tabReselectCallback = $method;

        return $this;
    }

    /** Inactive label colour. Default: `theme.on-surface-variant`. */
    public function tabColor(string $color): static
    {
        return $this->tabColorProp('tab_color', $color);
    }

    /** Active label colour. Default: `theme.on-surface`. */
    public function tabActiveColor(string $color): static
    {
        return $this->tabColorProp('tab_active_color', $color);
    }

    /** Indicator colour. Default: `theme.primary`. */
    public function tabIndicatorColor(string $color): static
    {
        return $this->tabColorProp('tab_indicator_color', $color);
    }

    /** Colour of the hairline under the row; `transparent` hides it. Default: `theme.outline-variant`. */
    public function tabDividerColor(string $color): static
    {
        return $this->tabColorProp('tab_divider_color', $color);
    }

    /** Label font: a bundled font file's basename or a `fonts` alias. Default: the theme's font. */
    public function tabFont(string $font): static
    {
        $this->pagerProps['tab_font'] = $font;

        return $this;
    }

    /** Label size in points. Default: `theme.font-md`. */
    public function tabFontSize(float $size): static
    {
        $this->pagerProps['tab_font_size'] = max(0.0, $size);

        return $this;
    }

    /** Indicator thickness in points. Default: 3. */
    public function tabIndicatorHeight(float $height): static
    {
        $this->pagerProps['tab_indicator_height'] = max(0.0, $height);

        return $this;
    }

    /**
     * Space around each label, in points: `$x` either side, `$top` above it
     * and `$bottom` between it and the indicator. Defaults: 12, 14 and 11,
     * which with the indicator makes a 48pt tab at the default font size.
     */
    public function tabPadding(?float $x = null, ?float $top = null, ?float $bottom = null): static
    {
        foreach (['tab_padding_x' => $x, 'tab_padding_top' => $top, 'tab_padding_bottom' => $bottom] as $prop => $value) {
            if ($value !== null) {
                $this->pagerProps[$prop] = max(0.0, $value);
            }
        }

        return $this;
    }

    /** Space before the first and after the last tab of a scrollable row, in points. Default: 4. */
    public function tabEdgePadding(float $padding): static
    {
        $this->pagerProps['tab_edge_padding'] = max(0.0, $padding);

        return $this;
    }

    /**
     * @param  array<string, mixed>  $attrs
     */
    protected function applyTabAttributes(array $attrs): void
    {
        // Each attribute as written in Blade, in snake case, or in camel case.
        $attr = fn (string $name): mixed => $attrs[$name] ?? $attrs[str_replace('-', '_', $name)] ?? $attrs[Str::camel($name)] ?? null;

        if (is_array($tabs = $attr('tabs'))) {
            $this->tabs($tabs);
        }
        if (($scrollable = $attr('tabs-scrollable')) !== null) {
            $this->tabsScrollable(filter_var($scrollable, FILTER_VALIDATE_BOOLEAN));
        }
        if (($reselect = $attr('on-tab-reselect')) !== null) {
            $this->onTabReselect((string) $reselect);
        }
        if (($color = $attr('tab-color')) !== null) {
            $this->tabColor((string) $color);
        }
        if (($color = $attr('tab-active-color')) !== null) {
            $this->tabActiveColor((string) $color);
        }
        if (($color = $attr('tab-indicator-color')) !== null) {
            $this->tabIndicatorColor((string) $color);
        }
        if (($color = $attr('tab-divider-color')) !== null) {
            $this->tabDividerColor((string) $color);
        }
        if (($font = $attr('tab-font')) !== null) {
            $this->tabFont((string) $font);
        }
        if (($size = $attr('tab-font-size')) !== null) {
            $this->tabFontSize((float) $size);
        }
        if (($height = $attr('tab-indicator-height')) !== null) {
            $this->tabIndicatorHeight((float) $height);
        }

        $paddingX = $attr('tab-padding-x');
        $paddingTop = $attr('tab-padding-top');
        $paddingBottom = $attr('tab-padding-bottom');
        $this->tabPadding(
            $paddingX === null ? null : (float) $paddingX,
            $paddingTop === null ? null : (float) $paddingTop,
            $paddingBottom === null ? null : (float) $paddingBottom,
        );

        if (($edge = $attr('tab-edge-padding')) !== null) {
            $this->tabEdgePadding((float) $edge);
        }
    }

    /**
     * A colour in the theme config's grammar, or `theme-<token>` for one of
     * the theme's tokens, which also sends its dark shade.
     */
    protected function tabColorProp(string $prop, string $color): static
    {
        unset($this->pagerProps[$prop], $this->pagerProps['dark_'.$prop]);

        if (! str_starts_with($color, 'theme-')) {
            $this->pagerProps[$prop] = $this->resolveColorValue($color);

            return $this;
        }

        $token = substr($color, 6);
        $light = Theme::get("light.{$token}");
        $dark = Theme::get("dark.{$token}");

        if (is_string($light)) {
            $this->pagerProps[$prop] = $light;
        }
        if (is_string($dark) && $dark !== $light) {
            $this->pagerProps['dark_'.$prop] = $dark;
        }

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->pagerProps;

        if (! isset($props['count'])) {
            $props['count'] = count($this->children);
        }

        if ($this->pageCallback !== null) {
            // Rides the TAB_CHANGE transport: dispatch hands the handler
            // one int — the settled page index.
            $props['on_page_change'] = $registry->register($this->pageCallback);
        }

        if ($this->tabReselectCallback !== null) {
            // Same transport: the handler gets the tapped tab's index.
            $props['on_tab_reselect'] = $registry->register($this->tabReselectCallback);
        }

        return $props;
    }
}
