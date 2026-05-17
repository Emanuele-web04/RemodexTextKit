// FILE: UIKitAttributedTextView.swift
// Purpose: Lightweight UITextView bridge for optimized attributed text fragments.
// Layer: Internal UIKit Rendering
// Exports: UIKitAttributedTextView
// Depends on: SwiftUI, UIKit, TextEnvironmentValues

#if canImport(UIKit) && !os(watchOS) && !os(tvOS)
  import SwiftUI
  import UIKit

  struct UIKitAttributedTextView: UIViewRepresentable {
    enum FontDesign: Hashable, Sendable {
      case `default`
      case monospaced
    }

    let attributedString: AttributedString
    let textEnvironment: TextEnvironmentValues
    let isSelectable: Bool
    let wrapsText: Bool
    let fontDesign: FontDesign
    let fallbackForegroundColor: Color?

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
      let textView = UITextView()
      textView.backgroundColor = .clear
      textView.isEditable = false
      textView.isScrollEnabled = false
      textView.textContainerInset = .zero
      textView.textContainer.lineFragmentPadding = 0
      textView.adjustsFontForContentSizeCategory = true
      textView.setContentCompressionResistancePriority(.required, for: .vertical)
      textView.setContentHuggingPriority(.required, for: .vertical)
      textView.delegate = context.coordinator
      updateUIView(textView, context: context)
      return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
      context.coordinator.openURL = context.environment.openURL
      context.coordinator.render(
        attributedString,
        in: textView,
        environment: textEnvironment,
        isSelectable: isSelectable,
        wrapsText: wrapsText,
        fontDesign: fontDesign,
        fallbackForegroundColor: fallbackForegroundColor
      )
    }

    func sizeThatFits(
      _ proposal: ProposedViewSize,
      uiView: UITextView,
      context _: Context
    ) -> CGSize? {
      let measuredSize = uiView.attributedText.textualBoundingSize(
        constrainedTo: proposal.width,
        wrapsText: wrapsText
      )

      if wrapsText, let width = proposal.width {
        return CGSize(width: width, height: measuredSize.height)
      }

      return measuredSize
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
      var openURL: OpenURLAction?

      private var renderedAttributedString = AttributedString()
      private var renderedEnvironment = TextEnvironmentValues()
      private var renderedIsSelectable = true
      private var renderedWrapsText = true
      private var renderedFontDesign = FontDesign.default
      private var renderedFallbackForegroundColor: Color?

      func render(
        _ attributedString: AttributedString,
        in textView: UITextView,
        environment: TextEnvironmentValues,
        isSelectable: Bool,
        wrapsText: Bool,
        fontDesign: FontDesign,
        fallbackForegroundColor: Color?
      ) {
        textView.textContainer.lineBreakMode = wrapsText ? .byWordWrapping : .byClipping
        textView.textContainer.widthTracksTextView = wrapsText
        textView.isSelectable = isSelectable || attributedString.containsValues(for: [\.link])
        textView.isUserInteractionEnabled = textView.isSelectable
        textView.tintColor = .tintColor

        guard
          attributedString != renderedAttributedString
            || environment != renderedEnvironment
            || isSelectable != renderedIsSelectable
            || wrapsText != renderedWrapsText
            || fontDesign != renderedFontDesign
            || fallbackForegroundColor != renderedFallbackForegroundColor
        else {
          return
        }

        let selectedRange = textView.selectedRange
        let hadSelection = selectedRange.location != NSNotFound

        textView.attributedText = Self.resolvedAttributedString(
          from: attributedString,
          environment: environment,
          fontDesign: fontDesign,
          fallbackForegroundColor: fallbackForegroundColor
        )

        if hadSelection {
          let safeLocation = min(selectedRange.location, textView.textStorage.length)
          let safeLength = min(selectedRange.length, textView.textStorage.length - safeLocation)
          textView.selectedRange = NSRange(location: safeLocation, length: safeLength)
        }

        renderedAttributedString = attributedString
        renderedEnvironment = environment
        renderedIsSelectable = isSelectable
        renderedWrapsText = wrapsText
        renderedFontDesign = fontDesign
        renderedFallbackForegroundColor = fallbackForegroundColor
        textView.invalidateIntrinsicContentSize()
      }

      @available(iOS, deprecated: 17.0, message: "Use UITextView text item delegate methods.")
      func textView(
        _: UITextView,
        shouldInteractWith URL: URL,
        in _: NSRange,
        interaction _: UITextItemInteraction
      ) -> Bool {
        guard let openURL else {
          return true
        }

        openURL(URL)
        return false
      }

      private static func resolvedAttributedString(
        from attributedString: AttributedString,
        environment: TextEnvironmentValues,
        fontDesign: FontDesign,
        fallbackForegroundColor: Color?
      ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let fallbackForegroundColor = fallbackForegroundColor.map(UIColor.init) ?? UIColor.label

        for run in attributedString.runs {
          let substring = AttributedString(attributedString[run.range])
          let piece = NSMutableAttributedString(attributedString: NSAttributedString(substring))
          let range = NSRange(location: 0, length: piece.length)

          guard range.length > 0 else {
            continue
          }

          piece.addAttribute(
            .font,
            value: platformFont(
              for: run.font,
              intent: run.inlinePresentationIntent,
              environment: environment,
              design: fontDesign
            ),
            range: range
          )

          if let foregroundColor = run.foregroundColor {
            piece.addAttribute(.foregroundColor, value: UIColor(foregroundColor), range: range)
          } else {
            piece.addAttribute(.foregroundColor, value: fallbackForegroundColor, range: range)
          }

          if let backgroundColor = run.backgroundColor {
            piece.addAttribute(.backgroundColor, value: UIColor(backgroundColor), range: range)
          }

          if run.underlineStyle != nil {
            piece.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
          }

          if run.strikethroughStyle != nil {
            piece.addAttribute(
              .strikethroughStyle,
              value: NSUnderlineStyle.single.rawValue,
              range: range
            )
          }

          if let link = run.link {
            piece.addAttribute(.link, value: link, range: range)
          }

          output.append(piece)
        }

        return output
      }

      private static func platformFont(
        for font: Font?,
        intent: InlinePresentationIntent?,
        environment: TextEnvironmentValues,
        design: FontDesign
      ) -> UIFont {
        let pointSize =
          font?.provider()?.size(in: environment)
          ?? environment.font?.provider()?.size(in: environment)
          ?? UIFont.preferredFont(forTextStyle: .body).pointSize

        let intent = intent ?? []
        let weight: UIFont.Weight = intent.contains(.stronglyEmphasized) ? .semibold : .regular

        let baseFont: UIFont
        if design == .monospaced || intent.contains(.code) {
          baseFont = UIFont.monospacedSystemFont(ofSize: pointSize, weight: weight)
        } else {
          baseFont = UIFont.systemFont(ofSize: pointSize, weight: weight)
        }

        guard intent.contains(.emphasized),
          let italicDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic)
        else {
          return baseFont
        }

        return UIFont(descriptor: italicDescriptor, size: pointSize)
      }
    }
  }

  extension NSAttributedString {
    func textualBoundingSize(constrainedTo width: CGFloat?, wrapsText: Bool) -> CGSize {
      guard length > 0 else {
        return .zero
      }

      let targetWidth: CGFloat
      if wrapsText, let width {
        targetWidth = width
      } else {
        targetWidth = CGFloat.greatestFiniteMagnitude
      }

      let rect = boundingRect(
        with: CGSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )

      return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
  }
#endif
