import CSystem
import EightyCore
import Foundation
import IOKit.ps

public enum Paths {
  public static let label = "dev.eighty"
  /// The menu bar app's CFBundleIdentifier, set in scripts/build-app.sh.
  public static let appBundleID = "dev.eighty.menubar"
  /// Where Homebrew installs the app; the daemon updates itself from it.
  public static let appBundle = "/Applications/Eighty.app"
  /// Root-owned copy of the CLI that launchd runs, so the daemon never runs a
  /// binary a normal user could replace.
  public static let daemonBinary = "/Library/PrivilegedHelperTools/\(label)"
  public static let plist = "/Library/LaunchDaemons/\(label).plist"
  public static let supportDir = "/Library/Application Support/eighty"
  public static let config = "\(supportDir)/config.json"
  public static let logDir = "/Library/Logs/eighty"
  public static let history = "\(logDir)/history.csv"
  public static let errors = "\(logDir)/errors.log"
  /// Posted after the config changes, so the daemon reacts at once.
  public static let configChanged = "\(label).config-changed"
}

public struct SystemError: Error, CustomStringConvertible {
  public let description: String
}

/// Calls a CSystem function that reports failure as -1 plus a message buffer.
private func check(_ body: (UnsafeMutablePointer<CChar>, Int32) -> Int32) throws(SystemError) {
  var buffer = [CChar](repeating: 0, count: 256)
  let status = buffer.withUnsafeMutableBufferPointer { body($0.baseAddress!, Int32($0.count)) }
  guard status == 0 else { throw SystemError(description: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
}

public func readBattery() throws(SystemError) -> Reading {
  let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
  let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
  for source in sources {
    guard
      let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
      let percent = description[kIOPSCurrentCapacityKey] as? Int,
      let charging = description[kIOPSIsChargingKey] as? Bool
    else { continue }
    let temperature = eighty_battery_temp_c()
    return Reading(percent: percent, charging: charging, temperature: temperature.isNaN ? nil : temperature)
  }
  throw SystemError(description: "no internal battery found")
}

/// macOS's built-in charge limit. `nil` when it is off.
public func readNativeLimit() throws(SystemError) -> Int? {
  var limit: Int32 = 0
  var enabled: Int32 = 0
  try check { eighty_limit_read(&limit, &enabled, $0, $1) }
  return enabled != 0 ? Int(limit) : nil
}

/// Makes macOS's charge limit match `target` (100 = off). Needs root.
public func applyNativeLimit(_ target: Int) throws(SystemError) {
  let current = try readNativeLimit()
  if target == 100 {
    if current != nil { try check { eighty_limit_disable($0, $1) } }
    return
  }
  if current == target { return }
  try check { eighty_limit_set_exact(Int32(target), $0, $1) }
}

/// Targets powerd is enforcing right now. The agent can accept a new target a
/// few minutes before powerd registers it.
public func registeredLimits() -> [Int] {
  guard let output = output(of: "/usr/bin/pmset", "-g", "battlimit") else { return [] }
  return output.split(separator: "}").compactMap { row in
    guard row.contains("Terminated = 0"), let match = row.firstMatch(of: /chargeSocLimitSoc = (\d+)/) else { return nil }
    return Int(match.1)
  }
}

public func loadConfig() throws -> Config {
  guard let data = FileManager.default.contents(atPath: Paths.config) else { return .standard }
  return try Config.decode(data)
}

/// Validates and saves the config, then wakes the daemon so it applies it at once.
/// The config file is writable by admin users, so this needs no sudo.
public func saveConfig(_ config: Config) throws {
  try config.validated().encoded().write(to: URL(fileURLWithPath: Paths.config), options: .atomic)
  notify_post(Paths.configChanged)
}

/// Runs a program and returns its trimmed standard output, or nil if it can't start.
public func output(of executable: String, _ arguments: String...) -> String? {
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
