import Foundation

/// Defers a burst of render-driven values and applies only the newest one.
///
/// Geometry and preference callbacks can publish several intermediate values
/// during one SwiftUI frame. Applying each value immediately feeds back into
/// layout and triggers SwiftUI's multiple-updates-per-frame diagnostics.
@MainActor
final class DeferredUpdateCoalescer<Value> {
  private var pendingTask: Task<Void, Never>?
  private var generation = 0

  func submit(
    _ value: Value,
    apply: @escaping @MainActor (Value) -> Void
  ) {
    generation &+= 1
    let submissionGeneration = generation
    pendingTask?.cancel()
    pendingTask = Task { @MainActor [self] in
      try? await Task.sleep(for: .milliseconds(1))
      guard !Task.isCancelled, generation == submissionGeneration else {
        return
      }

      pendingTask = nil
      apply(value)
    }
  }

  func cancel() {
    generation &+= 1
    pendingTask?.cancel()
    pendingTask = nil
  }
}
