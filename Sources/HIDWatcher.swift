import Foundation
import IOKit
import IOKit.hid

/// Reports whether the device is currently connected to this Mac as an input
/// device. Uses IOKit registry notifications, which need no permission.
final class HIDWatcher {
    var onChange: ((Bool) -> Void)?
    private(set) var isConnected = false

    private let port = IONotificationPortCreate(kIOMainPortDefault)
    private var iterators: [io_iterator_t] = []

    init() {
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()

        for event in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            IOServiceAddMatchingNotification(port, event, Self.matchingDictionary(), { context, iterator in
                let watcher = Unmanaged<HIDWatcher>.fromOpaque(context!).takeUnretainedValue()
                drain(iterator)
                // A terminated service can linger in the registry for a moment.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { watcher.update() }
            }, context, &iterator)
            drain(iterator) // arms the notification
            iterators.append(iterator)
        }
        isConnected = Self.deviceCount() > 0
    }

    private func update() {
        let connected = Self.deviceCount() > 0
        guard connected != isConnected else { return }
        isConnected = connected
        onChange?(connected)
    }

    private static func matchingDictionary() -> CFDictionary {
        let dict = IOServiceMatching("IOHIDDevice") as NSMutableDictionary
        dict[kIOHIDVendorIDKey] = Config.vendorID
        dict[kIOHIDProductIDKey] = Config.productID
        dict[kIOHIDTransportKey] = "Bluetooth Low Energy"
        return dict
    }

    private static func deviceCount() -> Int {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary(), &iterator) == KERN_SUCCESS
        else { return 0 }
        defer { IOObjectRelease(iterator) }
        return drain(iterator)
    }
}

/// Releases every object in an IOKit iterator and returns how many there were.
@discardableResult
private func drain(_ iterator: io_iterator_t) -> Int {
    var count = 0
    while case let object = IOIteratorNext(iterator), object != 0 {
        IOObjectRelease(object)
        count += 1
    }
    return count
}
