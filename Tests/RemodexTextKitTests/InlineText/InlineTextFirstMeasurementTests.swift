#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  import RemodexTextKit

  @MainActor
  struct InlineTextFirstMeasurementTests {
    @Test(arguments: [390.0, 700.0], [17.0, 23.0])
    func firstSynchronousMeasurementMatchesNativeText(width: Double, fontSize: Double) {
      let text = (1...14).map {
        "Synthetic paragraph \($0): synchronous first layout should measure this text before deferred callbacks."
      }.joined(separator: " ")
      let font = Font.system(size: fontSize, design: fontSize == 23 ? .serif : .default)
      let reference = NSHostingController(
        rootView: Text(text)
          .font(font)
          .frame(width: width, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      )
      let fragment = NSHostingController(
        rootView: InlineText(markdown: text)
          .font(font)
          .frame(width: width, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      )
      let proposal = CGSize(width: width, height: 100_000)

      // Measure before appearance callbacks or a runloop can replace an empty fragment.
      let expected = reference.sizeThatFits(in: proposal)
      let actual = fragment.sizeThatFits(in: proposal)

      #expect(abs(actual.height - expected.height) < 0.5)
    }
  }
#endif
