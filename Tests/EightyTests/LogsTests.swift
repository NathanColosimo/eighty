import Foundation
import Testing

@testable import EightyCore
@testable import EightyKit

@Test func historyRowsReadBackWhatTheDaemonWrote() throws {
  let reading = Reading(percent: 63, charging: true, temperature: 36.04)
  let date = Date(timeIntervalSince1970: 1_800_000_000)

  let paused = History.line(reading: reading, target: 63, mode: .heatPaused(at: 63), date: date)
  #expect(paused.hasSuffix(",63,true,36.0,63,heat-pause\n"))
  let row = try #require(History.parse(String(paused.dropLast())))
  #expect(row.mode == .heatPaused(at: 63))
  #expect(ISO8601DateFormatter().date(from: row.time) == date)

  let limiting = History.line(reading: reading, target: 80, mode: .limiting, date: date)
  #expect(History.parse(String(limiting.dropLast()))?.mode == .limiting)
}

@Test func historyRowWithoutTemperatureStillParses() {
  let line = History.line(reading: Reading(percent: 50, charging: false, temperature: nil), target: 80, mode: .limiting, date: Date())
  #expect(History.parse(String(line.dropLast())) != nil)
}

@Test func errorLogMessageReadsBackWithoutItsTimestamp() {
  let line = ErrorLog.line("macOS refused the target", date: Date())
  #expect(ErrorLog.message(of: String(line.dropLast())) == "macOS refused the target")
}
