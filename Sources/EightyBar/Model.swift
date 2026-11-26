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
  private(set) var serviceStatus = SMAppService.Status.notRegistered
  private(set) var error: String?

  /// The daemon, run by launchd from this app's bundle.
  private let service = SMAppService.daemon(plistName: "\(Paths.daemonLabel).plist")
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
    serviceStatus = service.status
    health = Health.check(serviceOn: serviceStatus == .enabled)
  }

  /// Registers the daemon. The first time, macOS asks the user to allow it in
  /// System Settings, so this opens that page.
  func turnOnService() {
    error = nil
    do {
      try service.register()
    } catch {
      if service.status != .requiresApproval {
        self.error = "Could not turn on the background service: \(error.localizedDescription)"
      }
    }
    if service.status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
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
      self.error = "Could not save settings. Turn on the background service first."
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
