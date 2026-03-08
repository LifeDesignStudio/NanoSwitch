import Cocoa
import ScreenCaptureKit

class ThumbnailFetcher {

    private var fetchTask: Task<Void, Never>?

    func cancel() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    func fetchThumbnails(for windows: [WindowInfo],
                         completion: @escaping ([CGWindowID: NSImage]) -> Void) {
        fetchTask?.cancel()
        print("[NanoSwitch] ThumbnailFetcher 取得開始 - \(windows.count) 件")

        fetchTask = Task {
            let thumbnails = await capture(windows: windows)
            guard !Task.isCancelled else {
                print("[NanoSwitch] ThumbnailFetcher キャンセル")
                return
            }
            print("[NanoSwitch] ThumbnailFetcher 完了 - \(thumbnails.count) 件")
            await MainActor.run { completion(thumbnails) }
        }
    }

    // MARK: - Capture

    private func capture(windows: [WindowInfo]) async -> [CGWindowID: NSImage] {
        // ScreenCaptureKit を優先（CGWindowListCreateImage は macOS 14 で非推奨、15 以降で動作しない場合あり）
        if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) {
            return await captureWithSCK(windows: windows, content: content)
        }
        // SCShareableContent 取得失敗時は旧 API にフォールバック
        print("[NanoSwitch] SCShareableContent 取得失敗 → CGWindowList にフォールバック")
        return captureWithCGWindowList(windows: windows)
    }

    private func captureWithSCK(windows: [WindowInfo], content: SCShareableContent) async -> [CGWindowID: NSImage] {
        let scByID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        var thumbnails: [CGWindowID: NSImage] = [:]

        for windowInfo in windows {
            if Task.isCancelled { break }

            guard let scWindow = scByID[windowInfo.windowID] else {
                if let icon = windowInfo.app.icon { thumbnails[windowInfo.windowID] = icon }
                continue
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.showsCursor = false
            // アスペクト比を維持しつつ最大 600×400 でキャプチャ（後段の resize で最終サイズに調整）
            let ww = max(1.0, scWindow.frame.width)
            let wh = max(1.0, scWindow.frame.height)
            let scale = min(600.0 / ww, 400.0 / wh, 1.0)
            config.width  = max(1, Int(ww * scale))
            config.height = max(1, Int(wh * scale))

            if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                thumbnails[windowInfo.windowID] = ThumbnailFetcher.resize(
                    NSImage(cgImage: cgImage, size: .zero), maxSize: NSSize(width: 300, height: 200))
            } else if let icon = windowInfo.app.icon {
                thumbnails[windowInfo.windowID] = icon
            }
        }
        return thumbnails
    }

    private func captureWithCGWindowList(windows: [WindowInfo]) -> [CGWindowID: NSImage] {
        var thumbnails: [CGWindowID: NSImage] = [:]
        for windowInfo in windows {
            if Task.isCancelled { break }
            if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowInfo.windowID,
                                                      [.boundsIgnoreFraming, .nominalResolution]) {
                thumbnails[windowInfo.windowID] = ThumbnailFetcher.resize(
                    NSImage(cgImage: cgImage, size: .zero), maxSize: NSSize(width: 300, height: 200))
            } else if let icon = windowInfo.app.icon {
                thumbnails[windowInfo.windowID] = icon
            }
        }
        return thumbnails
    }

    // MARK: - Resize

    // アスペクト比を維持しつつ maxSize に収まるようリサイズ（拡大はしない）
    private static func resize(_ image: NSImage, maxSize: NSSize) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1.0)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: size),
                   operation: .copy,
                   fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
