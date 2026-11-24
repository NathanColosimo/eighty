import Foundation

/// User settings, stored as JSON and edited through the CLI.
public struct Config: Codable, Equatable, Sendable {
  /// Charge target in percent. 100 turns the limit off.
  public var limit: Int
  /// Heat pause, or nil when turned off.
  public var heat: Heat?

  public struct Heat: Codable, Equatable, Sendable {
    /// Pause charging at or above this battery temperature (°C).
    public var pauseAt: Double
    /// Resume charging at or below this battery temperature (°C).
    public var resumeAt: Double

    public init(pauseAt: Double, resumeAt: Double) {
      self.pauseAt = pauseAt
      self.resumeAt = resumeAt
    }
  }

  public static let standard = Config(limit: 80, heat: Heat(pauseAt: 35, resumeAt: 32))

  public init(limit: Int, heat: Heat?) {
    self.limit = limit
    self.heat = heat
  }

  public enum Invalid: Error, Equatable, CustomStringConvertible {
    case limit(Int)
    case temperature(Double)
    case resumeNotBelowPause

    public var description: String {
      switch self {
      case .limit(let value): "limit must be 10-100, got \(value)"
      case .temperature(let value): "temperature must be 25-50 °C, got \(value)"
      case .resumeNotBelowPause: "resume temperature must be below the pause temperature"
      }
    }
  }

  public func validated() throws(Invalid) -> Config {
    guard (10...100).contains(limit) else { throw .limit(limit) }
    if let heat {
      for value in [heat.pauseAt, heat.resumeAt] where !(25...50).contains(value) {
        throw .temperature(value)
      }
      guard heat.resumeAt < heat.pauseAt else { throw .resumeNotBelowPause }
    }
    return self
  }

  public static func decode(_ data: Data) throws -> Config {
    try JSONDecoder().decode(Config.self, from: data).validated()
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
}
