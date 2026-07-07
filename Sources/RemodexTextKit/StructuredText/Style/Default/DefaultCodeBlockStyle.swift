// FILE: DefaultCodeBlockStyle.swift
// Purpose: Default code block visual style. Renders a rounded code card with a
//          compact header that exposes per-block Wrap and Copy actions.
// Layer: StructuredText / Style
// Exports: StructuredText.DefaultCodeBlockStyle
// Depends on: SwiftUI, Overflow, OverflowFrameKey, DynamicColor, StructuredText.CodeBlockProxy

import Foundation
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Public style

extension StructuredText {
  /// The default code block style used by ``StructuredText/DefaultStyle``.
  ///
  /// Renders a soft rounded card with a compact header. The header shows the
  /// language hint on the leading edge and two trailing actions:
  ///
  /// - A wrap toggle that switches the block between horizontal scrolling and word wrapping.
  ///   This overrides the ambient ``OverflowMode`` set with
  ///   ``TextualNamespace/overflowMode(_:)`` for the lifetime of the block.
  /// - A copy button that writes the block contents to the system pasteboard.
  public struct DefaultCodeBlockStyle: CodeBlockStyle {
    /// A code-block action icon.
    ///
    /// Use `.asset("copy")` for Remodex-style bundled template artwork, `.systemName(...)` for
    /// SF Symbols, or `.custom { ... }` when the host app has its own icon resolver.
    public struct ActionIcon {
      private let makeBody: () -> AnyView

      private init(makeBody: @escaping () -> AnyView) {
        self.makeBody = makeBody
      }

      /// Creates an icon from an SF Symbol name.
      public static func systemName(_ systemName: String) -> Self {
        .init {
          AnyView(SwiftUI.Image(systemName: systemName))
        }
      }

      /// Creates an icon from a bundled image asset.
      ///
      /// The asset is rendered as a resizable template image, matching Remodex's `Image("copy")`
      /// treatment for its Central copy glyph.
      public static func asset(_ name: String, bundle: Bundle? = nil) -> Self {
        .init {
          AnyView(
            SwiftUI.Image(name, bundle: bundle)
              .renderingMode(.template)
              .resizable()
              .scaledToFit()
          )
        }
      }

      /// Creates an icon from a custom view.
      public static func custom<Icon: View>(@ViewBuilder _ body: @escaping () -> Icon) -> Self {
        .init {
          AnyView(body())
        }
      }

      fileprivate func view() -> AnyView {
        makeBody()
      }
    }

    /// Optional icon views used by the default code block actions.
    ///
    /// Leave any value `nil` to use RemodexTextKit's built-in SF Symbol fallback for that state.
    public struct ActionIcons {
      let wrap: ActionIcon?
      let unwrap: ActionIcon?
      let copy: ActionIcon?
      let copied: ActionIcon?

      /// Creates a set of optional code-block action icons.
      ///
      /// - Parameters:
      ///   - wrap: Icon shown when tapping will enable wrapping.
      ///   - unwrap: Icon shown when tapping will return to horizontal scrolling.
      ///   - copy: Icon shown before the code block has been copied.
      ///   - copied: Icon shown during copied feedback.
      public init(
        wrap: ActionIcon? = nil,
        unwrap: ActionIcon? = nil,
        copy: ActionIcon? = nil,
        copied: ActionIcon? = nil
      ) {
        self.wrap = wrap
        self.unwrap = unwrap
        self.copy = copy
        self.copied = copied
      }
    }

    private let actionIcons: ActionIcons

    /// Creates the default code block style.
    ///
    /// - Parameter actionIcons: Optional custom icons for the wrap/copy controls. Missing icons
    ///   fall back to RemodexTextKit's built-in SF Symbols.
    public init(actionIcons: ActionIcons = .init()) {
      self.actionIcons = actionIcons
    }

    public func makeBody(configuration: Configuration) -> some View {
      DefaultCodeBlockBody(configuration: configuration, actionIcons: actionIcons)
    }
  }
}

extension StructuredText.CodeBlockStyle where Self == StructuredText.DefaultCodeBlockStyle {
  /// The default code block style.
  public static var `default`: Self { .init() }

  /// The default code block style with custom action icons.
  public static func `default`(
    actionIcons: StructuredText.DefaultCodeBlockStyle.ActionIcons
  ) -> Self {
    .init(actionIcons: actionIcons)
  }
}

