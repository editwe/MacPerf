import AppKit

enum WindowStyler {
    private static var configured = false

    static func configureIfNeeded(attempt: Int = 0) {
        guard !configured else { return }
        let windows = NSApp.windows.filter { $0.contentView != nil && $0.canBecomeMain }
        guard let window = windows.first(where: { $0.isVisible }) ?? windows.first else {
            if attempt < 12 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    configureIfNeeded(attempt: attempt + 1)
                }
            }
            return
        }
        configured = true
        window.title = "Mac 性能测评"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 1060, height: 680)
        window.backgroundColor = NSColor(calibratedRed: 0.027, green: 0.043, blue: 0.070, alpha: 1)
        window.isOpaque = true

        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1408, height: 860)
        let width = min(1180, max(1060, visible.width - 32))
        let height = min(730, max(680, visible.height - 70))
        window.setContentSize(NSSize(width: width, height: height))
        window.setFrameOrigin(NSPoint(x: visible.midX - width / 2,
                                      y: visible.midY - height / 2 - 8))
    }
}
