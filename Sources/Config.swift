import Foundation

/// Everything that is specific to the managed device lives here.
/// To adapt M650Switch to another single-host Bluetooth LE mouse or keyboard,
/// change these values (find them with `ioreg -r -c IOHIDDevice -l`).
enum Config {
    /// Name shown in the menu bar panel.
    static let displayName = "Logi M650"
    /// Substring of the device's Bluetooth name, used to recognise it.
    static let deviceName = "M650"
    /// USB-IF vendor ID (Logitech = 0x046D).
    static let vendorID = 0x046D
    /// Product ID (Logitech Signature M650 = 0xB02A).
    static let productID = 0xB02A

    /// How long a Mac ignores the device after it disconnected, so that the
    /// *other* Mac wins the race to pair it.
    static let defaultYieldSeconds = 10
    /// How long to wait for a pairing attempt to complete.
    static let pairingTimeout: TimeInterval = 25
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/M650Switch.log")
    private static let formatter = ISO8601DateFormatter()

    static func write(_ message: String) {
        let line = Data("\(formatter.string(from: Date())) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