// MARK: - Body

// Owns the wrap-toggle state and composes the header with the existing `Overflow` content tree.
private struct DefaultCodeBlockBody: View {
  let configuration: StructuredText.CodeBlockStyleConfiguration
  let actionIcons: StructuredText.DefaultCodeBlockStyle.ActionIcons

  @Environment(\.overflowMode) private var environmentOverflowMode
  @State private var wrapOverride: Bool?

  // Locally-toggled wrap mode wins over the env value the call site provided.
  private var effectiveOverflowMode: OverflowMode {
    if let wrapOverride { return wrapOverride ? .wrap : .scroll }
    return environmentOverflowMode
  }

  // Matches Remodex's project-section expand/collapse cadence in the sidebar.
  private static let wrapAnimation: Animation = .snappy(duration: 0.22)
  private static let cornerRadius: CGFloat = 20

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DefaultCodeBlockHeader(
        languageHint: configuration.languageHint,
        isWrapping: effectiveOverflowMode == .wrap,
        toggleWrap: {
          let next = !(effectiveOverflowMode == .wrap)
          withAnimation(Self.wrapAnimation) {
            wrapOverride = next
          }
        },
        codeBlock: configuration.codeBlock,
        actionIcons: actionIcons
      )

      Overflow {
        configuration.label
          .textual.lineSpacing(.fontScaled(0.39))
          .textual.fontScale(0.882)
          .fixedSize(horizontal: false, vertical: true)
          .monospaced()
          .padding(.vertical, 10)
          .padding(.horizontal, 14)
      }
      .environment(\.overflowMode, effectiveOverflowMode)
    }
    .clipped()
    .background(
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(.regularMaterial)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .stroke(DynamicColor.grid, lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    .textual.blockSpacing(.fontScaled(top: 0.88, bottom: 0))
  }
}

// MARK: - Header

// Compact header showing the language label + Wrap / Copy actions.
//
// The header publishes its own frame to `OverflowFrameKey` so RemodexTextKit's selection overlay
// excludes the button area from hit testing; without this the overlay swallows taps and the
// buttons appear inert.
private struct DefaultCodeBlockHeader: View {
  let languageHint: String?
  let isWrapping: Bool
  let toggleWrap: () -> Void
  let codeBlock: StructuredText.CodeBlockProxy
  let actionIcons: StructuredText.DefaultCodeBlockStyle.ActionIcons

  var body: some View {
    HStack(spacing: 8) {
      Text(displayName)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 8)

      HStack(spacing: 4) {
        WrapButton(isWrapping: isWrapping, actionIcons: actionIcons, action: toggleWrap)

        #if !os(tvOS) && !os(watchOS)
          CopyButton(codeBlock: codeBlock, actionIcons: actionIcons)
        #endif
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .background(
      // Excludes the header area from RemodexTextKit's selection hit-testing overlay so taps reach
      // the buttons. Same mechanism `Overflow` uses for scrollable code regions.
      GeometryReader { geometry in
        Color.clear
          .preference(
            key: OverflowFrameKey.self,
            value: [geometry.frame(in: .textContainer)]
          )
      }
    )
  }

  // MARK: Display name

  private var displayName: String {
    guard
      let hint = languageHint?.trimmingCharacters(in: .whitespacesAndNewlines),
      !hint.isEmpty
    else { return "Code" }
    return Self.languageDisplayNames[hint.lowercased()] ?? hint.capitalized
  }

  // Pretty names for common language hints. Anything not listed falls back to `.capitalized`.
  private static let languageDisplayNames: [String: String] = [
    "bash": "Shell",
    "c": "C",
    "c++": "C++",
    "cpp": "C++",
    "cs": "C#",
    "csharp": "C#",
    "css": "CSS",
    "diff": "Diff",
    "dockerfile": "Dockerfile",
    "fish": "Shell",
    "go": "Go",
    "haskell": "Haskell",
    "hs": "Haskell",
    "html": "HTML",
    "java": "Java",
    "javascript": "JavaScript",
    "js": "JavaScript",
    "json": "JSON",
    "jsx": "JSX",
    "kotlin": "Kotlin",
    "kt": "Kotlin",
    "lua": "Lua",
    "makefile": "Makefile",
    "markdown": "Markdown",
    "md": "Markdown",
    "objc": "Objective-C",
    "objective-c": "Objective-C",
    "objectivec": "Objective-C",
    "php": "PHP",
    "py": "Python",
    "python": "Python",
    "rb": "Ruby",
    "ruby": "Ruby",
    "rs": "Rust",
    "rust": "Rust",
    "scss": "SCSS",
    "sh": "Shell",
    "shell": "Shell",
    "sql": "SQL",
    "swift": "Swift",
    "toml": "TOML",
    "ts": "TypeScript",
    "tsx": "TSX",
    "typescript": "TypeScript",
    "xml": "XML",
    "yaml": "YAML",
    "yml": "YAML",
    "zsh": "Shell",
  ]
}

// MARK: - Wrap button

private struct WrapButton: View {
  let isWrapping: Bool
  let actionIcons: StructuredText.DefaultCodeBlockStyle.ActionIcons
  let action: () -> Void

