// FILE: StreamingText.swift
// Purpose: UIKit-backed streaming text renderer for high-frequency AI response updates.
// Layer: Public SwiftUI view
// Exports: StreamingText
// Depends on: SwiftUI, MarkupParser, StructuredText, UITextView on UIKit platforms

import SwiftUI

#if canImport(UIKit) && !os(watchOS) && !os(tvOS)
  import UIKit
#endif

/// Displays text that changes frequently, such as a live AI response stream.
///
/// `StreamingText` keeps the token-by-token path lightweight by mutating UIKit text storage directly
/// on UIKit platforms. While `isStreaming` is true, it renders plain text at a bounded cadence. When
/// the stream finishes, the view switches back to ``StructuredText`` so the settled response uses
/// Textual's full markup renderer.
public struct StreamingText: View {
  private let markup: String
  private let appendedMarkup: String?
  private let parser: any MarkupParser
  private let isStreaming: Bool
  private let configuration: Configuration

  @Environment(\.textEnvironment) private var textEnvironment

  /// Runtime tuning for the streaming renderer.
  public struct Configuration: Hashable, Sendable {
    /// Allows native text selection and copy in the underlying UIKit text view.
    public var isSelectable: Bool

    /// Minimum time between visible streaming mutations after the initial render.
    public var updateInterval: TimeInterval

    public init(
      isSelectable: Bool = true,
      updateInterval: TimeInterval = 1.0 / 30.0
    ) {
      self.isSelectable = isSelectable
      self.updateInterval = updateInterval
    }
  }

  /// Creates streaming text from markup using a custom parser.
  ///
  /// - Parameters:
  ///   - markup: The latest complete markup snapshot.
  ///   - appendedMarkup: Optional exact text appended since the previous update. Supplying this lets
  ///     the UIKit fast path append without scanning the full snapshot for a shared prefix.
  ///   - parser: Parser used for final, settled rendering.
  ///   - isStreaming: Pass `true` while tokens are still arriving, then `false` for final rendering.
  ///   - configuration: Runtime tuning for cadence and selection.
  public init(
    _ markup: String,
    appendedMarkup: String? = nil,
    parser: any MarkupParser,
    isStreaming: Bool = true,
    configuration: Configuration = .init()
  ) {
    self.markup = markup
    self.appendedMarkup = appendedMarkup
    self.parser = parser
    self.isStreaming = isStreaming
    self.configuration = configuration
  }

  @ViewBuilder
  public var body: some View {
    if isStreaming {
      streamingBody
    } else {
      settledBody
    }
  }

  @ViewBuilder
  private var streamingBody: some View {
    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
      UIKitStreamingTextView(
        markup: markup,
        appendedMarkup: appendedMarkup,
        configuration: configuration,
        textEnvironment: textEnvironment
      )
    #else
      settledBody
    #endif
  }

  @ViewBuilder
  private var settledBody: some View {
    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
      StructuredText(markup, parser: parser)
        .textual.optimizedTextFragments(isSelectable: configuration.isSelectable)
    #elseif TEXTUAL_ENABLE_TEXT_SELECTION && !os(tvOS) && !os(watchOS)
      if configuration.isSelectable {
        StructuredText(markup, parser: parser)
          .textual.textSelection(.enabled)
      } else {
        StructuredText(markup, parser: parser)
          .textual.textSelection(.disabled)
      }
    #else
      StructuredText(markup, parser: parser)
    #endif
  }
}

enum StreamingTextPendingEdit: Equatable {
  case replace
  case append(String)
}

enum StreamingTextAppendPolicy {
  static func shouldIgnoreUpdate(
    hasScheduledUpdate: Bool,
    pendingMarkup: String?,
    nextMarkup: String,
    configurationChanged: Bool,
    environmentChanged: Bool
  ) -> Bool {
    hasScheduledUpdate
      && !configurationChanged
      && !environmentChanged
      && pendingMarkup == nextMarkup
  }

