import Cocoa

// Private API: AXUIElement から CGWindowID を直接取得
// AXWindowID 属性を公開しないアプリ（Chrome 等）でも機能する
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                    _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

class SwitcherWindowController {

    private var panel: NSPanel?
    private var switcherView: SwitcherView?
    private var visualEffectView: NSVisualEffectView?
    private var currentWindows: [WindowInfo] = []
    var onClose: ((WindowInfo) -> Void)?

    // MARK: - Public

    var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    func show(windows: [WindowInfo],
              thumbnails: [CGWindowID: NSImage],
              startAtEnd: Bool = false) {
        guard !windows.isEmpty else { return }
        currentWindows = windows
        #if DEBUG
        print("[NanoSwitch] SwitcherWindowController.show() - \(windows.count) ウィンドウ")
        #endif

        if panel == nil {
            createPanel()
        }

        let preferredSize = SwitcherView.preferredSize(for: windows.count)

        // 画面中央に配置（マウスカーソルのある画面を優先）
        let activeScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                        ?? NSScreen.main
        if let screen = activeScreen {
            let sf = screen.visibleFrame
            let origin = NSPoint(x: sf.midX - preferredSize.width / 2,
                                 y: sf.midY - preferredSize.height / 2)
            panel?.setFrame(NSRect(origin: origin, size: preferredSize), display: false)
        }

        // ビューサイズ更新
        visualEffectView?.frame = NSRect(origin: .zero, size: preferredSize)
        switcherView?.frame = NSRect(origin: .zero, size: preferredSize)
        switcherView?.configure(windows: windows, thumbnails: thumbnails)

        if startAtEnd {
            switcherView?.selectedIndex = max(0, windows.count - 1)
        }

        let alreadyVisible = isVisible
        if !alreadyVisible { panel?.alphaValue = 0 }
        panel?.orderFrontRegardless()
        panel?.makeFirstResponder(switcherView)
        if !alreadyVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel?.animator().alphaValue = 1.0
            }
        } else {
            panel?.alphaValue = 1.0
        }
        #if DEBUG
        print("[NanoSwitch] パネル表示完了。isVisible=\(panel?.isVisible ?? false), frame=\(panel?.frame ?? .zero)")
        #endif
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel?.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1.0
            self?.currentWindows = []
            self?.switcherView?.configure(windows: [], thumbnails: [:])
        })
    }

    /// サムネイルだけを差し替える（パネル再配置・再front化なし）
    func updateThumbnails(_ thumbnails: [CGWindowID: NSImage]) {
        switcherView?.configure(windows: currentWindows, thumbnails: thumbnails)
    }

    func moveSelection(by delta: Int) {
        switcherView?.moveSelection(by: delta)
    }

    func activateSelectedWindow() {
        guard let windowInfo = switcherView?.activateSelectedWindow() else { return }
        dismiss()
        activateWindow(windowInfo)
    }

    func closeSelectedWindow() {
        guard let windowInfo = switcherView?.activateSelectedWindow() else { return }
        onClose?(windowInfo)
    }

    // MARK: - Panel Setup

    private func createPanel() {
        let view = SwitcherView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))
        view.onActivate = { [weak self] windowInfo in
            self?.dismiss()
            self?.activateWindow(windowInfo)
        }
        view.onDismiss = { [weak self] in
            self?.dismiss()
        }
        view.onClose = { [weak self] windowInfo in
            self?.onClose?(windowInfo)
        }
        switcherView = view

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.addSubview(view)
        visualEffectView = effectView

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .modalPanel
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.contentView = effectView
        newPanel.acceptsMouseMovedEvents = true
        // 全Spaceおよびフルスクリーンアプリの上に表示するために必要
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel = newPanel
        #if DEBUG
        print("[NanoSwitch] NSPanel 作成完了")
        #endif
    }

    // MARK: - Window Activation

    /// _AXUIElementGetWindow で CGWindowID を取得する（Chrome など AXWindowID 属性未公開アプリにも対応）
    private func cgWindowID(for axWindow: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        guard _AXUIElementGetWindow(axWindow, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    private func activateWindow(_ windowInfo: WindowInfo) {
        let axApp = AXUIElementCreateApplication(windowInfo.ownerPID)
        // 応答しないアプリで AX 呼び出しがメインスレッドを既定 ~6 秒ブロックするのを防ぐ
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {

            // 1st: CGWindowID でマッチ（最も確実）
            var target: AXUIElement? = axWindows.first(where: {
                guard let wid = cgWindowID(for: $0) else { return false }
                return wid == windowInfo.windowID
            })

            if target == nil {
                // アクティベート時点の最新情報で照合（スナップショット後のタイトル変更・移動に対応）
                let (freshBounds, freshTitle) = currentCGInfo(for: windowInfo.windowID)

                // 2nd: タイトルでフォールバック
                if let title = freshTitle, !title.isEmpty {
                    target = axWindows.first(where: {
                        var ref: CFTypeRef?
                        guard AXUIElementCopyAttributeValue($0, kAXTitleAttribute as CFString, &ref) == .success,
                              let t = ref as? String else { return false }
                        return t == title
                    })
                }

                // 3rd: 位置・サイズでフォールバック（Chrome の複数ウィンドウ対応）
                // CGWindowBounds は CG座標系（Y: 上→下）、AXFrame は Cocoa座標系（Y: 下→上）なので変換が必要
                // primaryHeight が 0 の場合（ディスプレイ未初期化）は座標変換が破綻するためスキップ
                if target == nil, let bounds = freshBounds, bounds != .zero,
                   let primaryHeight = NSScreen.screens.first?.frame.height, primaryHeight > 0 {
                    let cocoaY = primaryHeight - bounds.origin.y - bounds.height
                    target = axWindows.first(where: {
                        var frameRef: CFTypeRef?
                        guard AXUIElementCopyAttributeValue($0, "AXFrame" as CFString, &frameRef) == .success,
                              let rawVal = frameRef,
                              CFGetTypeID(rawVal) == AXValueGetTypeID() else { return false }
                        let axValue = rawVal as! AXValue  // CFGetTypeID チェック済みなので安全
                        var axFrame = CGRect.zero
                        AXValueGetValue(axValue, .cgRect, &axFrame)
                        return abs(axFrame.origin.x - bounds.origin.x) < 10 &&
                               abs(axFrame.origin.y - cocoaY)          < 10 &&
                               abs(axFrame.width    - bounds.width)     < 10 &&
                               abs(axFrame.height   - bounds.height)    < 10
                    })
                }
            }

            if let axWindow = target {
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, axWindow as CFTypeRef)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            }
        }

        windowInfo.app.activate()
    }

    /// アクティベート時点で CGWindowList を再クエリして最新の bounds と title を返す
    private func currentCGInfo(for windowID: CGWindowID) -> (CGRect?, String?) {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = list.first else { return (nil, nil) }
        var bounds: CGRect?
        if let bd = info[kCGWindowBounds as String] as? [String: CGFloat] {
            bounds = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0,
                            width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
        }
        let title = info[kCGWindowName as String] as? String
        return (bounds, title)
    }
}
