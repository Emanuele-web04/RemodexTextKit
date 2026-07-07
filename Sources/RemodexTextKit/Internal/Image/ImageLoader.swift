import Foundation

// MARK: - Overview
//
// ImageLoader fetches and caches images with task deduplication. When multiple requests for
// the same URL arrive concurrently, they share a single Task rather than creating redundant
// network requests.
//
// The actor ensures thread-safe access to the cache and ongoing tasks dictionary. Each
// request checks the cache first, then ongoing tasks, and only creates a new task if neither
// exists. Tasks are removed from the ongoing dictionary via defer after completion or failure.

actor ImageLoader {
  static let shared = ImageLoader()

  /// The maximum number of bytes buffered for a single image download. Downloads exceeding this
  /// cap throw `URLError(.dataLengthExceedsMaximum)` instead of buffering an unbounded response
  /// body, which would otherwise be an easy memory-exhaustion vector for untrusted markup.
  static let maximumBodyBytes = 50 * 1024 * 1024  // 50 MB

  private let cache: NSCache<NSURL, Box<Image>>
  private let data: (URL) async throws -> (Data, URLResponse)
  private var ongoingTasks: [URL: Task<Image, Error>] = [:]

  init(
    session: URLSession = URLSession(
      configuration: .imageLoading,
      delegate: RedirectPolicy(),
      delegateQueue: nil
    )
  ) {
    self.init(cache: NSCache()) { url in
      let (bytes, response) = try await session.bytes(from: url)

      if response.expectedContentLength > Int64(ImageLoader.maximumBodyBytes) {
        throw URLError(.dataLengthExceedsMaximum)
      }

      var data = Data()
      data.reserveCapacity(
        min(Int(max(response.expectedContentLength, 0)), ImageLoader.maximumBodyBytes))
      for try await byte in bytes {
        data.append(byte)
        if data.count > ImageLoader.maximumBodyBytes {
          throw URLError(.dataLengthExceedsMaximum)
        }
      }

      return (data, response)
    }
  }

  init(
    cache: @autoclosure @Sendable () -> NSCache<NSURL, Box<Image>>,
    data: @escaping (URL) async throws -> (Data, URLResponse)
  ) {
    self.cache = cache()
    self.data = data
  }

  func image(for url: URL) async throws -> Image {
    // Check for a cached image
    if let image = self.cache.object(forKey: url as NSURL) {
      return image.wrappedValue
    }

    // Check for an ongoing task
    if let task = self.ongoingTasks[url] {
      return try await task.value
    }

    // Create a task
    let task = Task<Image, Error> {
      defer {
        // Remove ongoing task
        self.ongoingTasks.removeValue(forKey: url)
      }

      let (data, response) = try await self.data(url)

      // Guard against oversized payloads regardless of how `data` was produced, so the cap is
      // enforced even when this actor is constructed through the `cache:data:` injection seam.
      guard data.count <= Self.maximumBodyBytes else {
        throw URLError(.dataLengthExceedsMaximum)
      }

      // Notice that `data` and `file` URL schemes will not return `HTTPURLResponse`
      if let httpResponse = response as? HTTPURLResponse {
        guard 200..<300 ~= httpResponse.statusCode else {
          throw URLError(.badServerResponse)
        }
      }

      guard let image = Image(data: data) else {
        throw URLError(.cannotDecodeContentData)
      }

      // Cache image
      self.cache.setObject(Box(image), forKey: url as NSURL)

      return image
    }

    // Add ongoing task
    self.ongoingTasks[url] = task

    return try await task.value
  }
}

extension URLSessionConfiguration {
  fileprivate static var imageLoading: URLSessionConfiguration {
    let configuration = Self.default

    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.timeoutIntervalForRequest /= 2
    configuration.httpAdditionalHeaders = ["Accept": "image/*"]

    return configuration
  }
}

/// A session delegate that refuses to follow redirects to non-HTTP(S) schemes.
///
/// `URLAttachmentLoader` only permits `http`/`https` (or an explicitly opted-in scheme) before
/// the initial request is made, but the server can still respond with a redirect to a `file:` or
/// other local-resource URL. This delegate closes that gap by declining any redirect whose
/// destination scheme isn't `http`/`https`; declining delivers the original response instead,
/// which then fails the status-code check above.
private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    guard let scheme = request.url?.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else { return nil }
    return request
  }
}
