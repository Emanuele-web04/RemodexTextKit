#if os(iOS)
  import SwiftUI
  import UIKit
  import XCTest

  import RemodexTextKit

  // A chat timeline mounts and unmounts structured-text rows while it scrolls, and a row that
  // resizes after its first layout pass moves every row below it. These tests pin that a view
  // reports its settled size on the first pass, with no follow-up size from preferences or
  // deferred state, and that block spacing keeps its collapsing rules.
  //
  // XCTest rather than Swift Testing: the measurements spin the main run loop, which must not
  // interleave with other main-actor tests.
  @MainActor
  final class FirstLayoutSizingTests: XCTestCase {
    private static let width: CGFloat = 390
    private static let bodyFontSize: CGFloat = 17

    private static let document = """
      # Release notes

      The parser now resolves **relative links** against the configured base URL, and falls \
      back to the document origin when no base is provided. See [the docs](https://example.com) \
      for the full rules.

      - Rebuilt the layout cache after each structural change
      - Kept `characterRange` stable across rewraps

      1. First
      2. Second

      | Command | Description |
      | --- | --- |
      | `git status` | List all new or modified files |
      | `git diff` | Show file differences that haven't been staged |

      ```swift
      func resolve(_ url: URL, against base: URL?) -> URL {
        URL(string: url.relativeString, relativeTo: base) ?? url
      }
      ```

      > A quoted paragraph.

      Closing paragraph.
      """

    func testFirstPassMatchesSettledSizeWhenOverflowScrolls() {
      assertStableSize(StructuredText(markdown: Self.document).remodex.overflowMode(.scroll))
    }

    func testFirstPassMatchesSettledSizeWhenOverflowWraps() {
      assertStableSize(StructuredText(markdown: Self.document).remodex.overflowMode(.wrap))
    }

    func testFirstPassMatchesSettledSizeWithUnboundedScrollingTables() {
      assertStableSize(
        StructuredText(markdown: Self.document)
          .remodex.tableStyle(.overflow(relativeWidth: .infinity))
          .remodex.overflowMode(.scroll)
      )
    }

    // Marker widths vary ("9." vs "1000."), so the list lines its markers up while measuring.
    func testOrderedListWithWideMarkersSizesOnFirstPass() {
      assertStableSize(
        StructuredText(
          markdown: """
            998. The sky above the port was the color of television, tuned to a dead channel.
            999. Short.
            1000. It was a bright cold day in April, and the clocks were striking thirteen.
               1. Nested item
               2. Another nested item
            """
        )
      )
    }

    // Capping a table at a multiple of the container width needs the container width, read
    // during layout: the mounted table must not resize once that width is known.
    func testCappedScrollingTableDoesNotResizeAfterMounting() {
      let view = StructuredText(
        markdown: """
          | Area | Notes |
          | --- | --- |
          | Rendering | Layout passes are predictable, but long cells should wrap cleanly once the table reaches its width cap. |
          """
      )
      .remodex.tableStyle(.overflow)
      .remodex.overflowMode(.scroll)

      let measurement = Self.measure(view)

      XCTAssertEqual(measurement.distinctReportedHeights.count, 1, "\(measurement)")
    }

    func testListCollapsesItsMarginsWithTheParagraphsInsideIt() {
      let spacing = Self.spacingBetween("Paragraph.", and: "- Item one\n- Item two")

      XCTAssertEqual(spacing, 0.8 * Self.bodyFontSize, accuracy: 0.5)
    }

    func testQuoteCollapsesItsMarginsWithTheParagraphsInsideIt() {
      let spacing = Self.spacingBetween("Paragraph.", and: "> Quoted paragraph.")

      XCTAssertEqual(spacing, 0.8 * Self.bodyFontSize, accuracy: 0.5)
    }

    func testHeadingKeepsItsTopSpacingAfterAParagraph() {
      let spacing = Self.spacingBetween("Paragraph.", and: "## Heading")

      XCTAssertEqual(spacing, 1.6 * Self.bodyFontSize, accuracy: 0.5)
    }

    func testListItemsUseListItemSpacing() {
      let single = Self.measure(StructuredText(markdown: "- Item")).settled
      let pair = Self.measure(StructuredText(markdown: "- Item\n- Item")).settled

      XCTAssertEqual(pair - 2 * single, 0.25 * Self.bodyFontSize, accuracy: 0.5)
    }

    // MARK: - Helpers

    private struct Measurement: CustomStringConvertible {
      /// The size measured before the view is in a window or the run loop turns.
      let firstPass: CGFloat
      /// Every height the view reported while mounted and settling, in order.
      let reportedHeights: [CGFloat]

      var settled: CGFloat { reportedHeights.last ?? 0 }

      var distinctReportedHeights: [CGFloat] {
        reportedHeights.reduce(into: []) { distinct, height in
          if let last = distinct.last, abs(last - height) < 0.5 { return }
          distinct.append(height)
        }
      }

      var description: String {
        "first pass \(firstPass), reported \(reportedHeights)"
      }
    }

    private final class HeightRecorder {
      var heights: [CGFloat] = []
    }

    private func assertStableSize(
      _ view: some View,
      file: StaticString = #filePath,
      line: UInt = #line
    ) {
      let measurement = Self.measure(view)

      XCTAssertEqual(
        measurement.distinctReportedHeights.count, 1, "\(measurement)", file: file, line: line)
      XCTAssertEqual(
        measurement.firstPass, measurement.settled, accuracy: 0.5, "\(measurement)", file: file,
        line: line)
    }

    private static func spacingBetween(_ first: String, and second: String) -> CGFloat {
      let combined = measure(StructuredText(markdown: first + "\n\n" + second)).settled
      return combined - measure(StructuredText(markdown: first)).settled
        - measure(StructuredText(markdown: second)).settled
    }

    private static func measure(_ view: some View) -> Measurement {
      let recorder = HeightRecorder()
      let host = UIHostingController(
        rootView:
          view
          .frame(width: width)
          .fixedSize(horizontal: false, vertical: true)
          .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
            recorder.heights.append(height)
          }
      )
      host.safeAreaRegions = []

      let firstPass = host.sizeThatFits(in: CGSize(width: width, height: 100_000)).height

      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 2_000))
      window.rootViewController = host
      window.makeKeyAndVisible()
      window.layoutIfNeeded()
      // Long enough for code highlighting and any deferred update to land.
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
      window.isHidden = true
      window.rootViewController = nil

      return Measurement(firstPass: firstPass, reportedHeights: recorder.heights)
    }
  }
#endif
