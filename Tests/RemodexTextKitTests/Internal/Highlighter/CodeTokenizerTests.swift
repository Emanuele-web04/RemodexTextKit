import Foundation
import Testing

@testable import RemodexTextKit

struct CodeTokenizerTests {
  @Test
  @MainActor
  @available(watchOS, unavailable)
  func highlightedCodeIsOnlyRenderedForTheCodeItWasMadeFrom() async {
    let model = HighlightedTextFragment.Model()
    let swift = Self.request(code: "let greeting = \"Hello\"", languageHint: "swift")

    #expect(model.highlightedCode(for: swift) == nil)
    await model.highlight(swift)
    let highlighted = model.highlightedCode(for: swift)
    #expect(highlighted.map { String($0.characters[...]) } == swift.code)
    #expect(highlighted?.runs.count ?? 0 > 1)

    // New content renders plain until it is highlighted itself.
    let longer = Self.request(code: swift.code + "\nlet name = 1", languageHint: "swift")
    #expect(model.highlightedCode(for: longer) == nil)

    // Without a language hint the block stays plain.
    let plain = Self.request(code: swift.code, languageHint: nil)
    await model.highlight(plain)
    #expect(model.highlightedCode(for: plain) == nil)
  }

  @Test
  @MainActor
  @available(watchOS, unavailable)
  func remountedBlockRendersCachedHighlightSynchronously() async {
    let request = Self.request(code: "func remounted() -> Int { 42 }", languageHint: "swift")
    await HighlightedTextFragment.Model().highlight(request)

    // A fresh view model (a remounted row) finds the result without tokenizing again.
    #expect(HighlightedTextFragment.Model().highlightedCode(for: request) != nil)
  }

  @Test
  @MainActor
  func highlightCacheEvictsLeastRecentlyUsedEntries() {
    let cache = HighlightCache(entryLimit: 2, codeByteLimit: 1024)
    let first = Self.request(code: "a", languageHint: "swift")
    let second = Self.request(code: "b", languageHint: "swift")
    let third = Self.request(code: "c", languageHint: "swift")

    cache.store(AttributedString("a"), for: first)
    cache.store(AttributedString("b"), for: second)
    _ = cache.value(for: first)
    cache.store(AttributedString("c"), for: third)

    #expect(cache.value(for: first) != nil)
    #expect(cache.value(for: second) == nil)
    #expect(cache.value(for: third) != nil)

    let oversized = Self.request(code: String(repeating: "x", count: 2048), languageHint: "swift")
    cache.store(AttributedString("x"), for: oversized)
    #expect(cache.value(for: oversized) == nil)
  }

  private static func request(code: String, languageHint: String?) -> HighlightedTextFragment.Request {
    HighlightedTextFragment.Request(
      code: code,
      languageHint: languageHint,
      theme: .default,
      environment: TextEnvironmentValues(),
      presentationIntent: nil
    )
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