  var body: some View {
    Button {
      triggerHaptic()
      action()
    } label: {
      icon
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(minWidth: 28, minHeight: 28)
        .contentShape(Rectangle())
        .contentTransition(.symbolEffect(.replace))
        .animation(.easeOut(duration: 0.15), value: isWrapping)
    }
    .buttonStyle(.plain)
    .help(isWrapping ? "Disable word wrap" : "Enable word wrap")
    .accessibilityLabel(isWrapping ? "Disable word wrap" : "Enable word wrap")
  }

  @ViewBuilder
  private var icon: some View {
    if isWrapping, let unwrap = actionIcons.unwrap {
      unwrap.view()
    } else if !isWrapping, let wrap = actionIcons.wrap {
      wrap.view()
    } else {
      SwiftUI.Image(systemName: isWrapping ? "arrow.left.and.right" : "text.alignleft")
    }
  }
}

// MARK: - Copy button

#if !os(tvOS) && !os(watchOS)
  // Compact copy affordance with an inline "Copied" feedback chip, mirroring the look used in
  // Remodex's `CopyBlockButton` (icon + secondary-foreground label, 1.5s reset).
  private struct CopyButton: View {
    let codeBlock: StructuredText.CodeBlockProxy
    let actionIcons: StructuredText.DefaultCodeBlockStyle.ActionIcons

    @State private var didCopy = false

    var body: some View {
      Button(action: copy) {
        HStack(spacing: 4) {
          icon
            .font(.system(size: 12, weight: .medium))
            .frame(width: 16, height: 16)

          if didCopy {
            Text("Copied")
              .font(.system(size: 11, weight: .medium))
              .transition(.opacity)
          }
        }
        .foregroundStyle(.secondary)
        .frame(minHeight: 28)
        .padding(.horizontal, didCopy ? 6 : 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .animation(.easeInOut(duration: 0.18), value: didCopy)
      .help(didCopy ? "Copied" : "Copy code")
      .accessibilityLabel(didCopy ? "Copied" : "Copy code")
    }

    private func copy() {
      triggerHaptic()
      codeBlock.copyToPasteboard()
      withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
      Task { @MainActor in
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation(.easeInOut(duration: 0.15)) { didCopy = false }
      }
    }

    @ViewBuilder
    private var icon: some View {
      if didCopy, let copied = actionIcons.copied {
        copied.view()
      } else if !didCopy, let copy = actionIcons.copy {
        copy.view()
      } else {
        SwiftUI.Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
      }
    }
  }
#endif

// MARK: - Haptic

@MainActor
private func triggerHaptic() {
  #if os(iOS)
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  #endif
}

// MARK: - Preview

@available(tvOS, unavailable)
@available(watchOS, unavailable)
#Preview {
  ScrollView {
    StructuredText(
      markdown: """
        The sky above the port was the color of television, tuned to a dead channel.

        ```swift
        struct Sightseeing: Activity {
            func perform(with sloth: inout Sloth) -> Speed {
                sloth.energyLevel -= 10
                return .slow
            }
        }
        ```

        It was a bright cold day in April, and the clocks were striking thirteen.

        ```bash
        $ swift test --filter appFlowDiagnosticProvesCommercialStoryBreakFinaleHandoff
        Building for debugging...
        [0/5] Write sources
        [1/5] Write swift-version--6CDFA230AE1E.txt
        ```
        """
    )
    .padding()
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .textual.textSelection(.enabled)
    .textual.overflowMode(.wrap)
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
}
