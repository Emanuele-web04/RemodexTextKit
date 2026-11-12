import SwiftUI

// MARK: - Overview
//
// HighlightedTextFragment displays syntax-highlighted code. Highlighted results live in a
// main-actor cache keyed by code, language, theme, and text environment, so a block that mounts
// again (for example a timeline row scrolled back into view) renders its highlighted code from
// `body` on the first frame, with no task and no swap.
//
// On a cache miss the block renders plain code, tokenizes off the main thread, and applies the
// result once. Only content that keeps changing under the same view (streaming) waits for a pause
// before tokenizing. A highlighted result is only ever shown for the content it was made from.
//
// Highlighting changes colors and, for some tokens, weight; monospaced faces keep the same
// advances across weights, so the swap from plain to highlighted code does not resize the block.
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

  var body: some View {
    let request = Request(
      code: String(content.characters[...]),
      languageHint: languageHint,
      theme: theme,
      environment: textEnvironment,
      presentationIntent: content.presentationIntent
    )
    let highlightedCode = model.highlightedCode(for: request)

    renderedCode(highlightedCode ?? AttributedString(content))
      // In a background so the code keeps its identity when highlighting lands.
      .background {
        if highlightedCode == nil, languageHint != nil {
          Color.clear
            .task(id: request) {
              await model.highlight(request)
            }
        }
      }
  }

  @ViewBuilder
  private func renderedCode(_ code: AttributedString) -> some View {
    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
      if uikitTextRenderingOptions.prefersTextFragments {
        UIKitAttributedTextView(
          attributedString: code,
          textEnvironment: textEnvironment,
          isSelectable: uikitTextRenderingOptions.isSelectable,
          wrapsText: false,
          fontDesign: .monospaced,
          fallbackForegroundColor: theme.foregroundColor.bestMatch(
            for: textEnvironment.colorEnvironment
          )
        )
      } else {
        swiftUITextFragment(code)
      }
    #else
      swiftUITextFragment(code)
    #endif
  }

  private func swiftUITextFragment(_ code: AttributedString) -> some View {
    TextFragment(code)
      .foregroundStyle(theme.foregroundColor)
  }
}

extension HighlightedTextFragment {
  struct Request: Hashable, Sendable {
    let code: String
    let languageHint: String?
    let theme: StructuredText.HighlighterTheme
    let environment: TextEnvironmentValues
    let presentationIntent: PresentationIntent?
  }

  @MainActor @Observable final class Model {
    // Bumped when a highlight lands so `body` reads the new result.
    private var completedHighlights = 0
    @ObservationIgnored private var memo: (request: Request, value: AttributedString?)?
    @ObservationIgnored private var lastRequestedCode: String?

    /// The highlighted code for exactly this request, or `nil` to render it plain.
    func highlightedCode(for request: Request) -> AttributedString? {
      _ = completedHighlights
      if let memo, memo.request == request {
        return memo.value
      }
      let value = HighlightCache.shared.value(for: request)
      memo = (request, value)
      return value
    }

    func highlight(_ request: Request) async {
      guard let languageHint = request.languageHint else {
        return
      }

      // Debounce content that changes under this view (streaming), so only code that is stable
      // for the interval reaches the JS tokenizer. A first mount tokenizes at once.
      let isChanging = lastRequestedCode.map { $0 != request.code } ?? false
      lastRequestedCode = request.code
      if isChanging {
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }
      }

      guard let tokenizer = CodeTokenizer.shared else {
        return
      }
      let tokens = await tokenizer.tokenize(code: request.code, language: languageHint)
      guard !Task.isCancelled else { return }

      let value = Self.highlight(tokens: tokens, request: request)
      HighlightCache.shared.store(value, for: request)
      memo = (request, value)
      completedHighlights &+= 1
    }

    static func highlight(tokens: [CodeToken], request: Request) -> AttributedString {
      var attributes = AttributeContainer()
      // Re-apply the presentation intent for pasteboard formatters
      attributes.presentationIntent = request.presentationIntent
      ForegroundColorProperty(request.theme.foregroundColor)
        .apply(in: &attributes, environment: request.environment)
      var highlightedCode = AttributedString()
      // Token properties are resolved once per token type, not once per token.
      var attributesByType: [StructuredText.HighlighterTheme.TokenType: AttributeContainer] = [:]

      for token in tokens {
        let tokenAttributes: AttributeContainer
        if let cached = attributesByType[token.type] {
          tokenAttributes = cached
        } else {
          var resolved = attributes
          request.theme.tokenProperties[token.type]?
            .apply(in: &resolved, environment: request.environment)
          attributesByType[token.type] = resolved
          tokenAttributes = resolved
        }

        highlightedCode.append(AttributedString(token.content, attributes: tokenAttributes))
      }

      return highlightedCode
    }
  }
}

// Least-recently-used highlighted code, bounded by entry count and by the total size of the
// cached source so a few huge blocks cannot pin a lot of memory.
@MainActor final class HighlightCache {
  static let shared = HighlightCache()

  private struct Entry {
    let value: AttributedString
    let codeBytes: Int
    var lastUse: UInt64
  }

  private let entryLimit: Int
  private let codeByteLimit: Int
  private var entries: [HighlightedTextFragment.Request: Entry] = [:]
  private var codeBytes = 0
  private var clock: UInt64 = 0

  init(entryLimit: Int = 96, codeByteLimit: Int = 512 * 1024) {
    self.entryLimit = entryLimit
    self.codeByteLimit = codeByteLimit
  }

  func value(for request: HighlightedTextFragment.Request) -> AttributedString? {
    guard var entry = entries[request] else {
      return nil
    }
    clock &+= 1
    entry.lastUse = clock
    entries[request] = entry
    return entry.value
  }

  func store(_ value: AttributedString, for request: HighlightedTextFragment.Request) {
    let bytes = request.code.utf8.count
    guard bytes <= codeByteLimit else {
      return
    }
    if let existing = entries.removeValue(forKey: request) {
      codeBytes -= existing.codeBytes
    }
    clock &+= 1
    entries[request] = Entry(value: value, codeBytes: bytes, lastUse: clock)
    codeBytes += bytes

    while entries.count > entryLimit || codeBytes > codeByteLimit,
      let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })
    {
      entries.removeValue(forKey: oldest.key)
      codeBytes -= oldest.value.codeBytes
    }
  }
}
