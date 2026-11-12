import SwiftUI

// MARK: - Overview
//
// `TextLinkUnderline` draws the environment's `LinkUnderline` under every link run of a `Text`
// fragment. The dots are drawn by a `TextRenderer` together with the text: each run with a `url`
// gets a row of dots spanning its typographic bounds, `offset` points below its baseline.
//
// Drawing with the text, instead of from the fragment's `Text.LayoutKey` preference, keeps the
// fragment free of geometry observers: an anchored layout changes whenever the fragment moves on
// screen, so a preference-driven overlay would lay the text out and redraw on every frame of a
// scroll.

struct TextLinkUnderline: ViewModifier {
  @Environment(\.linkUnderline) private var linkUnderline

  func body(content: Content) -> some View {
    if let linkUnderline {
      content.textRenderer(LinkUnderlineRenderer(underline: linkUnderline))
    } else {
      content
    }
  }
}

private struct LinkUnderlineRenderer: TextRenderer {
  let underline: LinkUnderline

  // The dots sit below the last line's descent, outside the text's frame.
  var displayPadding: EdgeInsets {
    EdgeInsets(
      top: 0, leading: 0, bottom: max(0, underline.offset + underline.dotDiameter), trailing: 0)
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for line in layout {
      context.draw(line)
    }

    let step = underline.dotDiameter + underline.spacing
    guard step > 0 else { return }
    var dots = Path()
    for line in layout {
      for run in line where run.url != nil {
        let bounds = run.typographicBounds
        let y = bounds.origin.y + underline.offset
        var x = bounds.rect.minX + underline.dotDiameter / 2
        while x <= bounds.rect.maxX {
          dots.addEllipse(
            in: CGRect(
              x: x - underline.dotDiameter / 2,
              y: y - underline.dotDiameter / 2,
              width: underline.dotDiameter,
              height: underline.dotDiameter
            ))
          x += step
        }
      }
    }
    guard !dots.isEmpty else { return }
    if let color = underline.color {
      context.fill(dots, with: .color(color))
    } else {
      context.fill(dots, with: .style(.tint))
    }
  }
}
