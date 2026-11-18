import SwiftUI
import CoreBluetooth

// MARK: - Presentation state

extension AppState {
    enum Tone { case good, busy, neutral, warning }

    var menuBarSymbol: String {
        switch activity {
        case .cleaning: return "sparkles"
        case .pairing: return "computermouse.fill"
        case .idle: return isConnectedHere ? "computermouse.fill" : "computermouse"
        }
    }

    var status: (text: String, tone: Tone) {
        switch bluetoothState {
        case .unauthorized: return ("Bluetooth access needed", .warning)
        case .poweredOff: return ("Bluetooth is off", .warning)
        default: break
        }
        switch activity {
        case .pairing: return ("Pairing…", .busy)
        case .cleaning: return ("Removing old pairings…", .busy)
        case .idle: break
        }
        if isConnectedHere { return ("Connected to this Mac", .good) }
        if isYielding { return ("Handing off to your other Mac", .busy) }
        if !autoPair { return ("Paused", .neutral) }
        return ("Ready to take over", .neutral)
    }
}

// MARK: - Panel

struct MenuPanel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Header()
            HandOffCard()
            CleanupCard()
            if !state.hasAccessibility || state.bluetoothState == .unauthorized {
                PermissionsCard()
            }
            Footer()
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct Header: View {
    @EnvironmentObject private var state: AppState

    private var tint: Color {
        switch state.status.tone {
        case .good: return .green
        case .busy: return .blue
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.gradient.opacity(state.status.tone == .neutral ? 0.25 : 0.9))
                Image(systemName: state.isConnectedHere ? "computermouse.fill" : "computermouse")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(state.status.tone == .neutral ? Color.primary : .white)
                    .symbolEffect(.pulse, isActive: state.activity != .idle || state.isYielding)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(Config.displayName).font(.system(size: 13, weight: .semibold))
                Text(state.status.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: state.status.text)
            }

            Spacer()

            Toggle("Auto-pair", isOn: $state.autoPair)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help("Take over the device automatically when it enters pairing mode")
        }
        .padding(.horizontal, 2)
    }
}

private struct HandOffCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Card(title: "Hand-off", symbol: "arrow.left.arrow.right") {
            if let until = state.yieldingUntil, state.isYielding {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let remaining = max(0, until.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: remaining, total: Double(state.yieldSeconds))
                            .tint(.blue)
                        Text("This Mac stays out of the way for \(Int(remaining.rounded(.up))) s")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("Hold the pairing button under the mouse for 3 s — the Mac that doesn't have it takes over.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Yield time").font(.system(size: 12))
                Spacer()
                Picker("Yield time", selection: $state.yieldSeconds) {
                    ForEach([5, 10, 20, 30], id: \.self) { Text("\($0)s").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
            }

            if let lastSwitch = state.lastSwitch {
                Text("Last switch \(lastSwitch, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct CleanupCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Card(title: "Old pairings", symbol: "sparkles") {
            HStack {
                if state.staleEntryCount == 0 {
                    Label("All clean", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                } else {
                    Text("\(state.staleEntryCount) stale \(state.staleEntryCount == 1 ? "entry" : "entries")")
                        .font(.system(size: 12))
                        .monospacedDigit()
                }
                Spacer()
                Button(state.activity == .cleaning ? "Cleaning…" : "Clean up", action: state.cleanUp)
                    .controlSize(.small)
                    .disabled(state.staleEntryCount == 0 || state.activity != .idle || !state.hasAccessibility)
            }
            Toggle("Clean up after each switch", isOn: $state.autoClean)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
        }
    }
}

private struct PermissionsCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Card(title: "Permissions", symbol: "lock.shield") {
            if state.bluetoothState == .unauthorized {
                row("Bluetooth", symbol: "dot.radiowaves.left.and.right") {
                    state.openPrivacySettings("Privacy_Bluetooth")
                }
            }
            if !state.hasAccessibility {
                row("Accessibility", symbol: "accessibility", action: state.requestAccessibility)
            }
        }
    }

    private func row(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: symbol).font(.system(size: 12))
            Spacer()
            Button("Grant…", action: action).controlSize(.small)
        }
    }
}

private struct Footer: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Open at login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.launchAtLogin = $0 }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Spacer()

            Button { NSWorkspace.shared.open(Log.url) } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Open log")

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(.horizontal, 2)
    }
}

/// Rounded, subtly tinted container used for each section.
private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}
