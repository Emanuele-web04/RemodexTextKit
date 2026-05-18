// FILE: UIKitTextViewHelpers.swift
// Purpose: Shared UIKit text-view primitives for RemodexTextKit renderers.
// Layer: Internal UIKit Rendering
// Exports: TextualTextMeasurementCache, UITextView rendering helpers
// Depends on: UIKit

#if canImport(UIKit) && !os(watchOS) && !os(tvOS)
  import UIKit

  struct TextualTextMeasurementKey: Equatable {
    let width: CGFloat?
    let wrapsText: Bool
    let textLength: Int
    let fontPointSize: CGFloat?

    init(
      width: CGFloat?,
      wrapsText: Bool,
      textLength: Int,
      fontPointSize: CGFloat? = nil
    ) {
      self.width = width
      self.wrapsText = wrapsText
      self.textLength = textLength
      self.fontPointSize = fontPointSize
    }
  }

  struct TextualTextMeasurementCache {
    private var key: TextualTextMeasurementKey?
    private var measuredSize: CGSize?

    mutating func size(
      for key: TextualTextMeasurementKey,
      measure: () -> CGSize
    ) -> CGSize {
      if self.key == key, let measuredSize {
        return measuredSize
      }

      let measuredSize = measure()
      self.key = key
      self.measuredSize = measuredSize
      return measuredSize
    }

    mutating func invalidate() {
      key = nil
      measuredSize = nil
    }
  }

  extension UITextView {
    // Applies the common non-scrolling, intrinsic-height setup used by RemodexTextKit renderers.
    func configureForTextualIntrinsicRendering() {
      backgroundColor = .clear
      isEditable = false
      isScrollEnabled = false
      textContainerInset = .zero
      textContainer.lineFragmentPadding = 0
      adjustsFontForContentSizeCategory = true
      setContentCompressionResistancePriority(.required, for: .vertical)
      setContentHuggingPriority(.required, for: .vertical)
    }

    // Preserves copy/selection state while replacing or mutating backing text storage.
    func textualPreservingSelectedRange(_ updates: () -> Void) {
      let selectedRange = selectedRange
      let hadSelection = selectedRange.location != NSNotFound

      updates()

      guard hadSelection else {
        return
      }

      let safeLocation = min(selectedRange.location, textStorage.length)
      let safeLength = min(selectedRange.length, textStorage.length - safeLocation)
      self.selectedRange = NSRange(location: safeLocation, length: safeLength)
    }

    // Invalidates SwiftUI/UIKit layout after direct text-storage changes.
    func invalidateTextualIntrinsicLayout(includingSuperview: Bool = false) {
      invalidateIntrinsicContentSize()

      guard includingSuperview else {
        return
      }

      setNeedsLayout()
      superview?.setNeedsLayout()
    }
  }
#endif
