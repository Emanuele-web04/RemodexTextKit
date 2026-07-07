#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  import Foundation
  import Testing

  @testable import RemodexTextKit

  struct TextRangeClampingTests {
    private func position(
      runSlice: Int = 0,
      run: Int = 0,
      line: Int = 0,
      layout: Int = 0,
      affinity: TextPosition.Affinity = .downstream
    ) -> TextPosition {
      TextPosition(
        indexPath: .init(runSlice: runSlice, run: run, line: line, layout: layout),
        affinity: affinity
      )
    }

    @Test
    func rangeFullyInsideBoundsIsUnchanged() {
      // given
      let bounds = TextRange(
        from: position(run: 0, line: 0),
        to: position(run: 5, line: 0)
      )
      let range = TextRange(
        from: position(run: 1, line: 0),
        to: position(run: 3, line: 0)
      )

      // when
      let clamped = range.intersectionClamped(to: bounds)

      // then
      #expect(clamped == range)
    }

    @Test
    func rangeStraddlingBoundsIsClampedToBounds() {
      // given
      let bounds = TextRange(
        from: position(run: 1, line: 0),
        to: position(run: 4, line: 0)
      )
      let range = TextRange(
        from: position(run: 0, line: 0),
        to: position(run: 6, line: 0)
      )

      // when
      let clamped = range.intersectionClamped(to: bounds)

      // then
      #expect(clamped == bounds)
    }

    @Test
    func staleRangeBeyondBoundsEndProducesValidCollapsedRange() {
      // given: both endpoints come from a larger, pre-reshape layout whose
      // index paths now lexicographically exceed every position in
      // `bounds`. The old buggy formula (`max(rawStart, bounds.start)` for
      // start, `min(rawEnd, bounds.end)` for end) produced
      // `start == rawStart > end == bounds.end`, tripping the
      // `TextRange.init(start:end:)` assert. This is the crash regression.
      let bounds = TextRange(
        from: position(run: 0, line: 0),
        to: position(run: 3, line: 0)
      )
      let range = TextRange(
        from: position(run: 10, line: 0),
        to: position(run: 15, line: 0)
      )

      // when
      let clamped = range.intersectionClamped(to: bounds)

      // then
      #expect(clamped.start <= clamped.end)
      #expect(clamped.start >= bounds.start)
      #expect(clamped.end <= bounds.end)
      #expect(clamped == TextRange(from: bounds.end, to: bounds.end))
    }

    @Test
    func staleRangeBeforeBoundsStartProducesValidCollapsedRange() {
      // given: both endpoints sit entirely below `bounds.start`.
      let bounds = TextRange(
        from: position(run: 2, line: 0),
        to: position(run: 5, line: 0)
      )
      let range = TextRange(
        from: position(run: 0, line: 0),
        to: position(run: 1, line: 0)
      )

      // when
      let clamped = range.intersectionClamped(to: bounds)

      // then
      #expect(clamped.start <= clamped.end)
      #expect(clamped.start >= bounds.start)
      #expect(clamped.end <= bounds.end)
      #expect(clamped == TextRange(from: bounds.start, to: bounds.start))
    }
  }
#endif
