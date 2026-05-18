import Foundation
import os

#if canImport(JavaScriptCore)
  import JavaScriptCore
#endif

// MARK: - Overview
//
// CodeTokenizer wraps Prism.js via JavaScriptCore for syntax highlighting. The actor
// ensures thread-safe access to the JavaScript context.
//
// The tokenizer gracefully degrades when JavaScriptCore is unavailable, when the
// Prism bundle is missing, or when tokenization fails. In all cases, it returns
// a single plain token containing the entire code string.

struct CodeToken: Hashable, Sendable {
  let content: String
  let type: StructuredText.HighlighterTheme.TokenType
}

#if canImport(JavaScriptCore)
  actor CodeTokenizer {
    private struct CacheKey: Hashable {
      let language: String
      let code: String
    }

    private static let cacheLimit = 32

    private let context: JSContext
    private let logger = Logger(category: .codeTokenizer)
    private var cachedTokens: [CacheKey: [CodeToken]] = [:]
    private var cacheOrder: [CacheKey] = []

    static let shared = CodeTokenizer()

    init?() {
      guard let context = JSContext() else {
        logger.error("JavascriptCore is not available.")
        return nil
      }

      guard
        let bundleURL = Bundle.textual?.url(
          forResource: "prism-bundle",
          withExtension: "js"
        ),
        let script = try? String(contentsOf: bundleURL, encoding: .utf8)
      else {
        logger.error("Prism JavaScript bundle is missing.")
        return nil
      }

      context.evaluateScript(script)
      self.context = context
    }

    func tokenize(code: String, language: String) -> [CodeToken] {
      let key = CacheKey(language: language, code: code)
      if let tokens = cachedTokens[key] {
        markRecentlyUsed(key)
        return tokens
      }

      guard
        let tokenizeCode = context.objectForKeyedSubscript("tokenizeCode"),
        let result = tokenizeCode.call(withArguments: [code, language]),
        let array = result.toArray() as? [[String: String]]
      else {
        logger.error("Tokenization failed.")
        return [CodeToken(content: code, type: .plain)]
      }

      let tokens: [CodeToken] = array.compactMap { token in
        guard
          let content = token["content"],
          let type = token["type"]
        else {
          return nil
        }
        return CodeToken(content: content, type: .init(rawValue: type))
      }
      cache(tokens, for: key)
      return tokens
    }

    private func cache(_ tokens: [CodeToken], for key: CacheKey) {
      cachedTokens[key] = tokens
      markRecentlyUsed(key)

      while cacheOrder.count > Self.cacheLimit {
        let removed = cacheOrder.removeFirst()
        cachedTokens.removeValue(forKey: removed)
      }
    }

    private func markRecentlyUsed(_ key: CacheKey) {
      cacheOrder.removeAll { $0 == key }
      cacheOrder.append(key)
    }
  }
#else
  actor CodeTokenizer {
    private let logger = Logger(category: .codeTokenizer)

    static let shared = CodeTokenizer()

    init?() {
      logger.error("JavascriptCore is not available in this platform.")
      return nil
    }

    func tokenize(code: String, language: String) -> [CodeToken] {
      [CodeToken(content: code, type: .plain)]
    }
  }
#endif

extension Logger.Textual.Category {
  fileprivate static let codeTokenizer = Self(rawValue: "codeTokenizer")
}
