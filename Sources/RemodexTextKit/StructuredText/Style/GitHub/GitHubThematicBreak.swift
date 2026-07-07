import SwiftUI

extension StructuredText {
  /// A thematic break style inspired by GitHub’s rendering.
  public struct GitHubThematicBreakStyle: ThematicBreakStyle {
    /// Creates the GitHub thematic break style.
    public init() {}

    public func makeBody(configuration _: Configuration) -> some View {
      Divider()
        .remodex.frame(height: .fontScaled(0.25))
        .overlay(DynamicColor.gitHubBorder)
        .remodex.blockSpacing(.init(top: 24, bottom: 24))
    }
  }
}

extension StructuredText.ThematicBreakStyle where Self == StructuredText.GitHubThematicBreakStyle {
  /// A GitHub-like thematic break style.
  public static var gitHub: Self {
    .init()
  }
}

#Preview {
  StructuredText(
    markdown: """
      The sky above the port was the color of television, tuned to a dead channel.

      ---

      It was a bright cold day in April, and the clocks were striking thirteen.
      """
  )
  .padding()
  .remodex.paragraphStyle(.gitHub)
  .remodex.thematicBreakStyle(.gitHub)
}
