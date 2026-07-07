#if os(iOS)
  import SwiftUI
  import Testing
  import SnapshotTesting

  import RemodexTextKit

  extension StructuredText {
    @MainActor
    struct UnorderedListTests {
      private let layout = SwiftUISnapshotLayout.device(config: .iPhone8)

      @Test func hiearchicalSymbolList() {
        let view = StructuredText(
          markdown: """
            * Systems
              * FFF units
              * Great Underground Empire (Zork)
              * Potrzebie
                * Equals the thickness of Mad issue 26
                  * Developed by 19-year-old Donald E. Knuth
            """
        )
        .background(Color.guide)
        .padding(.horizontal)
        .remodex.unorderedListMarker(.hierarchical(.disc, .circle, .square))

        assertSnapshot(of: view, as: .image(layout: layout))
      }

      @Test func dashList() {
        let view = StructuredText(
          markdown: """
            * Systems
              * FFF units
              * Great Underground Empire (Zork)
              * Potrzebie
                * Equals the thickness of Mad issue 26
                  * Developed by 19-year-old Donald E. Knuth
            """
        )
        .background(Color.guide)
        .padding(.horizontal)
        .remodex.unorderedListMarker(.dash)

        assertSnapshot(of: view, as: .image(layout: layout))
      }
    }
  }

#endif
