import SwiftUI

// MARK: - Overview
//
// Block spacing travels as container values so `BlockVStack` reads it while it resolves its
// children, on the same pass that measures them. A preference would only reach the stack after
// the first layout, so every block would be measured once with default spacing and then again
// with the real one.
//
// `blockSpacing` is what a block's own style asks for (`.remodex.blockSpacing`).
// `nestedBlockSpacing` is the union of the blocks nested inside a container block (lists and
// quotes), which the enclosing stack folds into that block's margins.

extension StructuredText {
  struct BlockSpacingKey: LayoutValueKey {
    static let defaultValue = BlockSpacing()
  }
}

extension ContainerValues {
  @Entry var blockSpacing = StructuredText.BlockSpacing()
  @Entry var nestedBlockSpacing = StructuredText.BlockSpacing()

  /// The spacing a block contributes to its parent stack: its own spacing merged with the
  /// spacing of the blocks nested inside it.
  var effectiveBlockSpacing: StructuredText.BlockSpacing {
    blockSpacing.union(nestedBlockSpacing)
  }
}

extension SubviewsCollection {
  /// The union of the spacing every block in this collection contributes.
  var blockSpacingUnion: StructuredText.BlockSpacing {
    reduce(into: StructuredText.BlockSpacing()) { union, subview in
      union = union.union(subview.containerValues.effectiveBlockSpacing)
    }
  }
}
