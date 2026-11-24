import CSystem
import EightyCore
import EightyKit
import Foundation

private let interval: TimeInterval = 60
private let historyLimitBytes = 5_000_000

/// Runs forever as root under launchd: samples the battery every minute, and
/// whenever the CLI changes the config.
func runDaemon() -> Never {
  guard geteuid() == 0 else { fail("the daemon must run as root (sudo eighty install)") }

  var mode = Mode.limiting
  var config = Config.standard
  var updater = SelfUpdater()

  func tick() {
    updater?.updateIfAppIsNewer()
    do {
      config = try loadConfig()
    } catch {
      warn("ignoring invalid \(Paths.config), keeping previous settings: \(error)")
    }
    do {
      let reading = try readBattery()
      mode = nextMode(config: config, reading: reading, mode: mode)
      let target = chargeTarget(config: config, mode: mode)
      try applyNativeLimit(target)
      appendHistory(reading: reading, target: target, mode: mode)
    } catch {
      warn("\(error)")
    }
  }

  var token: Int32 = 0
  notify_register_dispatch(Paths.configChanged, &token, .main) { _ in tick() }

  let timer = DispatchSource.makeTimerSource(queue: .main)
  timer.schedule(deadline: .now(), repeating: interval, leeway: .seconds(10))
  timer.setEventHandler(handler: tick)
  timer.resume()
  dispatchMain()
}

private func appendHistory(reading: Reading, target: Int, mode: Mode) {
  let manager = FileManager.default
  if let size = try? manager.attributesOfItem(atPath: Paths.history)[.size] as? Int, size > historyLimitBytes {
    try? manager.removeItem(atPath: Paths.history + ".1")
    try? manager.moveItem(atPath: Paths.history, toPath: Paths.history + ".1")
  }
  if !manager.fileExists(atPath: Paths.history) {
    manager.createFile(atPath: Paths.history, contents: Data(History.header.utf8))
  }
  let time = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
  let temperature = reading.temperature.map { String(format: "%.1f", $0) } ?? ""
  let line = "\(time),\(reading.percent),\(reading.charging),\(temperature),\(target),\(mode.name)\n"
  guard let handle = FileHandle(forWritingAtPath: Paths.history) else { return }
  defer { try? handle.close() }
  _ = try? handle.seekToEnd()
  try? handle.write(contentsOf: Data(line.utf8))
}

func warn(_ message: String) {
  FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8))
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("eighty: \(message)\n".utf8))
  exit(1)
}
