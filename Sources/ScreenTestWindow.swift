import AppKit
import Combine

final class ScreenTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ScreenTestPresenter: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isPresenting = false

    private var window: ScreenTestWindow?
    private var previousPresentationOptions: NSApplication.PresentationOptions = []

    func show(startIndex: Int, on display: DisplayDescriptor) {
        if isPresenting {
            close()
        }
        let screen = NSScreen.screens.first(where: { screenID($0) == display.id }) ?? NSScreen.main
        guard let screen else { return }

        let frame = screen.frame
        let view = ScreenTestPatternView(
            frame: NSRect(origin: .zero, size: frame.size),
            patterns: ScreenPatternCatalog.all,
            startIndex: max(0, min(startIndex, ScreenPatternCatalog.all.count - 1)),
            display: display
        )
        view.onClose = { [weak self] in self?.close() }

        let window = ScreenTestWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = view
        window.colorSpace = .displayP3
        window.isOpaque = true
        window.backgroundColor = .black
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "MacPerf 屏幕检测"

        previousPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
        NSApp.activate(ignoringOtherApps: true)

        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        window.orderFrontRegardless()
        self.window = window
        isPresenting = true
    }

    func close() {
        guard let window else {
            restorePresentation()
            isPresenting = false
            return
        }
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        self.window = nil
        isPresenting = false
        restorePresentation()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        isPresenting = false
        restorePresentation()
    }

    private func restorePresentation() {
        NSApp.presentationOptions = previousPresentationOptions
    }

    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}

final class ScreenTestPatternView: NSView {
    var onClose: (() -> Void)?

    private let patterns: [ScreenPattern]
    private let display: DisplayDescriptor
    private var index: Int
    private var labelsPinned = false
    private var hudVisible = true
    private var labelsVisible: Bool { labelsPinned || hudVisible }
    private var hudTimer: Timer?
    private var tracking: NSTrackingArea?

    private let spectralLocus: [(CGFloat, CGFloat)] = [
        (0.1741, 0.0050), (0.1738, 0.0049), (0.1733, 0.0048), (0.1726, 0.0048),
        (0.1714, 0.0051), (0.1689, 0.0069), (0.1644, 0.0109), (0.1566, 0.0177),
        (0.1440, 0.0297), (0.1241, 0.0578), (0.0913, 0.1327), (0.0454, 0.2950),
        (0.0082, 0.5384), (0.0139, 0.7502), (0.0743, 0.8338), (0.1547, 0.8059),
        (0.2296, 0.7543), (0.3016, 0.6923), (0.3731, 0.6245), (0.4441, 0.5547),
        (0.5125, 0.4866), (0.5752, 0.4242), (0.6270, 0.3725), (0.6658, 0.3340),
        (0.6915, 0.3083), (0.7079, 0.2920), (0.7190, 0.2809), (0.7260, 0.2740),
        (0.7300, 0.2700), (0.7320, 0.2680), (0.7330, 0.2670), (0.7340, 0.2660),
        (0.7347, 0.2653)
    ]

