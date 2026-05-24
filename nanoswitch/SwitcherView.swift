import Cocoa

class SwitcherView: NSView {

    // MARK: - Constants

    private static let cellWidth: CGFloat = 220
    private static let cellHeight: CGFloat = 190
    private static let thumbnailHeight: CGFloat = 150
    private static let padding: CGFloat = 12
    static let maxColumns: Int = 5
    private static let iconSize: CGFloat = 28
    private static let closeButtonSize: CGFloat = 14

    // MARK: - State

    private var windows: [WindowInfo] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]

    var selectedIndex: Int = 0 {
        didSet { needsDisplay = true }
    }

    private var hoveredIndex: Int? {
        didSet { if oldValue != hoveredIndex { needsDisplay = true } }
    }

    // MARK: - Callbacks

    var onActivate: ((WindowInfo) -> Void)?
    var onDismiss: (() -> Void)?
    var onClose: ((WindowInfo) -> Void)?

    // MARK: - Public

    func configure(windows: [WindowInfo], thumbnails: [CGWindowID: NSImage]) {
        self.windows = windows
        self.thumbnails = thumbnails
        hoveredIndex = nil
        if selectedIndex >= windows.count {
            selectedIndex = max(0, windows.count - 1)  // didSet triggers needsDisplay
        } else {
            needsDisplay = true
        }
    }

    func moveSelection(by delta: Int) {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + windows.count) % windows.count
    }

    func activateSelectedWindow() -> WindowInfo? {
        guard selectedIndex < windows.count else { return nil }
        return windows[selectedIndex]
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: // Tab
            if event.modifierFlags.contains(.shift) {
                moveSelection(by: -1)
            } else {
                moveSelection(by: 1)
            }
        case 123: // 左矢印
            moveSelection(by: -1)
        case 124: // 右矢印
            moveSelection(by: 1)
        case 125: // 下矢印
            moveSelection(by: Self.maxColumns)
        case 126: // 上矢印
            moveSelection(by: -Self.maxColumns)
        case 36: // Return
            if let windowInfo = activateSelectedWindow() {
                onActivate?(windowInfo)
            }
        case 53: // Escape
            onDismiss?()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoveredIndex = windows.indices.first { cellFrame(for: $0).contains(point) }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, _) in windows.enumerated() {
            if index == hoveredIndex && closeButtonFrame(for: index).contains(point) { return }
            if cellFrame(for: index).contains(point) {
                selectedIndex = index
                break
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, windowInfo) in windows.enumerated() {
            if index == hoveredIndex && closeButtonFrame(for: index).contains(point) {
                onClose?(windowInfo)
                return
            }
            if cellFrame(for: index).contains(point) && index == selectedIndex {
                onActivate?(windowInfo)
                return
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        for (index, windowInfo) in windows.enumerated() {
            drawCell(windowInfo: windowInfo,
                     at: cellFrame(for: index),
                     isSelected: index == selectedIndex,
                     isHovered: index == hoveredIndex)
        }
    }

    private func cellFrame(for index: Int) -> NSRect {
        let column = index % Self.maxColumns
        let row = index / Self.maxColumns
        let totalRows = (windows.count + Self.maxColumns - 1) / Self.maxColumns

        let x = SwitcherView.padding + CGFloat(column) * (SwitcherView.cellWidth + SwitcherView.padding)
        // NSView は y=0 が下端なので上段ほど大きい y 値
        let y = CGFloat(totalRows - 1 - row) * (SwitcherView.cellHeight + SwitcherView.padding) + SwitcherView.padding

        return NSRect(x: x, y: y, width: SwitcherView.cellWidth, height: SwitcherView.cellHeight)
    }

    private func closeButtonFrame(for index: Int) -> NSRect {
        let cell = cellFrame(for: index)
        return NSRect(
            x: cell.minX + 4,
            y: cell.maxY - Self.closeButtonSize - 4,
            width: Self.closeButtonSize,
            height: Self.closeButtonSize
        )
    }

    private func drawCell(windowInfo: WindowInfo, at frame: NSRect, isSelected: Bool, isHovered: Bool) {
        // セル背景
        let bgColor = isSelected
            ? NSColor.selectedControlColor.withAlphaComponent(0.35)
            : NSColor.white.withAlphaComponent(0.06)
        let cellPath = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        bgColor.setFill()
        cellPath.fill()

        // 選択ボーダー（青、2px）
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            cellPath.lineWidth = 2
            cellPath.stroke()
        }

        // サムネイル描画エリア
        let thumbRect = NSRect(
            x: frame.minX + 8,
            y: frame.minY + 40,
            width: frame.width - 16,
            height: SwitcherView.thumbnailHeight
        )

        if let thumbnail = thumbnails[windowInfo.windowID] {
            let imgSize = thumbnail.size
            let scale = min(thumbRect.width / imgSize.width, thumbRect.height / imgSize.height)
            let drawWidth = imgSize.width * scale
            let drawHeight = imgSize.height * scale
            let drawRect = NSRect(
                x: thumbRect.minX + (thumbRect.width - drawWidth) / 2,
                y: thumbRect.minY + (thumbRect.height - drawHeight) / 2,
                width: drawWidth,
                height: drawHeight
            )
            thumbnail.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // アプリ名
        let appNameRect = NSRect(x: frame.minX + 38, y: frame.minY + 22, width: frame.width - 44, height: 18)
        let appNameStyle = NSMutableParagraphStyle()
        appNameStyle.lineBreakMode = .byTruncatingTail
        let appNameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: appNameStyle
        ]
        NSAttributedString(string: windowInfo.appName, attributes: appNameAttrs).draw(in: appNameRect)

        // ウィンドウタイトル
        let titleRect = NSRect(x: frame.minX + 38, y: frame.minY + 10, width: frame.width - 44, height: 14)
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55),
            .paragraphStyle: titleStyle
        ]
        NSAttributedString(string: windowInfo.windowTitle, attributes: titleAttrs).draw(in: titleRect)

        // アプリアイコン（上端をテキスト上端と揃える）
        if let icon = windowInfo.app.icon {
            let iconRect = NSRect(x: frame.minX + 6, y: frame.minY + 12,
                                  width: Self.iconSize, height: Self.iconSize)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }

        // 閉じるボタン（ホバー中のセルのみ表示、半透明ダーク円＋白 ×）
        if isHovered {
            let cbRect = NSRect(
                x: frame.minX + 4,
                y: frame.maxY - Self.closeButtonSize - 4,
                width: Self.closeButtonSize,
                height: Self.closeButtonSize
            )
            let circlePath = NSBezierPath(ovalIn: cbRect)
            NSColor.black.withAlphaComponent(0.5).setFill()
            circlePath.fill()
            let symConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(symConfig) {
                let iconSize = img.size
                let iconRect = NSRect(
                    x: cbRect.midX - iconSize.width / 2,
                    y: cbRect.midY - iconSize.height / 2,
                    width: iconSize.width,
                    height: iconSize.height
                )
                img.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
        }
    }

    // MARK: - Size Calculation

    static func preferredSize(for windowCount: Int,
                               cellWidth: CGFloat = SwitcherView.cellWidth,
                               cellHeight: CGFloat = SwitcherView.cellHeight,
                               padding: CGFloat = SwitcherView.padding,
                               maxColumns: Int = SwitcherView.maxColumns) -> NSSize {
        guard windowCount > 0 else { return NSSize(width: 260, height: 220) }
        let columns = min(windowCount, maxColumns)
        let rows = (windowCount + maxColumns - 1) / maxColumns
        let width = padding + CGFloat(columns) * (cellWidth + padding)
        let height = padding + CGFloat(rows) * (cellHeight + padding)
        return NSSize(width: width, height: height)
    }
}
