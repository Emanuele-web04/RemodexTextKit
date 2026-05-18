// FILE: StreamingTextTests.swift
// Purpose: Verifies the public streaming renderer can be constructed with markdown input.
// Layer: Unit Test
// Exports: StreamingTextTests
// Depends on: Testing, SwiftUI, RemodexTextKit

import SwiftUI
import Testing

@testable import RemodexTextKit

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

  @Test func appendPolicyUsesExplicitDeltaForExistingText() {
    let edit = StreamingTextAppendPolicy.edit(
      renderedMarkupIsEmpty: false,
      hasScheduledUpdate: false,
      pendingAppend: "",
      isPendingAppend: false,
      appendedMarkup: " response",
      environmentChanged: false
    )

    #expect(edit == .append(" response"))
  }

  @Test func appendPolicyCoalescesQueuedDeltas() {
    let edit = StreamingTextAppendPolicy.edit(
      renderedMarkupIsEmpty: false,
      hasScheduledUpdate: true,
      pendingAppend: " fast",
      isPendingAppend: true,
      appendedMarkup: " response",
      environmentChanged: false
    )

    #expect(edit == .append(" fast response"))
  }

  @Test func appendPolicyRequiresExplicitDelta() {
    let edit = StreamingTextAppendPolicy.edit(
      renderedMarkupIsEmpty: false,
      hasScheduledUpdate: false,
      pendingAppend: "",
      isPendingAppend: false,
      appendedMarkup: nil,
      environmentChanged: false
    )

    #expect(edit == .replace)
  }

  @Test func appendPolicyFallsBackWhenEnvironmentChanges() {
    let edit = StreamingTextAppendPolicy.edit(
      renderedMarkupIsEmpty: false,
      hasScheduledUpdate: false,
      pendingAppend: "",
      isPendingAppend: false,
      appendedMarkup: " response",
      environmentChanged: true
    )

    #expect(edit == .replace)
  }

  @Test func appendPolicyDoesNotAppendIntoInitialEmptyRender() {
    let edit = StreamingTextAppendPolicy.edit(
      renderedMarkupIsEmpty: true,
      hasScheduledUpdate: false,
      pendingAppend: "",
      isPendingAppend: false,
      appendedMarkup: "response",
      environmentChanged: false
    )

    #expect(edit == .replace)
  }

  @Test func appendPolicyDoesNotAppendAfterQueuedReplace() {
    let edit = StreamingTextAppendPolicy.edit(
      renderedMarkupIsEmpty: false,
      hasScheduledUpdate: true,
      pendingAppend: "",
      isPendingAppend: false,
      appendedMarkup: " response",
      environmentChanged: false
    )

    #expect(edit == .replace)
  }

  @Test func appendPolicyIgnoresDuplicateQueuedMarkup() {
    let shouldIgnore = StreamingTextAppendPolicy.shouldIgnoreUpdate(
      hasScheduledUpdate: true,
      pendingMarkup: "Streaming response",
      nextMarkup: "Streaming response",
      configurationChanged: false,
      environmentChanged: false
    )

    #expect(shouldIgnore)
  }

  @Test func appendPolicyDoesNotIgnoreEnvironmentChanges() {
    let shouldIgnore = StreamingTextAppendPolicy.shouldIgnoreUpdate(
      hasScheduledUpdate: true,
      pendingMarkup: "Streaming response",
      nextMarkup: "Streaming response",
      configurationChanged: false,
      environmentChanged: true
    )

    #expect(!shouldIgnore)
  }

  @Test func appendPolicyDoesNotIgnoreConfigurationChanges() {
    let shouldIgnore = StreamingTextAppendPolicy.shouldIgnoreUpdate(
      hasScheduledUpdate: true,
      pendingMarkup: "Streaming response",
      nextMarkup: "Streaming response",
      configurationChanged: true,
      environmentChanged: false
    )

    #expect(!shouldIgnore)
  }
}