    init(frame frameRect: NSRect,
         patterns: [ScreenPattern],
         startIndex: Int,
         display: DisplayDescriptor) {
        self.patterns = patterns
        self.index = startIndex
        self.display = display
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        scheduleHUDHide()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        hudTimer?.invalidate()
        if let tracking { removeTrackingArea(tracking) }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private var current: ScreenPattern {
        patterns[max(0, min(index, patterns.count - 1))]
    }

    private func scheduleHUDHide() {
        hudTimer?.invalidate()
        hudVisible = true
        needsDisplay = true
        hudTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.hudVisible = false
            self.needsDisplay = true
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func advance(_ delta: Int) {
        guard !patterns.isEmpty else { return }
        index = (index + delta + patterns.count) % patterns.count
        scheduleHUDHide()
        needsDisplay = true
    }

    private func jump(to id: String) {
        if let target = patterns.firstIndex(where: { $0.id == id }) {
            index = target
            scheduleHUDHide()
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onClose?()
        case 123:
            advance(-1)
        case 124, 49:
            advance(1)
        case 18...29:
            if let characters = event.charactersIgnoringModifiers,
               let number = Int(characters), number >= 1, number <= min(9, patterns.count) {
                index = number - 1
                scheduleHUDHide()
                needsDisplay = true
            }
        default:
            if let characters = event.charactersIgnoringModifiers?.lowercased() {
                switch characters {
                case "w": jump(to: "white")
                case "b": jump(to: "black")
                case "g": jump(to: "graySteps")
                case "c": jump(to: "colorBars")
                case "p": jump(to: "gamutCompare")
                case "t": jump(to: "gamutTriangle")
                case "l":
                    labelsPinned.toggle()
                    scheduleHUDHide()
                    needsDisplay = true
                case "h":
                    scheduleHUDHide()
                default:
                    super.keyDown(with: event)
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let midpoint = bounds.midX
        advance(event.locationInWindow.x < midpoint ? -1 : 1)
    }

    override func rightMouseDown(with event: NSEvent) {
        onClose?()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.unhide()
        scheduleHUDHide()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()
        context.fill(bounds)

        switch current.kind {
        case .solid:
            drawSolid()
        case .graySteps:
            drawSteps(count: 21, values: (0...20).map { CGFloat($0) / 20.0 })
        case .nearBlack:
            drawSteps(count: 11, values: (0...10).map { CGFloat($0) / 100.0 })
        case .colorBars:
            drawColorBars()
        case .rgbRamp:
            drawRGBRamps()
        case .hueSweep:
            drawHueSweep()
        case .gamutCompare:
            drawGamutCompare()
        case .gamutTriangle:
            drawGamutTriangle()
        case .uniformity:
            drawUniformity()
        }

        if hudVisible {
            drawHUD()
        }
    }

    private func drawSolid() {
        (current.color ?? .black).setFill()
        NSBezierPath(rect: bounds).fill()
        if labelsVisible, let hex = current.hexLabel {
            drawBadge(text: "\(current.title)  \(hex)",
                      at: NSPoint(x: bounds.midX, y: bounds.height - 74),
                      centered: true,
                      color: readableColor(on: current.color ?? .black))
        }
    }

    private func drawSteps(count: Int, values: [CGFloat]) {
        let barWidth = bounds.width / CGFloat(count)
        for i in 0..<count {
            let rect = NSRect(x: CGFloat(i) * barWidth,
                              y: 0,
                              width: barWidth + 1,
                              height: bounds.height)
            NSColor(displayP3Red: values[i], green: values[i], blue: values[i], alpha: 1).setFill()
            rect.fill()
            if labelsVisible {
                let percent = Int((values[i] * 100).rounded())
                let color: NSColor = values[i] > 0.45 ? .black : .white
                drawText("\(percent)", in: NSRect(x: rect.minX, y: 18, width: rect.width, height: 18),
                         size: 11, color: color.withAlphaComponent(0.78), centered: true)
            }
        }
    }

    private func drawColorBars() {
        let topHeight = bounds.height * 0.66
        let middleHeight = bounds.height * 0.20
        let bottomHeight = bounds.height - topHeight - middleHeight
        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0.75, 0.75, 0.75), (0.75, 0.75, 0.0), (0.0, 0.75, 0.75), (0.0, 0.75, 0.0),
            (0.75, 0.0, 0.75), (0.75, 0.0, 0.0), (0.0, 0.0, 0.75)
        ]
        let barWidth = bounds.width / CGFloat(colors.count)
        for (i, color) in colors.enumerated() {
            NSColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1).setFill()
            NSRect(x: CGFloat(i) * barWidth, y: bottomHeight, width: barWidth + 1, height: topHeight).fill()
        }
        let reverse = [colors[6], colors[4], colors[2], colors[0], colors[3], colors[1], colors[5]]
        for (i, color) in reverse.enumerated() {
            NSColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1).setFill()
            NSRect(x: CGFloat(i) * barWidth, y: bottomHeight + 1, width: barWidth + 1, height: middleHeight - 1).fill()
        }
        let pluge = [0.0, 0.04, 0.075, 0.11]
        for (i, value) in pluge.enumerated() {
            NSColor(srgbRed: value, green: value, blue: value, alpha: 1).setFill()
            let width = bounds.width / CGFloat(pluge.count)
            NSRect(x: CGFloat(i) * width, y: 0, width: width + 1, height: bottomHeight).fill()
        }
        if labelsVisible {
            drawText("75% COLOR BARS  ·  PLUGE",
                     in: NSRect(x: 30, y: bounds.height - 44, width: 520, height: 20),
                     size: 12, color: .white.withAlphaComponent(0.70))
        }
    }

    private func drawRGBRamps() {
        let bandHeight = bounds.height / 3.0
        let primaries: [NSColor] = [
            NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1),
            NSColor(displayP3Red: 0, green: 1, blue: 0, alpha: 1),
            NSColor(displayP3Red: 0, green: 0, blue: 1, alpha: 1)
        ]
        for (i, color) in primaries.enumerated() {
            let rect = NSRect(x: 0, y: CGFloat(i) * bandHeight, width: bounds.width, height: bandHeight + 1)
            NSGradient(starting: .black, ending: color)?.draw(in: rect, angle: 0)
        }
        if labelsVisible {
            for (i, label) in ["BLUE", "GREEN", "RED"].enumerated() {
                drawText(label,
                         in: NSRect(x: 26, y: CGFloat(i) * bandHeight + bandHeight * 0.5 - 8,
                                    width: 80, height: 20),
                         size: 12, color: .white.withAlphaComponent(0.62))
            }
        }
    }

