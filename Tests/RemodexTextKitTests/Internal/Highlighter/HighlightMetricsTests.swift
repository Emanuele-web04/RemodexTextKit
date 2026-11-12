#if os(iOS)
  import SwiftUI
  import Testing
  import UIKit

  @testable import RemodexTextKit

  // Code renders plain until its highlight lands. The default theme sets some tokens semibold;
  // these tests pin that the swap keeps the block's size with monospaced faces, so a code block
  // does not resize when highlighting arrives.
  @MainActor
  struct HighlightMetricsTests {
    private static let code = (0..<12).map { index in
      "\(index): let value = resolve(url, against: base) ?? fallback // true when cached"
    }.joined(separator: "\n")

    @Test(arguments: [nil, 300.0])
    func defaultThemeKeepsSystemMonospacedMetrics(width: Double?) {
      expectSameSize(font: .system(size: 15, design: .monospaced), width: width)
    }

    // The default code block style keeps the body font and applies `.monospaced()`.
    @Test(arguments: [nil, 300.0])
    func defaultThemeKeepsMonospacedBodyMetrics(width: Double?) {
      expectSameSize(font: .body, width: width)
    }

    private func expectSameSize(font: Font, width: Double?) {
      let request = HighlightedTextFragment.Request(
        code: Self.code,
        languageHint: "swift",
        theme: .default,
        environment: TextEnvironmentValues(font: font),
        presentationIntent: nil
      )
      let highlighted = HighlightedTextFragment.Model.highlight(
        tokens: Self.tokens(for: Self.code),
        request: request
      )

      #expect(highlighted.runs.contains { $0.font != nil })
      #expect(
        measuredSize(Text(Self.code), font: font, width: width)
          == measuredSize(Text(highlighted), font: font, width: width)
      )
    }

    // Marks `let` and `true` as keywords and comments as comments, like the Prism tokenizer.
    private static func tokens(for code: String) -> [CodeToken] {
      var tokens: [CodeToken] = []
      for (index, word) in code.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
        if index > 0 {
          tokens.append(CodeToken(content: " ", type: .plain))
        }
        let type: StructuredText.HighlighterTheme.TokenType =
          ["let", "true"].contains(word) ? .keyword : word.hasPrefix("//") ? .comment : .plain
        tokens.append(CodeToken(content: String(word), type: type))
      }
      return tokens
    }

    private func measuredSize(_ text: Text, font: Font, width: Double?) -> CGSize {
      let host = UIHostingController(
        rootView:
          text
          .font(font)
          .monospaced()
          .frame(width: width.map { CGFloat($0) }, alignment: .leading)
          .fixedSize(horizontal: width == nil, vertical: true)
      )
      return host.sizeThatFits(in: CGSize(width: width ?? 10_000, height: 100_000))
    }
  }
#endif
