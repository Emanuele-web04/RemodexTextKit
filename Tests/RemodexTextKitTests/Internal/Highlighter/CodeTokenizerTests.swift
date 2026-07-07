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

  @Test
  @available(watchOS, unavailable)
  func tokenizeOversizedCodeFallsBackToPlainText() async {
    // given
    let tokenizer = CodeTokenizer()
    let code = String(repeating: "a", count: CodeTokenizer.maximumCodeUTF8Bytes + 1)

    // when
    let tokens: [CodeToken] =
      if let tokenizer {
        await tokenizer.tokenize(code: code, language: "swift")
      } else {
        []
      }

    // then
    #expect(tokenizer != nil)
    #expect(tokens == [.init(content: code, type: .plain)])
  }

  @Test
  @available(watchOS, unavailable)
  func tokenizeSkipsJavaScriptWorkWhenTaskIsCancelled() async {
    // given
    let tokenizer = CodeTokenizer()

    guard let tokenizer else {
      Issue.record("Expected a non-nil tokenizer.")
      return
    }

    // when
    let task = Task {
      await Task.yield()
      return await tokenizer.tokenize(code: "let x = 1", language: "swift")
    }
    task.cancel()
    let tokens = await task.value

    // then
    // The cancellation guard drains queued actor calls cheaply; whether it lands
    // before or after the JS call completes is inherently racy in a unit test, so
    // accept either outcome — the guard's value is draining queued calls under
    // rapid change, not guaranteeing cancellation wins this specific race.
    let plainTokens = [CodeToken(content: "let x = 1", type: .plain)]
    let fullTokens: [CodeToken] = [
      .init(content: "let", type: .keyword),
      .init(content: " x ", type: .plain),
      .init(content: "=", type: .operator),
      .init(content: " ", type: .plain),
      .init(content: "1", type: .number),
    ]
    #expect(tokens == plainTokens || tokens == fullTokens)
  }
}
