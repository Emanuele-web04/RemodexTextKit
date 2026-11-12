import SwiftUI

// MARK: - Overview
//
// `WithInlineStyle` applies an `InlineStyle` to an `AttributedString` before it reaches the
// rendering pipeline.
//
// The input `AttributedString` is expected to carry inline semantics using standard Foundation
// attributes:
// - `inlinePresentationIntent` identifies spans like code, emphasis, strong, and strikethrough.
// - `link` identifies URLs.
//
// The view reads `InlineStyle` and `TextEnvironmentValues` from the environment, then produces a
// styled copy of the attributed string by merging attributes into each matching span.
//
// Styling is recomputed whenever the input, style, or environment snapshot changes. The result is
// memoized in a reference type during `body`, so a view resolves its style once per change and
// renders the styled content on its first frame.

struct WithInlineStyle<Content: View>: View {
  @Environment(\.inlineStyle) private var style
  @Environment(\.textEnvironment) private var environment

  @State private var memo = Memo()

  private let input: AttributedString
  private let content: (AttributedString) -> Content

  init(
    _ input: AttributedString,
    @ViewBuilder content: @escaping (AttributedString) -> Content
  ) {
    self.input = input
    self.content = content
  }

  var body: some View {
    content(memo.output(for: input, style: style, environment: environment))
  }
}

extension WithInlineStyle {
  // A reference type, so updating the memo inside `body` does not invalidate the view.
  @MainActor final class Memo {
    private var key: Tuple<AttributedString, InlineStyle, TextEnvironmentValues>?
    private var output = AttributedString()

    func output(
      for input: AttributedString,
      style: InlineStyle,
      environment: TextEnvironmentValues
    ) -> AttributedString {
      let key = Tuple(input, style, environment)
      if key != self.key {
        output = WithInlineStyle.resolve(attributedString: input, style: style, in: environment)
        self.key = key
      }
      return output
    }
  }

  static func resolve(
    attributedString: AttributedString,
    style: InlineStyle,
    in environment: TextEnvironmentValues
  ) -> AttributedString {
    var output = attributedString

    for run in attributedString.runs {
      guard run.inlinePresentationIntent != nil || run.link != nil else {
        continue
      }

      var attributes = AttributeContainer()

      if let intent = run.inlinePresentationIntent {
        if intent.contains(.code) {
          style.code.apply(in: &attributes, environment: environment)
        }

        if intent.contains(.emphasized) {
          style.emphasis.apply(in: &attributes, environment: environment)
        }

        if intent.contains(.stronglyEmphasized) {
          style.strong.apply(in: &attributes, environment: environment)
        }

        if intent.contains(.strikethrough) {
          style.strikethrough.apply(in: &attributes, environment: environment)
        }
      }

      if run.link != nil {
        style.link.apply(in: &attributes, environment: environment)
      }

      output[run.range].mergeAttributes(attributes, mergePolicy: .keepNew)
    }

    return output
  }
}
