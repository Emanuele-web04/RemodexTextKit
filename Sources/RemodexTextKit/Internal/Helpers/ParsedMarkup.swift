import Foundation

// Memoizes the parse of the current markup for a text view. Parsing during `body` (instead of
// in `onChange(initial:)`) means a freshly mounted view renders its content on the first frame:
// the state-driven version laid out an empty string first, so every new view reported a
// near-zero height for a frame and shifted everything below it (and clamped scroll offsets).
// A reference type, so updating the memo inside `body` does not invalidate the view.
@MainActor final class ParsedMarkup {
  private var markup: String?
  private var value = AttributedString()
  private var referencesAttachments = false

  /// The parsed markup plus whether it references images or custom emoji, decided once per
  /// parse so attachment resolution is skipped synchronously for plain documents.
  func document(for markup: String, parser: any MarkupParser) -> ParsedDocument {
    if markup != self.markup {
      value = (try? parser.attributedString(for: markup)) ?? .init()
      referencesAttachments = value.referencesAttachments
      self.markup = markup
    }
    return ParsedDocument(value: value, referencesAttachments: referencesAttachments)
  }
}

struct ParsedDocument {
  let value: AttributedString
  let referencesAttachments: Bool
}

extension AttributedString {
  /// Whether any run carries an image or custom emoji URL that `WithAttachments` resolves.
  var referencesAttachments: Bool {
    runs.contains { $0.imageURL != nil || $0.remodex.emojiURL != nil }
  }
}
