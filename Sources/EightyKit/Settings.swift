import CSystem
import EightyCore
import Foundation

/// Validates and saves the config, then wakes the daemon so it applies it at once.
/// The config file is writable by admin users, so this needs no sudo.
public func saveConfig(_ config: Config) throws {
  try config.validated().encoded().write(to: URL(fileURLWithPath: Paths.config), options: .atomic)
  notify_post(Paths.configChanged)
}

/// The daemon's per-minute samples in `Paths.history`.
public enum History {
  public static let header = "time,percent,charging,temp_c,target,mode\n"

  public struct Row: Sendable {
    public let time: String
    public let mode: Mode
  }

  /// Data lines, oldest first, without the header.
  public static func lines() -> [String] {
    guard let text = try? String(contentsOfFile: Paths.history, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").dropFirst().map(String.init)
  }

  public static func lastRow() -> Row? {
    guard let line = lines().last else { return nil }
    let fields = line.split(separator: ",", omittingEmptySubsequences: false)
    guard fields.count == 6, let target = Int(fields[4]) else { return nil }
    let mode: Mode = fields[5] == Mode.heatPaused(at: target).name ? .heatPaused(at: target) : .limiting
    return Row(time: String(fields[0]), mode: mode)
  }
}

extension Mode {
  /// The name used in history and `status --json`.
  public var name: String {
    switch self {
    case .limiting: "limit"
    case .heatPaused: "heat-pause"
    }
  }

  public var isHeatPause: Bool {
    if case .heatPaused = self { true } else { false }
  }
}
