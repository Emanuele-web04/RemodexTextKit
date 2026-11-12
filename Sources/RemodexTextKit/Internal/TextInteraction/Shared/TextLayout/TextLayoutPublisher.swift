import SwiftUI

// MARK: - Overview
//
// `TextLayoutPublisher` forwards a fragment's anchored `Text.Layout` to the enclosing selection
// through `PublishedTextLayoutKey`, but only while that selection asks for it
// (`publishesTextLayout`).
//
// An anchored layout moves with its fragment, so observing `Text.LayoutKey` makes SwiftUI resolve
// the layout again, and the selection rebuild its collection, on every frame the text scrolls.
// Selection only needs the layouts once the text is touched or selected, so idle text publishes
// nothing and costs nothing while it moves. Starting or stopping to publish recreates only the
// fragment's own text view, which holds no state; the views around it keep their identity.

struct TextLayoutPublisher: ViewModifier {
  @Environment(\.publishesTextLayout) private var publishesTextLayout

  func body(content: Content) -> some View {
    if publishesTextLayout {
      content.backgroundPreferenceValue(Text.LayoutKey.self) { value in
        Color.clear.preference(key: PublishedTextLayoutKey.self, value: value)
      }
    } else {
      content
    }
  }
}

struct PublishedTextLayoutKey: PreferenceKey {
  static var defaultValue: Text.LayoutKey.Value { [] }

  static func reduce(value: inout Text.LayoutKey.Value, nextValue: () -> Text.LayoutKey.Value) {
    value.append(contentsOf: nextValue())
  }
}

extension EnvironmentValues {
  @Entry var publishesTextLayout = false
}
