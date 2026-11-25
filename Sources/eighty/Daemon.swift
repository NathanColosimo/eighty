import CSystem
import EightyCore
import EightyKit
import Foundation

private let interval: TimeInterval = 60

/// Runs forever as root under launchd: samples the battery every minute, and
/// whenever the CLI changes the config.
func runDaemon() -> Never {
  guard geteuid() == 0 else { fail("the daemon must run as root (sudo eighty install)") }
  // The binary is a copy from the Homebrew app, so it carries the app's
  // quarantine flag. Gatekeeper checks a quarantined bare binary with Apple's
  // servers, which fails at boot before the network is up: launchd's start is
  // blocked and macOS shows "Eighty Not Opened".
  if removexattr(Paths.daemonBinary, "com.apple.quarantine", 0) != 0, errno != ENOATTR {
    ErrorLog.write("cannot clear the quarantine flag on \(Paths.daemonBinary): \(String(cString: strerror(errno)))")
  }

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
