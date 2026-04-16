import SwiftUI
import AppKit

@main
struct miniMapSpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: FloatingPanel?
    let spacesManager = SpacesManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        checkAccessibilityPermission()

        panel = makeFloatingPanel(manager: spacesManager)
        panel?.orderFrontRegardless()
    }

    private func checkAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
