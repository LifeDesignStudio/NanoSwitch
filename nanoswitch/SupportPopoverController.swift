import Cocoa

// MARK: - SupportPopoverController

class SupportPopoverController: NSObject {

    private static let bmcURL = URL(string: "https://buymeacoffee.com/lifedesignstudio")!

    private let popover = NSPopover()
    private let contentVC = SupportViewController()

    override init() {
        super.init()
        contentVC.popoverRef = popover
        popover.contentViewController = contentVC
        popover.contentSize = NSSize(width: 300, height: 160)
        popover.behavior = .transient
        popover.animates = true
    }

    func show(relativeTo button: NSButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        contentVC.refreshMessage()
        recordShow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: - State (UserDefaults)

    private enum DefaultsKey {
        static let showCount  = "com.lifedesign.nanoswitch.supportShowCount"
        static let hasSupported = "com.lifedesign.nanoswitch.hasSupported"  // 将来用
    }

    private func recordShow() {
        let n = UserDefaults.standard.integer(forKey: DefaultsKey.showCount)
        UserDefaults.standard.set(n + 1, forKey: DefaultsKey.showCount)
    }

    var showCount: Int {
        UserDefaults.standard.integer(forKey: DefaultsKey.showCount)
    }

    // 将来: ユーザーが支援済みであることを記録するフラグ
    var hasSupported: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.hasSupported) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.hasSupported) }
    }

    // MARK: - Action

    static func openBMC() {
        NSWorkspace.shared.open(bmcURL)
    }
}

// MARK: - SupportViewController

class SupportViewController: NSViewController {

    weak var popoverRef: NSPopover?

    private static let messages: [String] = [
        "If NanoSwitch saves you time, consider supporting ☕",
        "Enjoying NanoSwitch? You can support its development",
        "Built to stay fast and simple — support if you like it",
        "A small coffee keeps NanoSwitch alive ☕",
        "If this app helps your workflow, support is appreciated",
        "No ads, no tracking — just NanoSwitch. Support if you want",
        "Support development and keep NanoSwitch evolving",
        "Save time daily? Buy me a coffee ☕",
        "NanoSwitch is built by a solo developer — support welcome",
        "If it fits your workflow, you can support the project",
    ]

    private let titleLabel   = NSTextField(labelWithString: "NanoSwitch is free and ad-free.")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let bmcButton    = NSButton(title: "Support with Buy Me a Coffee", target: nil, action: nil)

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        refreshMessage()
    }

    func refreshMessage() {
        messageLabel.stringValue = Self.messages.randomElement() ?? Self.messages[0]
    }

    // MARK: - UI Setup

    private func setupUI() {
        let padding: CGFloat = 20

        // Title
        titleLabel.font      = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // Message
        messageLabel.font                  = .systemFont(ofSize: 12)
        messageLabel.textColor             = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = 300 - padding * 2
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        // Button
        bmcButton.bezelStyle    = .rounded
        bmcButton.font          = .systemFont(ofSize: 13)
        bmcButton.target        = self
        bmcButton.action        = #selector(openBMC)
        bmcButton.keyEquivalent = "\r"          // Return キーで発火（青くなる）
        bmcButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(messageLabel)
        view.addSubview(bmcButton)

        NSLayoutConstraint.activate([
            // Title — 上端に固定
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),

            // Message — タイトルの直下
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),

            // Button — メッセージの下、右端揃え
            bmcButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 14),
            bmcButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            bmcButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
        ])
    }

    @objc private func openBMC() {
        SupportPopoverController.openBMC()
        popoverRef?.performClose(nil)
    }
}
