<?php

namespace Native\Mobile\UI\Concerns;

/**
 * State holder for `<native:reel>`. Native fires `on_page_change(index)`
 * after each swipe settles; the handler records it and the next render
 * emits the pages around it.
 *
 * A feed has no total. `reelLoaded` is how many items the screen has
 * fetched so far (the reel's `count`); when the settled page gets within
 * `reelNeedsMore()`'s threshold of that edge, fetch the next batch and
 * `extendReel()` — the pager grows in place. While `reelHasMore` is true
 * the reel appends a loading page after the last item, so the user can
 * pull into it instead of hitting a wall; settling there reports
 * `index === reelLoaded`, which `reelNeedsMore()` also treats as "more".
 *
 *   public function onReelPage(int $index): void
 *   {
 *       $this->setReelPage($index);
 *       if ($this->reelNeedsMore()) {
 *           $batch = $this->api->feed(cursor: $this->cursor);
 *           $this->ids = [...$this->ids, ...$batch->ids];
 *           $this->cursor = $batch->nextCursor;
 *           $this->extendReel(count($batch->ids), hasMore: $batch->nextCursor !== null);
 *       }
 *   }
 *
 * Every page's root element must carry `native:key="page-{$index}"` (or
 * any position-independent key); see Reel's docblock for why.
 *
 * Single reel per screen for now.
 */
trait HasReelPage
{
    /** Absolute index of the page currently settled on screen. */
    public int $reelPage = 0;

    /**
     * Pages shipped either side of the current one. 2 keeps a fast second
     * swipe on-device: the page after next is already there while the PHP
     * round-trip for the settle is still in flight. Each shipped page is
     * rendered Blade plus a buffering (not yet drawing) video, so keep it
     * small.
     */
    public int $reelWindow = 2;

    /** Items fetched so far — the reel's `count`. */
    public int $reelLoaded = 0;

    /** Whether another batch can be fetched; drives the trailing loading page. */
    public bool $reelHasMore = true;

    public function setReelPage(int $index): void
    {
        $this->reelPage = max(0, $index);
    }

    /** Record a fetched batch: grows the pager and updates the tail state. */
    public function extendReel(int $added, bool $hasMore = true): void
    {
        $this->reelLoaded += max(0, $added);
        $this->reelHasMore = $hasMore;
    }

    /**
     * True when the settled page is within `$threshold` items of the end
     * of what's loaded (or on the loading page itself) and more can be
     * fetched. Three is the usual feed default: the PHP round-trip plus
     * the API call has to land before the user swipes there.
     */
    public function reelNeedsMore(int $threshold = 3): bool
    {
        return $this->reelHasMore
            && $this->reelPage >= $this->reelLoaded - max(0, $threshold);
    }

    /** First page index PHP should emit for the current window. */
    public function reelWindowFrom(): int
    {
        return max(0, $this->reelPage - $this->reelWindow);
    }

    /** Last page index PHP should emit (inclusive), clamped to what's loaded. */
    public function reelWindowTo(): int
    {
        $to = $this->reelPage + $this->reelWindow;

        return $this->reelLoaded > 0 ? min($to, $this->reelLoaded - 1) : $to;
    }
}
