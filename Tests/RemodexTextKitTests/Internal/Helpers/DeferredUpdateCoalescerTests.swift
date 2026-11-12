import Testing

@testable import RemodexTextKit

@MainActor
struct DeferredUpdateCoalescerTests {
  @Test
  func appliesOnlyTheNewestValueFromABurst() async throws {
    let coalescer = DeferredUpdateCoalescer<Int>()
    var appliedValues: [Int] = []

    coalescer.submit(1) { appliedValues.append($0) }
    coalescer.submit(2) { appliedValues.append($0) }
    coalescer.submit(3) { appliedValues.append($0) }

    // Wait for the deferred apply; the main actor can be busy with other tests in parallel.
    for _ in 0..<100 where appliedValues.isEmpty {
      try await Task.sleep(for: .milliseconds(10))
    }
    try await Task.sleep(for: .milliseconds(20))

    #expect(appliedValues == [3])
  }

  @Test
  func cancellationDropsThePendingValue() async throws {
    let coalescer = DeferredUpdateCoalescer<Int>()
    var appliedValues: [Int] = []

    coalescer.submit(1) { appliedValues.append($0) }
    coalescer.cancel()

    try await Task.sleep(for: .milliseconds(20))

    #expect(appliedValues.isEmpty)
  }
}
