import SwiftUI

// MARK: - Overview
//
// BlockVStack arranges blocks vertically with CSS-style margin collapsing behavior. Adjacent
// blocks' top and bottom spacing collapses by taking the maximum value rather than summing,
// matching how CSS margins work.
//
// Each block's spacing is read from its container values while the children are resolved, so
// the first layout pass already uses the final spacing (see `BlockSpacingKey`). The stack also
// publishes the union of its children's spacing, which lets an enclosing list or quote collapse
// its margins against the blocks nested inside it.
//
// List items can override block spacing with environment-driven list item spacing for consistent
// spacing within lists regardless of individual block styles.
//
// In ordered lists the stack also lines the items' markers up by their trailing edges, read from
// an explicit alignment guide while measuring, so every item's content starts at the same x on
// the first layout pass.

extension StructuredText {
  struct BlockVStack<Content: View>: View {
    @Environment(\.multilineTextAlignment) private var textAlignment
    @Environment(\.listItemSpacingEnabled) private var listItemSpacingEnabled
    @Environment(\.resolvedListItemSpacing) private var resolvedListItemSpacing

    private let alignsListMarkers: Bool
    private let content: Content

    init(alignsListMarkers: Bool = false, @ViewBuilder content: () -> Content) {
      self.alignsListMarkers = alignsListMarkers
      self.content = content()
    }

    var body: some View {
      Group(subviews: content) { children in
        BlockVStackLayout(textAlignment: textAlignment, alignsListMarkers: alignsListMarkers) {
          ForEach(children) { child in
            child.layoutValue(
              key: BlockSpacingKey.self,
              value: listItemSpacingEnabled
                ? resolvedListItemSpacing : child.containerValues.effectiveBlockSpacing
            )
          }
        }
        .containerValue(\.nestedBlockSpacing, children.blockSpacingUnion)
      }
    }
  }
}

extension StructuredText {
  struct BlockAlignmentKey: LayoutValueKey {
    static let defaultValue: TextAlignment? = nil
  }

  fileprivate struct BlockVStackLayout: Layout {
    struct Cache {
      let spacings: [CGFloat]
    }

    let textAlignment: TextAlignment
    let alignsListMarkers: Bool

    func makeCache(subviews: Subviews) -> Cache {
      return Cache(
        spacings: subviews.indices.dropLast().map { index in
          let current = subviews[index]
          let next = subviews[index + 1]
          let currentBottom = current[BlockSpacingKey.self].bottom
          let nextTop = next[BlockSpacingKey.self].top

          // Take the maximum block spacing, otherwise the preferred view spacing
          return [currentBottom, nextTop].compactMap(\.self).max()
            ?? current.spacing.distance(to: next.spacing, along: .vertical)
        }
      )
    }

    func sizeThatFits(
      proposal: ProposedViewSize,
      subviews: Subviews, cache: inout Cache
    ) -> CGSize {
      if let width = proposal.width, width <= 0 {
        return .zero
      }

      var size = CGSize.zero
      let insets = markerInsets(width: proposal.width, subviews: subviews)

      for (view, inset) in zip(subviews, insets) {
        let viewSize = view.sizeThatFits(viewProposal(width: proposal.width, inset: inset))
        size.height += viewSize.height
        size.width = max(size.width, inset + viewSize.width)
      }

      size.height += cache.spacings.reduce(0, +)

      return size
    }

    func placeSubviews(
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews, cache: inout Cache
    ) {
      var currentY: CGFloat = 0
      let insets = markerInsets(width: proposal.width, subviews: subviews)

      for (index, view) in zip(subviews.indices, subviews) {
        let inset = insets[index]
        let viewProposal = viewProposal(width: proposal.width, inset: inset)
        let viewSize = view.sizeThatFits(viewProposal)
        let width = inset + viewSize.width

        var point = bounds.origin
        point.x += inset
        let alignment = view[BlockAlignmentKey.self] ?? textAlignment

        switch alignment {
        case .leading:
          break  // do nothing
        case .center:
          point.x += (bounds.width - width) / 2
        case .trailing:
          point.x += bounds.width - width
        }

        point.y += currentY

        view.place(at: point, proposal: viewProposal)

        currentY += viewSize.height

        if index < subviews.count - 1 {
          currentY += cache.spacings[index]
        }
      }
    }

    // The stack places its children itself, so it exposes none of their explicit horizontal
    // guides. Otherwise a nested list's marker guide would leak into the enclosing list item and
    // misalign the outer markers. Vertical guides (text baselines) still propagate.
    func explicitAlignment(
      of guide: HorizontalAlignment,
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout Cache
    ) -> CGFloat? {
      nil
    }

    private func viewProposal(width: CGFloat?, inset: CGFloat) -> ProposedViewSize {
      ProposedViewSize(width: width.map { max($0 - inset, 0) }, height: nil)
    }

    // How far each item moves so its marker's trailing edge lines up with the widest marker's.
    private func markerInsets(width: CGFloat?, subviews: Subviews) -> [CGFloat] {
      let none = Array(repeating: CGFloat.zero, count: subviews.count)
      guard alignsListMarkers else {
        return none
      }

      let proposal = ProposedViewSize(width: width, height: nil)
      let trailingEdges = subviews.map {
        $0.dimensions(in: proposal)[explicit: HorizontalAlignment.listMarkerTrailing]
      }
      guard let widest = trailingEdges.compactMap(\.self).max() else {
        return none
      }
      return trailingEdges.map { $0.map { widest - $0 } ?? 0 }
    }
  }
}

extension HorizontalAlignment {
  private enum ListMarkerTrailing: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
      context[.trailing]
    }
  }

  /// The trailing edge of an ordered-list item's marker.
  static let listMarkerTrailing = Self(ListMarkerTrailing.self)
}

@available(tvOS, unavailable)
@available(watchOS, unavailable)
#Preview {
  @Previewable @State var textAlignment = TextAlignment.leading
  @Previewable @State var blockSpacing: CGFloat = 1

  VStack {
    GroupBox {
      Picker("Text Alignment", selection: $textAlignment) {
        Text("Leading").tag(TextAlignment.leading)
        Text("Center").tag(TextAlignment.center)
        Text("Trailing").tag(TextAlignment.trailing)
      }
      .pickerStyle(.segmented)
      HStack {
        Text("2nd / 3rd Spacing")
        Slider(value: $blockSpacing, in: 0...3)
      }
    }
    Spacer()
    StructuredText.BlockVStack {
      Text(
        """
        Listen to your sister, Morty. To live is to risk it all, otherwise you’re just an inert \
        chunk of randomly assembled molecules drifting wherever the universe blows you.
        """
      )
      .remodex.blockSpacing(.fontScaled(bottom: 1))
      Text(
        """
        Listen, Morty, I hate to break it to you but what people call "love" is just a chemical \
        reaction that compels animals to breed. It hits hard, Morty, then it slowly fades, \
        leaving you stranded in a failing marriage. I did it. Your parents are gonna do it. \
        Break the cycle, Morty. Rise above. Focus on science.
        """
      )
      .remodex.blockSpacing(.fontScaled(bottom: blockSpacing))
      Text(
        """
        Wow, I really Cronenberged up the whole place, huh Morty? Just a bunch a Cronenbergs \
        walkin' around.
        """
      )
      .remodex.blockSpacing(.fontScaled(top: 1, bottom: 1))
    }
    .border(Color.red)
    Spacer()
  }
  .multilineTextAlignment(textAlignment)
  .padding()
}
