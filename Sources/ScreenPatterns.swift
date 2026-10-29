import AppKit

enum ScreenPatternKind {
    case solid
    case graySteps
    case nearBlack
    case colorBars
    case rgbRamp
    case hueSweep
    case gamutCompare
    case gamutTriangle
    case uniformity
}

struct ScreenPattern: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: String
    let kind: ScreenPatternKind
    let color: NSColor?

    var hexLabel: String? {
        guard let color, let srgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((srgb.redComponent * 255).rounded())
        let g = Int((srgb.greenComponent * 255).rounded())
        let b = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

enum ScreenPatternCatalog {
    private static func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(displayP3Red: r, green: g, blue: b, alpha: 1)
    }

    private static func gray(_ value: CGFloat) -> NSColor {
        NSColor(displayP3Red: value, green: value, blue: value, alpha: 1)
    }

    static let all: [ScreenPattern] = [
        ScreenPattern(id: "white", title: "纯白", subtitle: "检查亮度、色温与均匀性",
                      category: "纯色", kind: .solid, color: .white),
        ScreenPattern(id: "gray50", title: "50% 灰", subtitle: "中性灰参考",
                      category: "纯色", kind: .solid, color: gray(0.5)),
        ScreenPattern(id: "gray18", title: "18% 灰", subtitle: "常见摄影中性灰",
                      category: "纯色", kind: .solid, color: gray(0.18)),
        ScreenPattern(id: "black", title: "纯黑", subtitle: "检查漏光与黑位",
                      category: "纯色", kind: .solid, color: .black),
        ScreenPattern(id: "red", title: "纯红", subtitle: "P3 红色原色",
                      category: "纯色", kind: .solid, color: p3(1, 0, 0)),
        ScreenPattern(id: "green", title: "纯绿", subtitle: "P3 绿色原色",
                      category: "纯色", kind: .solid, color: p3(0, 1, 0)),
        ScreenPattern(id: "blue", title: "纯蓝", subtitle: "P3 蓝色原色",
                      category: "纯色", kind: .solid, color: p3(0, 0, 1)),
        ScreenPattern(id: "cyan", title: "青色", subtitle: "P3 二次色",
                      category: "纯色", kind: .solid, color: p3(0, 1, 1)),
        ScreenPattern(id: "magenta", title: "洋红", subtitle: "P3 二次色",
                      category: "纯色", kind: .solid, color: p3(1, 0, 1)),
        ScreenPattern(id: "yellow", title: "黄色", subtitle: "P3 二次色",
                      category: "纯色", kind: .solid, color: p3(1, 1, 0)),
        ScreenPattern(id: "graySteps", title: "灰阶 21 级", subtitle: "0–100% 灰阶过渡",
                      category: "灰阶", kind: .graySteps, color: nil),
        ScreenPattern(id: "nearBlack", title: "近黑 11 级", subtitle: "0–10% 黑位分辨",
                      category: "灰阶", kind: .nearBlack, color: nil),
        ScreenPattern(id: "rgbRamp", title: "RGB 渐变", subtitle: "R / G / B 独立色阶",
                      category: "灰阶", kind: .rgbRamp, color: nil),
        ScreenPattern(id: "hueSweep", title: "色相扫描", subtitle: "观察色带与过渡",
                      category: "灰阶", kind: .hueSweep, color: nil),
        ScreenPattern(id: "colorBars", title: "标准彩条", subtitle: "75% 彩条 + PLUGE",
                      category: "标准图", kind: .colorBars, color: nil),
        ScreenPattern(id: "gamutCompare", title: "sRGB / P3 对比", subtitle: "同数值不同色域",
                      category: "色域", kind: .gamutCompare, color: nil),
        ScreenPattern(id: "gamutTriangle", title: "色域三角", subtitle: "CIE 1931 xy 色度图",
                      category: "色域", kind: .gamutTriangle, color: nil),
        ScreenPattern(id: "uniformity", title: "白场网格", subtitle: "15 区亮度与色温检查",
                      category: "均匀性", kind: .uniformity, color: nil),
        ScreenPattern(id: "blackUniformity", title: "黑场网格", subtitle: "检查背光漏光分布",
                      category: "均匀性", kind: .uniformity, color: .black)
    ]

    static func index(of id: String) -> Int {
        all.firstIndex(where: { $0.id == id }) ?? 0
    }

    static let categories = ["纯色", "灰阶", "标准图", "色域", "均匀性"]
}
