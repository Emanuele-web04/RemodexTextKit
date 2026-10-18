#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import RemodexTextKit

  @MainActor
  struct TextBuilderLayoutTests {
    @Test(arguments: [390.0, 700.0], [17.0, 23.0])
    func attributedCodeKeepsNativeWrappingAndFontMetrics(width: Double, fontSize: Double) {
      let font = Font.custom("Menlo", fixedSize: fontSize)
      var content = AttributedString()
      for index in 0..<40 {
        var keyword = AttributedString("let ")
        keyword.font = font.bold()
        keyword.foregroundColor = .purple
        var value = AttributedString("value\(index) = \"Unicode λ, 👩🏽‍💻 and a wrapped string\"\n")
        value.font = index.isMultiple(of: 2) ? font.italic() : font
        value.foregroundColor = .green
        content += keyword
        content += value
      }
      let builder = TextFragment<AttributedString>.TextBuilder(
        content, environment: TextEnvironmentValues(font: font)
      )
      let reference = measuredSize(Text(content), width: width)
      let actual = measuredSize(builder.text, width: width)

      #expect(abs(actual.height - reference.height) < 0.5)
      #expect(abs(actual.width - reference.width) < 0.5)

      // A native Text control also guards colors and mixed bold/italic/custom-font runs.
      let referenceImage = ImageRenderer(content: fitted(Text(content), width: width)).cgImage
      let actualImage = ImageRenderer(content: fitted(builder.text, width: width)).cgImage
      #expect(referenceImage != nil)
      #expect(actualImage != nil)
      #expect(pixelData(actualImage) == pixelData(referenceImage))
    }

    @Test func linkedRunsKeepCustomHitTestingMetadata() {
      let url = URL(string: "https://example.invalid/code")!
      var content = AttributedString("Read this link")
      content[content.range(of: "link")!].link = url
      let builder = TextFragment<AttributedString>.TextBuilder(
        content, environment: TextEnvironmentValues()
      )
      let probe = LayoutProbe()
      let image = ImageRenderer(content: builder.text.textRenderer(ProbeRenderer(probe: probe)))
      #expect(image.cgImage != nil)
      #expect(probe.links == [url])
    }

    @Test func attachmentPlaceholderKeepsSizingAndRunMetadata() {
      var content = AttributedString("\u{FFFC}")
      content.remodex.attachment = AnyAttachment(WidthAttachment())
      let builder = TextFragment<AttributedString>.TextBuilder(
        content, environment: TextEnvironmentValues()
      )
      let initial = LayoutProbe()
      let initialImage = ImageRenderer(
        content: builder.text.textRenderer(ProbeRenderer(probe: initial)))
      #expect(initialImage.cgImage != nil)
      #expect(initial.attachmentWidths.contains { abs($0 - 32) < 0.5 })

      builder.sizeChanged(CGSize(width: 120, height: 800), environment: TextEnvironmentValues())
      let resized = LayoutProbe()
      let resizedImage = ImageRenderer(
        content: builder.text.textRenderer(ProbeRenderer(probe: resized)))
      #expect(resizedImage.cgImage != nil)
      #expect(resized.attachmentWidths.contains { abs($0 - 120) < 0.5 })
    }

    private func fitted(_ text: Text, width: Double) -> some View {
      text.frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
    }

    private func pixelData(_ image: CGImage?) -> Data? {
      image?.dataProvider?.data.map { $0 as Data }
    }

    private func measuredSize(_ text: Text, width: Double) -> CGSize {
      let host = NSHostingController(
        rootView: text.frame(width: width, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      )
      return host.sizeThatFits(in: CGSize(width: width, height: 100_000))
    }
  }

  private final class LayoutProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedLinks: Set<URL> = []
    private var recordedAttachmentWidths: [CGFloat] = []

    var links: Set<URL> { lock.withLock { recordedLinks } }
    var attachmentWidths: [CGFloat] { lock.withLock { recordedAttachmentWidths } }

    func record(_ layout: Text.Layout) {
      lock.withLock {
        for line in layout {
          for run in line {
            if let url = run.url { recordedLinks.insert(url) }
            if run[AttachmentAttribute.self] != nil {
              recordedAttachmentWidths.append(run.typographicBounds.rect.width)
            }
          }
        }
      }
    }
  }

  private struct ProbeRenderer: TextRenderer {
    let probe: LayoutProbe

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
      probe.record(layout)
      for line in layout { context.draw(line) }
    }
  }

  private struct WidthAttachment: RemodexTextKit.Attachment {
    var description: String { "width-aware-test-attachment" }
    var body: some View { Color.red }

    func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
      CGSize(width: proposal.width ?? 32, height: 24)
    }
  }
#endif
