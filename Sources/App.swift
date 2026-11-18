import SwiftUI

@main
struct M650SwitchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel().environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}
