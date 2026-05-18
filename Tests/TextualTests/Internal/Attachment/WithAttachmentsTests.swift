import SwiftUI
import Testing

@testable import Textual

@MainActor
struct WithAttachmentsTests {
  @Test func resolvingPlainTextClearsPreviousAttachments() async {
    let model = WithAttachments<EmptyView>.Model()
    let loader = TestAttachmentLoader()

    await model.resolveAttachments(
      in: attributedStringWithImage(),
      imageAttachmentLoader: loader,
      emojiAttachmentLoader: loader,
      environment: colorEnvironment
    )

    #expect(model.resolvedAttributedString?.hasAttachments() == true)

    await model.resolveAttachments(
      in: AttributedString("plain"),
      imageAttachmentLoader: loader,
      emojiAttachmentLoader: loader,
      environment: colorEnvironment
    )

    #expect(model.resolvedAttributedString == nil)
  }

  private func attributedStringWithImage() -> AttributedString {
    var attributedString = AttributedString("alt")
    attributedString[attributedString.startIndex..<attributedString.endIndex].imageURL =
      URL(string: "asset://image")!
    return attributedString
  }

  private var colorEnvironment: ColorEnvironmentValues {
    ColorEnvironmentValues(colorScheme: .light, colorSchemeContrast: .standard)
  }
}

private struct TestAttachment: Textual.Attachment {
  let id: String

  var description: String { id }

  var body: some View {
    EmptyView()
  }

  func sizeThatFits(_: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
    .zero
  }
}

private struct TestAttachmentLoader: AttachmentLoader {
  func attachment(
    for url: URL,
    text: String,
    environment _: ColorEnvironmentValues
  ) async throws -> TestAttachment {
    TestAttachment(id: "\(text):\(url.absoluteString)")
  }
}
