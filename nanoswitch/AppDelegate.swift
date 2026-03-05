import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var windowManager: WindowManager?
    private var eventTapManager: EventTapManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[NanoSwitch] ▶ applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        // メニューバーアイコンは権限状態に関わらず常に最初に表示する
        setupStatusItem()

        startIfPermitted()
    }

    // MARK: - Permission Check & Startup

    private func startIfPermitted() {
        // Accessibility 権限チェック（未許可の場合はダイアログを表示）
        let axTrusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        print("[NanoSwitch] Accessibility権限: \(axTrusted ? "✅ 許可済み" : "❌ 未許可")")

        guard axTrusted else {
            // 自動終了せず、メニューに案内を表示してユーザーが再起動できるようにする
            print("[NanoSwitch] ⚠️ Accessibility未許可 → システム設定で許可後、アプリを再起動してください")
            updateMenuForMissingPermission()
            return
        }

        // Screen Recording 権限チェック（サムネイル取得に必要、任意）
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        let hasScreenRecording = CGPreflightScreenCaptureAccess()
        print("[NanoSwitch] Screen Recording権限: \(hasScreenRecording ? "✅ 許可済み" : "⚠️ 未許可（サムネイルはアイコンにフォールバック）")")

        windowManager = WindowManager()
        guard let wm = windowManager else {
            print("[NanoSwitch] ❌ WindowManager の初期化に失敗")
            return
        }
        eventTapManager = EventTapManager(windowManager: wm)

        print("[NanoSwitch] ✅ 初期化完了")
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                   accessibilityDescription: "NanoSwitch")
        }

        buildMainMenu()
    }

    private func buildMainMenu() {
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "NanoSwitch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "終了",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    /// Accessibility 権限がない場合のメニュー表示
    private func updateMenuForMissingPermission() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()

        let warnItem = NSMenuItem(title: "⚠️ Accessibility 権限が必要です", action: nil, keyEquivalent: "")
        warnItem.isEnabled = false
        menu.addItem(warnItem)

        let settingsItem = NSMenuItem(title: "システム設定を開く…",
                                      action: #selector(openAccessibilitySettings),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "許可後にここから再起動",
                                     action: #selector(relaunch),
                                     keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "終了",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            NSApp.terminate(nil)
        }
    }
}
