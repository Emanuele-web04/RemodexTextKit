import SwiftUI

extension InlineStyle {
  /// The default inline style used by ``InlineText`` and ``StructuredText``.
  ///
  /// This style uses a slightly smaller monospaced font for inline code, semibold weight for
  /// strong text, and dotted links with a color that adapts to the current appearance.
  public static var `default`: InlineStyle {
    InlineStyle()
      .code(.monospaced, .fontScale(0.94), .tracking(-0.2), .foregroundColor(Color.secondary))
      .strong(.fontWeight(.semibold))
      .link(.foregroundColor(DynamicColor.link), .underlineStyle(.init(pattern: .dot)))
  }
}
