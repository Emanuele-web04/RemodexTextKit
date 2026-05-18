import SwiftUI

// MARK: - Overview
//
// `TextSelectionBackground` draws selection highlights behind a `Text` fragment.
//
// The platform selection interaction stores a `TextSelectionModel` in the environment at fragment
// scope. This modifier reads the fragment’s anchored `Text.Layout` and forwards it to the AppKit
// selection view so it can convert the current selected range into highlight rectangles.

struct TextSelectionBackground: ViewModifier {
  func body(content: Content) -> some View {
    #if REMODEX_TEXT_KIT_ENABLE_TEXT_SELECTION && canImport(AppKit)
      content
        .backgroundPreferenceValue(Text.LayoutKey.self) { value in
          if let anchoredLayout = value.first {
            GeometryReader { geometry in
              AppKitTextSelectionView(
                layout: anchoredLayout.layout,
                origin: geometry[anchoredLayout.origin]
              )
            }
          }
        }
    #else
      content
    #endif
  }
}
