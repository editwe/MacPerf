import SwiftUI
import AppKit

struct ScreenTestView: View {
    @StateObject private var presenter = ScreenTestPresenter()
    @StateObject private var viewState = ScreenTestViewState()

    private var selectedDisplay: DisplayDescriptor? {
        viewState.displays.first(where: { $0.id == viewState.selectedDisplayID }) ?? viewState.displays.first
    }

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(tab: .screen) {
                SmallTag(text: presenter.isPresenting ? "全屏测试中" : "手动切换", color: Palette.blue)
            }

            HStack(alignment: .top, spacing: 14) {
                displayCard.frame(width: 300)
                controlCard
            }

            ForEach(ScreenPatternCatalog.categories, id: \.self) { category in
                let patterns = ScreenPatternCatalog.all.filter { $0.category == category }
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        SectionLabel(text: category == "纯色" ? "SOLID COLORS" :
                                        category == "灰阶" ? "GRAYSCALE & RAMPS" :
                                        category == "标准图" ? "TEST PATTERNS" :
                                        category == "色域" ? "COLOR GAMUT" : "UNIFORMITY")
                        Spacer()
                        Text("\(patterns.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], spacing: 10) {
                        ForEach(patterns) { pattern in
                            patternButton(pattern)
                        }
                    }
                }
            }
        }
        .onAppear(perform: reloadDisplays)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            reloadDisplays()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPerfShowScreenTest)) { note in
            guard let display = selectedDisplay else { return }
            let id = note.object as? String ?? "white"
            presenter.show(startIndex: ScreenPatternCatalog.index(of: id), on: display)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPerfCloseScreenTest)) { _ in
            presenter.close()
        }
    }

    private var displayCard: some View {
        Card(padding: 16, accent: Palette.blue) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "DISPLAY")
                    Spacer()
                    SmallTag(text: selectedDisplay?.gamutName ?? "--", color: Palette.blue)
                }
                if viewState.displays.count > 1 {
                    Picker("显示器", selection: $viewState.selectedDisplayID) {
                        ForEach(viewState.displays) { display in
                            Text(display.name).tag(Optional(display.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                } else {
                    Text(selectedDisplay?.name ?? "未检测到显示器")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                }
                if let display = selectedDisplay {
                    InfoRow(icon: "rectangle.on.rectangle", label: "分辨率", value: display.resolutionText,
                            detail: display.logicalResolutionText)
                    Divider().overlay(Palette.hairline)
                    InfoRow(icon: "arrow.clockwise", label: "刷新率", value: display.refreshText)
                    Divider().overlay(Palette.hairline)
                    InfoRow(icon: "paintpalette", label: "ICC 描述", value: display.profileName)
                    Divider().overlay(Palette.hairline)
                    InfoRow(icon: "circle.lefthalf.filled", label: "色域容积", value: display.gamutSummary,
                            detail: "按 ICC 三角形面积")
                }
            }
            .frame(height: 250, alignment: .top)
        }
    }

    private var controlCard: some View {
        Card(padding: 18, accent: Palette.blue) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: "display")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.blue)
                        Text("全屏屏幕检测")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Text("进入全屏后，用方向键或点击手动切换测试图。所有图案都由程序实时绘制，不依赖外部图片。")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        SmallTag(text: "纯色", color: Palette.blue)
                        SmallTag(text: "灰阶", color: Palette.blue)
                        SmallTag(text: "色域", color: Palette.blue)
                        SmallTag(text: "均匀性", color: Palette.blue)
                    }
                    Button {
                        if let display = selectedDisplay {
                            presenter.show(startIndex: 0, on: display)
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("进入全屏测试")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Palette.blue))
                    .disabled(selectedDisplay == nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().overlay(Palette.hairline).frame(height: 160)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "CONTROLS")
                    controlKey("← → / 空格", "上一张 / 下一张")
                    controlKey("1 – 9", "跳到第 N 张")
                    controlKey("G / C / P / T", "灰阶 / 彩条 / 色域 / 三角")
                    controlKey("L", "显示或隐藏标签")
                    controlKey("Esc / 右键", "退出全屏")
                    Spacer(minLength: 0)
                    Text("提示：检查坏点、漏光、色带时建议关闭环境光，并逐张切换观察。")
                        .font(.system(size: 8.5, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 230, alignment: .leading)
            }
            .frame(height: 250, alignment: .top)
        }
    }

    private func patternButton(_ pattern: ScreenPattern) -> some View {
        Button {
            guard let display = selectedDisplay else { return }
            presenter.show(startIndex: ScreenPatternCatalog.index(of: pattern.id), on: display)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                PatternThumbnail(pattern: pattern)
                    .frame(height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .padding(8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(pattern.subtitle)
                        .font(.system(size: 8.5, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(viewState.hoveredPattern == pattern.id ? 0.06 : 0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(viewState.hoveredPattern == pattern.id ? Palette.blue.opacity(0.35) : Color.white.opacity(0.06),
                                  lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            viewState.hoveredPattern = inside ? pattern.id : (viewState.hoveredPattern == pattern.id ? nil : viewState.hoveredPattern)
        }
        .help("全屏显示「\(pattern.title)」")
    }

    private func controlKey(_ key: String, _ description: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)))
                .frame(width: 88, alignment: .leading)
            Text(description)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func reloadDisplays() {
        let loaded = DisplayInfo.load()
        viewState.displays = loaded
        if viewState.selectedDisplayID == nil || !loaded.contains(where: { $0.id == viewState.selectedDisplayID }) {
            viewState.selectedDisplayID = loaded.first(where: { $0.isMain })?.id ?? loaded.first?.id
        }
    }
}

struct PatternThumbnail: View {
    let pattern: ScreenPattern

    var body: some View {
        ZStack {
            switch pattern.kind {
            case .solid:
                Color(nsColor: pattern.color ?? .black)
            case .graySteps:
                HStack(spacing: 0) {
                    ForEach(0..<11, id: \.self) { i in
                        Color(white: Double(i) / 10.0)
                    }
                }
            case .nearBlack:
                HStack(spacing: 0) {
                    ForEach(0..<11, id: \.self) { i in
                        Color(white: Double(i) / 100.0)
                    }
                }
            case .colorBars:
                HStack(spacing: 0) {
                    Rectangle().fill(Color(hex: "C0C0C0"))
                    Rectangle().fill(Color(hex: "C0C000"))
                    Rectangle().fill(Color(hex: "00C0C0"))
                    Rectangle().fill(Color(hex: "00C000"))
                    Rectangle().fill(Color(hex: "C000C0"))
                    Rectangle().fill(Color(hex: "C00000"))
                    Rectangle().fill(Color(hex: "0000C0"))
                }
            case .rgbRamp:
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black, .red], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black, .green], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black, .blue], startPoint: .leading, endPoint: .trailing)
                }
            case .hueSweep:
                LinearGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                               startPoint: .leading, endPoint: .trailing)
            case .gamutCompare:
                HStack(spacing: 2) {
                    gamutHalf(wide: false)
                    gamutHalf(wide: true)
                }
            case .gamutTriangle:
                Canvas { context, size in
                    let sRGB = trianglePoints([(0.64, 0.33), (0.30, 0.60), (0.15, 0.06)], size)
                    let p3 = trianglePoints([(0.68, 0.32), (0.265, 0.69), (0.15, 0.06)], size)
                    var p1 = Path()
                    p1.addLines(sRGB); p1.closeSubpath()
                    var p2 = Path()
                    p2.addLines(p3); p2.closeSubpath()
                    context.fill(p1, with: .color(Palette.cyan.opacity(0.16)))
                    context.stroke(p1, with: .color(Palette.cyan), lineWidth: 1.2)
                    context.fill(p2, with: .color(Palette.orange.opacity(0.13)))
                    context.stroke(p2, with: .color(Palette.orange), lineWidth: 1.2)
                }
                .background(Color(hex: "070B12"))
            case .uniformity:
                let isBlack = pattern.id == "blackUniformity"
                (isBlack ? Color.black : Color.white)
                    .overlay {
                        GeometryReader { geo in
                            Path { path in
                                for i in 1..<5 {
                                    let x = geo.size.width * CGFloat(i) / 5
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                                }
                                for i in 1..<3 {
                                    let y = geo.size.height * CGFloat(i) / 3
                                    path.move(to: CGPoint(x: 0, y: y))
                                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                                }
                            }
                            .stroke(isBlack ? Color.white.opacity(0.12) : Color.black.opacity(0.6), lineWidth: 1)
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let hex = pattern.hexLabel, pattern.kind == .solid {
                Text(hex)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(5)
            }
        }
    }

    private func gamutHalf(wide: Bool) -> some View {
        let colors: [Color] = wide
            ? [Color(.displayP3, red: 1, green: 0, blue: 0), Color(.displayP3, red: 0, green: 1, blue: 0),
               Color(.displayP3, red: 0, green: 0, blue: 1), Color(.displayP3, red: 1, green: 0, blue: 1)]
            : [Color(.sRGB, red: 1, green: 0, blue: 0), Color(.sRGB, red: 0, green: 1, blue: 0),
               Color(.sRGB, red: 0, green: 0, blue: 1), Color(.sRGB, red: 1, green: 0, blue: 1)]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
            ForEach(0..<4, id: \.self) { index in
                colors[index]
            }
        }
    }

    private func trianglePoints(_ xy: [(CGFloat, CGFloat)], _ size: CGSize) -> [CGPoint] {
        xy.map { point in
            CGPoint(x: size.width * point.0 / 0.8,
                    y: size.height - size.height * point.1 / 0.9)
        }
    }
}
