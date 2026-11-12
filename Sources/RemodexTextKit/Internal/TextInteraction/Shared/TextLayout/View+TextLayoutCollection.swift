#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  import SwiftUI

  // MARK: - Overview
  //
  // `overlayTextLayoutCollection` adapts SwiftUI’s `Text.Layout` preference values into a
  // `TextLayoutCollection` that the selection system can query.
  //
  // The collection includes each anchored layout plus the geometry needed to convert anchors into
  // concrete origins. Platform interactions and selection rendering use the collection for hit
  // testing, position mapping, and selection rectangle computation.
  //
  // Selection reads the layouts its fragments publish while it needs them (see
  // `TextLayoutPublisher`); reading `Text.LayoutKey` directly collects every text in the subtree.

  extension View {
    func overlayTextLayoutCollection<Key: PreferenceKey>(
      _ key: Key.Type = Text.LayoutKey.self,
      @ViewBuilder content: @escaping (any TextLayoutCollection) -> some View
    ) -> some View where Key.Value == Text.LayoutKey.Value {
      overlayPreferenceValue(key) { value in
        GeometryReader { geometry in
          content(LiveTextLayoutCollection(base: value, geometry: geometry))
        }
      }
    }
  }
#endif
