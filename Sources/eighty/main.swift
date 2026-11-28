import EightyCore
import EightyKit
import Foundation

struct Command {
  let name: String
  let usage: String
  let summary: String
  let details: String
  let run: (ArraySlice<String>) -> Void
}

let commands: [Command] = [
  Command(
    name: "status", usage: "status [--json]",
    summary: "Battery, temperature, settings, and what macOS is enforcing",
    details: """
      Fields:
        battery       percent, charging, hottest battery sensor in °C
        limit         charge limit in percent (100 = off)
        heat          pause and resume temperatures in °C, or off
        macOS target  the limit macOS has loaded; "enforcing" is what it applies now
        daemon        on (installed) or off, limiting or paused for heat, last sample time
        health        OK, or what is wrong: off, not responding, or an error

      --json prints one object. Missing values are null:
        {"battery": {"percent": 79, "charging": true, "temperatureC": 31.2},
         "limit": 80, "heat": {"pauseAt": 35, "resumeAt": 32},
         "macosTarget": 80, "enforcing": [80], "problem": null,
         "daemon": {"installed": true, "mode": "limit", "lastSample": "2026-11-22T18:24:29-05:00"}}
      daemon.mode is "limit" or "heat-pause". problem is null when healthy.
      """,
    run: status),
  Command(
    name: "limit", usage: "limit <10-100>",
    summary: "Set the charge limit (100 = off)",
    details: """
      Stops charging at this percentage. Eighty applies it within seconds; while
      charging, macOS can take a few minutes to enforce it.
      Above the limit, macOS runs the Mac from the battery until it drops to the limit.
      Example: eighty limit 80
      """,
    run: setLimit),
  Command(
    name: "heat", usage: "heat <pause> [resume] | off",
    summary: "Pause charging while the battery is hot",
    details: """
      While charging below the limit, at or above <pause> °C, charging stops at the
      current percentage. It resumes once the battery cools to [resume] °C
      (default: pause - 3). Temperatures must be 25-50 and resume below pause.
      Examples: eighty heat 35 32
                eighty heat off
      """,
    run: setHeat),
  Command(
    name: "history", usage: "history [count]",
    summary: "Last samples, one per minute (default 20)",
    details: """
      CSV with a header row: time,percent,charging,temp_c,target,mode
        time     ISO 8601 local time
        temp_c   hottest battery sensor, empty if unreadable
        target   the limit eighty asked macOS for
        mode     limit or heat-pause
      Example: eighty history 60
      """,
    run: history),
]

let overview = """
  eighty: keep a MacBook's battery at a charge limit, and pause charging while it is hot.

  Usage: eighty <command> [arguments]

  \(commands.map { "  \($0.usage.padding(toLength: 34, withPad: " ", startingAt: 0))\($0.summary)" }.joined(separator: "\n"))

  Run `eighty help <command>` for details. `eighty -v` prints the version.

  For scripts and agents:
    - Exit code 0 on success, 1 on error; errors go to stderr.
    - Use `eighty status --json` to read state; `history` prints CSV.
    - No command needs sudo. Setting changes apply within seconds.
    - The background service is turned on from the Eighty menu bar app.
    - Settings: \(Paths.config)
  """