    private func drawHueSweep() {
        var colors: [NSColor] = []
        for i in 0...36 {
            let hue = CGFloat(i) / 36.0
            colors.append(NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0))
        }
        NSGradient(colors: colors)?.draw(in: bounds, angle: 0)
    }

    private func drawGamutCompare() {
        let half = bounds.width / 2.0
        let labels = ["R", "G", "B", "M"]
        let srgbColors: [NSColor] = [
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
            NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
            NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        ]
        let p3Colors: [NSColor] = [
            NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1),
            NSColor(displayP3Red: 0, green: 1, blue: 0, alpha: 1),
            NSColor(displayP3Red: 0, green: 0, blue: 1, alpha: 1),
            NSColor(displayP3Red: 1, green: 0, blue: 1, alpha: 1)
        ]

        if labelsVisible {
            drawText("sRGB", in: NSRect(x: 0, y: bounds.height - 70, width: half, height: 30),
                     size: 22, color: .white.withAlphaComponent(0.8), centered: true)
            drawText("DISPLAY P3", in: NSRect(x: half, y: bounds.height - 70, width: half, height: 30),
                     size: 22, color: .white.withAlphaComponent(0.8), centered: true)
        }

        let inset: CGFloat = 26
        let gridTop = bounds.height - 90
        let gridHeight = gridTop - 70
        let cellW = (half - inset * 2) / 2
        let cellH = gridHeight / 2
        for i in 0..<4 {
            let col = CGFloat(i % 2)
            let row = CGFloat(i / 2)
            let leftRect = NSRect(x: inset + col * cellW, y: 58 + row * cellH,
                                  width: cellW - 6, height: cellH - 6)
            let rightRect = NSRect(x: half + inset + col * cellW, y: 58 + row * cellH,
                                   width: cellW - 6, height: cellH - 6)
            srgbColors[i].setFill()
            leftRect.fill()
            p3Colors[i].setFill()
            rightRect.fill()
            if labelsVisible {
                drawText(labels[i], in: NSRect(x: leftRect.minX + 12, y: leftRect.minY + 10, width: 40, height: 24),
                         size: 14, color: .white.withAlphaComponent(0.7))
                drawText(labels[i], in: NSRect(x: rightRect.minX + 12, y: rightRect.minY + 10, width: 40, height: 24),
                         size: 14, color: .white.withAlphaComponent(0.7))
            }
        }

        NSColor.white.withAlphaComponent(0.34).setFill()
        NSRect(x: half - 1, y: 0, width: 2, height: bounds.height).fill()
    }

    private func drawGamutTriangle() {
        NSColor(calibratedRed: 0.018, green: 0.027, blue: 0.045, alpha: 1).setFill()
        bounds.fill()

        let chart = NSRect(x: bounds.width * 0.10, y: bounds.height * 0.24,
                           width: bounds.width * 0.56, height: bounds.height * 0.60)
        drawCIEBackground(in: chart)
        drawTriangle(display.srgbTriangle, in: chart, color: NSColor(hex: 0x4FE3C1), label: "sRGB", labelOffset: 8)
        drawTriangle(display.p3Triangle, in: chart, color: NSColor(hex: 0xFFB86B), label: "Display P3", labelOffset: 32)
        drawTriangle(display.adobeTriangle, in: chart, color: NSColor(hex: 0xA78BFA), label: "Adobe RGB", labelOffset: 56)
        drawTriangle(display.primaries, in: chart, color: .white, label: "本机 ICC", labelOffset: 80, dashed: true)
        drawGamutLegend(chart: chart)
    }

    private func drawCIEBackground(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.13).setStroke()
        for i in 0...8 {
            let x = rect.minX + rect.width * CGFloat(i) / 8
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: rect.minY))
            path.line(to: NSPoint(x: x, y: rect.maxY))
            path.lineWidth = 0.6
            path.stroke()
        }
        for i in 0...9 {
            let y = rect.minY + rect.height * CGFloat(i) / 9
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
            path.lineWidth = 0.6
            path.stroke()
        }

        let locus = NSBezierPath()
        for (i, point) in spectralLocus.enumerated() {
            let p = chartPoint(x: point.0, y: point.1, in: rect)
            if i == 0 { locus.move(to: p) } else { locus.line(to: p) }
        }
        locus.close()
        NSColor.white.withAlphaComponent(0.035).setFill()
        locus.fill()
        NSColor.white.withAlphaComponent(0.48).setStroke()
        locus.lineWidth = 1.6
        locus.stroke()

        drawText("CIE 1931 xy", in: NSRect(x: rect.minX, y: rect.maxY + 12,
                                          width: rect.width, height: 24),
                 size: 15, color: .white.withAlphaComponent(0.72))
        for i in 0...4 {
            let value = CGFloat(i) * 0.2
            drawText(String(format: "%.1f", value),
                     in: NSRect(x: rect.minX + rect.width * value - 20, y: rect.minY - 26,
                                width: 40, height: 18),
                     size: 10, color: .white.withAlphaComponent(0.38), centered: true)
        }
        drawText("x", in: NSRect(x: rect.maxX + 4, y: rect.minY - 26, width: 20, height: 18),
                 size: 11, color: .white.withAlphaComponent(0.4))
        drawText("y", in: NSRect(x: rect.minX - 22, y: rect.maxY - 18, width: 20, height: 18),
                 size: 11, color: .white.withAlphaComponent(0.4))
    }

    private func drawTriangle(_ points: [ChromaticityPoint],
                              in rect: NSRect,
                              color: NSColor,
                              label: String,
                              labelOffset: CGFloat = 6,
                              dashed: Bool = false) {
        guard points.count == 3 else { return }
        let path = NSBezierPath()
        path.move(to: chartPoint(x: CGFloat(points[0].x), y: CGFloat(points[0].y), in: rect))
        path.line(to: chartPoint(x: CGFloat(points[1].x), y: CGFloat(points[1].y), in: rect))
        path.line(to: chartPoint(x: CGFloat(points[2].x), y: CGFloat(points[2].y), in: rect))
        path.close()
        color.withAlphaComponent(0.06).setFill()
        path.fill()
        color.withAlphaComponent(0.92).setStroke()
        path.lineWidth = dashed ? 1.4 : 2.0
        if dashed {
            let dash: [CGFloat] = [6, 5]
            path.setLineDash(dash, count: dash.count, phase: 0)
        }
        path.stroke()

        let anchor = chartPoint(x: CGFloat(points[0].x), y: CGFloat(points[0].y), in: rect)
        drawBadge(text: label, at: NSPoint(x: anchor.x + 8, y: anchor.y + labelOffset), color: color)
    }

    private func chartPoint(x: CGFloat, y: CGFloat, in rect: NSRect) -> NSPoint {
        NSPoint(x: rect.minX + rect.width * (x / 0.8),
                y: rect.minY + rect.height * (y / 0.9))
    }

    private func drawGamutLegend(chart: NSRect) {
        let left = chart.maxX + 64
        let width = bounds.width - left - 70
        var y = chart.maxY - 40
        drawText("色域覆盖", in: NSRect(x: left, y: y, width: width, height: 28),
                 size: 18, color: .white.withAlphaComponent(0.9))
        y -= 40

        let rows: [(String, NSColor, String)] = [
            ("sRGB", NSColor(hex: 0x4FE3C1), "\(Int(display.srgbAreaPercent.rounded()))%"),
            ("Display P3", NSColor(hex: 0xFFB86B), "\(Int(display.p3AreaPercent.rounded()))%"),
            ("Adobe RGB", NSColor(hex: 0xA78BFA), "\(Int(display.adobeRGBAreaPercent.rounded()))%")
        ]
        for row in rows {
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSRect(x: left, y: y - 8, width: width, height: 34).fill()
            row.1.setFill()
            NSRect(x: left + 10, y: y + 3, width: 4, height: 16).fill()
            drawText(row.0, in: NSRect(x: left + 24, y: y, width: 160, height: 22),
                     size: 13, color: .white.withAlphaComponent(0.75))
            drawText(row.2, in: NSRect(x: left + width - 70, y: y, width: 56, height: 22),
                     size: 13, color: row.1, centered: true)
            y -= 44
        }

        y -= 18
        drawText("本机 ICC", in: NSRect(x: left, y: y, width: width, height: 20),
                 size: 11, color: .white.withAlphaComponent(0.42))
        y -= 26
        drawText(display.profileName, in: NSRect(x: left, y: y, width: width, height: 24),
                 size: 15, color: .white.withAlphaComponent(0.82))
        y -= 28
        drawText(display.gamutSummary, in: NSRect(x: left, y: y, width: width, height: 22),
                 size: 12, color: .white.withAlphaComponent(0.52))
        y -= 40
        drawText("三角形面积比，仅反映 ICC 报告色域", in: NSRect(x: left, y: y, width: width, height: 20),
                 size: 10, color: .white.withAlphaComponent(0.32))
    }

    private func drawUniformity() {
        let isBlack = current.id == "blackUniformity"
        (isBlack ? NSColor.black : NSColor(displayP3Red: 1, green: 1, blue: 1, alpha: 1)).setFill()
        bounds.fill()
        let lineColor = isBlack ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.82)
        lineColor.setStroke()
        for i in 1..<5 {
            let path = NSBezierPath()
            let x = bounds.width * CGFloat(i) / 5
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: bounds.height))
            path.lineWidth = 2
            path.stroke()
        }
        for i in 1..<3 {
            let path = NSBezierPath()
            let y = bounds.height * CGFloat(i) / 3
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: bounds.width, y: y))
            path.lineWidth = 2
            path.stroke()
        }
        if labelsVisible {
            drawText(isBlack ? "BLACK UNIFORMITY 15-ZONE" : "WHITE UNIFORMITY 15-ZONE",
                     in: NSRect(x: 30, y: bounds.height - 44, width: 420, height: 20),
                     size: 11, color: lineColor.withAlphaComponent(0.9))
        }
    }

    private func drawHUD() {
        let title = "\(index + 1)/\(patterns.count)  \(current.title)"
        let subtitle = "\(current.subtitle)\(current.hexLabel.map { "  ·  \($0)" } ?? "")"
        let hint = "← → / 空格 切换   ·   点击切换   ·   Esc / 右键 退出   ·   L 标签   ·   G 灰阶   ·   P 色域"

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.96)
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.55)
        ]
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.46)
        ]

        let titleSize = (title as NSString).size(withAttributes: titleAttrs)
        let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttrs)
        let hintSize = (hint as NSString).size(withAttributes: hintAttrs)
        let width = max(titleSize.width, max(subtitleSize.width, hintSize.width)) + 56
        let height: CGFloat = 88
        let rect = NSRect(x: (bounds.width - width) / 2,
                          y: 28,
                          width: width,
                          height: height)
        NSColor.black.withAlphaComponent(0.76).setFill()
        let panel = NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16)
        panel.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        panel.lineWidth = 1
        panel.stroke()

        (title as NSString).draw(at: NSPoint(x: rect.minX + 28, y: rect.maxY - 32), withAttributes: titleAttrs)
        (subtitle as NSString).draw(at: NSPoint(x: rect.minX + 28, y: rect.maxY - 52), withAttributes: subtitleAttrs)
        (hint as NSString).draw(at: NSPoint(x: rect.midX - hintSize.width / 2, y: rect.minY + 14), withAttributes: hintAttrs)

    }

    private func drawBadge(text: String, at point: NSPoint, centered: Bool = false, color: NSColor = .white) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: color.withAlphaComponent(0.72)
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = centered ? NSPoint(x: point.x - size.width / 2, y: point.y) : point
        NSColor.black.withAlphaComponent(0.30).setFill()
        let background = NSRect(x: origin.x - 7, y: origin.y - 4, width: size.width + 14, height: size.height + 8)
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    private func drawText(_ text: String,
                          in rect: NSRect,
                          size: CGFloat,
                          color: NSColor,
                          centered: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private func readableColor(on color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55 ? .black : .white
    }
}
