import SwiftUI

// MARK: - Overview
//
// TextFragment renders attributed content as SwiftUI.Text with support for inline
// attachments, links, and selection. It uses a TextBuilder to construct and cache
// Text values, minimizing rebuilds during resize by keying on attachment sizes.
//
// Attachments are represented as placeholder images tagged with AttachmentAttribute. The
// actual attachment views are rendered in an overlay using the resolved Text.Layout
// geometry. These modifiers are applied at the fragment level:
//
// - TextSelectionBackground renders selection highlights on macOS
// - TextLayoutPublisher hands the layout to the enclosing selection while it asks for it
// - AttachmentOverlay draws attachments at their run locations with selection-aware dimming
// - TextLinkInteraction handles tap gestures on links of text that is not selectable
// - TextLinkUnderline draws the dotted link underline with the text
//
// The overlays use backgroundPreferenceValue and overlayPreferenceValue to access
// Text.Layout and render in fragment-local coordinates. Fragment-level overlays enable
// coordinate space isolation and keep scrollable regions interactive. An overlay that reads
// the layout follows the fragment on every frame it moves, so only these opt-in or uncommon
// cases read it.
//
// An ancestor view must define a named coordinate space (.textContainer) for the text
// container. TextFragment uses onGeometryChange to observe the container size and rebuild
// Text when attachment sizes need to change.
//
// The rendered Text and the facts derived from the content (attachments, links) are memoized
// in a reference type updated during `body`, so a fragment builds its Text once per content
// change, on its first frame, and never renders the previous content after a change.
//
// TextFragment is used by InlineText and StructuredText (via BlockContent) to render
// attributed content with inline attachments, links, and selection.

struct TextFragment<Content: AttributedStringProtocol>: View {
  @Environment(\.textEnvironment) private var textEnvironment
  @Environment(\.uikitTextRenderingOptions) private var uikitTextRenderingOptions
  @State private var memo = Memo()

  private let content: Content

  init(_ content: Content) {
    self.content = content
  }

  @ViewBuilder
  var body: some View {
    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
      if usesUIKitTextFragment {
        UIKitAttributedTextView(
          attributedString: materializedContent,
          textEnvironment: textEnvironment,
          isSelectable: uikitTextRenderingOptions.isSelectable,
          wrapsText: true,
          fontDesign: .default,
          fallbackForegroundColor: nil
        )
      } else {
        swiftUITextFragment
      }
    #else
      swiftUITextFragment
    #endif
  }

  private var swiftUITextFragment: some View {
    let rendering = memo.rendering(for: content, environment: textEnvironment)
    let renderedText = attachmentSizedText(rendering)
      .modifier(TextSelectionBackground())
      .modifier(TextLayoutPublisher())
    return linkInteractiveText(
      attachmentOverlaidText(renderedText, attachments: rendering.attachments),
      containsLinks: rendering.containsLinks
    )
  }

  @ViewBuilder
  private func attachmentSizedText(_ rendering: Rendering) -> some View {
    let renderedText = rendering.text.customAttribute(TextFragmentAttribute())
    if let textBuilder = rendering.textBuilder {
      renderedText
        .onGeometryChange(for: CGSize?.self, of: \.textContainerSize) { size in
          guard let size else { return }
          textBuilder.sizeChanged(size, environment: textEnvironment)
        }
    } else {
      // Code/prose without attachments needs no container-size adoption.
      renderedText
    }
  }

  @ViewBuilder
  private func attachmentOverlaidText<Rendered: View>(
    _ renderedText: Rendered, attachments: Set<AnyAttachment>
  ) -> some View {
    if attachments.isEmpty {
      // An empty attachment Canvas would still traverse every highlighted code run.
      renderedText
    } else {
      renderedText.modifier(AttachmentOverlay(attachments: attachments))
    }
  }

  @ViewBuilder
  private func linkInteractiveText<Rendered: View>(
    _ renderedText: Rendered, containsLinks: Bool
  ) -> some View {
    if containsLinks {
      renderedText
        .modifier(TextLinkInteraction())
        .modifier(TextLinkUnderline())
    } else {
      // Keep no-link code fragments out of the link gesture and underline layout walks.
      renderedText
    }
  }

  private var usesUIKitTextFragment: Bool {
    uikitTextRenderingOptions.prefersTextFragments && !content.hasAttachments()
  }

  private var materializedContent: AttributedString {
    if let attributedString = content as? AttributedString {
      return attributedString
    }

    if let attributedSubstring = content as? AttributedSubstring {
      return AttributedString(attributedSubstring)
    }

    return AttributedString(String(content.characters[...]))
  }
}

extension TextFragment {
  struct Rendering {
    // Read through `text` so a builder's resize-driven updates re-render the fragment.
    @MainActor var text: Text { textBuilder?.text ?? staticText }

    let attachments: Set<AnyAttachment>
    let containsLinks: Bool
    let textBuilder: TextBuilder?
    fileprivate let staticText: Text
  }

  // A reference type, so updating the memo inside `body` does not invalidate the view.
  @MainActor final class Memo {
    private var content: Content?
    private var environment: TextEnvironmentValues?
    private var rendering: Rendering?

    func rendering(for content: Content, environment: TextEnvironmentValues) -> Rendering {
      if let rendering, content == self.content,
        rendering.textBuilder == nil || environment == self.environment
      {
        return rendering
      }

      let attachments = content.attachments()
      // Only attachments are sized by the environment; plain text keeps one Text value and no
      // resize cache.
      let textBuilder = attachments.isEmpty ? nil : TextBuilder(content, environment: environment)
      let rendering = Rendering(
        attachments: attachments,
        containsLinks: content.containsValue(for: \.link),
        textBuilder: textBuilder,
        staticText: textBuilder?.text ?? TextBuilder.text(for: content, environment: environment)
      )
      self.content = content
      self.environment = environment
      self.rendering = rendering
      return rendering
    }
  }
}

struct TextFragmentAttribute: TextAttribute {
}

extension Text.Layout {
  var isTextFragment: Bool {
    first?.first?[TextFragmentAttribute.self] != nil
  }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
  static var textContainer: NamedCoordinateSpace {
    .named("textContainer")
  }
}

extension GeometryProxy {
  fileprivate var textContainerSize: CGSize? {
    bounds(of: .textContainer)?.size
  }
}
