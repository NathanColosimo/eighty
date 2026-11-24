// Renders an SVG to a PNG with WebKit, as a browser would draw it (2x on a Retina Mac).
//   swift scripts/svg-to-png.swift docs/battery-wear.svg docs/battery-wear.png
import AppKit
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
  let output: URL
  init(output: URL) { self.output = output }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    let config = WKSnapshotConfiguration()
    // Points; the snapshot comes back at the display scale (2x on Retina).
    config.snapshotWidth = NSNumber(value: Double(webView.frame.width))
    webView.takeSnapshot(with: config) { image, error in
      guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        fatalError("snapshot failed: \(String(describing: error))")
      }
      try! rep.representation(using: .png, properties: [:])!.write(to: self.output)
      exit(0)
    }
  }
}

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: svg-to-png.swift <in.svg> <out.png>") }
let input = URL(fileURLWithPath: args[1]).absoluteURL
let svg = try! String(contentsOf: input, encoding: .utf8)
let size = NSImage(contentsOf: input)!.size

let renderer = Renderer(output: URL(fileURLWithPath: args[2]))
let web = WKWebView(frame: NSRect(origin: .zero, size: size))
web.navigationDelegate = renderer
web.loadHTMLString("<html><body style='margin:0'>\(svg)</body></html>", baseURL: nil)
RunLoop.main.run()
