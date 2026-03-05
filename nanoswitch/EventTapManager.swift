import Cocoa

class EventTapManager {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private weak var windowManager: WindowManager?
    private let switcherController = SwitcherWindowController()
    private let thumbnailFetcher = ThumbnailFetcher()

    // MARK: - Init / Deinit

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        setupEventTap()
    }

    deinit {
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
            NSLog("[NanoSwitch] SwitcherWindowController.show() 呼び出し")
            switcherController.show(windows: windows,
                                    thumbnails: initialThumbnails,
                                    startAtEnd: reverse)

            thumbnailFetcher.fetchThumbnails(for: windows) { [weak self] thumbnails in
                guard let self, self.switcherController.isVisible else { return }
                let merged = initialThumbnails.merging(thumbnails) { _, new in new }
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
}
