#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION && canImport(UIKit)
  import SwiftUI
  import os
  import UniformTypeIdentifiers

  // MARK: - Overview
  //
  // `UITextInteractionView` implements selection and link interaction on iOS-family platforms.
  //
  // The view sits in an overlay above one or more rendered `Text` fragments. It uses
  // `TextSelectionModel` to translate touch locations into URLs and selection ranges, and it
  // respects `exclusionRects` so embedded scrollable regions can continue to handle gestures.
  // Selection UI is provided by `UITextInteraction` configured for non-editable content.
  // While text is selected, a tap anywhere off the selection clears it, including elsewhere
  // in the same text, which `UITextInteraction` leaves selected for non-editable content.

  final class UITextInteractionView: UIView {
    override var canBecomeFirstResponder: Bool {
      true
    }

    var model: TextSelectionModel
    var exclusionRects: [CGRect]
    var openURL: OpenURLAction

    weak var inputDelegate: (any UITextInputDelegate)?

    let logger = Logger(category: .textInteraction)

    private(set) lazy var _tokenizer = UITextInputStringTokenizer(textInput: self)
    private let selectionInteraction: UITextInteraction
    private lazy var outsideTapGesture: UITapGestureRecognizer = {
      let gesture = UITapGestureRecognizer(target: self, action: #selector(handleOutsideTap(_:)))
      // Observe only: the tapped control or scroll view still gets the touch.
      gesture.cancelsTouchesInView = false
      gesture.delegate = self
      return gesture
    }()

    init(
      model: TextSelectionModel,
      exclusionRects: [CGRect],
      openURL: OpenURLAction
    ) {
      self.model = model
      self.exclusionRects = exclusionRects
      self.openURL = openURL
      self.selectionInteraction = UITextInteraction(for: .nonEditable)

      super.init(frame: .zero)
      self.backgroundColor = .clear

      setUp()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
      for exclusionRect in exclusionRects {
        if exclusionRect.contains(point) {
          return false
        }
      }
      return super.point(inside: point, with: event)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
      switch action {
      case #selector(copy(_:)), #selector(share(_:)):
        return !(model.selectedRange?.isCollapsed ?? true)
      default:
        return false
      }
    }

    override func copy(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let formatter = Formatter(attributedText)

      UIPasteboard.general.setItems(
        [
          [
            UTType.plainText.identifier: formatter.plainText(),
            UTType.html.identifier: formatter.html(),
          ]
        ]
      )
    }

    private func setUp() {
      model.selectionWillChange = { [weak self] in
        guard let self else { return }
        self.inputDelegate?.selectionWillChange(self)
      }
      model.selectionDidChange = { [weak self] in
        guard let self else { return }
        self.inputDelegate?.selectionDidChange(self)
        self.updateOutsideTapGesture()
      }

      let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      addGestureRecognizer(tapGesture)

      selectionInteraction.textInput = self
      selectionInteraction.delegate = self

      for gesture in selectionInteraction.gesturesForFailureRequirements {
        tapGesture.require(toFail: gesture)
        // A double tap selects a word; its first tap must not clear the result.
        outsideTapGesture.require(toFail: gesture)
      }

      addInteraction(selectionInteraction)
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      updateOutsideTapGesture()
    }

    // The window-level recognizer exists only while there is a selection to clear.
    private func updateOutsideTapGesture() {
      let hasSelection = !(model.selectedRange?.isCollapsed ?? true)
      let targetView: UIView? = hasSelection ? window : nil
      guard outsideTapGesture.view !== targetView else {
        return
      }
      outsideTapGesture.view?.removeGestureRecognizer(outsideTapGesture)
      targetView?.addGestureRecognizer(outsideTapGesture)
    }

    @objc private func handleOutsideTap(_ gesture: UITapGestureRecognizer) {
      // Deferred so an edit-menu action from the same tap (Copy, Share) still
      // reads the selection before it is cleared.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.model.selectedRange != nil else {
          return
        }
        self.model.selectedRange = nil
        if self.isFirstResponder {
          _ = self.resignFirstResponder()
        }
      }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
      let location = gesture.location(in: self)
      guard let url = model.url(for: location) else {
        return
      }
      openURL(url)
    }

    @objc private func share(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let itemSource = TextActivityItemSource(attributedString: attributedText)

      let activityViewController = UIActivityViewController(
        activityItems: [itemSource],
        applicationActivities: nil
      )

      if let popover = activityViewController.popoverPresentationController {
        let rect =
          model.selectionRects(for: selectedRange)
          .last?.rect.integral ?? .zero
        popover.sourceView = self
        popover.sourceRect = rect
      }

      if let windowScene = window?.windowScene,
        let viewController = windowScene.windows.first?.rootViewController
      {
        viewController.present(activityViewController, animated: true)
      }
    }
  }

  extension UITextInteractionView: UITextInteractionDelegate {
    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
      logger.debug("interactionShouldBegin(at: \(point.logDescription)) -> true")
      return true
    }

    func interactionWillBegin(_ interaction: UITextInteraction) {
      logger.debug("interactionWillBegin")
      _ = self.becomeFirstResponder()
    }

    func interactionDidEnd(_ interaction: UITextInteraction) {
      logger.debug("interactionDidEnd")
    }
  }

  extension UITextInteractionView: UIGestureRecognizerDelegate {
    private static let selectionHitSlop: CGFloat = 12

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldReceive touch: UITouch
    ) -> Bool {
      guard gestureRecognizer === outsideTapGesture else {
        return true
      }
      // Taps on the selection itself toggle the edit menu.
      return !isOnSelection(touch.location(in: self))
    }

    private func isOnSelection(_ point: CGPoint) -> Bool {
      guard let selectedRange = model.selectedRange else {
        return false
      }
      return model.selectionRects(for: selectedRange).contains {
        // Include the selection handles drawn just outside the text.
        $0.rect.insetBy(dx: -Self.selectionHitSlop, dy: -Self.selectionHitSlop).contains(point)
      }
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      gestureRecognizer === outsideTapGesture
    }
  }

  extension Logger.RemodexTextKit.Category {
    fileprivate static let textInteraction = Self(rawValue: "textInteraction")
  }
#endif
