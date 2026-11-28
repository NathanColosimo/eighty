/// One sample of the battery.
public struct Reading: Equatable, Sendable {
  public var percent: Int
  public var charging: Bool
  /// Hottest battery sensor in °C, or nil when no sensor could be read.
  public var temperature: Double?

  public init(percent: Int, charging: Bool, temperature: Double?) {
    self.percent = percent
    self.charging = charging
    self.temperature = temperature
  }
}

/// What the daemon is doing about charging.
public enum Mode: Equatable, Sendable {
  case limiting
  /// Charging paused for heat, holding the battery at this percentage.
  case heatPaused(at: Int)

  public var isHeatPause: Bool {
    if case .heatPaused = self { true } else { false }
  }
}

/// Decides the next mode. Heat only matters while charging: a battery that is
/// not charging gets no hotter from the charger. A pause follows the battery
/// down, so one that drained while unplugged doesn't charge back up while hot.
public func nextMode(config: Config, reading: Reading, mode: Mode) -> Mode {
  guard let heat = config.heat, let temperature = reading.temperature else { return .limiting }

  switch mode {
  case .heatPaused(let held):
    return temperature <= heat.resumeAt ? .limiting : .heatPaused(at: min(held, reading.percent))
  case .limiting:
    let charging = reading.charging && reading.percent < config.limit
    return charging && temperature >= heat.pauseAt ? .heatPaused(at: reading.percent) : .limiting
  }
}

/// The charge target to hand macOS. 100 means no limit.
public func chargeTarget(config: Config, mode: Mode) -> Int {
  switch mode {
  case .limiting: config.limit
  case .heatPaused(let percent): min(max(percent, 10), config.limit)
  }
}
