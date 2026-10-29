import SwiftUI
import AppKit

enum Palette {
    static let backgroundTop = Color(hex: "070B12")
    static let backgroundBottom = Color(hex: "0C1421")
    static let panel = Color(hex: "111A28")
    static let panelRaised = Color(hex: "162233")
    static let cyan = Color(hex: "4FE3C1")
    static let blue = Color(hex: "5B8CFF")
    static let violet = Color(hex: "A78BFA")
    static let orange = Color(hex: "FFB86B")
    static let red = Color(hex: "FF6B81")
    static let green = Color(hex: "6EE7A8")
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.36)
    static let hairline = Color.white.opacity(0.075)
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        switch cleaned.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >> 8) & 0xFF) / 255.0
            a = Double(value & 0xFF) / 255.0
        case 6:
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
            a = 1.0
        default:
            r = 1; g = 1; b = 1; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop, Palette.backgroundBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Palette.cyan.opacity(0.13), .clear],
                           center: UnitPoint(x: 0.83, y: 0.06),
                           startRadius: 4, endRadius: 560)
            RadialGradient(colors: [Palette.blue.opacity(0.13), .clear],
                           center: UnitPoint(x: 0.06, y: 0.92),
                           startRadius: 4, endRadius: 620)
            RadialGradient(colors: [Palette.violet.opacity(0.07), .clear],
                           center: UnitPoint(x: 0.55, y: 0.88),
                           startRadius: 4, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat
    var accent: Color?
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    init(padding: CGFloat = 20,
         accent: Color? = nil,
         cornerRadius: CGFloat = 22,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.accent = accent
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(colors: [
                            Color(hex: "162131").opacity(0.92),
                            Color(hex: "0E1724").opacity(0.94)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [
                            (accent ?? Color.white).opacity(accent == nil ? 0.11 : 0.34),
                            Color.white.opacity(0.035)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.28), radius: 22, x: 0, y: 12)
    }
}

struct SectionLabel: View {
    let text: String
    var color: Color = Palette.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.45)
            .foregroundStyle(color)
    }
}

struct StatusDot: View {
    var color: Color = Palette.green

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .frame(width: 14, height: 14)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.7), radius: 4)
        }
    }
}

struct SmallTag: View {
    let text: String
    var color: Color = Palette.cyan
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.black.opacity(0.82) : color)
            .background(
                Capsule().fill(filled ? color : color.opacity(0.10))
            )
            .overlay(
                Capsule().strokeBorder(color.opacity(filled ? 0 : 0.22), lineWidth: 1)
            )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Palette.cyan
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(destructive ? Color.white : Color(hex: "04110E"))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        destructive
                        ? AnyShapeStyle(LinearGradient(colors: [Palette.red, Color(hex: "E04F63")],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.78)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: destructive ? Palette.red.opacity(0.18) : color.opacity(0.22),
                    radius: 14, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.055))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

extension View {
    func panelShadow() -> some View {
        shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 10)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
