import Cocoa

class SwitcherWindowController {

    private var panel: NSPanel?
    private var switcherView: SwitcherView?
    private var currentWindows: [WindowInfo] = []

    // MARK: - Public

    var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    func show(windows: [WindowInfo],
              thumbnails: [CGWindowID: NSImage],
              startAtEnd: Bool = false) {
        guard !windows.isEmpty else { return }
        currentWindows = windows
        print("[NanoSwitch] SwitcherWindowController.show() - \(windows.count) ウィンドウ")

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
        switcherView?.frame = NSRect(origin: .zero, size: preferredSize)
        switcherView?.configure(windows: windows, thumbnails: thumbnails)

        if startAtEnd {
            switcherView?.selectedIndex = max(0, windows.count - 1)
        }

        panel?.orderFrontRegardless()
        panel?.makeFirstResponder(switcherView)
        print("[NanoSwitch] パネル表示完了。isVisible=\(panel?.isVisible ?? false), frame=\(panel?.frame ?? .zero)")
    }

    func dismiss() {
        panel?.orderOut(nil)
        currentWindows = []
        // サムネイル参照をすべて解放してメモリ解放
        switcherView?.configure(windows: [], thumbnails: [:])
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
        switcherView = view

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .modalPanel
        newPanel.isOpaque = false
        newPanel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        newPanel.hasShadow = true
        newPanel.contentView = view
        newPanel.acceptsMouseMovedEvents = true
        // 全Spaceおよびフルスクリーンアプリの上に表示するために必要
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel = newPanel
        print("[NanoSwitch] NSPanel 作成完了")
    }

    // MARK: - Window Activation

    /// 公式属性 "AXWindowID" で CGWindowID を取得する（プライベートAPI不使用）
    private func cgWindowID(for axWindow: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow,
                                            "AXWindowID" as CFString,
                                            &value) == .success,
              let number = value as? NSNumber else { return nil }
        return CGWindowID(number.uint32Value)
    }

    private func activateWindow(_ windowInfo: WindowInfo) {
        let axApp = AXUIElementCreateApplication(windowInfo.ownerPID)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let axWindows = windowsRef as? [AXUIElement] {

            // 1st: AXWindowID でマッチ（最も確実）
            var target: AXUIElement? = axWindows.first(where: {
                guard let wid = cgWindowID(for: $0), wid != 0 else { return false }
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
                if target == nil, let bounds = freshBounds, bounds != .zero {
                    target = axWindows.first(where: {
                        var frameRef: CFTypeRef?
                        guard AXUIElementCopyAttributeValue($0, "AXFrame" as CFString, &frameRef) == .success,
                              let axVal = frameRef,
                              CFGetTypeID(axVal) == AXValueGetTypeID() else { return false }
                        var axFrame = CGRect.zero
                        AXValueGetValue(axVal as! AXValue, .cgRect, &axFrame)
                        return abs(axFrame.origin.x - bounds.origin.x) < 10 &&
                               abs(axFrame.origin.y - bounds.origin.y) < 10 &&
                               abs(axFrame.width  - bounds.width)  < 10 &&
                               abs(axFrame.height - bounds.height) < 10
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
