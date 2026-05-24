import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var windowManager: WindowManager?
    private var eventTapManager: EventTapManager?
    private let supportPopover = SupportPopoverController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        print("[NanoSwitch] ▶ applicationDidFinishLaunching")
        #endif
        NSApp.setActivationPolicy(.accessory)

        checkInstallLocation()

        // メニューバーアイコンは権限状態に関わらず常に最初に表示する
        setupStatusItem()

        startIfPermitted()
    }

    // MARK: - Permission Check & Startup

    private func startIfPermitted() {
        guard AXIsProcessTrustedWithOptions(nil) else {
            #if DEBUG
            print("[NanoSwitch] Accessibility権限: ❌ 未許可")
            #endif
            // 未許可のときだけシステムダイアログを表示
            AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            updateMenuForMissingPermission()
            pollForAccessibilityPermission()
            return
        }
        completeSetup()
    }

    /// システム設定でアクセシビリティを許可するまで1秒ごとに確認する（再起動不要）
    private func pollForAccessibilityPermission() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXIsProcessTrustedWithOptions(nil) else { return }
            timer.invalidate()
            self?.completeSetup()
        }
    }

    private func completeSetup() {
        #if DEBUG
        print("[NanoSwitch] Accessibility権限: ✅ 許可済み")
        #endif

        windowManager = WindowManager()
        guard let wm = windowManager else {
            NSLog("[NanoSwitch] ❌ WindowManager の初期化に失敗")
            return
        }
        eventTapManager = EventTapManager(windowManager: wm)

        if CGPreflightScreenCaptureAccess() {
            #if DEBUG
            print("[NanoSwitch] Screen Recording権限: ✅ 許可済み")
            #endif
            buildMainMenu()
        } else {
            #if DEBUG
            print("[NanoSwitch] Screen Recording権限: ⚠️ 未許可")
            #endif
            CGRequestScreenCaptureAccess()  // 初回のみシステムダイアログを表示
            updateMenuForMissingScreenRecording()
            pollForScreenRecordingPermission()
        }

        #if DEBUG
        print("[NanoSwitch] ✅ 初期化完了（スイッチャーは利用可能）")
        #endif
    }

    /// システム設定でスクリーン収録を許可するまで1秒ごとに確認する
    private func pollForScreenRecordingPermission() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard CGPreflightScreenCaptureAccess() else { return }
            timer.invalidate()
            #if DEBUG
            print("[NanoSwitch] Screen Recording権限: ✅ 許可済み（自動検知）")
            #endif
            self?.buildMainMenu()
        }
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

        let supportItem = NSMenuItem(title: "☕ Support NanoSwitch",
                                     action: #selector(showSupportPopover),
                                     keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit NanoSwitch",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showSupportPopover() {
        guard let button = statusItem?.button else { return }
        supportPopover.show(relativeTo: button)
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

        let hintItem = NSMenuItem(title: "許可後、自動的に有効になります", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

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

    /// スクリーン収録権限がない場合のメニュー表示（スイッチャー自体は動作する）
    private func updateMenuForMissingScreenRecording() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "NanoSwitch", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let warnItem = NSMenuItem(title: "⚠️ スクリーン収録権限が必要です", action: nil, keyEquivalent: "")
        warnItem.isEnabled = false
        menu.addItem(warnItem)

        let subItem = NSMenuItem(title: "サムネイル表示にはスクリーン収録が必要です", action: nil, keyEquivalent: "")
        subItem.isEnabled = false
        menu.addItem(subItem)

        let settingsItem = NSMenuItem(title: "システム設定を開く…",
                                      action: #selector(openScreenRecordingSettings),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let hintItem = NSMenuItem(title: "許可後、自動的に有効になります", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(NSMenuItem.separator())

        let supportItem = NSMenuItem(title: "☕ Support NanoSwitch",
                                     action: #selector(showSupportPopover),
                                     keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit NanoSwitch",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Install Location Check

    private func checkInstallLocation() {
        let path = Bundle.main.bundlePath
        guard !path.hasPrefix("/Applications/") else { return }

        let alert = NSAlert()
        alert.messageText = "Move NanoSwitch to Applications?"
        alert.informativeText = "NanoSwitch must run from /Applications/ for thumbnail previews to work.\n\nMove it there now?"
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let dest = "/Applications/NanoSwitch.app"
        do {
            if FileManager.default.fileExists(atPath: dest) {
                try FileManager.default.removeItem(atPath: dest)
            }
            try FileManager.default.moveItem(atPath: path, toPath: dest)
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [dest]
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("[NanoSwitch] ⚠️ 移動失敗: \(error)")
        }
    }

}
