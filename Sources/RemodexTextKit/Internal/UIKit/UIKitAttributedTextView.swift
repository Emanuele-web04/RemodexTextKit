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

    func makeUIView(context: Context) -> MeasuringTextView {
      let textView = MeasuringTextView()
      textView.configureForTextualIntrinsicRendering()
      textView.delegate = context.coordinator
      updateUIView(textView, context: context)
      return textView
    }

    func updateUIView(_ textView: MeasuringTextView, context: Context) {
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
      uiView: MeasuringTextView,
      context _: Context
    ) -> CGSize? {
      let measuredSize = uiView.measuredSize(
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
      private var renderedContainsLinks = false

      func render(
        _ attributedString: AttributedString,
        in textView: MeasuringTextView,
        environment: TextEnvironmentValues,
        isSelectable: Bool,
        wrapsText: Bool,
        fontDesign: FontDesign,
        fallbackForegroundColor: Color?
      ) {
        let attributedStringChanged = attributedString != renderedAttributedString
        let containsLinks =
          attributedStringChanged
          ? attributedString.containsValue(for: \.link)
          : renderedContainsLinks

        textView.textContainer.lineBreakMode = wrapsText ? .byWordWrapping : .byClipping
        textView.textContainer.widthTracksTextView = wrapsText
        textView.isSelectable = isSelectable || containsLinks
        textView.isUserInteractionEnabled = textView.isSelectable
        textView.tintColor = .tintColor

        guard
          attributedStringChanged
            || environment != renderedEnvironment
            || isSelectable != renderedIsSelectable
            || wrapsText != renderedWrapsText
            || fontDesign != renderedFontDesign
            || fallbackForegroundColor != renderedFallbackForegroundColor
        else {
          return
        }

        textView.textualPreservingSelectedRange {
          textView.attributedText = Self.resolvedAttributedString(
            from: attributedString,
            environment: environment,
            fontDesign: fontDesign,
            fallbackForegroundColor: fallbackForegroundColor
          )
        }

        renderedAttributedString = attributedString
        renderedEnvironment = environment
        renderedIsSelectable = isSelectable
        renderedWrapsText = wrapsText
        renderedFontDesign = fontDesign
        renderedFallbackForegroundColor = fallbackForegroundColor
        renderedContainsLinks = containsLinks
        textView.invalidateMeasuredSize()
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

    final class MeasuringTextView: UITextView {
      private var measurementCache = TextualTextMeasurementCache()

      override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else {
          return super.intrinsicContentSize
        }

        let size = measuredSize(
          constrainedTo: bounds.width,
          wrapsText: textContainer.widthTracksTextView
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
      }

      func measuredSize(constrainedTo width: CGFloat?, wrapsText: Bool) -> CGSize {
        let key = TextualTextMeasurementKey(
          width: width,
          wrapsText: wrapsText,
          textLength: attributedText.length
        )

        return measurementCache.size(for: key) {
          attributedText.textualBoundingSize(
            constrainedTo: width,
            wrapsText: wrapsText
          )
        }
      }

      func invalidateMeasuredSize() {
        measurementCache.invalidate()
        invalidateTextualIntrinsicLayout()
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
