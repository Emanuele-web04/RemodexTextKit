// FILE: TextBuilderTests.swift
// Purpose: Guards TextFragment text construction against deep recursive Text trees.
// Layer: Unit Test
// Exports: TextBuilderTests
// Depends on: Testing, SwiftUI, Textual

import SwiftUI
import Testing

@testable import Textual

struct TextBuilderTests {
  @MainActor
  @Test func buildsHighlyFragmentedTextWithoutRecursiveConcatenationOverflow() {
    // Mirrors streamed AI markdown where thousands of tiny runs can arrive in one response.
    let content = Self.fragmentedAttributedString(fragmentCount: 2_500)
    let builder = TextFragment<AttributedString>.TextBuilder(
      content,
      environment: TextEnvironmentValues()
    )

    builder.sizeChanged(
      CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude),
      environment: TextEnvironmentValues()
    )

    #expect(content.characters.count > 0)
  }

  private static func fragmentedAttributedString(fragmentCount: Int) -> AttributedString {
    var content = AttributedString()

    for index in 0..<fragmentCount {
      var strong = AttributedString("bold-\(index)")
      strong.inlinePresentationIntent = .stronglyEmphasized

      var link = AttributedString(" file-\(index).swift ")
      link.link = URL(string: "file:///tmp/file-\(index).swift")

      content += strong
      content += link
    }

    return content
  }
}
