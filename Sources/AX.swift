import AppKit
import ApplicationServices

/// Minimal helpers around the Accessibility API.
enum AX {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func role(_ element: AXUIElement) -> String { string(element, kAXRoleAttribute) ?? "" }
    static func value(_ element: AXUIElement) -> String { string(element, kAXValueAttribute) ?? "" }
    static func description(_ element: AXUIElement) -> String { string(element, kAXDescriptionAttribute) ?? "" }

    /// Title, falling back to the description (icon buttons only have the latter).
    static func label(_ element: AXUIElement) -> String {
        string(element, kAXTitleAttribute).flatMap { $0.isEmpty ? nil : $0 } ?? description(element)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        attribute(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// All elements in the subtree (depth-first, pre-order) matching `predicate`.
    static func find(in root: AXUIElement, maxDepth: Int = 20,
                     where predicate: (AXUIElement) -> Bool) -> [AXUIElement] {
        var result: [AXUIElement] = []
        func visit(_ element: AXUIElement, depth: Int) {
            if predicate(element) { result.append(element) }
            guard depth < maxDepth else { return }
            for child in children(element) { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return result
    }

    /// Every title/value/description string in the subtree.
    static func texts(in root: AXUIElement) -> [String] {
        var result: [String] = []
        _ = find(in: root, maxDepth: 14) { element in
            for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                if let text = string(element, key), !text.isEmpty { result.append(text) }
            }
            return false
        }
        return result
    }

    /// Re-evaluates `probe` every 100 ms until it returns a value or `timeout` passes.
    static func waitFor<T>(timeout: TimeInterval, _ probe: @escaping () -> T?,
                           then completion: @escaping (T?) -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func tick() {
            if let value = probe() { return completion(value) }
            if Date() > deadline { return completion(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: tick)
        }
        tick()
    }
}
