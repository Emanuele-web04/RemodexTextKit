import SwiftUI

// MARK: - Overview
//
// `TextSelectionInteraction` manages the text selection model lifecycle for multiple `Text` fragments.
//
// Selection is opt-in through the `textSelection` environment value. When enabled, the modifier
// observes text layout changes via `overlayTextLayoutCollection` and creates or updates a
// `TextSelectionModel`. The model is then passed to the platform-specific implementation
// (`PlatformTextSelectionInteraction`), which presents the appropriate selection UI for macOS
// or iOS. This separation keeps model management in shared code while platform interactions
// remain independent.

struct TextSelectionInteraction: ViewModifier {
  #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
    @Environment(\.textSelection) private var textSelection
    @Environment(TextSelectionCoordinator.self) private var coordinator: TextSelectionCoordinator?

    @State private var model = TextSelectionModel()
  #endif

  func body(content: Content) -> some View {
    #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
      if textSelection.allowsSelection {
        content
          .overlayTextLayoutCollection { layoutCollection in
            // task(id:) instead of onChange: at mount, Text fragments publish their
            // layouts across several layout passes within one frame, so the observed
            // collection changes repeatedly and onChange trips SwiftUI's
            // "tried to update multiple times per frame" runtime issue. task(id:)
            // coalesces naturally - intermediate ids cancel, the model adopts only
            // the settled collection, and the work runs after the frame commits.
            // Stale queries in the gap are safe: the model clamps incoming positions.
            Color.clear
              .task(id: AnyTextLayoutCollection(layoutCollection)) {
                model.setCoordinator(coordinator)
                model.setLayoutCollection(layoutCollection)
              }
          }
          .modifier(PlatformTextSelectionInteraction(model: model))
      } else {
        content
      }
    #else
      content
    #endif
  }
}

#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  extension EnvironmentValues {
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @usableFromInline
    @Entry var textSelection: any TextSelectability.Type = DisabledTextSelectability.self
  }
#endif
