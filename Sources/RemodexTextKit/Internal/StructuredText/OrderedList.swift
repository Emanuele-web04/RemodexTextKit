import SwiftUI

// MARK: - Overview
//
// OrderedList aligns all list item markers by their trailing edges, so item content lines up
// even when marker widths vary (e.g., "1." vs "10."). Each marker marks its trailing edge with an
// explicit alignment guide, and the list's `BlockVStack` insets the items with narrower markers
// while it lays them out.

extension StructuredText {
  struct OrderedList: View {
    @Environment(\.listItemSpacing) private var listItemSpacing
    @Environment(\.textEnvironment) private var textEnvironment

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring

    init(intent: PresentationIntent.IntentType?, content: AttributedSubstring) {
      self.intent = intent
      self.content = content
    }

    var body: some View {
      let runs = content.blockRuns(parent: intent)

      BlockVStack(alignsListMarkers: true) {
        ForEach(runs.identifiedIndices, id: \.id) { item in
          let run = runs[item.index]

          OrderedListItem(
            intent: run.intent,
            content: content[run.range]
          )
        }
      }
      .environment(\.resolvedListItemSpacing, listItemSpacing.resolve(in: textEnvironment))
      .environment(\.listItemSpacingEnabled, true)
    }
  }
}

extension StructuredText {
  fileprivate struct OrderedListItem: View {
    @Environment(\.listItemStyle) private var listItemStyle
    @Environment(\.orderedListMarker) private var orderedListMarker

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring

    init(
      intent: PresentationIntent.IntentType?,
      content: AttributedSubstring
    ) {
      self.intent = intent
      self.content = content
    }

    var body: some View {
      // The item style may place the block in a stack, which container values cannot leave,
      // so resolve the nested blocks here and publish their spacing on the item itself.
      Group(subviews: BlockContent(parent: intent, content: content)) { blocks in
        let configuration = ListItemStyleConfiguration(
          marker: .init(marker),
          block: .init(blocks),
          indentationLevel: indentationLevel
        )
        let resolvedStyle = listItemStyle.resolve(configuration: configuration)

        AnyView(resolvedStyle)
          .containerValue(\.nestedBlockSpacing, blocks.blockSpacingUnion)
      }
    }

    private var marker: some View {
      AnyView(
        orderedListMarker.resolve(
          configuration: .init(
            indentationLevel: indentationLevel,
            ordinal: ordinal
          )
        )
      )
      .alignmentGuide(.listMarkerTrailing) { $0[.trailing] }
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }

    private var ordinal: Int {
      guard case .listItem(let ordinal) = intent?.kind else {
        return 0
      }
      return ordinal
    }
  }
}