  // Trusts explicit append deltas so the streaming path never scans the full accumulated response.
  static func edit(
    renderedMarkupIsEmpty: Bool,
    hasScheduledUpdate: Bool,
    pendingAppend: String,
    isPendingAppend: Bool,
    appendedMarkup: String?,
    environmentChanged: Bool
  ) -> StreamingTextPendingEdit {
    guard
      !environmentChanged,
      let appendedMarkup,
      !appendedMarkup.isEmpty
    else {
      return .replace
    }

    if hasScheduledUpdate {
      guard isPendingAppend else { return .replace }
    } else {
      guard !renderedMarkupIsEmpty else { return .replace }
    }

    return .append(pendingAppend + appendedMarkup)
  }
}

extension StreamingText {
  /// Creates streaming text from Markdown.
  public init(
    markdown: String,
    appendedMarkdown: String? = nil,
    isStreaming: Bool = true,
    baseURL: URL? = nil,
    syntaxExtensions: [AttributedStringMarkdownParser.SyntaxExtension] = [],
    configuration: Configuration = .init()
  ) {
    self.init(
      markdown,
      appendedMarkup: appendedMarkdown,
      parser: .markdown(
        baseURL: baseURL,
        syntaxExtensions: syntaxExtensions
      ),
      isStreaming: isStreaming,
      configuration: configuration
    )
  }
}

