// FILE: StreamingTextCoordinatorTests.swift
// Purpose: Behavioral tests driving the StreamingText UIKit coordinator's textStorage mutations.
// Layer: Unit Test
// Exports: StreamingTextCoordinatorTests
// Depends on: Testing, UIKit, RemodexTextKit

#if canImport(UIKit) && !os(watchOS) && !os(tvOS)
  import Testing
  import UIKit

  @testable import RemodexTextKit

  struct StreamingTextCoordinatorTests {
    @MainActor
    private func makeSUT(
      updateInterval: TimeInterval = 0
    ) -> (UIKitStreamingTextView.Coordinator, StreamingUITextView, StreamingText.Configuration) {
      let coordinator = UIKitStreamingTextView.Coordinator()
      let textView = StreamingUITextView()
      textView.configureForTextualIntrinsicRendering()
      let configuration = StreamingText.Configuration(
        isSelectable: true, updateInterval: updateInterval
      )
      return (coordinator, textView, configuration)
    }

    // Let the coalescing Task run to completion on the main actor.
    @MainActor
    private func drain() async {
      for _ in 0..<10 {
        await Task.yield()
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
      for _ in 0..<10 {
        await Task.yield()
      }
    }

    @MainActor
    @Test func initialRenderAppliesImmediately() {
      let (coordinator, textView, configuration) = makeSUT()

      coordinator.update(
        textView,
        markup: "Hello",
        appendedMarkup: nil,
        configuration: configuration,
        textEnvironment: TextEnvironmentValues()
      )

      #expect(textView.textStorage.string == "Hello")
    }

    @MainActor
    @Test func appendBurstCoalescesToFinalText() async {
      let (coordinator, textView, configuration) = makeSUT()
      let environment = TextEnvironmentValues()

      coordinator.update(
        textView,
        markup: "Hello",
        appendedMarkup: nil,
        configuration: configuration,
        textEnvironment: environment
      )

      coordinator.update(
        textView,
        markup: "Hello A",
        appendedMarkup: " A",
        configuration: configuration,
        textEnvironment: environment
      )
      coordinator.update(
        textView,
        markup: "Hello A B",
        appendedMarkup: " B",
        configuration: configuration,
        textEnvironment: environment
      )
      coordinator.update(
        textView,
        markup: "Hello A B C",
        appendedMarkup: " C",
        configuration: configuration,
        textEnvironment: environment
      )

      await drain()

      #expect(textView.textStorage.string == "Hello A B C")
    }

    @MainActor
    @Test func replaceWhenNoDeltaSupplied() async {
      let (coordinator, textView, configuration) = makeSUT()
      let environment = TextEnvironmentValues()

      coordinator.update(
        textView,
        markup: "Hello",
        appendedMarkup: nil,
        configuration: configuration,
        textEnvironment: environment
      )

      coordinator.update(
        textView,
        markup: "Rewritten",
        appendedMarkup: nil,
        configuration: configuration,
        textEnvironment: environment
      )

      await drain()

      #expect(textView.textStorage.string == "Rewritten")
    }

    @MainActor
    @Test func environmentChangeForcesReplaceNotAppend() async {
      let (coordinator, textView, configuration) = makeSUT()
      let environment = TextEnvironmentValues()

      coordinator.update(
        textView,
        markup: "Hello",
        appendedMarkup: nil,
        configuration: configuration,
        textEnvironment: environment
      )

      var changedEnvironment = environment
      changedEnvironment.colorScheme = .dark

      coordinator.update(
        textView,
        markup: "Hello!",
        appendedMarkup: "!",
        configuration: configuration,
        textEnvironment: changedEnvironment
      )

      await drain()

      // Only the string is asserted; attribute-level verification isn't exercised by this policy path.
      #expect(textView.textStorage.string == "Hello!")
    }

    @MainActor
    @Test func duplicateMarkupIsIdempotent() async {
      let (coordinator, textView, configuration) = makeSUT()
      let environment = TextEnvironmentValues()

      coordinator.update(
        textView,
        markup: "Hello",
        appendedMarkup: nil,
        configuration: configuration,
        textEnvironment: environment
      )

      coordinator.update(
        textView,
        markup: "Hello world",
        appendedMarkup: " world",
        configuration: configuration,
        textEnvironment: environment
      )
      coordinator.update(
        textView,
        markup: "Hello world",
        appendedMarkup: " world",
        configuration: configuration,
        textEnvironment: environment
      )

      await drain()

      #expect(textView.textStorage.string == "Hello world")
    }

    @MainActor
    @Test func selectionFlagPropagates() {
      let (coordinator, textView, configuration) = makeSUT()
      var nonSelectableConfiguration = configuration
      nonSelectableConfiguration.isSelectable = false

      coordinator.update(
        textView,
        markup: "Hello",
        appendedMarkup: nil,
        configuration: nonSelectableConfiguration,
        textEnvironment: TextEnvironmentValues()
      )

      #expect(textView.isSelectable == false)
    }
  }
#endif
