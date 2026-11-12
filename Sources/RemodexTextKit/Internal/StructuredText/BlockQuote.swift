import SwiftUI

extension StructuredText {
  struct BlockQuote: View {
    @Environment(\.blockQuoteStyle) private var blockQuoteStyle

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring

    init(intent: PresentationIntent.IntentType?, content: AttributedSubstring) {
      self.intent = intent
      self.content = content
    }

    var body: some View {
      // The quote style may place its label in a stack, which container values cannot leave,
      // so resolve the nested blocks here and publish their spacing on the quote itself.
      Group(subviews: BlockContent(parent: intent, content: content)) { blocks in
        let configuration = BlockStyleConfiguration(
          label: .init(blocks),
          indentationLevel: indentationLevel
        )
        let resolvedStyle = blockQuoteStyle.resolve(configuration: configuration)

        AnyView(resolvedStyle)
          .containerValue(\.nestedBlockSpacing, blocks.blockSpacingUnion)
      }
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }
  }
}
