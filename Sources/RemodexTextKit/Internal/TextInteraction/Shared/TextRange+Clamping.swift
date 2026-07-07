#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  extension TextRange {
    /// Intersects this range with `bounds`, tolerating endpoints that are
    /// out of order or outside `bounds` (stale UIKit positions replayed
    /// after the layout collection reshaped).
    func intersectionClamped(to bounds: TextRange) -> TextRange {
      let clampedStart = min(max(start, bounds.start), bounds.end)
      let clampedEnd = min(max(end, bounds.start), bounds.end)
      return TextRange(from: clampedStart, to: clampedEnd)
    }
  }
#endif
