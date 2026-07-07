// FILE: RemodexNamespaceTests.swift
// Purpose: Verifies the `.remodex` namespace is primary and the deprecated `.textual` alias
//   still resolves for out-of-repo consumers that have not migrated yet.
// Layer: Unit Test
// Exports: RemodexNamespaceTests
// Depends on: Testing, RemodexTextKit

import Testing

@testable import RemodexTextKit

private struct NamespaceTestSubject: RemodexCompatible, Equatable {
  var value: Int
}

/// Calls into the deprecated `.textual` alias from a context that is itself deprecated, so the
/// call site doesn't produce a deprecation warning in this test target.
@available(*, deprecated)
private func legacyTextualNamespace(_ subject: NamespaceTestSubject) -> RemodexNamespace<
  NamespaceTestSubject
> {
  subject.textual
}

struct RemodexNamespaceTests {
  @Test func remodexNamespaceWrapsInstanceAndPreservesBase() {
    let subject = NamespaceTestSubject(value: 42)
    let namespace = subject.remodex

    let modifier: RemodexNamespace<NamespaceTestSubject> = namespace
    #expect(modifier.base == subject)
  }

  @Test func deprecatedTextualAliasStillResolvesToTheSameWrapper() {
    let subject = NamespaceTestSubject(value: 7)

    let viaRemodex = subject.remodex
    let viaTextual = legacyTextualNamespace(subject)

    #expect(viaRemodex.base == viaTextual.base)
  }
}
