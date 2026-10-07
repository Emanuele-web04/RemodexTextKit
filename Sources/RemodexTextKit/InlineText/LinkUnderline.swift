import SwiftUI

/// A dotted underline drawn under links, independent of the font's own underline metrics.
///
/// The system underline sits tight against the glyphs and sizes its dots from the font, so a
/// dotted link reads heavy at body sizes. `LinkUnderline` draws its own row of dots under each
/// link run instead: you choose how big they are, how far apart, and how far below the baseline
/// they sit.
///
/// ```swift
/// StructuredText(markdown: text)
///   .remodex.inlineStyle(.default.link(.foregroundColor(.blue)))
///   .remodex.linkUnderline(.dotted(color: .blue.opacity(0.6)))
/// ```
///
/// Pair it with an inline style whose `link` property sets no `underlineStyle`, or the link gets
/// both underlines.
public struct LinkUnderline: Hashable, Sendable {
  /// The diameter of each dot, in points.
  public var dotDiameter: CGFloat
  /// The gap between two dots, in points.
  public var spacing: CGFloat
  /// The distance from the baseline down to the dots' centers, in points.
  public var offset: CGFloat
  /// The dots' color. `nil` uses the environment's tint.
  public var color: Color?

  public init(dotDiameter: CGFloat, spacing: CGFloat, offset: CGFloat, color: Color? = nil) {
    self.dotDiameter = dotDiameter
    self.spacing = spacing
    self.offset = offset
    self.color = color
  }

  /// Small dots a few points below the baseline.
  public static func dotted(
    dotDiameter: CGFloat = 1.25,
    spacing: CGFloat = 1.75,
    offset: CGFloat = 4,
    color: Color? = nil
  ) -> LinkUnderline {
    LinkUnderline(dotDiameter: dotDiameter, spacing: spacing, offset: offset, color: color)
  }
}

extension EnvironmentValues {
  @usableFromInline
  @Entry var linkUnderline: LinkUnderline? = nil
}
