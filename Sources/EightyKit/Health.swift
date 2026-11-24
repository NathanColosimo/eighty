import Foundation

/// Whether the daemon is doing its job, judged from the files it leaves behind,
/// so the CLI and menu bar app can check it without root.
public enum Health: Equatable, Sendable {
  case ok
  case notInstalled
  /// No sample for a few minutes: the daemon is stopped or stuck.
  case notResponding(lastSample: String?)
  /// The daemon's latest attempt failed, for example macOS refused the target.
  case failing(String)

  /// The daemon samples every minute; allow a few missed ticks before alarming.
  static let staleAfter: TimeInterval = 180

  public var problem: String? {
    switch self {
    case .ok: nil
    case .notInstalled: "The background service is not installed."
    case .notResponding(let last?): "The background service isn't responding (last sample \(last))."
    case .notResponding(nil): "The background service isn't responding (no samples yet)."
    case .failing(let message): "The background service hit an error: \(message)"
    }
  }

  public static func check() -> Health {
    evaluate(
      installed: FileManager.default.fileExists(atPath: Paths.plist),
      lastSample: History.lastRow(), lastError: ErrorLog.last(), now: Date())
  }

  static func evaluate(installed: Bool, lastSample: History.Row?, lastError: (date: Date, message: String)?, now: Date) -> Health {
    guard installed else { return .notInstalled }
    let sampled = lastSample.flatMap { ISO8601DateFormatter().date(from: $0.time) }
    // A sample after the error means the daemon recovered. Samples carry whole
    // seconds, so an error earlier in the same second as a sample doesn't count.
    if let lastError, lastError.date.timeIntervalSince(sampled ?? .distantPast) >= 1 {
      return .failing(lastError.message)
    }
    guard let sampled, now.timeIntervalSince(sampled) < staleAfter else {
      return .notResponding(lastSample: lastSample?.time)
    }
    return .ok
  }
}
