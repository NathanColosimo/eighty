import Foundation
import Testing

@testable import EightyCore
@testable import EightyKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func sample(secondsAgo: TimeInterval) -> History.Row {
  History.Row(time: ISO8601DateFormatter().string(from: now.addingTimeInterval(-secondsAgo)), mode: .limiting)
}

@Test func recentSampleIsHealthy() {
  #expect(Health.evaluate(serviceOn: true, lastSample: sample(secondsAgo: 60), lastError: nil, lastWake: .distantPast, now: now) == .ok)
}

@Test func serviceOffWins() {
  #expect(Health.evaluate(serviceOn: false, lastSample: sample(secondsAgo: 0), lastError: nil, lastWake: .distantPast, now: now) == .off)
}

@Test func staleSamplesMeanNotResponding() {
  let old = sample(secondsAgo: 181)
  #expect(Health.evaluate(serviceOn: true, lastSample: old, lastError: nil, lastWake: .distantPast, now: now) == .notResponding(lastSample: old.time))
  #expect(Health.evaluate(serviceOn: true, lastSample: nil, lastError: nil, lastWake: .distantPast, now: now) == .notResponding(lastSample: nil))
}

@Test func errorAfterLastSampleIsFailing() {
  let error = (date: now.addingTimeInterval(-10), message: "macOS refused the target")
  #expect(Health.evaluate(serviceOn: true, lastSample: sample(secondsAgo: 70), lastError: error, lastWake: .distantPast, now: now) == .failing("macOS refused the target"))
}

@Test func sampleAfterErrorMeansRecovered() {
  let error = (date: now.addingTimeInterval(-70), message: "transient")
  #expect(Health.evaluate(serviceOn: true, lastSample: sample(secondsAgo: 10), lastError: error, lastWake: .distantPast, now: now) == .ok)
}

@Test func errorInTheSameSecondAsASampleDoesNotCount() {
  // Samples are stamped to the second; the error came 0.4 s into that second.
  let error = (date: now.addingTimeInterval(-9.6), message: "logged just before the sample")
  #expect(Health.evaluate(serviceOn: true, lastSample: sample(secondsAgo: 10), lastError: error, lastWake: .distantPast, now: now) == .ok)
}

@Test func timeAsleepDoesNotCount() {
  // Sampled 8 minutes ago, then the Mac slept; it woke 30 s ago, before the daemon's next tick.
  let beforeSleep = sample(secondsAgo: 480)
  #expect(Health.evaluate(serviceOn: true, lastSample: beforeSleep, lastError: nil, lastWake: now.addingTimeInterval(-30), now: now) == .ok)
  #expect(
    Health.evaluate(serviceOn: true, lastSample: beforeSleep, lastError: nil, lastWake: now.addingTimeInterval(-181), now: now)
      == .notResponding(lastSample: beforeSleep.time))
}
