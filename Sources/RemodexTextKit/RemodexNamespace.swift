import Foundation

/// A namespace for RemodexTextKit-specific extensions.
///
/// Use `RemodexNamespace` as a customization point for constrained extensions. By placing
/// modifiers and helpers under `.remodex`, RemodexTextKit avoids adding lots of methods directly to
/// `View` and other widely used types.
///
/// The general pattern is:
///
/// ```swift
/// // Add APIs under `.remodex` for a specific kind of base.
/// extension RemodexNamespace where Base: View {
///   func myModifier() -> some View { ... }
/// }
/// ```
///
/// SwiftUI views get the namespace through the ``SwiftUICore/View/remodex`` property.
/// Other types can opt into it by conforming to ``RemodexCompatible``.
public struct RemodexNamespace<Base> {
  @usableFromInline let base: Base
  @inlinable public init(_ base: Base) { self.base = base }
}

extension RemodexNamespace: Sendable where Base: Sendable {}

/// A type that opts into the `.remodex` namespace.
///
/// Types that conform to `RemodexCompatible` gain `remodex` helpers on both the instance and the
/// type.
public protocol RemodexCompatible {}

extension RemodexCompatible {
  /// The `RemodexNamespace` type for this conforming type.
  @inlinable public static var remodex: RemodexNamespace<Self>.Type {
    RemodexNamespace<Self>.self
  }

  /// A `RemodexNamespace` wrapper around this instance.
  @inlinable public var remodex: RemodexNamespace<Self> { .init(self) }
}

/// Deprecated alias for ``RemodexNamespace``.
@available(*, deprecated, renamed: "RemodexNamespace")
public typealias TextualNamespace<Base> = RemodexNamespace<Base>

/// Deprecated alias for ``RemodexCompatible``.
@available(*, deprecated, renamed: "RemodexCompatible")
public typealias TextualCompatible = RemodexCompatible
