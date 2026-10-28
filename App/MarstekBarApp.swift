import AppKit
import MarstekKit
import SwiftUI

@main
struct MarstekBarApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra(isInserted: $state.showMenuBarIcon) {
            MenuPanelView(state: state)
        } label: {
            Image(systemName: state.menuBarSymbol)
            Text(state.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}

/// With the menu bar icon hidden, launching the app again brings it back.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppGroup.defaults.set(true, forKey: "showMenuBarIcon")
        NotificationCenter.default.post(name: .showMenuBarIcon, object: nil)
        return true
    }
}

extension Notification.Name {
    static let showMenuBarIcon = Notification.Name("MarstekBar.showMenuBarIcon")
}
