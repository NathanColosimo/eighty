import EightyCore
import EightyKit
import Foundation
import Security

/// Keeps the daemon in step with the menu bar app, so `brew upgrade` needs no
/// password. When /Applications/Eighty.app carries a newer `eighty`, the daemon
/// copies it next to itself, checks the copy is signed by the same Developer ID
/// team, swaps it in, and exits so launchd restarts it on the new binary.
///
/// /Applications is writable by admin users, so the checks are what keep this
/// from running someone else's code as root: same team ID as this daemon, the
/// `eighty` identifier, a Developer ID certificate, and a strictly newer version.
struct SelfUpdater {
  private let team: String
  /// The version last rejected, so a bad candidate is reported once, not every minute.
  private var rejected: String?

  /// Nil when this daemon isn't Developer ID–signed (a local build): those update
  /// with `sudo eighty install`.
  init?() {
    guard let team = Self.teamOfRunningCode() else { return nil }
    self.team = team
  }

  mutating func updateIfAppIsNewer() {
    guard
      let info = NSDictionary(contentsOfFile: Paths.appBundle + "/Contents/Info.plist"),
      let version = info["CFBundleShortVersionString"] as? String,
      isNewer(version, than: eightyVersion),
      version != rejected
    else { return }

    let staged = Paths.daemonBinary + ".new"
    let manager = FileManager.default
    do {
      try? manager.removeItem(atPath: staged)
      // Verify the copy, not the original, so what was checked is what runs.
      try manager.copyItem(atPath: Paths.appBundle + "/Contents/Helpers/eighty", toPath: staged)
      try manager.setAttributes([.posixPermissions: 0o755, .ownerAccountName: "root", .groupOwnerAccountName: "wheel"], ofItemAtPath: staged)
      guard Self.isSigned(path: staged, team: team) else {
        throw Rejected(description: "the app's eighty \(version) is not signed by team \(team)")
      }
      guard output(of: staged, "version") == version else {
        throw Rejected(description: "the app's eighty does not report version \(version)")
      }
      _ = try manager.replaceItemAt(URL(fileURLWithPath: Paths.daemonBinary), withItemAt: URL(fileURLWithPath: staged))
    } catch {
      try? manager.removeItem(atPath: staged)
      rejected = version
      warn("not updating to \(version): \(error)")
      return
    }
    exit(0)
  }

  private static func teamOfRunningCode() -> String? {
    var code: SecCode?
    var staticCode: SecStaticCode?
    var info: CFDictionary?
    guard
      SecCodeCopySelf([], &code) == errSecSuccess, let code,
      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
      SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
    else { return nil }
    return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
  }

  private static func isSigned(path: String, team: String) -> Bool {
    // Apple's designated requirement for a Developer ID application, pinned to our team.
    let text = """
      identifier "eighty" and anchor apple generic \
      and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
      and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
      and certificate leaf[subject.OU] = "\(team)"
      """
    var code: SecStaticCode?
    var requirement: SecRequirement?
    guard
      SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code,
      SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement
    else { return false }
    return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess
  }
}

private struct Rejected: Error, CustomStringConvertible {
  let description: String
}
