import RemodexTextKit
import SwiftUI

struct AttachmentLoaderDemo: View {
  var body: some View {
    Form {
      Section {
        StructuredText(
          markdown: """
            These images are using an `URLAttachmentLoader` instance
            relative to `https://picsum.photos/seed/textual`:

            ![](400/250)
            ![](300/125)
            """
        )
        .remodex.imageAttachmentLoader(
          .image(relativeTo: URL(string: "https://picsum.photos/seed/textual"))
        )
      }
      Section {
        StructuredText(
          markdown: """
            This image is loaded from the asset catalog:

            ![](sad_dog)

            The same image is used as the `sad_dog` emoji :sad_dog:.
            """,
          syntaxExtensions: [
            .emoji([.init(shortcode: "sad_dog", url: URL(string: "sad_dog")!)])
          ]
        )
        .remodex.imageAttachmentLoader(.image(named: \.lastPathComponent))
        .remodex.emojiAttachmentLoader(.emoji(named: \.lastPathComponent))
      }
    }
    .formStyle(.grouped)
  }
}

#Preview {
  AttachmentLoaderDemo()
}
