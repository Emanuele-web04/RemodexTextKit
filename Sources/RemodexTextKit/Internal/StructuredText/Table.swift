import SwiftUI

// MARK: - Overview
//
// Table uses a two-pass layout system. The first pass renders cells which emit their bounds via
// preferences. The second pass collects all cell bounds, transforms them from anchor coordinates
// to geometry coordinates, and builds a `TableLayout` that the style uses to render overlays
// (such as grid lines) and backgrounds with precise cell positions.
//
// Cell spacing comes from the environment the style sets around its label, so the grid is
// measured with its final spacing on the first pass.
//
// Styles that only need lines between the cells set `tableDividers` instead: the grid then lays
// the lines out as cells of their own. Cell anchors move with every frame of a scroll, so an
// overlay built from them is rebuilt and redrawn while the table merely scrolls past; dividers
// laid out by the grid change only when the table does.

extension StructuredText {
  struct Table: View {
    @Environment(\.tableStyle) private var tableStyle

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring
    private let columns: [PresentationIntent.TableColumn]

    init(
      intent: PresentationIntent.IntentType?,
      content: AttributedSubstring,
      columns: [PresentationIntent.TableColumn]
    ) {
      self.intent = intent
      self.content = content
      self.columns = columns
    }

    var body: some View {
      let configuration = TableStyleConfiguration(
        label: .init(TableGrid(intent: intent, content: content, columns: columns)),
        indentationLevel: indentationLevel
      )
      let resolvedStyle = tableStyle.resolve(configuration: configuration)

      AnyView(resolvedStyle)
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }
  }

  // A separate view so the cell spacing is read where the style places the label.
  private struct TableGrid: View {
    @Environment(\.tableCellSpacing) private var spacing
    @Environment(\.tableDividers) private var dividers

    let intent: PresentationIntent.IntentType?
    let content: AttributedSubstring
    let columns: [PresentationIntent.TableColumn]

    var body: some View {
      let rowRuns = content.blockRuns(parent: intent)

      Grid(
        horizontalSpacing: dividers == nil ? spacing.horizontal : 0,
        verticalSpacing: dividers == nil ? spacing.vertical : 0
      ) {
        ForEach(rowRuns.identifiedIndices, id: \.id) { row in
          let rowRun = rowRuns[row.index]
          let rowContent = content[rowRun.range]
          let columnRuns = rowContent.blockRuns(parent: rowRun.intent)

          if let dividers, row.index > 0 {
            // A view outside a row spans every column; it takes the grid's width, not more.
            Rectangle()
              .fill(dividers.color)
              .frame(height: dividers.thickness)
              .gridCellUnsizedAxes(.horizontal)
          }

          GridRow {
            ForEach(columnRuns.identifiedIndices, id: \.id) { column in
              let cellRun = columnRuns[column.index]
              let cellContent = rowContent[cellRun.range]

              if let dividers, column.index > 0 {
                Rectangle()
                  .fill(dividers.color)
                  .frame(width: dividers.thickness)
                  .gridCellUnsizedAxes(.vertical)
              }

              TableCell(cellContent, row: row.index, column: column.index)
                .gridColumnAlignment(alignment(for: column.index))
            }
          }
        }
      }
    }

    private func alignment(for columnIndex: Int) -> HorizontalAlignment {
      guard columnIndex < columns.count else {
        return .leading
      }

      switch columns[columnIndex].alignment {
      case .left:
        return .leading
      case .center:
        return .center
      case .right:
        return .trailing
      @unknown default:
        return .leading
      }
    }
  }
}

extension StructuredText.Table {
  /// Lines the grid draws between its rows and columns, in place of cell spacing.
  struct Dividers: Hashable, Sendable {
    let color: DynamicColor
    let thickness: CGFloat
  }
}

extension EnvironmentValues {
  @Entry var tableCellSpacing = StructuredText.TableCell.Spacing()
  @Entry var tableDividers: StructuredText.Table.Dividers? = nil
}
