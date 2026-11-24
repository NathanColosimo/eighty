import EightyCore
import EightyKit
import Foundation

func install() {
  requireRoot("install")
  let manager = FileManager.default
  do {
    guard let source = Bundle.main.executableURL?.resolvingSymlinksInPath().path else { fail("cannot find own executable") }
    try manager.createDirectory(atPath: (Paths.daemonBinary as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try? manager.removeItem(atPath: Paths.daemonBinary)
    try manager.copyItem(atPath: source, toPath: Paths.daemonBinary)
    try manager.setAttributes([.posixPermissions: 0o755, .ownerAccountName: "root", .groupOwnerAccountName: "wheel"], ofItemAtPath: Paths.daemonBinary)

    // Admins may edit the config without sudo; the daemon validates every read.
    try manager.createDirectory(atPath: Paths.supportDir, withIntermediateDirectories: true)
    try manager.setAttributes([.posixPermissions: 0o775, .ownerAccountName: "root", .groupOwnerAccountName: "admin"], ofItemAtPath: Paths.supportDir)
    if !manager.fileExists(atPath: Paths.config) {
      try Config.standard.encoded().write(to: URL(fileURLWithPath: Paths.config))
    }
    try manager.setAttributes([.posixPermissions: 0o664, .groupOwnerAccountName: "admin"], ofItemAtPath: Paths.config)
    try manager.createDirectory(atPath: Paths.logDir, withIntermediateDirectories: true)

    let plist: [String: Any] = [
      "Label": Paths.label,
      "ProgramArguments": [Paths.daemonBinary, "daemon"],
      "RunAtLoad": true,
      "KeepAlive": true,
      "ProcessType": "Background",
      "StandardErrorPath": Paths.errors,
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: Paths.plist))
    try manager.setAttributes([.posixPermissions: 0o644, .ownerAccountName: "root", .groupOwnerAccountName: "wheel"], ofItemAtPath: Paths.plist)

    launchctl("bootout", "system/\(Paths.label)")
    guard launchctl("bootstrap", "system", Paths.plist) else { fail("launchctl bootstrap failed") }
  } catch {
    fail("install failed: \(error)")
  }
  print("Installed eighty \(eightyVersion). The daemon is running and starts at boot.")
  print("macOS may show \"Background Items Added\": leave it allowed.")
  print("Run `eighty status` to check it.")
}

func uninstall() {
  requireRoot("uninstall")
  launchctl("bootout", "system/\(Paths.label)")
  // Leave the plain limit in place, so a heat pause doesn't outlive the daemon.
  let limit = (try? loadConfig())?.limit ?? Config.standard.limit
  do {
    try applyNativeLimit(limit)
  } catch {
    warn("could not reset the charge limit to \(limit)%: \(error)")
  }
  for path in [Paths.plist, Paths.daemonBinary, Paths.supportDir, Paths.logDir] {
    try? FileManager.default.removeItem(atPath: path)
  }
  let note = limit == 100 ? "No charge limit is set." : "macOS keeps charging to \(limit)%. Change it in System Settings → Battery."
  print("Uninstalled. \(note)")
}

private func requireRoot(_ command: String) {
  guard geteuid() == 0 else { fail("\(command) needs admin rights: sudo eighty \(command)") }
}

@discardableResult
private func launchctl(_ arguments: String...) -> Bool {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
  process.arguments = arguments
  process.standardError = FileHandle.nullDevice
  guard (try? process.run()) != nil else { return false }
  process.waitUntilExit()
  return process.terminationStatus == 0
}