@MainActor func help(_ rest: ArraySlice<String>) {
  guard let name = rest.first else { return print(overview) }
  guard let command = commands.first(where: { $0.name == name }) else { fail("no command \(name). Run: eighty help") }
  print("Usage: eighty \(command.usage)\n\n\(command.summary).\n\n\(command.details)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let rest = arguments.dropFirst()

switch arguments.first {
case nil, "help", "-h", "--help": help(rest)
case "version", "--version", "-v": print(eightyVersion)
case "daemon": runDaemon()
case let name?:
  guard let command = commands.first(where: { $0.name == name }) else { fail("unknown command \(name). Run: eighty help") }
  if rest.contains("-h") || rest.contains("--help") { help([name]) } else { command.run(rest) }
}

func status(_ rest: ArraySlice<String>) {
  guard rest.isEmpty || Array(rest) == ["--json"] else { fail("usage: eighty status [--json]") }
  let config = savedConfig()
  let reading = try? readBattery()
  let native = Result { () throws(SystemError) in try readNativeLimit() }
  let enforcing = Set(registeredLimits()).sorted()
  let installed = serviceIsLoaded()
  let health = Health.check(serviceOn: installed)
  let last = History.lastRow()

  if rest.first == "--json" {
    let object: [String: Any] = [
      "battery": reading.map { ["percent": $0.percent, "charging": $0.charging, "temperatureC": nullable($0.temperature.map { NSDecimalNumber(string: String(format: "%.1f", $0)) })] } ?? NSNull(),
      "limit": config.limit,
      "problem": nullable(health.problem),
      "heat": config.heat.map { ["pauseAt": $0.pauseAt, "resumeAt": $0.resumeAt] } ?? NSNull(),
      "macosTarget": nullable(try? native.get()),
      "enforcing": enforcing,
      "daemon": ["installed": installed, "mode": nullable(last?.mode.name), "lastSample": nullable(last?.time)],
    ]
    // Only plain dictionaries, arrays, numbers, strings, and NSNull above, which always serialize.
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return print(String(decoding: data, as: UTF8.self))
  }

  print("Health:       \(health.problem ?? "OK")")
  if let reading {
    let temperature = reading.temperature.map { String(format: "%.1f °C", $0) } ?? "temperature unknown"
    print("Battery:      \(reading.percent)%, \(reading.charging ? "charging" : "not charging"), \(temperature)")
  } else {
    print("Battery:      unreadable")
  }
  print("Limit:        \(config.limit == 100 ? "off" : "\(config.limit)%")")
  print("Heat pause:   \(config.heat.map { "at \(format($0.pauseAt)) °C, resume at \(format($0.resumeAt)) °C" } ?? "off")")
  let target = switch native {
  case .success(let limit?): "\(limit)%"
  case .success(nil): "off"
  case .failure: "unreadable"
  }
  let enforced = enforcing.isEmpty ? "none" : enforcing.map { "\($0)%" }.joined(separator: ", ")
  print("macOS target: \(target) (enforcing: \(enforced))")
  let state = last.map { "\($0.mode.isHeatPause ? "paused for heat" : "limiting"), last sample \($0.time)" } ?? "no samples yet"
  print("Daemon:       \(installed ? "installed, \(state)" : "off (turn it on from the Eighty menu bar app)")")
}

/// Whether launchd has the daemon's job. Only the app can ask SMAppService.
func serviceIsLoaded() -> Bool {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
  process.arguments = ["print", "system/\(Paths.daemonLabel)"]
  process.standardOutput = FileHandle.nullDevice
  process.standardError = FileHandle.nullDevice
  guard (try? process.run()) != nil else { return false }
  process.waitUntilExit()
  return process.terminationStatus == 0
}

func setLimit(_ rest: ArraySlice<String>) {
  guard rest.count == 1, let limit = Int(rest[rest.startIndex]) else { fail("usage: eighty limit <10-100>") }
  updateConfig { $0.limit = limit }
  print("Limit set to \(limit == 100 ? "off" : "\(limit)%").")
}

func setHeat(_ rest: ArraySlice<String>) {
  let values = Array(rest)
  if values == ["off"] {
    updateConfig { $0.heat = nil }
    print("Heat pause off.")
    return
  }
  guard (1...2).contains(values.count), let pause = Double(values[0]) else { fail("usage: eighty heat <pause> [resume] | off") }
  guard let resume = values.count == 2 ? Double(values[1]) : pause - 3 else { fail("resume must be a number") }
  updateConfig { $0.heat = .init(pauseAt: pause, resumeAt: resume) }
  print("Heat pause at \(format(pause)) °C, resume at \(format(resume)) °C.")
}

/// Exits on an invalid file rather than showing defaults the daemon isn't
/// using, or saving them over the user's other settings.
func savedConfig() -> Config {
  do {
    return try loadConfig()
  } catch {
    fail("\(Paths.config) is invalid (\(error)). Fix it, or delete it to go back to the defaults.")
  }
}

func updateConfig(_ change: (inout Config) -> Void) {
  var config = savedConfig()
  change(&config)
  do {
    try saveConfig(config)
  } catch let error as Config.Invalid {
    fail(error.description)
  } catch {
    fail("cannot save settings (is the background service on? Turn it on from the Eighty menu bar app): \(error.localizedDescription)")
  }
}

func history(_ rest: ArraySlice<String>) {
  guard rest.count <= 1, let count = rest.isEmpty ? 20 : Int(rest[rest.startIndex]), count > 0 else {
    fail("usage: eighty history [count]")
  }
  print(History.header, terminator: "")
  History.lines().suffix(count).forEach { print($0) }
}

func format(_ value: Double) -> String {
  value == value.rounded() ? String(Int(value)) : String(value)
}

func nullable(_ value: Any?) -> Any {
  value ?? NSNull()
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("eighty: \(message)\n".utf8))
  exit(1)
}
