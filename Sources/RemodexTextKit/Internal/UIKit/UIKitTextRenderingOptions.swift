// FILE: UIKitTextRenderingOptions.swift
// Purpose: Carries opt-in UIKit text-rendering knobs through the SwiftUI environment.
// Layer: Internal Rendering Configuration
// Exports: UIKitTextRenderingOptions environment value
// Depends on: SwiftUI

import SwiftUI

struct UIKitTextRenderingOptions: Hashable, Sendable {
  var prefersTextFragments: Bool = false
  var isSelectable: Bool = true
}

extension EnvironmentValues {
  @Entry var uikitTextRenderingOptions = UIKitTextRenderingOptions()
}
