#if os(iOS)
  import SwiftUI
  import XCTest

  import RemodexTextKit

  // Measures the fixed cost of the text-selection machinery when many structured-text
  // views mount at once, like a chat timeline opening a long thread: per selectable view,
  // the selection system adds a `Text.LayoutKey` preference collection, a geometry reader,
  // and a `UITextInput` interaction overlay. The A/B delta between these two benchmarks
  // (same content, selection on vs off) is the number that decides whether callers need
  // viewport gating; absolute values are simulator/debug figures and only comparable
  // within one run.
  @MainActor
  final class TimelineSelectionBenchmarks: XCTestCase {
    private static let rowCount = 60

    private static func markdown(row: Int) -> String {
      """
      ## Update \(row)

      The parser now resolves **relative links** against the configured base URL, and \
      falls back to the document origin when no base is provided. See [the docs](https://example.com/docs/\(row)) \
      for the full resolution rules.

      - Rebuilt the layout cache after each structural change
      - Coalesced preference updates within a single frame
      - Kept `characterRange` stable across rewraps

      ```swift
      func resolve(_ url: URL, against base: URL?) -> URL {
        URL(string: url.relativeString, relativeTo: base) ?? url
      }
      ```

      In the worst case the resolver walks the whole chain once, so resolution stays \
      linear in the number of segments for message \(row).
      """
    }

    @ViewBuilder
    private func makeTimeline(selectable: Bool) -> some View {
      let timeline = ScrollView {
        // Eager VStack on purpose: mirrors a non-lazy chat timeline, so every row
        // pays its mount cost up front.
        VStack(alignment: .leading, spacing: 14) {
          ForEach(0..<Self.rowCount, id: \.self) { row in
            StructuredText(markdown: Self.markdown(row: row))
          }
        }
        .remodex.textSelectionScope()
        .padding(.horizontal, 16)
      }
      // Wrap overflow mirrors chat-timeline usage: code blocks wrap instead of
      // hosting their own scrollable region (and local interaction view).
      .remodex.overflowMode(.wrap)

      if selectable {
        timeline.remodex.textSelection(.enabled)
      } else {
        timeline
      }
    }

    // Mounts the timeline in a window and lets the run loop settle so preference
    // collection and overlay creation actually run, then tears it down. The run-loop
    // spin is fixed, so wall clock is flat by construction; compare the CPU and
    // memory metrics instead.
    private func mountAndSettle(selectable: Bool) -> UIWindow {
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
      window.rootViewController = UIHostingController(
        rootView: makeTimeline(selectable: selectable))
      window.makeKeyAndVisible()
      window.layoutIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
      return window
    }

    private func tearDown(_ window: UIWindow) {
      window.isHidden = true
      window.rootViewController = nil
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    private func interactionOverlayCount(in view: UIView) -> Int {
      var count = NSStringFromClass(type(of: view)).contains("UITextInteractionView") ? 1 : 0
      for subview in view.subviews {
        count += interactionOverlayCount(in: subview)
      }
      return count
    }

    // Sanity check, not a benchmark: the selectable variant must actually mount one
    // interaction overlay per row, and the plain variant none. If this fails, the
    // benchmarks compare nothing.
    func testBenchmarkFixtureMountsSelectionOverlays() {
      let plain = mountAndSettle(selectable: false)
      XCTAssertEqual(interactionOverlayCount(in: plain), 0)
      tearDown(plain)

      let selectable = mountAndSettle(selectable: true)
      XCTAssertEqual(interactionOverlayCount(in: selectable), Self.rowCount)
      tearDown(selectable)
    }

    private func firstInteractionOverlay(in view: UIView) -> UIView? {
      if NSStringFromClass(type(of: view)).contains("UITextInteractionView") {
        return view
      }
      for subview in view.subviews {
        if let match = firstInteractionOverlay(in: subview) {
          return match
        }
      }
      return nil
    }

    // Guards the benchmark against cross-iteration accumulation: a leaked interaction
    // overlay would both skew the measurements and leak in real apps on row unmount.
    func testSelectionOverlaysDeallocateAfterTeardown() {
      weak var probe: UIView?
      autoreleasepool {
        let window = mountAndSettle(selectable: true)
        probe = firstInteractionOverlay(in: window)
        XCTAssertNotNil(probe, "expected an interaction overlay in the selectable timeline")
        tearDown(window)
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
      XCTAssertNil(probe, "UITextInteractionView leaked after teardown")
    }

    func testMountTimelineWithSelectionDisabled() {
      measure(metrics: [XCTCPUMetric(), XCTMemoryMetric(), XCTClockMetric()]) {
        let window = mountAndSettle(selectable: false)
        tearDown(window)
      }
    }

    func testMountTimelineWithSelectionEnabled() {
      measure(metrics: [XCTCPUMetric(), XCTMemoryMetric(), XCTClockMetric()]) {
        let window = mountAndSettle(selectable: true)
        tearDown(window)
      }
    }
  }
#endif
