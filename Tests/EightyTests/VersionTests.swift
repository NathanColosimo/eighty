import Testing

@testable import EightyCore

@Test func newerVersionsCompareNumerically() {
  #expect(isNewer("0.1.10", than: "0.1.9"))
  #expect(isNewer("0.2", than: "0.1.9"))
  #expect(isNewer("1.0.0", than: "0.9.9"))
}

@Test func sameOrOlderIsNotNewer() {
  #expect(!isNewer("0.1.3", than: "0.1.3"))
  #expect(!isNewer("0.1", than: "0.1.0"))
  #expect(!isNewer("0.1.2", than: "0.1.3"))
}

@Test func garbageIsNeverNewer() {
  #expect(!isNewer("", than: "0.1.0"))
  #expect(!isNewer("1.x", than: "0.1.0"))
}
