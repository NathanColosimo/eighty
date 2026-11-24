import EightyCore
import EightyKit
import Foundation
import Observation
import ServiceManagement

enum DaemonState: Equatable {
  case missing
  case outdated
  case current
}

@MainActor @Observable
final class Model {
  private(set) var reading: Reading?
  private(set) var config = Config.standard
  private(set) var mode = Mode.limiting
  private(set) var daemon = DaemonState.missing
  private(set) var health = Health.ok
  private(set) var error: String?

  private var timer: Timer?

  init() {
    refresh()
    checkDaemon()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
  }

  func refresh() {
    reading = try? readBattery()
    do {
      config = try loadConfig()
    } catch {
      self.error = "Settings file is invalid: \(error)"
    }
    mode = History.lastRow()?.mode ?? .limiting
    health = Health.check()
    // Notice an install or upgrade done from the CLI or Homebrew. Spawns a
    // process, so only while the service needs attention.
    if daemon != .current || health == .notInstalled { checkDaemon() }
  }

  /// Compares the installed daemon's version with this app's.
  func checkDaemon() {
    guard FileManager.default.fileExists(atPath: Paths.plist) else {
      daemon = .missing
      return
    }
    daemon = output(of: Paths.daemonBinary, "version") == eightyVersion ? .current : .outdated
  }

  /// Runs the bundled CLI's `install` as root, behind the standard macOS password dialog.
  func installDaemon() {
    let cli = Bundle.main.bundleURL.appending(path: "Contents/Helpers/eighty").path
    guard FileManager.default.isExecutableFile(atPath: cli) else {
      error = "The eighty command is missing from this app. Reinstall Eighty."
      return
    }
    let quoted = cli.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let source = "do shell script quoted form of \"\(quoted)\" & \" install\" with administrator privileges"
    var failure: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&failure)
    let userCancelled = -128
    if let failure, failure[NSAppleScript.errorNumber] as? Int != userCancelled {
      error = "Install failed: \(failure[NSAppleScript.errorMessage] as? String ?? "unknown error")"
    } else if failure == nil {
      error = nil
    }
    checkDaemon()
    refresh()
  }

  /// The percentage charging stops at right now.
  var target: Int { chargeTarget(config: config, mode: mode) }

  func setLimit(_ limit: Int) {
    update { $0.limit = limit }
  }

  func setHeatEnabled(_ enabled: Bool) {
    update { $0.heat = enabled ? Config.standard.heat : nil }
  }

  /// Resume stays 3 °C below the pause point, the same default as the CLI.
  func setPauseAt(_ celsius: Double) {
    update { $0.heat = .init(pauseAt: celsius, resumeAt: celsius - 3) }
  }

  private func update(_ change: (inout Config) -> Void) {
    var next = config
    change(&next)
    do {
      try saveConfig(next)
      config = next
      error = nil
    } catch let invalid as Config.Invalid {
      error = invalid.description
    } catch {
      self.error = "Could not save settings. Install the background service first."
    }
  }

  var launchAtLogin: Bool {
    get { SMAppService.mainApp.status == .enabled }
    set {
      do {
        if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        error = nil
      } catch {
        self.error = "Could not change Open at Login: \(error.localizedDescription)"
      }
    }
  }
}

private func output(of executable: String, _ arguments: String...) -> String? {
  let pipe = Pipe()
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardOutput = pipe
  guard (try? process.run()) != nil else { return nil }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
