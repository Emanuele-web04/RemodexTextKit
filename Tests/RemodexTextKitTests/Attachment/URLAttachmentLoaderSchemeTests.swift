import SwiftUI
import Testing

@testable import RemodexTextKit

@MainActor
struct URLAttachmentLoaderSchemeTests {
  @Test func defaultLoaderRejectsFileScheme() async throws {
    let loader: URLAttachmentLoader<ImageAttachment> = .image()

    await assertThrowsUnsupportedURL(loader: loader, url: URL(string: "file:///etc/hosts")!)
  }

  @Test func defaultLoaderDoesNotRejectHTTPSSchemeUpfront() async {
    let loader: URLAttachmentLoader<ImageAttachment> = .image()

    // Scheme validation happens before any network access, so a refused local connection
    // (fails fast, no real network traffic) is enough to prove the request reached the fetch
    // layer instead of being rejected for its scheme.
    do {
      _ = try await loader.attachment(
        for: URL(string: "https://127.0.0.1:1/a.png")!,
        text: "",
        environment: colorEnvironment
      )
      Issue.record("Expected the fetch to fail once past scheme validation")
    } catch {
      #expect((error as? URLError)?.code != .unsupportedURL)
    }
  }

  @Test func fileBaseURLOptsIntoLocalScheme() async {
    let loader: URLAttachmentLoader<ImageAttachment> = .image(
      relativeTo: URL(string: "file:///bundle/docs/")!
    )

    do {
      _ = try await loader.attachment(
        for: URL(string: "image.png")!,
        text: "",
        environment: colorEnvironment
      )
    } catch {
      #expect((error as? URLError)?.code != .unsupportedURL)
    }
  }

  @Test func explicitAllowedSchemesRestrictsFurther() async {
    let loader: URLAttachmentLoader<ImageAttachment> = .image(allowedSchemes: ["https"])

    await assertThrowsUnsupportedURL(loader: loader, url: URL(string: "http://example.com/a.png")!)
  }

  @Test func emojiLoaderRejectsFileScheme() async {
    let loader: URLAttachmentLoader<EmojiAttachment> = .emoji()

    await assertThrowsUnsupportedURL(loader: loader, url: URL(string: "file:///etc/hosts")!)
  }

  private func assertThrowsUnsupportedURL(
    loader: some AttachmentLoader,
    url: URL
  ) async {
    do {
      _ = try await loader.attachment(for: url, text: "", environment: colorEnvironment)
      Issue.record("Expected URLError(.unsupportedURL) to be thrown")
    } catch {
      #expect((error as? URLError)?.code == .unsupportedURL)
    }
  }

  private var colorEnvironment: ColorEnvironmentValues {
    ColorEnvironmentValues(colorScheme: .light, colorSchemeContrast: .standard)
  }
}
