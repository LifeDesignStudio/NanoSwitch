import Cocoa

class EventTapManager {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdogTimer: Timer?

    private weak var windowManager: WindowManager?
    private let switcherController = SwitcherWindowController()
    private let thumbnailFetcher = ThumbnailFetcher()
    private var lastThumbnails: [CGWindowID: NSImage] = [:]

    // MARK: - Init / Deinit

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        switcherController.onClose = { [weak self] windowInfo in
            self?.handleWindowClose(windowInfo)
        }
        setupEventTap()
    }

    deinit {
        watchdogTimer?.invalidate()
        if let tap = eventTap        { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource   { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }

    // MARK: - EventTap Setup
    // cghidEventTap（HIDレベル）で Cmd+Tab を含む全キーイベントを Dock より前に横取りする

    private func setupEventTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        )

        guard let tap else {
            NSLog("[NanoSwitch] ❌ EventTap 作成失敗。Accessibility権限を確認してください。")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[NanoSwitch] ✅ EventTap 作成成功（Cmd+Tab横取り有効）")
        startWatchdog()
    }

    // MARK: - Watchdog
    // メインスレッドが一時的にブロックされるなどでタップが無効化され、かつ次のイベントが
    // コールバックに届かず再有効化の起点を失った場合に備える安全網。2秒ごとに点検する。
    private func startWatchdog() {
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                NSLog("[NanoSwitch] ⚠️ Watchdog: EventTap が無効化されていたため再有効化")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(proxy: CGEventTapProxy,
                             type: CGEventType,
                             event: CGEvent) -> Unmanaged<CGEvent>? {

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            NSLog("[NanoSwitch] ⚠️ EventTap 無効化 (rawValue=%d)、再有効化", type.rawValue)
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // Cmd 離し → 選択確定
        if type == .flagsChanged {
            if !event.flags.contains(.maskCommand) && switcherController.isVisible {
                DispatchQueue.main.async { [weak self] in self?.confirmSelection() }
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasCmd   = event.flags.contains(.maskCommand)
        let hasShift = event.flags.contains(.maskShift)

        // Cmd+Tab / Cmd+Shift+Tab を消費してスイッチャーを起動
        // ※ cghidEventTap は Dock より前に処理されるため、ここで return nil すると
        //   システムの App Switcher には届かない
        if keyCode == 48 && hasCmd { // Tab
            DispatchQueue.main.async { [weak self] in
                self?.showOrAdvanceSwitcher(reverse: hasShift)
            }
            return nil // イベントを消費（Dock に渡さない）
        }

        // スイッチャー表示中のみナビゲーションキーを横取り
        guard switcherController.isVisible else { return Unmanaged.passRetained(event) }

        switch keyCode {
        case 36: // Return
            DispatchQueue.main.async { [weak self] in self?.confirmSelection() }
            return nil
        case 53: // Escape
            DispatchQueue.main.async { [weak self] in self?.cancelSwitcher() }
            return nil
        case 13: // W — close selected window
            DispatchQueue.main.async { [weak self] in self?.switcherController.closeSelectedWindow() }
            return nil
        case 123: // 左矢印
            DispatchQueue.main.async { [weak self] in self?.switcherController.moveSelection(by: -1) }
            return nil
        case 124: // 右矢印
            DispatchQueue.main.async { [weak self] in self?.switcherController.moveSelection(by: 1) }
            return nil
        case 125: // 下矢印
            DispatchQueue.main.async { [weak self] in self?.switcherController.moveSelection(by: SwitcherView.maxColumns) }
            return nil
        case 126: // 上矢印
            DispatchQueue.main.async { [weak self] in self?.switcherController.moveSelection(by: -SwitcherView.maxColumns) }
            return nil
        default:
            return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Switcher Logic

    private func showOrAdvanceSwitcher(reverse: Bool) {
        guard let wm = windowManager else {
            NSLog("[NanoSwitch] ⚠️ windowManager が nil")
            return
        }

        wm.updateWindowList()
        let windows = wm.getWindows()
        NSLog("[NanoSwitch] ウィンドウ取得件数: %d", windows.count)

        guard !windows.isEmpty else {
            NSLog("[NanoSwitch] ⚠️ 表示するウィンドウがありません")
            return
        }

        if !switcherController.isVisible {
            var initialThumbnails: [CGWindowID: NSImage] = [:]
            for w in windows {
                if let icon = w.app.icon { initialThumbnails[w.windowID] = icon }
            }
            lastThumbnails = initialThumbnails
            NSLog("[NanoSwitch] SwitcherWindowController.show() 呼び出し")
            switcherController.show(windows: windows,
                                    thumbnails: initialThumbnails,
                                    startAtEnd: reverse)

            thumbnailFetcher.fetchThumbnails(for: windows) { [weak self] thumbnails in
                guard let self, self.switcherController.isVisible else { return }
                let merged = initialThumbnails.merging(thumbnails) { _, new in new }
                self.lastThumbnails = merged
                self.switcherController.updateThumbnails(merged)
            }
        } else {
            switcherController.moveSelection(by: reverse ? -1 : 1)
        }
    }

    private func confirmSelection() {
        NSLog("[NanoSwitch] 選択確定")
        thumbnailFetcher.cancel()
        switcherController.activateSelectedWindow()
    }

    private func cancelSwitcher() {
        NSLog("[NanoSwitch] キャンセル")
        thumbnailFetcher.cancel()
        switcherController.dismiss()
    }

    private func handleWindowClose(_ windowInfo: WindowInfo) {
        guard let wm = windowManager else { return }
        thumbnailFetcher.cancel()
        wm.closeWindow(windowInfo)
        // 閉じたウィンドウのキャッシュは即座に破棄
        lastThumbnails.removeValue(forKey: windowInfo.windowID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.switcherController.isVisible else { return }
            wm.updateWindowList()
            // 閉じたウィンドウが CGWindowList になお残っていても確実に除外する
            // （AX クローズの反映遅延でゴーストのアイコンセルが残るのを防ぐ）
            let updated = wm.getWindows().filter { $0.windowID != windowInfo.windowID }
            guard !updated.isEmpty else {
                self.switcherController.dismiss()
                return
            }
            // 取得済みサムネイルを維持し、アイコンへのちらつきを防ぐ。未取得分のみアイコンで補完
            var placeholders: [CGWindowID: NSImage] = [:]
            for w in updated {
                placeholders[w.windowID] = self.lastThumbnails[w.windowID] ?? w.app.icon
            }
            self.lastThumbnails = placeholders
            self.switcherController.show(windows: updated, thumbnails: placeholders)
            self.thumbnailFetcher.fetchThumbnails(for: updated) { [weak self] thumbnails in
                guard let self, self.switcherController.isVisible else { return }
                let merged = placeholders.merging(thumbnails) { _, new in new }
                self.lastThumbnails = merged
                self.switcherController.updateThumbnails(merged)
            }
        }
    }
}
