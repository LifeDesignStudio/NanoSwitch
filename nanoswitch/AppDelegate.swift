import Cocoa
import ServiceManagement
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {

    // Sparkle 自動更新コントローラ（SUFeedURL / SUPublicEDKey は Info.plist 参照）。
    // startingUpdater: true で定期チェックを自動開始する。
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private enum Link {
        static let github = URL(string: "https://github.com/LifeDesignStudio/NanoSwitch")!
    }

    private static let didSetupLoginItemKey = "com.lifedesign.nanoswitch.didSetupLoginItem"

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
        // EventTap の状態変化（失効・再有効化）をメニューの健全性表示に反映する
        eventTapManager?.onStateChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshMenu() }
        }

        // 初回起動時はログイン項目に自動登録する（再起動後も Cmd+Tab 乗っ取りを維持）。
        // メニューのトグルでいつでも解除可能。
        registerLoginItemIfFirstLaunch()

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
        menu.addItem(makeTitleItem())

        // 健全性：アクセシビリティは許可済みのはずなのに EventTap が無効な場合は警告する
        // （プライベート API の失効・権限剥奪・OS 側のタップ無効化を可視化）
        if let etm = eventTapManager, !etm.isActive {
            let warn = NSMenuItem(title: "⚠️ Cmd+Tab を横取りできていません", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
            let hint = NSMenuItem(title: "権限を再付与するか、アプリを再起動してください", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(NSMenuItem.separator())
        appendCommonItems(to: menu)
        statusItem?.menu = menu
    }

    /// 現在の権限状態に応じて適切なメニューを再構築する（トグル操作後などに呼ぶ）
    private func refreshMenu() {
        guard AXIsProcessTrustedWithOptions(nil) else {
            updateMenuForMissingPermission()
            return
        }
        if CGPreflightScreenCaptureAccess() {
            buildMainMenu()
        } else {
            updateMenuForMissingScreenRecording()
        }
    }

    // MARK: - Menu Building Helpers

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "v\(v)"
    }

    private func makeTitleItem() -> NSMenuItem {
        let item = NSMenuItem(title: "NanoSwitch \(appVersionString)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Launch at Login / Support / Help / About / Quit の共通フッターを追加する
    private func appendCommonItems(to menu: NSMenu) {
        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let supportItem = NSMenuItem(title: "☕ Support NanoSwitch",
                                     action: #selector(showSupportPopover),
                                     keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…",
                                     action: #selector(checkForUpdates),
                                     keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        let helpItem = NSMenuItem(title: "Help & GitHub…",
                                  action: #selector(openHelp),
                                  keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        let aboutItem = NSMenuItem(title: "About NanoSwitch",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit NanoSwitch",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    @objc private func showSupportPopover() {
        guard let button = statusItem?.button else { return }
        supportPopover.show(relativeTo: button)
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func openHelp() {
        NSWorkspace.shared.open(Link.github)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "ウィンドウ単位で切り替える macOS 用スイッチャー\n\(Link.github.absoluteString)",
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "NanoSwitch",
            .credits: credits
        ])
    }

    // MARK: - Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 初回起動時のみ自動でログイン項目へ登録する（以降はユーザーのトグル操作に委ねる）
    private func registerLoginItemIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: AppDelegate.didSetupLoginItemKey) else { return }
        UserDefaults.standard.set(true, forKey: AppDelegate.didSetupLoginItemKey)
        do {
            try SMAppService.mainApp.register()
            #if DEBUG
            print("[NanoSwitch] ログイン項目に自動登録しました（初回起動）")
            #endif
        } catch {
            NSLog("[NanoSwitch] ⚠️ ログイン項目の自動登録に失敗: %@", error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[NanoSwitch] ⚠️ Launch at Login の切替に失敗: %@", error.localizedDescription)
        }
        refreshMenu()
    }

    /// Accessibility 権限がない場合のメニュー表示
    private func updateMenuForMissingPermission() {
        let menu = NSMenu()
        menu.addItem(makeTitleItem())
        menu.addItem(NSMenuItem.separator())

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

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        let aboutItem = NSMenuItem(title: "About NanoSwitch",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit NanoSwitch",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// スクリーン収録権限がない場合のメニュー表示（スイッチャー自体は動作する）
    private func updateMenuForMissingScreenRecording() {
        let menu = NSMenu()
        menu.addItem(makeTitleItem())
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
        appendCommonItems(to: menu)
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

        // DMG で /Applications への配置を誘導するため、プログラム的な自動移動は行わず警告のみ。
        // ※ translocation 下では Bundle.main.bundlePath が読み取り専用の乱数パスになり、
        //   move が破綻するため撤去（DMG のドラッグ導線で最初から正しい場所に入れてもらう）。
        let alert = NSAlert()
        alert.messageText = "Move NanoSwitch to Applications"
        alert.informativeText = "NanoSwitch must run from the /Applications folder for window thumbnails to work.\n\nQuit, drag NanoSwitch into /Applications, then reopen it."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Anyway")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

}
