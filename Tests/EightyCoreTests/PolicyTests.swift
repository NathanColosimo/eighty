import Testing

@testable import EightyCore

private let config = Config.standard  // limit 80, pause at 35, resume at 32

private func reading(_ percent: Int, charging: Bool = true, _ temperature: Double?) -> Reading {
  Reading(percent: percent, charging: charging, temperature: temperature)
}

@Test func hotWhileChargingPausesAtCurrentPercent() {
  let mode = nextMode(config: config, reading: reading(63, 36), mode: .limiting)
  #expect(mode == .heatPaused(at: 63))
  #expect(chargeTarget(config: config, mode: mode) == 63)
}

@Test func hotWithoutChargingDoesNotPause() {
  #expect(nextMode(config: config, reading: reading(63, charging: false, 40), mode: .limiting) == .limiting)
}

@Test func coolWhileChargingKeepsLimit() {
  let mode = nextMode(config: config, reading: reading(63, 34.9), mode: .limiting)
  #expect(chargeTarget(config: config, mode: mode) == 80)
}

@Test func pauseHoldsBetweenResumeAndPauseTemperatures() {
  // Charging has stopped by now, which must not end the pause on its own.
  #expect(nextMode(config: config, reading: reading(63, charging: false, 33), mode: .heatPaused(at: 63)) == .heatPaused(at: 63))
}

@Test func pauseEndsOnceCool() {
  #expect(nextMode(config: config, reading: reading(63, charging: false, 32), mode: .heatPaused(at: 63)) == .limiting)
}

@Test func heatOffNeverPauses() {
  let noHeat = Config(limit: 80, heat: nil)
  #expect(nextMode(config: noHeat, reading: reading(63, 45), mode: .heatPaused(at: 63)) == .limiting)
}

@Test func missingTemperatureFallsBackToLimit() {
  #expect(nextMode(config: config, reading: reading(63, nil), mode: .heatPaused(at: 63)) == .limiting)
}

@Test func pausedTargetNeverExceedsALoweredLimit() {
  let lower = Config(limit: 50, heat: config.heat)
  #expect(chargeTarget(config: lower, mode: .heatPaused(at: 63)) == 50)
}

@Test func pausedTargetStaysInMacOSRange() {
  #expect(chargeTarget(config: config, mode: .heatPaused(at: 4)) == 10)
}

@Test func configRejectsBadValues() {
  #expect(throws: Config.Invalid.limit(5)) { try Config(limit: 5, heat: nil).validated() }
  #expect(throws: Config.Invalid.resumeNotBelowPause) {
    try Config(limit: 80, heat: .init(pauseAt: 35, resumeAt: 35)).validated()
  }
  #expect(throws: Config.Invalid.temperature(70)) {
    try Config(limit: 80, heat: .init(pauseAt: 70, resumeAt: 30)).validated()
  }
}
