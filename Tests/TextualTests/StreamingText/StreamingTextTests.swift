// FILE: StreamingTextTests.swift
// Purpose: Verifies the public streaming renderer can be constructed with markdown input.
// Layer: Unit Test
// Exports: StreamingTextTests
// Depends on: Testing, SwiftUI, Textual

import SwiftUI
import Testing

@testable import Textual

struct StreamingTextTests {
  @MainActor
  @Test func constructsMarkdownStreamingViewWithSelectionEnabled() {
    let configuration = StreamingText.Configuration(
      isSelectable: true,
      updateInterval: 1.0 / 60.0
    )

    let view = StreamingText(
      markdown: "**Streaming** response",
      appendedMarkdown: " response",
      isStreaming: true,
      configuration: configuration
    )

    _ = view.body
    #expect(configuration.isSelectable)
  }

  @MainActor
  @Test func constructsSettledMarkdownView() {
    let view = StreamingText(
      markdown: """
        ## Done

        Final **Markdown** response

        ```swift
        print("fast code")
        ```
        """,
      isStreaming: false
    )

    _ = view.body
  }

  @Test func constructsUIKitRenderingOptions() {
    let options = UIKitTextRenderingOptions(
      prefersTextFragments: true,
      isSelectable: false
    )

    #expect(options.prefersTextFragments)
    #expect(!options.isSelectable)
  }

  @MainActor
  @Test func constructsOptimizedTextFragmentsModifier() {
    let view = StructuredText(markdown: "Final **Markdown** response")
      .textual.optimizedTextFragments(isSelectable: false)

    _ = view
  }
}
