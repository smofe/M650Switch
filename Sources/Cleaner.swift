import AppKit
import ApplicationServices
import IOBluetooth

/// Removes stale pairings of the device.
///
/// Every re-pair leaves an orphaned entry behind. macOS only accepts unpair
/// requests from Apple-signed processes, so this drives System Settings →
/// Bluetooth instead: Show Detail → Forget This Device… → Forget Device.
///
/// The UI strings below match an English system language.
final class Cleaner {
    private static let settingsBundleID = "com.apple.systempreferences"
    private static let bluetoothPane = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!

    private var completion: ((Int) -> Void)?
    private var removed = 0
    private var attemptsLeft = 0
    private var settingsWasRunning = false

    /// Number of paired entries for the device, connected one included.
    static func pairedEntryCount() -> Int {
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.filter { ($0.name ?? "").contains(Config.deviceName) }.count
    }

    /// Forgets every entry of the device that is "Not Connected", then calls back with the count.
    func run(completion: @escaping (Int) -> Void) {
        self.completion = completion
        removed = 0
        settingsWasRunning = settingsApp() != nil

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(Self.bluetoothPane, configuration: configuration)

        AX.waitFor(timeout: 8, { () -> [AXUIElement]? in
            guard let window = self.window(), self.deviceListIsLoaded(in: window) else { return nil }
            return Self.staleDetailButtons(in: window)
        }, then: { buttons in
            guard let buttons else { return self.finish(error: "Bluetooth settings did not load") }
            self.attemptsLeft = buttons.count + 2 // safety net against loops
            self.forgetNext()
        })
    }

    private func forgetNext() {
        guard attemptsLeft > 0 else { return finish(error: "too many attempts") }
        attemptsLeft -= 1
        guard let window = window(), let detailButton = Self.staleDetailButtons(in: window).first
        else { return finish(error: nil) }
        let staleBefore = Self.staleDetailButtons(in: window).count
        AX.press(detailButton)

        // Step 1: the detail sheet must be about our device.
        AX.waitFor(timeout: 4, { () -> AXUIElement? in
            guard let sheet = self.sheets().first,
                  AX.texts(in: sheet).contains(where: { $0.contains(Config.deviceName) }) else { return nil }
            return AX.find(in: sheet) { AX.description($0) == "Forget This Device…" }.first
        }, then: { forgetButton in
            guard let forgetButton else { return self.abort("detail sheet not found") }
            AX.press(forgetButton)

            // Step 2: the confirmation is nested inside the detail sheet, so it is the last sheet.
            AX.waitFor(timeout: 4, { () -> AXUIElement? in
                guard let confirmation = self.sheets().last,
                      AX.texts(in: confirmation).contains(where: {
                          $0.contains("forget") && $0.contains(Config.deviceName) }) else { return nil }
                return AX.children(confirmation).first { AX.description($0) == "Forget Device" }
            }, then: { confirmButton in
                guard let confirmButton else { return self.abort("confirmation not found") }
                AX.press(confirmButton)
                self.removed += 1

                // Step 3: wait for the list to update before the next round.
                AX.waitFor(timeout: 5, { () -> Bool? in
                    guard let window = self.window(), self.sheets().isEmpty,
                          Self.staleDetailButtons(in: window).count < staleBefore else { return nil }
                    return true
                }, then: { _ in self.forgetNext() })
            })
        })
    }

    /// In "My Devices" each device is a run of siblings:
    /// [name text, status text, "Show Detail" button].
    private static func staleDetailButtons(in window: AXUIElement) -> [AXUIElement] {
        AX.find(in: window, maxDepth: 12) { AX.role($0) == kAXGroupRole }.flatMap { group in
            let items = AX.children(group)
            return items.indices.dropLast(2).compactMap { i -> AXUIElement? in
                let (name, status, button) = (items[i], items[i + 1], items[i + 2])
                let isStale = AX.value(name).contains(Config.deviceName)
                    && AX.value(status).hasPrefix("Not Connected")
                    && AX.role(button) == kAXButtonRole
                    && AX.description(button) == "Show Detail"
                return isStale ? button : nil
            }
        }
    }

    private func abort(_ reason: String) {
        for label in ["Cancel", "Done"] {
            for sheet in sheets().reversed() {
                if let button = AX.find(in: sheet, where: { AX.description($0) == label }).first { AX.press(button) }
            }
        }
        finish(error: reason)
    }

    private func finish(error: String?) {
        if let error { Log.write("cleanup stopped: \(error)") }
        if !settingsWasRunning { settingsApp()?.terminate() }
        completion?(removed)
        completion = nil
    }

    // MARK: - System Settings access

    private func settingsApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.settingsBundleID).first
    }

    private func window() -> AXUIElement? {
        settingsApp().flatMap { AX.windows(of: $0.processIdentifier).first }
    }

    private func sheets() -> [AXUIElement] {
        window().map { AX.find(in: $0, maxDepth: 5) { AX.role($0) == "AXSheet" } } ?? []
    }

    private func deviceListIsLoaded(in window: AXUIElement) -> Bool {
        !AX.find(in: window, maxDepth: 8) { AX.description($0) == "My Devices" }.isEmpty
    }
}
