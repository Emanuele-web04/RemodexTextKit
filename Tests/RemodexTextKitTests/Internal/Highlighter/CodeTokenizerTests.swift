import Foundation
import Testing

@testable import RemodexTextKit

struct CodeTokenizerTests {
  @Test
  @MainActor
  @available(watchOS, unavailable)
  func highlightedTextFragmentResetsTokensWhenLanguageHintIsRemoved() async {
    let model = HighlightedTextFragment.Model()
    let attributedCode = AttributedString("let greeting = \"Hello\"")
    let code = attributedCode[attributedCode.startIndex..<attributedCode.endIndex]

    await model.tokenize(content: code, languageHint: "swift")
    #expect(model.tokens.contains { $0.type != .plain })

    await model.tokenize(content: code, languageHint: nil)
    #expect(model.tokens == [.init(content: "let greeting = \"Hello\"", type: .plain)])
  }

  @Test
  @available(watchOS, unavailable)
  func tokenize() async {
    // given
    let tokenizer = CodeTokenizer()

    // when
    let tokens: [CodeToken] =
      if let tokenizer {
        await tokenizer.tokenize(
          code: "let greeting = \"Hello, world!\"",
          language: "swift"
        )
      } else {
        []
      }

    // then
    #expect(tokenizer != nil)
    #expect(
      tokens == [
        .init(content: "let", type: .keyword),
        .init(content: " greeting ", type: .plain),
        .init(content: "=", type: .operator),
        .init(content: " ", type: .plain),
        .init(content: "\"Hello, world!\"", type: .string),
      ]
    )
  }

  @Test
  @available(watchOS, unavailable)
  func tokenizeUnsupportedLanguage() async {
    // given
    let tokenizer = CodeTokenizer()

    // when
    let tokens: [CodeToken] =
      if let tokenizer {
        await tokenizer.tokenize(
          code: "let greeting = \"Hello, world!\"",
          language: "unsupported"
        )
      } else {
        []
      }

    // then
    #expect(tokenizer != nil)
    #expect(
      tokens == [
        .init(content: "let greeting = \"Hello, world!\"", type: .plain)
      ]
    )
  }
}
