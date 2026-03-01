import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    var windowManager: WindowManager!
    var eventTapManager: EventTapManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dockに表示しない
        NSApp.setActivationPolicy(.accessory)

        // Accessibility 権限チェック（未許可の場合はダイアログ表示して終了）
        guard checkAccessibilityPermissions() else { return }

        setupStatusItem()

        windowManager = WindowManager()
        eventTapManager = EventTapManager(windowManager: windowManager)
    }

    // MARK: - Accessibility

    private func checkAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            // 権限付与後に再起動が必要なためアプリを終了
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApp.terminate(nil)
            }
            return false
        }
        return true
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "NanoSwitch")
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "NanoSwitch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }
}
