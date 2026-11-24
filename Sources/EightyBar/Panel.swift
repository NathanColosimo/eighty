import AppKit
import EightyCore
import EightyKit
import SwiftUI

struct Panel: View {
  let model: Model
  @State private var draftLimit: Double?

  private let limitRange = 50.0...100.0

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      setup
      Divider()
      limitSection
      Divider()
      heatSection
      if let error = model.error {
        notice(error)
      }
      Divider()
      footer
    }
    .padding(16)
    .frame(width: 290)
    .onAppear {
      model.refresh()
      model.checkDaemon()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .firstTextBaseline) {
        Text("Eighty").font(.headline)
        Spacer()
        if let reading = model.reading {
          Label("\(reading.percent)%", systemImage: reading.charging ? "bolt.fill" : "battery.75percent")
            .labelStyle(.titleAndIcon)
            .monospacedDigit()
          if let temperature = reading.temperature {
            Text(String(format: "%.1f °C", temperature))
              .foregroundStyle(temperatureColor(temperature))
              .monospacedDigit()
          }
        }
      }
      Text(stateLine)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var setup: some View {
    switch model.daemon {
    case .current:
      if let problem = model.health.problem {
        setupCard(title: "Eighty isn't working", detail: problem, action: "Restart Background Service", tint: .red)
      }
    case .missing:
      setupCard(
        title: "One more step",
        detail: "Eighty needs a small background service to control charging. macOS will ask for your password once.",
        action: "Install Background Service")
    case .outdated:
      setupCard(
        title: "Update the background service",
        detail: "It doesn't match this version of Eighty (\(eightyVersion)). macOS will ask for your password.",
        action: "Update Background Service")
    }
  }

  private func setupCard(title: String, detail: String, action: String, tint: Color = .accentColor) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline.weight(.semibold))
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(action, action: model.installDaemon)
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .controlSize(.regular)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
  }

  private var stateLine: String {
    if model.health != .ok { return "Not active" }
    if model.mode.isHeatPause { return "Paused for heat at \(model.target)%" }
    if model.reading?.charging == true { return "Charging to \(model.config.limit)%" }
    if model.config.limit == 100 { return "No limit" }
    return "Stops charging at \(model.config.limit)%"
  }

  private var limitSection: some View {
    let shown = Int(draftLimit ?? Double(model.config.limit))
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Charge limit")
        Spacer()
        Text(shown == 100 ? "Off" : "\(shown)%")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Slider(
        value: Binding(
          get: { draftLimit ?? Double(model.config.limit) },
          set: { draftLimit = $0 }),
        in: limitRange, step: 5
      ) { editing in
        if !editing, let draftLimit {
          model.setLimit(Int(draftLimit))
          self.draftLimit = nil
        }
      }
      HStack(spacing: 6) {
        ForEach([80, 90, 100], id: \.self) { preset in
          Button(preset == 100 ? "Full" : "\(preset)%") { model.setLimit(preset) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(model.config.limit == preset ? .accentColor : nil)
        }
      }
    }
  }

  private var heatSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle(isOn: Binding(get: { model.config.heat != nil }, set: model.setHeatEnabled)) {
        Text("Pause charging when hot")
      }
      .toggleStyle(.switch)
      .controlSize(.small)

      if let heat = model.config.heat {
        Stepper(value: Binding(get: { heat.pauseAt }, set: model.setPauseAt), in: 30...45, step: 1) {
          HStack {
            Text("Pause at")
            Spacer()
            Text("\(Int(heat.pauseAt)) °C").monospacedDigit().foregroundStyle(.secondary)
          }
        }
        Text("Resumes at \(Int(heat.resumeAt)) °C")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var footer: some View {
    HStack {
      Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
        .toggleStyle(.checkbox)
        .controlSize(.small)
      Spacer()
      Button("Quit") { NSApp.terminate(nil) }
        .controlSize(.small)
    }
  }

  private func notice(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(.orange)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func temperatureColor(_ celsius: Double) -> Color {
    guard let heat = model.config.heat else { return .secondary }
    if celsius >= heat.pauseAt { return .red }
    if celsius >= heat.resumeAt { return .orange }
    return .secondary
  }
}
