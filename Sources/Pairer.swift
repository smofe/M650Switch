import CoreBluetooth

/// Watches for the device advertising in pairing mode and connects to it.
/// Connecting makes macOS start pairing and show its confirmation prompt,
/// which `PromptAcceptor` then confirms.
final class Pairer: NSObject, CBCentralManagerDelegate {
    /// Consulted on every sighting; return false to leave the device alone.
    var shouldPair: () -> Bool = { true }
    var onAttemptStarted: (() -> Void)?
    var onAttemptFinished: ((_ success: Bool) -> Void)?
    var onBluetoothStateChange: ((CBManagerState) -> Void)?

    private var central: CBCentralManager!
    private let promptAcceptor = PromptAcceptor()
    private var target: CBPeripheral?
    private var timeout: DispatchWorkItem?
    private var lastFailure: [UUID: Date] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Restarts scanning so devices seen while we were not allowed to act are reported again.
    func rescan() {
        guard central.state == .poweredOn, target == nil else { return }
        central.stopScan()
        central.scanForPeripherals(withServices: nil)
    }

    /// Called when the device shows up as an input device on this Mac.
    func deviceDidConnect() {
        if target != nil { finish(success: true) }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onBluetoothStateChange?(central.state)
        if central.state == .poweredOn { rescan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false
        guard target == nil, connectable, name.contains(Config.deviceName), shouldPair() else { return }
        if let failed = lastFailure[peripheral.identifier], Date().timeIntervalSince(failed) < 30 { return }

        Log.write("\(name) is advertising — connecting")
        target = peripheral
        central.stopScan()
        central.connect(peripheral)
        promptAcceptor.arm()
        onAttemptStarted?()

        let timeout = DispatchWorkItem { [weak self] in
            Log.write("pairing timed out")
            self?.finish(success: false)
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.pairingTimeout, execute: timeout)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Touching the GATT database nudges macOS into the pairing flow.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Log.write("connection failed: \(error?.localizedDescription ?? "unknown error")")
        finish(success: false)
    }

    // MARK: - Private

    private func finish(success: Bool) {
        timeout?.cancel()
        promptAcceptor.disarm()
        // Only our app-level handle is closed; the system keeps the bonded HID link.
        if let target {
            central.cancelPeripheralConnection(target)
            // Don't nag with repeated prompts for a device that was just declined.
            if !success { lastFailure[target.identifier] = Date() }
        }
        target = nil
        if success { Log.write("paired ✓") }
        onAttemptFinished?(success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.rescan() }
    }
}
