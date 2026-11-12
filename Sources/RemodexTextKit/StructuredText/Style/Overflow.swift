import SwiftUI

/// Controls how content behaves when it overflows horizontally.
public enum OverflowMode: Hashable {
  /// Wraps content to fit the available width.
  case wrap
  /// Allows horizontal scrolling.
  case scroll
}

/// Describes the current overflow behavior and available layout metrics.
public enum OverflowState: Hashable {
  /// Wraps content to fit the available width.
  case wrap
  /// Scrolls horizontally. The container width is provided when available.
  case scroll(containerWidth: CGFloat?)

  /// The scroll container width when available; otherwise `nil`.
  public var containerWidth: CGFloat? {
    guard case .scroll(let containerWidth) = self else {
      return nil
    }
    return containerWidth
  }
}

/// A container that adapts to the current ``OverflowMode``.
///
/// `Overflow` handles content that overflows horizontally. It can switch
/// between wrapping and horizontal scrolling based on an environment value.
///
/// You can set the mode using the ``RemodexNamespace/overflowMode(_:)`` modifier. The default is
/// ``OverflowMode/scroll``.
///
/// - Note: You should always use `Overflow` if your custom style needs horizontal scrolling.
///   Using a horizontal `ScrollView` directly will interfere with text selection gestures.
public struct Overflow<Content: View>: View {
  @Environment(\.overflowMode) private var mode

  private let content: (OverflowState) -> Content
  private let reportsContainerWidth: Bool

  /// Creates an overflow container.
  public init(@ViewBuilder content: @escaping () -> Content) {
    self.init(reportsContainerWidth: false) { _ in
      content()
    }
  }

  /// Creates an overflow container that exposes the current overflow state.
  ///
  /// The container width in ``OverflowState/scroll(containerWidth:)`` is only known after the
  /// scroll view lays out, so it is `nil` at first and content that depends on it resizes once
  /// after it appears.
  public init(@ViewBuilder content: @escaping (_ state: OverflowState) -> Content) {
    self.init(reportsContainerWidth: true, content: content)
  }

  /// Creates an overflow container. When `reportsContainerWidth` is `false`, the scroll state's
  /// container width stays `nil` and nothing waits on it, so the content sizes on its first layout
  /// pass; content that needs the container width reads it during layout instead (see
  /// `OverflowWidthLimit`).
  init(
    reportsContainerWidth: Bool,
    @ViewBuilder content: @escaping (_ state: OverflowState) -> Content
  ) {
    self.content = content
    self.reportsContainerWidth = reportsContainerWidth
  }

  public var body: some View {
    switch mode {
    case .wrap:
      content(.wrap)
        .frame(maxWidth: .infinity, alignment: .leading)

    case .scroll:
      scrollView
        // Propagate gesture exclusion area
        .background(
          GeometryReader { geometry in
            Color.clear
              .preference(
                key: OverflowFrameKey.self,
                value: [geometry.frame(in: .textContainer)]
              )
          }
        )
    }
  }

  @ViewBuilder
  private var scrollView: some View {
    if reportsContainerWidth {
      ContainerWidthReportingScrollView(content: content)
    } else {
      ScrollView(.horizontal) {
        OverflowScrollContent(content: content(.scroll(containerWidth: nil)))
      }
    }
  }
}

// Serves the public state-closure initializer, whose content may read the container width.
// That width arrives after the scroll view lays out, so it is applied a runloop turn later.
private struct ContainerWidthReportingScrollView<Content: View>: View {
  @State private var containerWidth: CGFloat?
  @State private var containerWidthUpdates = DeferredUpdateCoalescer<CGFloat>()

  let content: (OverflowState) -> Content

  var body: some View {
    ScrollView(.horizontal) {
      OverflowScrollContent(content: content(.scroll(containerWidth: containerWidth)))
    }
    .onScrollGeometryChange(for: CGFloat.self, of: \.containerSize.width) {
      containerWidthUpdates.submit($1) { width in
        guard width.isFinite, containerWidth != width else {
          return
        }
        containerWidth = width
      }
    }
    .onDisappear {
      containerWidthUpdates.cancel()
    }
  }
}

private struct OverflowScrollContent<Content: View>: View {
  // A horizontal scroll view hugs its content's height and follows it when the content resizes
  // on iOS 26 and macOS 26. Earlier releases are not verified, so they keep publishing the
  // content height as a minimum height, which forces the scroll view to re-measure.
  private static var tracksContentHeight: Bool {
    if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
      return false
    }
    return true
  }

  let content: Content

  var body: some View {
    let selectableContent =
      content
      // Make text selection local in scrollable regions
      .modifier(TextSelectionInteraction())
      .transformPreference(PublishedTextLayoutKey.self) { value in
        value = []
      }

    if Self.tracksContentHeight {
      selectableContent.modifier(ContentHeightTracking())
    } else {
      selectableContent
    }
  }
}

private struct ContentHeightTracking: ViewModifier {
  @State private var contentHeight: CGFloat?

  func body(content: Content) -> some View {
    ZStack {
      Color.clear
        .frame(minHeight: contentHeight)
      content
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
          guard height.isFinite, contentHeight != height else {
            return
          }
          contentHeight = height
        }
    }
  }
}

// MARK: - Width limit

// Caps scrolling content at a multiple of the scroll container's width. The container width is
// read during layout from a container-relative ruler, so the content is measured at its capped
// width on the same pass instead of after a state round trip. The ruler reports the container's
// last known width, so a first mount or a width change can settle within that layout pass; no
// update is deferred. Only meaningful inside a scrolling `Overflow`; a missing, infinite, or
// non-positive ratio leaves the content untouched and measures nothing.
struct OverflowWidthLimit: ViewModifier {
  let relativeWidth: CGFloat?

  func body(content: Content) -> some View {
    if let relativeWidth, relativeWidth.isFinite, relativeWidth > 0 {
      OverflowWidthLimitLayout(relativeWidth: relativeWidth) {
        Color.clear
          .containerRelativeFrame(.horizontal)
          .accessibilityHidden(true)
        content
      }
    } else {
      content
    }
  }
}

private struct OverflowWidthLimitLayout: Layout {
  private static let rulerProposal = ProposedViewSize(width: nil, height: 0)

  let relativeWidth: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    guard let content = subviews.last, subviews.count == 2 else {
      return .zero
    }
    return content.sizeThatFits(contentProposal(for: proposal, subviews: subviews))
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    guard let ruler = subviews.first, let content = subviews.last, subviews.count == 2 else {
      return
    }
    ruler.place(at: bounds.origin, proposal: Self.rulerProposal)
    content.place(at: bounds.origin, proposal: contentProposal(for: proposal, subviews: subviews))
  }

  private func contentProposal(
    for proposal: ProposedViewSize,
    subviews: Subviews
  ) -> ProposedViewSize {
    // The ruler measures zero until the scroll view has a size (for example when measured
    // outside a window); the content then keeps its ideal width.
    let containerWidth = subviews[0].sizeThatFits(Self.rulerProposal).width
    guard containerWidth.isFinite, containerWidth > 0 else {
      return proposal
    }

    let limit = min(containerWidth * relativeWidth, proposal.width ?? .infinity)
    guard subviews[1].sizeThatFits(proposal).width > limit else {
      return proposal
    }
    return ProposedViewSize(width: limit, height: proposal.height)
  }
}

extension EnvironmentValues {
  @usableFromInline
  @Entry var overflowMode = OverflowMode.scroll
}
