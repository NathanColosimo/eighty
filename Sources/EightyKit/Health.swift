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

  public static func check(now: Date = Date()) -> Health {
    guard FileManager.default.fileExists(atPath: Paths.plist) else { return .notInstalled }
    let last = History.lastRow()
    let lastDate = last.flatMap { ISO8601DateFormatter().date(from: $0.time) }
    // A sample after the error means the daemon recovered. Samples carry whole
    // seconds, so an error earlier in the same second as a sample doesn't count.
    if let error = lastError(), error.date.timeIntervalSince(lastDate ?? .distantPast) >= 1 {
      return .failing(error.message)
    }
    guard let lastDate, now.timeIntervalSince(lastDate) < staleAfter else {
      return .notResponding(lastSample: last?.time)
    }
    return .ok
  }

  /// The newest line of the daemon's error log, stamped with the log's modification time.
  private static func lastError() -> (date: Date, message: String)? {
    guard
      let date = (try? FileManager.default.attributesOfItem(atPath: Paths.errors))?[.modificationDate] as? Date,
      let text = try? String(contentsOfFile: Paths.errors, encoding: .utf8),
      let line = text.split(separator: "\n").last
    else { return nil }
    // Lines start with Date().description: "2026-11-24 20:59:00 +0000 message".
    let message = line.split(separator: " ", maxSplits: 3).dropFirst(3).first.map(String.init) ?? String(line)
    return (date, message)
  }
}
