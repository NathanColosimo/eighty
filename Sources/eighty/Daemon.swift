import CSystem
import EightyCore
import EightyKit
import Foundation

private let interval: TimeInterval = 60

/// Runs forever as root under launchd, straight from Eighty.app (the app
/// registers it with SMAppService): samples the battery every minute, and
/// whenever the CLI changes the config.
func runDaemon() -> Never {
  guard geteuid() == 0 else { fail("the daemon runs under launchd; turn it on from the Eighty menu bar app") }
  do {
    try prepareFiles()
  } catch {
    fail("cannot set up \(Paths.supportDir) and \(Paths.logDir): \(error)")
  }

  var mode = Mode.limiting
  var config = (try? loadConfig()) ?? .standard

  // launchd stops the daemon when it's turned off in System Settings. Leave
  // the plain limit, so a heat pause doesn't outlive it.
  signal(SIGTERM, SIG_IGN)
  let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
  termination.setEventHandler {
    try? applyNativeLimit(config.limit)
    exit(0)
  }
  termination.resume()

  removeLegacyService()

  // `brew upgrade` replaces the app. Exit, and launchd starts the new binary.
  let executable = Bundle.main.executableURL!.path  // always set for a running executable
  let startedFrom = fileNumber(executable)

  func tick() {
    if let current = fileNumber(executable), current != startedFrom { exit(0) }
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

/// Creates the settings and log folders, and sends standard error (`ErrorLog`)
/// to the error log. Admins may edit the config without sudo; the daemon
/// validates every read.
private func prepareFiles() throws {
  let manager = FileManager.default
  try manager.createDirectory(atPath: Paths.supportDir, withIntermediateDirectories: true)
  try manager.setAttributes([.posixPermissions: 0o775, .groupOwnerAccountName: "admin"], ofItemAtPath: Paths.supportDir)
  if !manager.fileExists(atPath: Paths.config) {
    try Config.standard.encoded().write(to: URL(fileURLWithPath: Paths.config))
  }
  try manager.setAttributes([.posixPermissions: 0o664, .groupOwnerAccountName: "admin"], ofItemAtPath: Paths.config)
  try manager.createDirectory(atPath: Paths.logDir, withIntermediateDirectories: true)
  guard freopen(Paths.errors, "a", stderr) != nil else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

/// Before 0.1.7, `sudo eighty install` ran the daemon as a plain launchd job,
/// from a copy of the CLI. Remove it. Those versions update themselves to this
/// code, so the old job usually runs this and stops itself; the app then asks
/// to turn on the new service.
private func removeLegacyService() {
  let plist = "/Library/LaunchDaemons/dev.eighty.plist"
  guard FileManager.default.fileExists(atPath: plist) else { return }
  for path in [plist, "/Library/PrivilegedHelperTools/dev.eighty", "/Library/PrivilegedHelperTools/dev.eighty.new"] {
    try? FileManager.default.removeItem(atPath: path)
  }
  // Not waited for: when this is the old job, launchd sends SIGTERM, which the main queue must handle.
  _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"), arguments: ["bootout", "system/dev.eighty"])
}

private func fileNumber(_ path: String) -> Int? {
  (try? FileManager.default.attributesOfItem(atPath: path))?[.systemFileNumber] as? Int
}
