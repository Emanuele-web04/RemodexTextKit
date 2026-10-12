import Foundation

// Memoizes the parse of the current markup for a text view. Parsing during `body` (instead of
// in `onChange(initial:)`) means a freshly mounted view renders its content on the first frame:
// the state-driven version laid out an empty string first, so every new view reported a
// near-zero height for a frame and shifted everything below it (and clamped scroll offsets).
// A reference type, so updating the memo inside `body` does not invalidate the view.
@MainActor final class ParsedMarkup {
  private var markup: String?
  private var value = AttributedString()

  func attributedString(for markup: String, parser: any MarkupParser) -> AttributedString {
    if markup != self.markup {
      value = (try? parser.attributedString(for: markup)) ?? .init()
      self.markup = markup
    }
    return value
  }
}
