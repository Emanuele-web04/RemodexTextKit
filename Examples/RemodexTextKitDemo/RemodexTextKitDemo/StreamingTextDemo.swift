import RemodexTextKit
import SwiftUI

struct StreamingTextDemo: View {
  @State private var text = ""
  @State private var lastDelta: String?
  @State private var isStreaming = false
  @State private var streamTask: Task<Void, Never>?

  var body: some View {
    Form {
      Section {
        ScrollView {
          StreamingText(markdown: text, appendedMarkdown: lastDelta, isStreaming: isStreaming)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 320)
      }
      Section {
        Button("Restart") {
          restart()
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      restart()
    }
    .onDisappear {
      streamTask?.cancel()
    }
  }

  private func restart() {
    streamTask?.cancel()
    text = ""
    lastDelta = nil
    isStreaming = true

    streamTask = Task {
      var remaining = Substring(Self.fullResponse)
      while !remaining.isEmpty {
        let chunkLength = Int.random(in: 5...15)
        let chunk = remaining.prefix(chunkLength)
        remaining = remaining.dropFirst(chunk.count)

        await MainActor.run {
          text += chunk
          lastDelta = String(chunk)
        }

        try? await Task.sleep(nanoseconds: 30_000_000)
        if Task.isCancelled { return }
      }

      await MainActor.run {
        isStreaming = false
      }
    }
  }

  private static let fullResponse = """
    Great question! Let's break down how you might approach caching expensive computations in Swift.

    The simplest option is a dictionary-backed memoizer. It trades memory for speed by remembering
    results you've already computed, which is a great fit when the same inputs recur often, such as
    when rendering a scroll view that recomputes layout metrics on every frame.

    Here's a small, generic memoizer you can drop into a project:

    ```swift
    final class Memoizer<Input: Hashable, Output> {
        private var cache: [Input: Output] = [:]
        private let compute: (Input) -> Output

        init(_ compute: @escaping (Input) -> Output) {
            self.compute = compute
        }

        func callAsFunction(_ input: Input) -> Output {
            if let cached = cache[input] {
                return cached
            }
            let result = compute(input)
            cache[input] = result
            return result
        }
    }
    ```

    A few things worth keeping in mind before you reach for this pattern:

    - Memoization only pays off when the same inputs repeat; otherwise you're just paying for a
      dictionary lookup on every call.
    - Unbounded caches can grow without limit, so consider an eviction policy (LRU, size cap, or
      time-based expiry) for long-lived processes.
    - If `compute` has side effects or depends on mutable external state, memoizing it can produce
      subtly wrong results — keep the wrapped closure pure.

    For most UI-adjacent workloads, a bounded `NSCache` is a safer default than a raw dictionary,
    since it responds to memory pressure automatically. Either way, measure before and after: caching
    adds complexity, and it's only worth it once you've confirmed the recomputation is actually your
    bottleneck.
    """
}

#Preview {
  StreamingTextDemo()
}
