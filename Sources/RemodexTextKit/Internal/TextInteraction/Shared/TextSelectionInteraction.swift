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
//
// The fragments publish their layouts to this modifier only while it asks for them
// (`TextLayoutPublisher`). On iOS that is while the text is touched or selected
// (`TextSelectionModel.observesLayout`, driven by `UITextInteractionView`), so selectable text
// costs nothing extra while it scrolls; AppKit keeps them published.

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
          .environment(\.publishesTextLayout, publishesTextLayout)
          .overlayTextLayoutCollection(PublishedTextLayoutKey.self) { layoutCollection in
            // A representable receives preference changes without using task(id:),
            // whose implementation still installs an onChange observer. Its
            // coordinator defers the burst and adopts only the settled collection.
            TextLayoutCollectionAdoptionView(
              layoutCollection: AnyTextLayoutCollection(layoutCollection),
              model: model,
              selectionCoordinator: coordinator
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
          }
          .modifier(PlatformTextSelectionInteraction(model: model))
      } else {
        content
      }
    #else
      content
    #endif
  }

  #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
    private var publishesTextLayout: Bool {
      #if canImport(UIKit)
        model.observesLayout
      #else
        true
      #endif
    }
  #endif
}

#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  extension EnvironmentValues {
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @usableFromInline
    @Entry var textSelection: any TextSelectability.Type = DisabledTextSelectability.self
  }
#endif
