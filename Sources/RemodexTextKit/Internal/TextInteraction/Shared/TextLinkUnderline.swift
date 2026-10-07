import SwiftUI

// MARK: - Overview
//
// `TextLinkUnderline` draws the environment's `LinkUnderline` under every link run of a `Text`
// fragment. Like `TextLinkInteraction`, it reads the anchored `Text.Layout` from the
// `Text.LayoutKey` preference and works in layout-local coordinates; each run with a `url` gets a
// row of dots spanning its typographic bounds, `offset` points below its baseline.

struct TextLinkUnderline: ViewModifier {
  @Environment(\.linkUnderline) private var linkUnderline

  func body(content: Content) -> some View {
    if let linkUnderline {
      content
        .backgroundPreferenceValue(Text.LayoutKey.self) { value in
          GeometryReader { geometry in
            Canvas { context, _ in
              for anchoredLayout in value {
                let origin = geometry[anchoredLayout.origin]
                draw(linkUnderline, in: anchoredLayout.layout, origin: origin, context: &context)
              }
            }
            .foregroundStyle(linkUnderline.color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
          }
          .allowsHitTesting(false)
        }
    } else {
      content
    }
  }

  private func draw(
    _ underline: LinkUnderline,
    in layout: Text.Layout,
    origin: CGPoint,
    context: inout GraphicsContext
  ) {
    let step = underline.dotDiameter + underline.spacing
    guard step > 0 else { return }
    var dots = Path()
    for line in layout {
      for run in line where run.url != nil {
        let bounds = run.typographicBounds
        let y = origin.y + bounds.origin.y + underline.offset
        var x = origin.x + bounds.rect.minX + underline.dotDiameter / 2
        let maxX = origin.x + bounds.rect.maxX
        while x <= maxX {
          dots.addEllipse(in: CGRect(
            x: x - underline.dotDiameter / 2,
            y: y - underline.dotDiameter / 2,
            width: underline.dotDiameter,
            height: underline.dotDiameter
          ))
          x += step
        }
      }
    }
    context.fill(dots, with: .foreground)
  }
}
