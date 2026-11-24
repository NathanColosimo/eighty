import EightyCore
import EightyKit
import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class Model {
  private(set) var reading: Reading?
  private(set) var config = Config.standard
  private(set) var mode = Mode.limiting
  private(set) var health = Health.ok
  /// The installed daemon's version, nil when it can't be read.
  private(set) var daemonVersion: String?
  private(set) var error: String?

  /// When the daemon was first seen out of date. A signed daemon updates itself
  /// within about a minute of an upgrade, so the app only asks after a grace period.
  private var outdatedSince: Date?

  private var timer: Timer?

  init() {
    refresh()
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
    // Reading the version starts a process, so only until it matches this app.
    if daemonVersion != eightyVersion {
      daemonVersion = output(of: Paths.daemonBinary, "version")
      outdatedSince = daemonVersion == eightyVersion ? nil : outdatedSince ?? Date()
    }
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
    refresh()
  }

  /// The daemon is installed but out of date, and hasn't updated itself within a
  /// few minutes (an unsigned build, or one from before self-update).
  var needsManualUpdate: Bool {
    guard health != .notInstalled, daemonVersion != eightyVersion, let outdatedSince else { return false }
    return Date().timeIntervalSince(outdatedSince) > 180
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
