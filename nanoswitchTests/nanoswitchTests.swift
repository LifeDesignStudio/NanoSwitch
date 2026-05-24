import Testing
import Cocoa
@testable import nanoswitch

// MARK: - WindowInfo

struct WindowInfoTests {

    @Test func propertiesPreserved() {
        let app = NSRunningApplication.current
        let bounds = CGRect(x: 10, y: 20, width: 800, height: 600)
        let info = WindowInfo(
            windowID: 42, appName: "TestApp", windowTitle: "Test Window",
            ownerPID: 100, app: app, bounds: bounds
        )
        #expect(info.windowID == 42)
        #expect(info.appName == "TestApp")
        #expect(info.windowTitle == "Test Window")
        #expect(info.ownerPID == 100)
        #expect(info.bounds == bounds)
    }

    @Test func emptyWindowTitleAllowed() {
        let app = NSRunningApplication.current
        let info = WindowInfo(
            windowID: 1, appName: "App", windowTitle: "",
            ownerPID: 1, app: app, bounds: .zero
        )
        #expect(info.windowTitle == "")
    }
}

// MARK: - ThumbnailFetcher.resize

struct ThumbnailFetcherResizeTests {

    private func makeTestImage(size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        return img
    }

    // 入力が maxSize より小さい場合は拡大しない
    @Test func noUpscaling() {
        let image = makeTestImage(size: NSSize(width: 100, height: 100))
        let result = ThumbnailFetcher.resize(image, maxSize: NSSize(width: 300, height: 200))
        #expect(result.size.width == 100)
        #expect(result.size.height == 100)
    }

    // 幅がボトルネックのとき正しくスケールされる
    // 600x200 → max 300x200: scale = min(300/600, 200/200, 1.0) = 0.5 → 300x100
    @Test func downscaleWidthConstrained() {
        let image = makeTestImage(size: NSSize(width: 600, height: 200))
        let result = ThumbnailFetcher.resize(image, maxSize: NSSize(width: 300, height: 200))
        #expect(result.size.width == 300)
        #expect(result.size.height == 100)
    }

    // 高さがボトルネックのとき正しくスケールされる
    // 200x600 → max 300x200: scale = min(300/200, 200/600, 1.0) = 1/3 → ~66.7x200
    @Test func downscaleHeightConstrained() {
        let image = makeTestImage(size: NSSize(width: 200, height: 600))
        let result = ThumbnailFetcher.resize(image, maxSize: NSSize(width: 300, height: 200))
        let expected = 200.0 * (200.0 / 600.0)
        #expect(abs(result.size.width - expected) < 1.0)
        #expect(abs(result.size.height - 200.0) < 1.0)
    }

    // ぴったり maxSize に一致するとき変化しない
    @Test func exactFitNoChange() {
        let image = makeTestImage(size: NSSize(width: 300, height: 200))
        let result = ThumbnailFetcher.resize(image, maxSize: NSSize(width: 300, height: 200))
        #expect(result.size.width == 300)
        #expect(result.size.height == 200)
    }

    // サイズ 0 の画像はそのまま返す（ガード節の確認）
    @Test func zeroSizeImagePassesThrough() {
        let image = NSImage(size: .zero)
        let result = ThumbnailFetcher.resize(image, maxSize: NSSize(width: 300, height: 200))
        #expect(result.size == .zero)
    }
}

// MARK: - ThumbnailFetcher ライフサイクル

struct ThumbnailFetcherLifecycleTests {

    @Test func cancelBeforeFetchDoesNotCrash() {
        let fetcher = ThumbnailFetcher()
        fetcher.cancel()
    }

    @Test func doubleCancelDoesNotCrash() {
        let fetcher = ThumbnailFetcher()
        fetcher.cancel()
        fetcher.cancel()
    }

    @Test func fetchEmptyWindowListReturnsEmpty() async {
        let fetcher = ThumbnailFetcher()
        let result: [CGWindowID: NSImage] = await withCheckedContinuation { cont in
            fetcher.fetchThumbnails(for: []) { thumbnails in
                cont.resume(returning: thumbnails)
            }
        }
        #expect(result.isEmpty)
    }

    @Test func cancelAfterFetchDoesNotCrash() {
        let fetcher = ThumbnailFetcher()
        fetcher.fetchThumbnails(for: []) { _ in }
        fetcher.cancel()
    }
}
