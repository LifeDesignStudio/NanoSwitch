import Cocoa

struct WindowInfo {
    let windowID: CGWindowID
    let appName: String
    let windowTitle: String
    let ownerPID: pid_t
    let app: NSRunningApplication
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
            return
        }

        let runningApps = NSWorkspace.shared.runningApplications

        var newWindows: [WindowInfo] = []

        for info in rawList {
            // レイヤー 0（通常ウィンドウ）のみ
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }

            // オンスクリーンのみ
            guard let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool, isOnscreen else { continue }

            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }

            // 通常アプリのみ（ヘルパー・バックグラウンドプロセスを除外）
            guard let app = runningApps.first(where: { $0.processIdentifier == pid }),
                  app.activationPolicy == .regular else { continue }

            let appName = info[kCGWindowOwnerName as String] as? String
                          ?? app.localizedName
                          ?? "Unknown"
            let windowTitle = info[kCGWindowName as String] as? String ?? ""

            let windowInfo = WindowInfo(
                windowID: windowID,
                appName: appName,
                windowTitle: windowTitle,
                ownerPID: pid,
                app: app
            )
            newWindows.append(windowInfo)
        }

        DispatchQueue.main.async {
            self.windows = newWindows
        }
    }
}
