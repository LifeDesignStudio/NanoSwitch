import Cocoa

struct WindowInfo {
    let windowID: CGWindowID
    let appName: String
    let windowTitle: String
    let ownerPID: pid_t
    let app: NSRunningApplication
    let bounds: CGRect
}

class WindowManager {

    private var windows: [WindowInfo] = []

    init() {
        setupNotifications()
        updateWindowList()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Public

    func getWindows() -> [WindowInfo] {
        return windows
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self,
                       selector: #selector(handleAppNotification(_:)),
                       name: NSWorkspace.didActivateApplicationNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleAppNotification(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleAppNotification(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification,
                       object: nil)
    }

    @objc private func handleAppNotification(_ notification: Notification) {
        updateWindowList()
    }

    // MARK: - Window List

    func updateWindowList() {
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("[NanoSwitch] ⚠️ CGWindowListCopyWindowInfo 失敗")
            return
        }

        let runningApps = NSWorkspace.shared.runningApplications

        var newWindows: [WindowInfo] = []

        for info in rawList {
            // レイヤー 0（通常ウィンドウ）のみ
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }

            // オンスクリーンのみ（kCGWindowIsOnscreen が存在しない場合は false 扱い）
            guard let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool, isOnscreen else { continue }

            // alpha=0 の不可視ウィンドウ（アプリ内部ウィンドウ等）を除外
            guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0 else { continue }

            // bounds 取得（極小ウィンドウ除外 & フォールバック照合用）
            var windowBounds = CGRect.zero
            if let bd = info[kCGWindowBounds as String] as? [String: CGFloat] {
                windowBounds = CGRect(x: bd["X"] ?? 0, y: bd["Y"] ?? 0,
                                     width: bd["Width"] ?? 0, height: bd["Height"] ?? 0)
                guard windowBounds.width >= 100 && windowBounds.height >= 60 else { continue }
            }

            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }

            // 通常アプリのみ（ヘルパー・バックグラウンドプロセスを除外）
            guard let app = runningApps.first(where: { $0.processIdentifier == pid }),
                  app.activationPolicy == .regular else { continue }

            let appName = info[kCGWindowOwnerName as String] as? String
                          ?? app.localizedName
                          ?? "Unknown"
            let windowTitle = info[kCGWindowName as String] as? String ?? ""

            newWindows.append(WindowInfo(
                windowID: windowID,
                appName: appName,
                windowTitle: windowTitle,
                ownerPID: pid,
                app: app,
                bounds: windowBounds
            ))
        }

        // 同期的に更新（呼び出し元は常にメインスレッド）
        // ※ 以前は DispatchQueue.main.async で遅延していたため、
        //   直後の getWindows() が古いリストを返すバグがあった
        windows = newWindows
        print("[NanoSwitch] ウィンドウリスト更新: \(windows.count) 件 \(windows.map { $0.appName })")
    }
}
