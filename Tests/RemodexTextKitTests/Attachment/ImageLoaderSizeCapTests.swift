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