#if canImport(UIKit) && !os(watchOS) && !os(tvOS)
  private struct UIKitStreamingTextView: UIViewRepresentable {
    let markup: String
    let appendedMarkup: String?
    let configuration: StreamingText.Configuration
    let textEnvironment: TextEnvironmentValues

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeUIView(context: Context) -> StreamingUITextView {
      let textView = StreamingUITextView()
      textView.configureForTextualIntrinsicRendering()
      context.coordinator.update(
        textView,
        markup: markup,
        appendedMarkup: appendedMarkup,
        configuration: configuration,
        textEnvironment: textEnvironment
      )
      return textView
    }

    func updateUIView(_ textView: StreamingUITextView, context: Context) {
      context.coordinator.update(
        textView,
        markup: markup,
        appendedMarkup: appendedMarkup,
        configuration: configuration,
        textEnvironment: textEnvironment
      )
    }

    func sizeThatFits(
      _ proposal: ProposedViewSize,
      uiView: StreamingUITextView,
      context _: Context
    ) -> CGSize? {
      guard let width = proposal.width else {
        return nil
      }

      let size = uiView.measuredSize(fittingWidth: width)
      return CGSize(width: width, height: ceil(size.height))
    }

    @MainActor
    final class Coordinator {
      private var renderedMarkup = ""
      private var renderedEnvironment = TextEnvironmentValues()
      private var pendingMarkup: String?
      private var pendingEdit = StreamingTextPendingEdit.replace
      private var pendingConfiguration = StreamingText.Configuration()
      private var pendingEnvironment = TextEnvironmentValues()
      private var updateTask: Task<Void, Never>?
      private weak var textView: StreamingUITextView?

      deinit {
        updateTask?.cancel()
      }

      func update(
        _ textView: StreamingUITextView,
        markup: String,
        appendedMarkup: String?,
        configuration: StreamingText.Configuration,
        textEnvironment: TextEnvironmentValues
      ) {
        self.textView = textView
        textView.isSelectable = configuration.isSelectable
        textView.font = Self.preferredFont(in: textEnvironment)
        textView.textColor = .label
        textView.tintColor = .tintColor

        let environmentChanged = textEnvironment != renderedEnvironment
        guard markup != renderedMarkup || updateTask != nil || environmentChanged else {
          return
        }

        guard !StreamingTextAppendPolicy.shouldIgnoreUpdate(
          hasScheduledUpdate: updateTask != nil,
          pendingMarkup: pendingMarkup,
          nextMarkup: markup,
          configurationChanged: configuration != pendingConfiguration,
          environmentChanged: environmentChanged
        ) else {
          return
        }

        pendingMarkup = markup
        pendingConfiguration = configuration
        pendingEnvironment = textEnvironment

        pendingEdit = StreamingTextAppendPolicy.edit(
          renderedMarkupIsEmpty: renderedMarkup.isEmpty,
          hasScheduledUpdate: updateTask != nil,
          pendingAppend: pendingAppend,
          isPendingAppend: isPendingAppend,
          appendedMarkup: appendedMarkup,
          environmentChanged: environmentChanged
        )

        if renderedMarkup.isEmpty && textView.textStorage.length == 0 {
          updateTask?.cancel()
          updateTask = nil
          applyPendingUpdate()
        } else {
          scheduleCoalescedUpdate()
        }
      }

      // Coalesces token bursts so SwiftUI can keep scrolling and gesture handling responsive.
      private func scheduleCoalescedUpdate() {
        guard updateTask == nil else { return }

        let nanoseconds = Self.sleepNanoseconds(for: pendingConfiguration.updateInterval)
        updateTask = Task { @MainActor in
          if nanoseconds > 0 {
            try? await Task.sleep(nanoseconds: nanoseconds)
          }
          guard !Task.isCancelled else { return }
          applyPendingUpdate()
          updateTask = nil
        }
      }

      private func applyPendingUpdate() {
        guard
          let textView,
          let markup = pendingMarkup
        else {
          return
        }

        let attributes = Self.baseAttributes(in: pendingEnvironment)

        switch pendingEdit {
        case .append(let appendedMarkup):
          editTextStorage(textView) {
            textView.textStorage.append(
              NSAttributedString(string: appendedMarkup, attributes: attributes)
            )
          }
        case .replace:
          let attributed = NSAttributedString(string: markup, attributes: attributes)
          editTextStorage(textView) {
            textView.textStorage.setAttributedString(attributed)
          }
        }

        renderedMarkup = markup
        renderedEnvironment = pendingEnvironment
        pendingEdit = .replace
        textView.invalidateStreamingLayout()
      }

      private var pendingAppend: String {
        if case .append(let value) = pendingEdit {
          return value
        }
        return ""
      }

      private var isPendingAppend: Bool {
        if case .append = pendingEdit {
          return true
        }
        return false
      }

      // Normalizes public cadence input before converting to Task.sleep nanoseconds.
      private static func sleepNanoseconds(for interval: TimeInterval) -> UInt64 {
        guard interval.isFinite, interval > 0 else { return 0 }

        let cappedInterval = min(interval, 60)
        return UInt64(cappedInterval * 1_000_000_000)
      }

      private func editTextStorage(_ textView: StreamingUITextView, _ edits: () -> Void) {
        textView.textualPreservingSelectedRange {
          textView.textStorage.beginEditing()
          edits()
          textView.textStorage.endEditing()
        }
      }

      private static func baseAttributes(
        in environment: TextEnvironmentValues
      ) -> [NSAttributedString.Key: Any] {
        [
          .font: preferredFont(in: environment),
          .foregroundColor: UIColor.label,
        ]
      }

      private static func preferredFont(in environment: TextEnvironmentValues) -> UIFont {
        if let size = environment.font?.provider()?.size(in: environment) {
          return UIFont.systemFont(ofSize: size)
        }

        return UIFont.preferredFont(forTextStyle: .body)
      }
    }
  }

  private final class StreamingUITextView: UITextView {
    private var measurementCache = TextualTextMeasurementCache()

    override var intrinsicContentSize: CGSize {
      guard bounds.width > 0 else {
        return super.intrinsicContentSize
      }

      let size = measuredSize(fittingWidth: bounds.width)
      return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    func measuredSize(fittingWidth width: CGFloat) -> CGSize {
      let key = TextualTextMeasurementKey(
        width: width,
        wrapsText: true,
        textLength: textStorage.length,
        fontPointSize: font?.pointSize
      )

      return measurementCache.size(for: key) {
        sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
      }
    }

    // Tells both UIKit and SwiftUI layout bridges that textStorage grew without a SwiftUI state tick.
    func invalidateStreamingLayout() {
      measurementCache.invalidate()
      invalidateTextualIntrinsicLayout(includingSuperview: true)
    }
  }
#endif
