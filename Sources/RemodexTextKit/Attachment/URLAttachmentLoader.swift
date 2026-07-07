import SwiftUI

/// An attachment loader that fetches images from URLs.
///
/// `URLAttachmentLoader` resolves URLs relative to an optional base URL, loads the image, and
/// builds an attachment value from it.
///
/// You can’t create `URLAttachmentLoader` directly. Use ``AttachmentLoader/image(relativeTo:)``
/// and ``AttachmentLoader/emoji(relativeTo:)`` instead.
public struct URLAttachmentLoader<Content: Attachment>: AttachmentLoader {
  private let baseURL: URL?
  private let allowedSchemes: Set<String>
  private let content: @Sendable (Image, String) -> Content

  fileprivate init(
    baseURL: URL?,
    allowedSchemes: Set<String>,
    content: @Sendable @escaping (Image, String) -> Content
  ) {
    self.baseURL = baseURL
    self.allowedSchemes = allowedSchemes
    self.content = content
  }

  public func attachment(
    for url: URL,
    text: String,
    environment: ColorEnvironmentValues
  ) async throws -> some Attachment {
    let imageURL = URL(string: url.absoluteString, relativeTo: baseURL) ?? url

    let scheme = imageURL.scheme?.lowercased() ?? ""
    guard allowedSchemes.contains(scheme) else {
      throw URLError(.unsupportedURL)
    }

    let image = try await ImageLoader.shared.image(for: imageURL)

    return content(image, text)
  }
}

extension AttachmentLoader where Self == URLAttachmentLoader<ImageAttachment> {
  /// Loads images referenced by URLs.
  ///
  /// - Parameters:
  ///   - baseURL: The base URL used to resolve relative URLs.
  ///   - allowedSchemes: The URL schemes this loader is permitted to fetch. Defaults to
  ///     `http`/`https` only, because markup is often untrusted (AI output, user messages,
  ///     remote READMEs) and must not be able to reach local resources via `file:` or similar
  ///     schemes. The scheme of `baseURL`, if provided, is always added to this set — supplying
  ///     a `file:` base URL is an explicit signal that local loads are intended.
  public static func image(
    relativeTo baseURL: URL? = nil,
    allowedSchemes: Set<String> = ["http", "https"]
  ) -> Self {
    var schemes = Set(allowedSchemes.map { $0.lowercased() })
    if let baseScheme = baseURL?.scheme?.lowercased() {
      schemes.insert(baseScheme)
    }
    return .init(
      baseURL: baseURL, allowedSchemes: schemes, content: ImageAttachment.init(image:text:))
  }
}

extension AttachmentLoader where Self == URLAttachmentLoader<EmojiAttachment> {
  /// Loads custom emoji referenced by URL.
  ///
  /// - Parameters:
  ///   - baseURL: The base URL used to resolve relative URLs.
  ///   - allowedSchemes: The URL schemes this loader is permitted to fetch. Defaults to
  ///     `http`/`https` only, because markup is often untrusted (AI output, user messages,
  ///     remote READMEs) and must not be able to reach local resources via `file:` or similar
  ///     schemes. The scheme of `baseURL`, if provided, is always added to this set — supplying
  ///     a `file:` base URL is an explicit signal that local loads are intended.
  public static func emoji(
    relativeTo baseURL: URL? = nil,
    allowedSchemes: Set<String> = ["http", "https"]
  ) -> Self {
    var schemes = Set(allowedSchemes.map { $0.lowercased() })
    if let baseScheme = baseURL?.scheme?.lowercased() {
      schemes.insert(baseScheme)
    }
    return .init(
      baseURL: baseURL, allowedSchemes: schemes, content: EmojiAttachment.init(image:text:))
  }
}
