import SwiftUI

// MARK: - Overview
//
// HighlightedTextFragment displays syntax-highlighted code using a two-phase approach.
// Tokenization runs asynchronously and is keyed by content plus language, while highlighting
// runs synchronously on token or environment changes (theme, color scheme, dynamic type).
//
// The presentationIntent is preserved after highlighting so pasteboard formatters can
// reconstruct the block structure when copying code.

struct HighlightedTextFragment: View {
  @Environment(\.textEnvironment) private var textEnvironment
  @Environment(\.uikitTextRenderingOptions) private var uikitTextRenderingOptions

  @State private var model = Model()

  private let content: AttributedSubstring
  private let languageHint: String?
  private let theme: StructuredText.HighlighterTheme

  init(
    _ content: AttributedSubstring,
    languageHint: String?,
    theme: StructuredText.HighlighterTheme
  ) {
    self.content = content
    self.languageHint = languageHint
    self.theme = theme
  }

  @ViewBuilder
  var body: some View {
    renderedCode
      .task(id: tokenizationRequest) {
        await model.tokenize(
          content: content,
          languageHint: languageHint
        )
      }
      .onChange(of: Tuple(model.tokens, textEnvironment)) { _, newValue in
        model.highlight(
          tokens: newValue.values.0,
          presentationIntent: content.presentationIntent,
          using: theme,
          environment: newValue.values.1
        )
      }
  }

  private var tokenizationRequest: TokenizationRequest {
    TokenizationRequest(content: content, languageHint: languageHint)
  }

  private struct TokenizationRequest: Equatable {
    let content: AttributedSubstring
    let languageHint: String?
  }

  @ViewBuilder
  private var renderedCode: some View {
    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
      if uikitTextRenderingOptions.prefersTextFragments {
        UIKitAttributedTextView(
          attributedString: model.highlightedCode ?? AttributedString(content),
          textEnvironment: textEnvironment,
          isSelectable: uikitTextRenderingOptions.isSelectable,
          wrapsText: false,
          fontDesign: .monospaced,
          fallbackForegroundColor: theme.foregroundColor.bestMatch(
            for: textEnvironment.colorEnvironment
          )
        )
      } else {
        swiftUITextFragment
      }
    #else
      swiftUITextFragment
    #endif
  }

  private var swiftUITextFragment: some View {
    TextFragment(model.highlightedCode ?? AttributedString(content))
      .foregroundStyle(theme.foregroundColor)
  }
}

extension HighlightedTextFragment {
  @MainActor @Observable final class Model {
    var tokens: [CodeToken] = []
    var highlightedCode: AttributedString?
    private var tokenizationKey: TokenizationKey?

    func tokenize(content: AttributedSubstring, languageHint: String?) async {
      let code = String(content.characters[...])
      let key = TokenizationKey(code: code, languageHint: languageHint)
      let plainTokens = [CodeToken(content: code, type: .plain)]

      if tokenizationKey != key {
        tokenizationKey = key
        if tokens != plainTokens {
          tokens = plainTokens
        }
      }

      guard let tokenizer = CodeTokenizer.shared, let languageHint else {
        return
      }

      // Debounce: content changing rapidly (streaming) cancels this task and
      // re-fires; only content stable for the interval reaches the JS tokenizer.
      try? await Task.sleep(nanoseconds: 120_000_000)
      guard !Task.isCancelled, tokenizationKey == key else { return }

      let nextTokens = await tokenizer.tokenize(code: code, language: languageHint)
      guard !Task.isCancelled, tokenizationKey == key else { return }

      if tokens != nextTokens {
        tokens = nextTokens
      }
    }

    func highlight(
      tokens: [CodeToken],
      presentationIntent: PresentationIntent?,
      using theme: StructuredText.HighlighterTheme,
      environment: TextEnvironmentValues
    ) {
      var attributes = AttributeContainer()
      // Re-apply the presentation intent for pasteboard formatters
      attributes.presentationIntent = presentationIntent
      ForegroundColorProperty(theme.foregroundColor)
        .apply(in: &attributes, environment: environment)
      var highlightedCode = AttributedString()

      for token in tokens {
        var content = AttributedString(token.content)
        var tokenAttributes = attributes

        if let tokenProperties = theme.tokenProperties[token.type] {
          tokenProperties.apply(in: &tokenAttributes, environment: environment)
        }

        content.mergeAttributes(tokenAttributes)
        highlightedCode.append(content)
      }

      self.highlightedCode = highlightedCode
    }

    private struct TokenizationKey: Equatable {
      let code: String
      let languageHint: String?
    }
  }
}
