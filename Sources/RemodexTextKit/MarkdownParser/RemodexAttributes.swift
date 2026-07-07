import SwiftUI

extension AttributeScopes {
  /// Attributes used by RemodexTextKit when parsing and rendering markup.
  public struct RemodexAttributes: AttributeScope {
    /// Stores an attachment value in attributed content.
    public enum AttachmentAttribute: AttributedStringKey {
      public typealias Value = AnyAttachment
      public static let name = "RemodexTextKit.Attachment"
    }

    /// Stores a URL for a custom emoji placeholder.
    ///
    /// RemodexTextKit uses this attribute as an intermediate representation before resolving emoji into
    /// an attachment.
    public enum EmojiURLAttribute: AttributedStringKey {
      public typealias Value = URL
      public static let name = "RemodexTextKit.EmojiURL"
    }

    /// A property for accessing an attachment attribute.
    public let attachment: AttachmentAttribute

    /// A property for accessing an emoji URL attribute.
    public let emojiURL: EmojiURLAttribute

    public let foundation: AttributeScopes.FoundationAttributes
  }

  /// Deprecated alias for ``RemodexAttributes``.
  @available(*, deprecated, renamed: "RemodexAttributes")
  public typealias TextualAttributes = RemodexAttributes

  /// The RemodexTextKit attribute scope.
  public var remodex: RemodexAttributes.Type {
    RemodexAttributes.self
  }

  /// Deprecated alias for ``remodex``.
  @available(*, deprecated, renamed: "remodex")
  public var textual: RemodexAttributes.Type {
    remodex
  }
}

extension AttributeDynamicLookup {
  /// Provides dynamic member lookup for RemodexTextKit attributes.
  public subscript<T: AttributedStringKey>(
    dynamicMember keyPath: KeyPath<AttributeScopes.RemodexAttributes, T>
  ) -> T {
    return self[T.self]
  }
}
