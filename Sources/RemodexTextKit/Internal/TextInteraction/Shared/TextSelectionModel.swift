#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  import SwiftUI

  // MARK: - Overview
  //
  // `TextSelectionModel` is the shared state object that backs selection and interaction.
  //
  // Platform views (AppKit/UIKit) mutate `selectedRange` in response to gestures and editing
  // commands. The model delegates layout-specific work to a `TextLayoutCollection`, which can be
  // rebuilt at any time as SwiftUI resolves new `Text.Layout` values. When the layout collection
  // changes, the model attempts to reconcile the current selection into the new layout so the
  // selection stays stable across updates.

  @Observable
  final class TextSelectionModel {
    var selectedRange: TextRange? {
      willSet {
        selectionWillChange?()
      }
      didSet {
        if selectedRange != nil {
          coordinator?.modelDidSelectText(self)
        }
        selectionDidChange?()
      }
    }

    @ObservationIgnored
    var selectionWillChange: (() -> Void)?

    @ObservationIgnored
    var selectionDidChange: (() -> Void)?

    @ObservationIgnored
    private var layoutCollection: any TextLayoutCollection

    @ObservationIgnored
    private weak var coordinator: TextSelectionCoordinator?

    init(
      layoutCollection: any TextLayoutCollection = EmptyTextLayoutCollection(),
      coordinator: TextSelectionCoordinator? = nil
    ) {
      self.layoutCollection = layoutCollection
      setCoordinator(coordinator)
    }

    func setLayoutCollection(_ layoutCollection: any TextLayoutCollection) {
      guard !layoutCollection.isEqual(to: self.layoutCollection) else {
        return
      }

      let oldLayoutCollection = self.layoutCollection
      self.layoutCollection = layoutCollection

      guard
        let selectedRange,
        layoutCollection.needsPositionReconciliation(with: oldLayoutCollection)
      else {
        return
      }

      // Try to reconcile the selected text range
      self.selectedRange = layoutCollection.reconcileRange(
        selectedRange,
        from: oldLayoutCollection
      )
    }

    func setCoordinator(_ coordinator: TextSelectionCoordinator?) {
      if self.coordinator === coordinator {
        return
      }

      self.coordinator = coordinator
      coordinator?.register(self)
    }

    func url(for point: CGPoint) -> URL? {
      layoutCollection.url(for: point)
    }

    func layoutIndex(of layout: Text.Layout) -> Int? {
      layoutCollection.index(of: layout)
    }
  }

  extension TextSelectionModel {
    var hasText: Bool {
      layoutCollection.stringLength > 0
    }

    var startPosition: TextPosition {
      layoutCollection.startPosition
    }

    var endPosition: TextPosition {
      layoutCollection.endPosition
    }

    // Positions and ranges arriving here can be stale: UIKit retains `UITextPosition`
    // boxes across SwiftUI layout rebuilds and replays them after the collection
    // changed shape. Clamp them at this boundary so every traversal below operates
    // on paths that resolve in the current collection.
    func clamped(_ position: TextPosition) -> TextPosition {
      layoutCollection.clamped(position)
    }

    func clamped(_ range: TextRange) -> TextRange {
      layoutCollection.clamped(range)
    }

    func attributedText(in range: TextRange) -> NSAttributedString {
      layoutCollection.attributedText(in: clamped(range))
    }

    func text(in range: TextRange) -> String {
      attributedText(in: range).string
    }

    func position(from position: TextPosition, offset: Int) -> TextPosition? {
      layoutCollection.position(from: clamped(position), offset: offset)
    }

    func offset(from: TextPosition, to: TextPosition) -> Int {
      layoutCollection.characterIndex(at: clamped(to))
        - layoutCollection.characterIndex(at: clamped(from))
    }

    func firstRect(for range: TextRange) -> CGRect {
      layoutCollection.firstRect(for: clamped(range))
    }

    func caretRect(for position: TextPosition) -> CGRect {
      layoutCollection.caretRect(for: clamped(position))
    }

    func selectionRects(for range: TextRange) -> [TextSelectionRect] {
      layoutCollection.selectionRects(for: clamped(range))
    }

    func selectionRects(for range: TextRange, layout: Text.Layout) -> [TextSelectionRect] {
      layoutCollection.selectionRects(for: clamped(range), layout: layout)
    }

    func closestPosition(to point: CGPoint) -> TextPosition? {
      layoutCollection.closestPosition(to: point)
    }

    func closestPosition(to point: CGPoint, within range: TextRange) -> TextPosition? {
      guard let position = closestPosition(to: point) else { return nil }
      let range = clamped(range)
      if position <= range.start { return range.start }
      if position >= range.end { return range.end }
      return position
    }

    func isPositionAtBlockBoundary(_ position: TextPosition) -> Bool {
      layoutCollection.isPositionAtBlockBoundary(clamped(position))
    }

    func positionAbove(_ position: TextPosition, anchor: TextPosition) -> TextPosition? {
      layoutCollection.positionAbove(clamped(position), anchor: clamped(anchor))
    }

    func positionBelow(_ position: TextPosition, anchor: TextPosition) -> TextPosition? {
      layoutCollection.positionBelow(clamped(position), anchor: clamped(anchor))
    }

    func characterRange(at point: CGPoint) -> TextRange? {
      layoutCollection.characterRange(at: point)
    }

    func blockStart(for position: TextPosition) -> TextPosition? {
      layoutCollection.blockStart(for: clamped(position))
    }

    func blockEnd(for position: TextPosition) -> TextPosition? {
      layoutCollection.blockEnd(for: clamped(position))
    }

    func blockRange(for position: TextPosition) -> TextRange? {
      layoutCollection.blockRange(for: clamped(position))
    }

    @available(macOS 10.0, *)
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    func wordRange(for position: TextPosition) -> TextRange? {
      layoutCollection.wordRange(for: clamped(position))
    }

    @available(macOS 10.0, *)
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    func nextWord(from position: TextPosition) -> TextPosition? {
      layoutCollection.nextWord(from: clamped(position))
    }

    @available(macOS 10.0, *)
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    func previousWord(from position: TextPosition) -> TextPosition? {
      layoutCollection.previousWord(from: clamped(position))
    }
  }
#endif
