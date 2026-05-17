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
      textView.backgroundColor = .clear
      textView.isEditable = false
      textView.isScrollEnabled = false
      textView.textContainerInset = .zero
      textView.textContainer.lineFragmentPadding = 0
      textView.adjustsFontForContentSizeCategory = true
      textView.setContentCompressionResistancePriority(.required, for: .vertical)
      textView.setContentHuggingPriority(.required, for: .vertical)
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

      let size = uiView.sizeThatFits(
        CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
      )
      return CGSize(width: width, height: ceil(size.height))
    }

    @MainActor
    final class Coordinator {
      private enum PendingEdit {
        case replace
        case append(String)
      }

      private var renderedMarkup = ""
      private var renderedEnvironment = TextEnvironmentValues()
      private var pendingMarkup: String?
      private var pendingEdit = PendingEdit.replace
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

        pendingMarkup = markup
        pendingConfiguration = configuration
        pendingEnvironment = textEnvironment

        let accumulatedAppend = pendingAppend + (appendedMarkup ?? "")
        if !environmentChanged, canAppendDelta(with: accumulatedAppend, updatingTo: markup) {
          pendingEdit = .append(accumulatedAppend)
        } else {
          pendingEdit = .replace
        }

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

      private func canAppendDelta(with accumulatedAppend: String, updatingTo markup: String) -> Bool {
        guard !accumulatedAppend.isEmpty else { return false }

        let canUseExistingAppendState: Bool
        if updateTask == nil {
          canUseExistingAppendState = !renderedMarkup.isEmpty
        } else if case .append = pendingEdit {
          canUseExistingAppendState = true
        } else {
          canUseExistingAppendState = false
        }

        return canUseExistingAppendState
          && markup.utf8.count == renderedMarkup.utf8.count + accumulatedAppend.utf8.count
          && markup.hasPrefix(renderedMarkup)
          && markup.hasSuffix(accumulatedAppend)
      }

      private var pendingAppend: String {
        if case .append(let value) = pendingEdit {
          return value
        }
        return ""
      }

      // Normalizes public cadence input before converting to Task.sleep nanoseconds.
      private static func sleepNanoseconds(for interval: TimeInterval) -> UInt64 {
        guard interval.isFinite, interval > 0 else { return 0 }

        let cappedInterval = min(interval, 60)
        return UInt64(cappedInterval * 1_000_000_000)
      }

      private func editTextStorage(_ textView: StreamingUITextView, _ edits: () -> Void) {
        let selectedRange = textView.selectedRange
        let hadSelection = selectedRange.location != NSNotFound

        textView.textStorage.beginEditing()
        edits()
        textView.textStorage.endEditing()

        if hadSelection {
          let safeLocation = min(selectedRange.location, textView.textStorage.length)
          let safeLength = min(selectedRange.length, textView.textStorage.length - safeLocation)
          textView.selectedRange = NSRange(location: safeLocation, length: safeLength)
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
    override var intrinsicContentSize: CGSize {
      guard bounds.width > 0 else {
        return super.intrinsicContentSize
      }

      let size = sizeThatFits(
        CGSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
      )
      return CGSize(width: UIView.noIntrinsicMetric, height: ceil(size.height))
    }

    // Tells both UIKit and SwiftUI layout bridges that textStorage grew without a SwiftUI state tick.
    func invalidateStreamingLayout() {
      invalidateIntrinsicContentSize()
      setNeedsLayout()
      superview?.setNeedsLayout()
    }
  }
#endif
