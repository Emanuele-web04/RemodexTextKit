import SwiftUI

// MARK: - Overview
//
// `TextSelectionCoordinator` ensures there’s at most one active selection across a view subtree.
//
// Selection can be driven by multiple independent overlays. For example, `Overflow`-backed
// scrollable regions install their own interaction views so selection works locally inside the
// scroll view, while the surrounding content can still be selectable.
//
// Each `TextSelectionModel` registers with a shared coordinator. When one model becomes selected,
// the coordinator clears selection in the others, preventing multiple active selections across
// local and non-scrollable regions.
//
// By default every `StructuredText` establishes its own coordinator, so coordination stops at the
// view's boundary. `TextSelectionScope` (exposed as `.remodex.textSelectionScope()`) injects a
// coordinator higher up the hierarchy; `TextSelectionCoordination` adopts an inherited coordinator
// instead of creating one, which lets a container like a chat timeline keep at most one active
// selection across many structured-text views.

#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  @Observable
  final class TextSelectionCoordinator {
    private var models: [WeakBox<TextSelectionModel>] = []

    func register(_ model: TextSelectionModel) {
      models.append(WeakBox(model))
      compact()
    }

    func modelDidSelectText(_ model: TextSelectionModel) {
      // Clear selection in the other models
      for weakModel in models where weakModel.wrapped !== model {
        weakModel.wrapped?.selectedRange = nil
      }
      compact()
    }

    private func compact() {
      models.removeAll {
        $0.wrapped == nil
      }
    }
  }
#endif

struct TextSelectionCoordination: ViewModifier {
  #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
    @Environment(TextSelectionCoordinator.self) private var inheritedCoordinator:
      TextSelectionCoordinator?
    @State private var coordinator = TextSelectionCoordinator()
  #endif

  func body(content: Content) -> some View {
    #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
      content.environment(inheritedCoordinator ?? coordinator)
    #else
      content
    #endif
  }
}

struct TextSelectionScope: ViewModifier {
  #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
    @State private var coordinator = TextSelectionCoordinator()
  #endif

  func body(content: Content) -> some View {
    #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
      content.environment(coordinator)
    #else
      content
    #endif
  }
}
