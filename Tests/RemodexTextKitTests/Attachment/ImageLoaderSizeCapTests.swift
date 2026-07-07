import Foundation
import Testing

@testable import RemodexTextKit

struct ImageLoaderSizeCapTests {
  @Test func oversizedPayloadIsRejected() async {
    let url = URL(string: "https://example.com/huge.png")!
    let oversizedData = Data(count: ImageLoader.maximumBodyBytes + 1)

    let loader = ImageLoader(cache: NSCache()) { _ in
      (oversizedData, URLResponse())
    }

    do {
      _ = try await loader.image(for: url)
      Issue.record("Expected URLError(.dataLengthExceedsMaximum) to be thrown")
    } catch {
      #expect((error as? URLError)?.code == .dataLengthExceedsMaximum)
    }
  }
}

struct RedirectPolicyTests {
  @Test func allowsHTTPToHTTPS() {
    #expect(
      RedirectPolicy.allowsRedirect(
        from: URL(string: "http://example.com/a.png"),
        to: URL(string: "https://example.com/a.png")
      )
    )
  }

  @Test func allowsHTTPToHTTP() {
    #expect(
      RedirectPolicy.allowsRedirect(
        from: URL(string: "http://example.com/a.png"),
        to: URL(string: "http://example.com/b.png")
      )
    )
  }

  @Test func allowsHTTPSToHTTPS() {
    #expect(
      RedirectPolicy.allowsRedirect(
        from: URL(string: "https://example.com/a.png"),
        to: URL(string: "https://example.com/b.png")
      )
    )
  }

  @Test func rejectsHTTPSDowngradeToHTTP() {
    #expect(
      !RedirectPolicy.allowsRedirect(
        from: URL(string: "https://example.com/a.png"),
        to: URL(string: "http://example.com/a.png")
      )
    )
  }

  @Test func rejectsNonHTTPDestinationScheme() {
    #expect(
      !RedirectPolicy.allowsRedirect(
        from: URL(string: "https://example.com/a.png"),
        to: URL(string: "file:///etc/hosts")
      )
    )
    #expect(
      !RedirectPolicy.allowsRedirect(
        from: URL(string: "http://example.com/a.png"),
        to: URL(string: "file:///etc/hosts")
      )
    )
  }
}
