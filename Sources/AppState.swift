import AppKit
import CoreBluetooth
import ServiceManagement

/// Ties the components together and holds everything the UI shows.
/// All callbacks arrive on the main queue.
final class AppState: ObservableObject {
    enum Activity { case idle, pairing, cleaning }

    @Published private(set) var activity = Activity.idle
    @Published private(set) var isConnectedHere = false
    @Published private(set) var yieldingUntil: Date?
    @Published private(set) var staleEntryCount = 0
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()
    @Published private(set) var bluetoothState = CBManagerState.unknown
    @Published private(set) var lastSwitch = Settings.lastSwitch

    @Published var autoPair = Settings.autoPair {
        didSet { Settings.autoPair = autoPair; if autoPair { pairer.rescan() } }
    }
    @Published var autoClean = Settings.autoClean {
        didSet { Settings.autoClean = autoClean }
    }
    @Published var yieldSeconds = Settings.yieldSeconds {
        didSet { Settings.yieldSeconds = yieldSeconds }
    }

    var isYielding: Bool { (yieldingUntil ?? .distantPast) > Date() }

    private let hid = HIDWatcher()
    private let pairer = Pairer()
    private let cleaner = Cleaner()
    private var refreshTimer: Timer?

    init() {
        isConnectedHere = hid.isConnected
        Log.write("started (device connected here: \(isConnectedHere), accessibility: \(hasAccessibility))")

        hid.onChange = { [weak self] connected in self?.deviceConnectionChanged(connected) }

        pairer.shouldPair = { [weak self] in
            guard let self else { return false }
            return autoPair && !isYielding && !isConnectedHere && activity == .idle
        }
        pairer.onAttemptStarted = { [weak self] in self?.activity = .pairing }
        pairer.onAttemptFinished = { [weak self] success in self?.pairingFinished(success) }
        pairer.onBluetoothStateChange = { [weak self] state in self?.bluetoothState = state }

        // Cheap periodic refresh for things without change notifications.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func cleanUp() {
        guard activity == .idle, hasAccessibility, staleEntryCount > 0 else { return }
        activity = .cleaning
        cleaner.run { [weak self] removed in
            Log.write("removed \(removed) stale entries")
            self?.activity = .idle
            self?.refresh()
        }
    }

    // MARK: - Events

    private func deviceConnectionChanged(_ connected: Bool) {
        isConnectedHere = connected
        if connected {
            Log.write("device connected")
            yieldingUntil = nil
            pairer.deviceDidConnect()
        } else {
            // The device most likely went into pairing mode for the other Mac.
            // Stay out of the race for a moment so the other Mac gets it.
            Log.write("device disconnected — yielding for \(yieldSeconds)s")
            let until = Date().addingTimeInterval(TimeInterval(yieldSeconds))
            yieldingUntil = until
            DispatchQueue.main.asyncAfter(deadline: .now() + until.timeIntervalSinceNow + 0.1) { [weak self] in
                guard let self, yieldingUntil == until else { return }
                yieldingUntil = nil
                pairer.rescan()
            }
        }
        refresh()
    }

    private func pairingFinished(_ success: Bool) {
        activity = .idle
        if success {
            lastSwitch = Date()
            Settings.lastSwitch = lastSwitch
            if autoClean {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.cleanUp() }
            }
        }
        refresh()
    }

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility { hasAccessibility = trusted }
        let stale = max(0, Cleaner.pairedEntryCount() - (isConnectedHere ? 1 : 0))
        if stale != staleEntryCount { staleEntryCount = stale }
    }

    // MARK: - System integration

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.write("could not change login item: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        openPrivacySettings("Privacy_Accessibility")
    }

    func openPrivacySettings(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

/// Persisted user preferences.
private enum Settings {
    private static let defaults = UserDefaults.standard

    static var autoPair: Bool {
        get { defaults.object(forKey: "autoPair") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoPair") }
    }
    static var autoClean: Bool {
        get { defaults.object(forKey: "autoClean") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoClean") }
    }
    static var yieldSeconds: Int {
        get { defaults.object(forKey: "yieldSeconds") as? Int ?? Config.defaultYieldSeconds }
        set { defaults.set(newValue, forKey: "yieldSeconds") }
    }
    static var lastSwitch: Date? {
        get { defaults.object(forKey: "lastSwitch") as? Date }
        set { defaults.set(newValue, forKey: "lastSwitch") }
    }
}
