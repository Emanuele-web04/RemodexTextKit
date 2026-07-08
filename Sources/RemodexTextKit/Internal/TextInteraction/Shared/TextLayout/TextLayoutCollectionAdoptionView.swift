#if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION
  import SwiftUI

  @MainActor
  final class TextLayoutCollectionAdoptionCoordinator {
    private let updates = DeferredUpdateCoalescer<AnyTextLayoutCollection>()

    func submit(
      _ layoutCollection: AnyTextLayoutCollection,
      model: TextSelectionModel,
      selectionCoordinator: TextSelectionCoordinator?
    ) {
      updates.submit(layoutCollection) { [weak model, weak selectionCoordinator] layoutCollection in
        guard let model else {
          return
        }
        model.setCoordinator(selectionCoordinator)
        model.setLayoutCollection(layoutCollection)
      }
    }

    func cancel() {
      updates.cancel()
    }
  }

  #if canImport(UIKit)
    import UIKit

    struct TextLayoutCollectionAdoptionView: UIViewRepresentable {
      let layoutCollection: AnyTextLayoutCollection
      let model: TextSelectionModel
      let selectionCoordinator: TextSelectionCoordinator?

      func makeCoordinator() -> TextLayoutCollectionAdoptionCoordinator {
        TextLayoutCollectionAdoptionCoordinator()
      }

      func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
      }

      func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.submit(
          layoutCollection,
          model: model,
          selectionCoordinator: selectionCoordinator
        )
      }

      static func dismantleUIView(
        _ uiView: UIView,
        coordinator: TextLayoutCollectionAdoptionCoordinator
      ) {
        coordinator.cancel()
      }
    }
  #elseif canImport(AppKit)
    import AppKit

    struct TextLayoutCollectionAdoptionView: NSViewRepresentable {
      let layoutCollection: AnyTextLayoutCollection
      let model: TextSelectionModel
      let selectionCoordinator: TextSelectionCoordinator?

      func makeCoordinator() -> TextLayoutCollectionAdoptionCoordinator {
        TextLayoutCollectionAdoptionCoordinator()
      }

      func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
      }

      func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.submit(
          layoutCollection,
          model: model,
          selectionCoordinator: selectionCoordinator
        )
      }

      static func dismantleNSView(
        _ nsView: NSView,
        coordinator: TextLayoutCollectionAdoptionCoordinator
      ) {
        coordinator.cancel()
      }
    }
  #endif
#endif
