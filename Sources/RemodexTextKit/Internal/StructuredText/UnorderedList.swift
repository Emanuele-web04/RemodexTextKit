import SwiftUI

extension StructuredText {
  struct UnorderedList: View {
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

      BlockVStack {
        ForEach(runs.identifiedIndices, id: \.id) { item in
          let run = runs[item.index]

          UnorderedListItem(
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
  fileprivate struct UnorderedListItem: View {
    @Environment(\.listItemStyle) private var listItemStyle
    @Environment(\.unorderedListMarker) private var unorderedListMarker

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
        unorderedListMarker.resolve(
          configuration: .init(
            indentationLevel: indentationLevel
          )
        )
      )
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }
  }
}
