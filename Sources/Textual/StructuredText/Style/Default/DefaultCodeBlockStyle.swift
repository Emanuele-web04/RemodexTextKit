// FILE: DefaultCodeBlockStyle.swift
// Purpose: Default code block visual style. Renders a rounded GitHub-ish card with a
//          compact header that exposes per-block Wrap and Copy actions.
// Layer: StructuredText / Style
// Exports: StructuredText.DefaultCodeBlockStyle
// Depends on: SwiftUI, Overflow, OverflowFrameKey, DynamicColor, StructuredText.CodeBlockProxy

import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

// MARK: - Public style

extension StructuredText {
  /// The default code block style used by ``StructuredText/DefaultStyle``.
  ///
  /// Renders a soft, GitHub-flavored rounded card with a compact header. The header shows the
  /// language hint on the leading edge and two trailing actions:
  ///
  /// - A wrap toggle that switches the block between horizontal scrolling and word wrapping.
  ///   This overrides the ambient ``OverflowMode`` set with
  ///   ``TextualNamespace/overflowMode(_:)`` for the lifetime of the block.
  /// - A copy button that writes the block contents to the system pasteboard.
  public struct DefaultCodeBlockStyle: CodeBlockStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
      DefaultCodeBlockBody(configuration: configuration)
    }
  }
}

extension StructuredText.CodeBlockStyle where Self == StructuredText.DefaultCodeBlockStyle {
  /// The default code block style.
  public static var `default`: Self { .init() }
}

// MARK: - Body

// Owns the wrap-toggle state and composes the header with the existing `Overflow` content tree.
private struct DefaultCodeBlockBody: View {
  let configuration: StructuredText.CodeBlockStyleConfiguration

  @Environment(\.overflowMode) private var environmentOverflowMode
  @State private var wrapOverride: Bool?

  // Locally-toggled wrap mode wins over the env value the call site provided.
  private var effectiveOverflowMode: OverflowMode {
    if let wrapOverride { return wrapOverride ? .wrap : .scroll }
    return environmentOverflowMode
  }

  // Keep layout changes non-animated. Animating the code block's real height lets parents (and
  // Xcode previews) interpolate the whole `StructuredText` from its center. Remodex only animates
  // chrome affordances here; the layout itself snaps and stays top-anchored.
  private static let cornerRadius: CGFloat = 14

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      DefaultCodeBlockHeader(
        languageHint: configuration.languageHint,
        isWrapping: effectiveOverflowMode == .wrap,
        toggleWrap: {
          let next = !(effectiveOverflowMode == .wrap)
          var transaction = Transaction()
          transaction.animation = nil
          withTransaction(transaction) {
            wrapOverride = next
          }
        },
        codeBlock: configuration.codeBlock
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
      .transaction { transaction in
        transaction.animation = nil
      }
    }
    .background(
      RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        .fill(configuration.highlighterTheme.backgroundColor)
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
// The header publishes its own frame to `OverflowFrameKey` so Textual's selection overlay
// excludes the button area from hit testing; without this the overlay swallows taps and the
// buttons appear inert.
private struct DefaultCodeBlockHeader: View {
  let languageHint: String?
  let isWrapping: Bool
  let toggleWrap: () -> Void
  let codeBlock: StructuredText.CodeBlockProxy

  var body: some View {
    HStack(spacing: 8) {
      Text(displayName)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 8)

      HStack(spacing: 4) {
        WrapButton(isWrapping: isWrapping, action: toggleWrap)

        #if !os(tvOS) && !os(watchOS)
          CopyButton(codeBlock: codeBlock)
        #endif
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 6)
    .background(
      // Excludes the header area from Textual's selection hit-testing overlay so taps reach
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
  let action: () -> Void

  var body: some View {
    Button {
      triggerHaptic()
      action()
    } label: {
      SwiftUI.Image(systemName: isWrapping ? "arrow.left.and.right" : "text.alignleft")
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
}

// MARK: - Copy button

#if !os(tvOS) && !os(watchOS)
  // Compact copy affordance with an inline "Copied" feedback chip, mirroring the look used in
  // Remodex's `CopyBlockButton` (icon + secondary-foreground label, 1.5s reset).
  private struct CopyButton: View {
    let codeBlock: StructuredText.CodeBlockProxy

    @State private var didCopy = false

    var body: some View {
      Button(action: copy) {
        HStack(spacing: 4) {
          SwiftUI.Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
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
