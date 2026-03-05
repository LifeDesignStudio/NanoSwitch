import Cocoa

class ThumbnailFetcher {

    private var workItem: DispatchWorkItem?

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }

    func fetchThumbnails(for windows: [WindowInfo],
                         completion: @escaping ([CGWindowID: NSImage]) -> Void) {
        workItem?.cancel()
        print("[NanoSwitch] ThumbnailFetcher 取得開始 - \(windows.count) 件")

        var item: DispatchWorkItem?
        item = DispatchWorkItem {
            var thumbnails: [CGWindowID: NSImage] = [:]

            for windowInfo in windows {
                if item?.isCancelled == true { break }

                if let cgImage = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    windowInfo.windowID,
                    [.boundsIgnoreFraming, .nominalResolution]
                ) {
                    let original = NSImage(cgImage: cgImage, size: .zero)
                    thumbnails[windowInfo.windowID] = ThumbnailFetcher.resize(
                        original, maxSize: NSSize(width: 300, height: 200))
                } else if let icon = windowInfo.app.icon {
                    thumbnails[windowInfo.windowID] = icon
                }
            }

            if item?.isCancelled == true {
                print("[NanoSwitch] ThumbnailFetcher キャンセル")
                return
            }

            print("[NanoSwitch] ThumbnailFetcher 完了 - \(thumbnails.count) 件")
            DispatchQueue.main.async { completion(thumbnails) }
        }

        workItem = item
        if let item { DispatchQueue.global(qos: .userInteractive).async(execute: item) }
    }

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
