import SwiftUI

// MARK: - Overview
//
// `WithAttachments` resolves attachment references in an `AttributedString`.
//
// Markup parsing keeps some items as URL attributes:
// - `run.imageURL` for images
// - `run.remodex.emojiURL` for custom emoji references emitted by pattern expansion
//
// This view asynchronously loads those URLs using the environment-provided attachment loaders and
// writes the resolved attachments back into the attributed string as `RemodexTextKit.Attachment`
// attributes. The rest of the rendering pipeline treats attachment runs like any other span.
//
// Attachments already resolved for a given URL are cached (`attachmentsByURL`) and are re-applied
// synchronously the moment a new `AttributedString` arrives, before the async fan-out for any new
// URLs completes. This prevents already-loaded images/emoji from flashing back to their unresolved
// placeholders on every content change (e.g. streaming token appends).
//
// Documents without image or emoji URLs, decided once per parse, render their content directly:
// no resolution task runs and a resolution left over from earlier content is never shown.

struct WithAttachments<Content: View>: View {
  @Environment(\.imageAttachmentLoader) private var imageAttachmentLoader
  @Environment(\.emojiAttachmentLoader) private var emojiAttachmentLoader
  @Environment(\.colorEnvironment) private var colorEnvironment

  @State private var model = Model()

  private let document: ParsedDocument
  private let content: (AttributedString) -> Content

  init(
    _ document: ParsedDocument,
    @ViewBuilder content: @escaping (AttributedString) -> Content
  ) {
    self.document = document
    self.content = content
  }

  var body: some View {
    let attributedString = document.value

    content(
      document.referencesAttachments
        ? model.resolved(attributedString) : attributedString
    )
    // In a background so the content keeps its identity when the document gains or loses
    // attachment references.
    .background {
      if document.referencesAttachments {
        Color.clear
          .task(id: attributedString) {
            await model.resolveAttachments(
              in: attributedString,
              imageAttachmentLoader: imageAttachmentLoader,
              emojiAttachmentLoader: emojiAttachmentLoader,
              environment: colorEnvironment
            )
          }
      }
    }
  }
}

extension WithAttachments {
  @MainActor @Observable final class Model {
    var resolvedAttributedString: AttributedString?

    /// The content `resolvedAttributedString` was resolved from.
    private var resolvedSource: AttributedString?

    /// Attachments resolved so far, keyed by the source URL they were resolved from. Used to
    /// carry already-resolved attachments across content changes without waiting on the async
    /// fan-out to complete again.
    private var attachmentsByURL: [URL: AnyAttachment] = [:]

    /// Bumped on every call so a stale async completion (from a superseded `attributedString`)
    /// can detect it's no longer current and avoid publishing over newer results.
    private var generation = 0

    func resolveAttachments(
      in attributedString: AttributedString,
      imageAttachmentLoader: any AttachmentLoader,
      emojiAttachmentLoader: any AttachmentLoader,
      environment: ColorEnvironmentValues
    ) async {
      generation += 1
      let currentGeneration = generation

      guard let partiallyResolved = partiallyResolved(attributedString) else {
        resolvedAttributedString = nil
        resolvedSource = nil
        attachmentsByURL = [:]
        return
      }

      resolvedAttributedString = partiallyResolved
      resolvedSource = attributedString

      var resolvedAttachments: [(Range<AttributedString.Index>, URL, AnyAttachment)] = []

      await withTaskGroup(
        of: (Range<AttributedString.Index>, URL, AnyAttachment?).self
      ) { group in
        for run in attributedString.runs {
          if let imageURL = run.imageURL {
            group.addTask {
              let attachment = try? await imageAttachmentLoader.attachment(
                for: imageURL,
                text: String(attributedString[run.range].characters[...]),
                environment: environment
              )
              return (run.range, imageURL, attachment.map(AnyAttachment.init))
            }
          } else if let emojiURL = run.remodex.emojiURL {
            group.addTask {
              let attachment = try? await emojiAttachmentLoader.attachment(
                for: emojiURL,
                text: String(attributedString[run.range].characters[...]),
                environment: environment
              )
              return (run.range, emojiURL, attachment.map(AnyAttachment.init))
            }
          }
        }

        for await (range, url, attachment) in group {
          guard let attachment else { continue }
          resolvedAttachments.append((range, url, attachment))
        }
      }

      guard generation == currentGeneration else {
        return
      }

      if !resolvedAttachments.isEmpty {
        resolveAttachmentsFinished(
          attributedString: attributedString,
          attachments: resolvedAttachments
        )
      } else {
        // No new attachments resolved this pass (every fetch failed, or there were no
        // attachment URLs left to resolve). Still prune the cache against the current content
        // so URLs no longer present don't survive indefinitely — this only trims
        // `attachmentsByURL`, it never touches `resolvedAttributedString`.
        pruneAttachmentsByURL(against: attributedString)
      }
    }

    /// The best rendering available now for `attributedString`: the resolution made for this
    /// content, or else the attachments already cached by URL applied synchronously.
    func resolved(_ attributedString: AttributedString) -> AttributedString {
      if let resolvedAttributedString, resolvedSource == attributedString {
        return resolvedAttributedString
      }
      return partiallyResolved(attributedString) ?? attributedString
    }

    /// Synchronously applies any already-cached attachments (matched by URL) to `attributedString`,
    /// so previously resolved images/emoji don't flash back to placeholders while the async
    /// fan-out for any new URLs is in flight. Returns `nil` when the string has no image/emoji
    /// attachment URL runs at all, signaling the caller to clear any previously resolved state.
    internal func partiallyResolved(_ attributedString: AttributedString) -> AttributedString? {
      var result = attributedString
      var hasAttachmentURLRun = false

      for run in attributedString.runs {
        if let imageURL = run.imageURL {
          hasAttachmentURLRun = true
          if let attachment = attachmentsByURL[imageURL] {
            result[run.range].remodex.attachment = attachment
          }
        } else if let emojiURL = run.remodex.emojiURL {
          hasAttachmentURLRun = true
          if let attachment = attachmentsByURL[emojiURL] {
            result[run.range].remodex.attachment = attachment
          }
        }
      }

      return hasAttachmentURLRun ? result : nil
    }

    private func resolveAttachmentsFinished(
      attributedString: AttributedString,
      attachments: [(Range<AttributedString.Index>, URL, AnyAttachment)]
    ) {
      var attributedString = attributedString

      let source = attributedString
      for (range, url, attachment) in attachments {
        attributedString[range].remodex.attachment = attachment
        attachmentsByURL[url] = attachment
      }

      self.resolvedAttributedString = attributedString
      self.resolvedSource = source

      pruneAttachmentsByURL(against: attributedString)
    }

    private func pruneAttachmentsByURL(against attributedString: AttributedString) {
      var urlsInString: Set<URL> = []

      for run in attributedString.runs {
        if let imageURL = run.imageURL {
          urlsInString.insert(imageURL)
        } else if let emojiURL = run.remodex.emojiURL {
          urlsInString.insert(emojiURL)
        }
      }

      attachmentsByURL = attachmentsByURL.filter { urlsInString.contains($0.key) }
    }
  }
}
