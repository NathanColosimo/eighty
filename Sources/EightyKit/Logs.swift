import EightyCore
import Foundation

/// The daemon's per-minute samples in `Paths.history`, one CSV row each.
/// The daemon writes them; the CLI and app read them.
public enum History {
  public static let header = "time,percent,charging,temp_c,target,mode\n"
  static let rotateAtBytes = 5_000_000

  public struct Row: Equatable, Sendable {
    public let time: String
    public let mode: Mode
  }

  /// Appends one row. Past 5 MB the file moves to `history.csv.1` and a new one starts.
  public static func append(reading: Reading, target: Int, mode: Mode) {
    let manager = FileManager.default
    if let size = try? manager.attributesOfItem(atPath: Paths.history)[.size] as? Int, size > rotateAtBytes {
      try? manager.removeItem(atPath: Paths.history + ".1")
      try? manager.moveItem(atPath: Paths.history, toPath: Paths.history + ".1")
    }
    if !manager.fileExists(atPath: Paths.history) {
      manager.createFile(atPath: Paths.history, contents: Data(header.utf8))
    }
    guard let handle = FileHandle(forWritingAtPath: Paths.history) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data(line(reading: reading, target: target, mode: mode, date: Date()).utf8))
  }

  /// Data lines, oldest first, without the header.
  public static func lines() -> [String] {
    guard let text = try? String(contentsOfFile: Paths.history, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").dropFirst().map(String.init)
  }

  public static func lastRow() -> Row? {
    lines().last.flatMap(parse)
  }

  static func line(reading: Reading, target: Int, mode: Mode, date: Date) -> String {
    let time = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withInternetDateTime])
    let temperature = reading.temperature.map { String(format: "%.1f", $0) } ?? ""
    return "\(time),\(reading.percent),\(reading.charging),\(temperature),\(target),\(mode.name)\n"
  }

  static func parse(_ line: String) -> Row? {
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
}

/// The daemon's error log. The daemon writes to standard error, which launchd
/// sends to `Paths.errors`; the health check reads the newest line back.
public enum ErrorLog {
  public static func write(_ message: String) {
    FileHandle.standardError.write(Data(line(message, date: Date()).utf8))
  }

  /// The newest message, stamped with the log's modification time.
  static func last() -> (date: Date, message: String)? {
    guard
      let date = (try? FileManager.default.attributesOfItem(atPath: Paths.errors))?[.modificationDate] as? Date,
      let text = try? String(contentsOfFile: Paths.errors, encoding: .utf8),
      let line = text.split(separator: "\n").last
    else { return nil }
    return (date, message(of: String(line)))
  }

  static func line(_ message: String, date: Date) -> String {
    "\(ISO8601DateFormatter().string(from: date)) \(message)\n"
  }

  static func message(of line: String) -> String {
    line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? line
  }
}
