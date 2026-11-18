import AppKit
import ApplicationServices

/// Confirms the system's "Connection Request from: <device>" prompt.
///
/// macOS shows this prompt (owned by BluetoothUIServer) whenever an app
/// initiates pairing, and offers no API to skip it. The acceptor only acts while
/// armed — i.e. for a few seconds after this app itself connected to the device —
/// and only on a prompt that names the configured device.
final class PromptAcceptor {
    private static let bundleID = "com.apple.BluetoothUIServer"
    private static let acceptTitles: Set<String> = ["Connect", "Pair"]

    private(set) var isArmed = false
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var fallbackTimer: Timer?

    init() {
        // BluetoothUIServer is launched on demand; attach whenever it appears.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let app, app.bundleIdentifier == Self.bundleID { self?.observe(app.processIdentifier) }
        }
    }

    func arm() {
        isArmed = true
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first {
            observe(app.processIdentifier)
        }
        // Polling fallback in case a window notification is missed.
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.acceptIfPresent()
        }
    }

    func disarm() {
        isArmed = false
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    /// Get notified the instant BluetoothUIServer opens a window.
    private func observe(_ pid: pid_t) {
        guard AXIsProcessTrusted(), pid != observedPID else { return }
        let callback: AXObserverCallback = { _, _, _, context in
            Unmanaged<PromptAcceptor>.fromOpaque(context!).takeUnretainedValue().acceptIfPresent()
        }
        var newObserver: AXObserver?
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let newObserver else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(newObserver, AXUIElementCreateApplication(pid),
                                  kAXWindowCreatedNotification as CFString, context)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
        observedPID = pid
    }

    private func acceptIfPresent() {
        guard isArmed, AXIsProcessTrusted() else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID) {
            for window in AX.windows(of: app.processIdentifier) {
                guard AX.texts(in: window).contains(where: { $0.contains(Config.deviceName) }) else { continue }
                let button = AX.find(in: window) {
                    AX.role($0) == kAXButtonRole && Self.acceptTitles.contains(AX.label($0))
                }.first
                if let button, AX.press(button) {
                    Log.write("confirmed pairing prompt ('\(AX.label(button))')")
                    disarm()
                    return
                }
            }
        }
    }
}
