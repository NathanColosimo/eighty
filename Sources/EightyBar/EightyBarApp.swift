import AppKit
import EightyCore
import SwiftUI

@main
struct EightyBarApp: App {
  @State private var model = Model()

  var body: some Scene {
    MenuBarExtra {
      Panel(model: model)
    } label: {
      Image(nsImage: menuBarIcon(limit: model.config.limit, mode: model.mode, healthy: model.health == .ok))
    }
    .menuBarExtraStyle(.window)
  }
}

/// A shield with a bolt and the charge limit ("protected charging, up to 80"),
/// drawn unlike a battery so it can't be mistaken for the current charge. While
/// paused for heat, a thermometer and the held percentage. With no limit, the
/// shield alone. A warning shield when the background service isn't working.
/// Template, so it follows the menu bar's colour.
@MainActor func menuBarIcon(limit: Int, mode: Mode, healthy: Bool) -> NSImage {
  let symbolName: String
  let number: String?
  switch mode {
  case _ where !healthy:
    (symbolName, number) = ("exclamationmark.shield", nil)
  case .heatPaused(let percent):
    (symbolName, number) = ("thermometer.medium", "\(min(percent, limit))")
  case .limiting:
    (symbolName, number) = ("bolt.shield", limit == 100 ? nil : "\(limit)")
  }
  let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Eighty")!
    .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))!
  let text = number.map {
    NSAttributedString(string: $0, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)])
  }
  let gap: CGFloat = text == nil ? 0 : 2
  let size = NSSize(width: ceil(symbol.size.width + gap + (text?.size().width ?? 0)), height: 16)

  let image = NSImage(size: size, flipped: false) { _ in
    symbol.draw(at: NSPoint(x: 0, y: (size.height - symbol.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
    if let text {
      text.draw(at: NSPoint(x: symbol.size.width + gap, y: (size.height - text.size().height) / 2))
    }
    return true
  }
  image.isTemplate = true
  return image
}
