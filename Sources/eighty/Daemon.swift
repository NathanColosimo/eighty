import CSystem
import EightyCore
import EightyKit
import Foundation

private let interval: TimeInterval = 60

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
      ErrorLog.write("ignoring invalid \(Paths.config), keeping previous settings: \(error)")
    }
    do {
      let reading = try readBattery()
      mode = nextMode(config: config, reading: reading, mode: mode)
      let target = chargeTarget(config: config, mode: mode)
      try applyNativeLimit(target)
      History.append(reading: reading, target: target, mode: mode)
    } catch {
      ErrorLog.write("\(error)")
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
