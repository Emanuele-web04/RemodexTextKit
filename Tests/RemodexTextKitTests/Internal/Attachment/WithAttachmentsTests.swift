import SwiftUI
import Testing

@testable import RemodexTextKit

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

  @Test func partiallyResolvedCarriesOverAlreadyResolvedAttachments() async {
    let model = WithAttachments<EmptyView>.Model()
    let loader = TestAttachmentLoader()

    await model.resolveAttachments(
      in: attributedStringWithImage(),
      imageAttachmentLoader: loader,
      emojiAttachmentLoader: loader,
      environment: colorEnvironment
    )

    #expect(model.resolvedAttributedString?.hasAttachments() == true)

    // A longer string that re-uses the same attachment URL (e.g. a streaming token append)
    // should have its attachment carried over synchronously, before any async resolution.
    var longerString = AttributedString("alt")
    longerString[longerString.startIndex..<longerString.endIndex].imageURL =
      URL(string: "asset://image")!
    longerString.append(AttributedString(" more text"))

    let partiallyResolved = model.partiallyResolved(longerString)

    #expect(partiallyResolved?.hasAttachments() == true)
  }

  @Test func staleResolutionDoesNotOverwriteNewerResult() async {
    let model = WithAttachments<EmptyView>.Model()
    let loader = DelayedAttachmentLoader()

    let slowString = attributedString(text: "slow", url: URL(string: "asset://slow")!)
    let fastString = attributedString(text: "fast", url: URL(string: "asset://fast")!)

    async let slow: Void = model.resolveAttachments(
      in: slowString,
      imageAttachmentLoader: loader,
      emojiAttachmentLoader: loader,
      environment: colorEnvironment
    )

    // Let the first call's task group start (and suspend on the delayed load) before starting
    // the second call.
    await Task.yield()

    await model.resolveAttachments(
      in: fastString,
      imageAttachmentLoader: loader,
      emojiAttachmentLoader: loader,
      environment: colorEnvironment
    )

    _ = await slow

    #expect(model.resolvedAttributedString.map { String($0.characters) } == "fast")
  }

  @Test func pruningRunsEvenWhenResolutionPassYieldsNoSuccesses() async {
    let model = WithAttachments<EmptyView>.Model()
    let successLoader = TestAttachmentLoader()
    let failingLoader = FailingAttachmentLoader()

    let cachedURL = URL(string: "asset://image")!
    await model.resolveAttachments(
      in: attributedString(text: "alt", url: cachedURL),
      imageAttachmentLoader: successLoader,
      emojiAttachmentLoader: successLoader,
      environment: colorEnvironment
    )

    #expect(model.resolvedAttributedString?.hasAttachments() == true)

    // A second resolve pass for unrelated content whose only URL always fails to load. Every
    // fetch in this pass fails, so `resolvedAttachments` is empty and
    // `resolveAttachmentsFinished` never runs — the cache must still be pruned against this
    // content.
    let otherURL = URL(string: "asset://other")!
    await model.resolveAttachments(
      in: attributedString(text: "other", url: otherURL),
      imageAttachmentLoader: failingLoader,
      emojiAttachmentLoader: failingLoader,
      environment: colorEnvironment
    )

    // The cached URL is no longer present in any resolved content, so it should have been
    // pruned. Proving this through the internal seam: re-presenting a string containing the
    // originally cached URL should no longer synchronously carry over the attachment.
    let partiallyResolved = model.partiallyResolved(attributedString(text: "alt", url: cachedURL))

    #expect(partiallyResolved?.hasAttachments() == false)
  }

  private func attributedStringWithImage() -> AttributedString {
    attributedString(text: "alt", url: URL(string: "asset://image")!)
  }

  private func attributedString(text: String, url: URL) -> AttributedString {
    var attributedString = AttributedString(text)
    attributedString[attributedString.startIndex..<attributedString.endIndex].imageURL = url
    return attributedString
  }

  private var colorEnvironment: ColorEnvironmentValues {
    ColorEnvironmentValues(colorScheme: .light, colorSchemeContrast: .standard)
  }
}

private struct TestAttachment: RemodexTextKit.Attachment {
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

private struct FailingLoaderError: Error {}

private struct FailingAttachmentLoader: AttachmentLoader {
  func attachment(
    for url: URL,
    text: String,
    environment _: ColorEnvironmentValues
  ) async throws -> TestAttachment {
    throw FailingLoaderError()
  }
}

private struct DelayedAttachmentLoader: AttachmentLoader {
  func attachment(
    for url: URL,
    text: String,
    environment _: ColorEnvironmentValues
  ) async throws -> TestAttachment {
    if url.absoluteString.contains("slow") {
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return TestAttachment(id: "\(text):\(url.absoluteString)")
  }
}
