import SwiftUI
import AppKit


struct PageHeader<Trailing: View>: View {
    let tab: AppTab
    @ViewBuilder var trailing: () -> Trailing

    init(tab: AppTab, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.tab = tab
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(text: tab.kicker, color: Palette.cyan.opacity(0.8))
                Text(tab.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text(tab.subtitle)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 20)
            trailing()
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.cyan
    var fixedMax: Double? = nil
    var lineWidth: CGFloat = 1.6
    var filled: Bool = false

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else {
                var flat = Path()
                flat.move(to: CGPoint(x: 0, y: size.height * 0.62))
                flat.addLine(to: CGPoint(x: size.width, y: size.height * 0.62))
                context.stroke(flat, with: .color(color.opacity(0.24)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                return
            }
            let maximum = max(fixedMax ?? (values.max() ?? 1), 0.0001)
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let normalized = max(0, min(1, value / maximum))
                let point = CGPoint(x: CGFloat(index) * step,
                                    y: size.height - CGFloat(normalized) * (size.height - 3) - 1.5)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            if filled {
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.28), color.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

struct LiveMetricPill: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color
    let values: [Double]
    var fixedMax: Double? = nil
    var accessory: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 2)
                if let accessory {
                    Text(accessory)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(color.opacity(0.8))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
            }
            Sparkline(values: values, color: color, fixedMax: fixedMax, lineWidth: 1.2)
                .frame(height: 14)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.035))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
    }
}

struct RingGauge: View {
    let value: Double
    let maximum: Double
    let color: Color
    var size: CGFloat = 104
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value / max(maximum, 0.001))))
                .stroke(
                    AngularGradient(colors: [color.opacity(0.45), color, color.opacity(0.85)],
                                    center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.28), radius: 7)
            Circle()
                .fill(color.opacity(0.07))
                .frame(width: size - lineWidth * 3.1, height: size - lineWidth * 3.1)
        }
        .frame(width: size, height: size)
    }
}

struct ChartSeries: Identifiable {
    let id = UUID()
    let name: String
    let color: Color
    let values: [Double]
    var fixedMax: Double? = nil
}

struct LiveChartCard: View {
    let title: String
    let subtitle: String
    let series: [ChartSeries]
    var height: CGFloat = 175
    var axisLabel: String = ""
    var trailing: AnyView? = nil

    private var axisMax: Double {
        let fixed = series.compactMap(\.fixedMax).max()
        if let fixed, fixed > 0 { return fixed }
        let observed = series.flatMap(\.values).max() ?? 1
        return max(observed * 1.18, 1)
    }

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            StatusDot(color: Palette.green)
                            Text(title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.textPrimary)
                        }
                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    if let trailing { trailing }
                }

                chart
                    .frame(height: height)

                HStack(spacing: 16) {
                    ForEach(series) { item in
                        HStack(spacing: 6) {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                            Text(item.name)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Palette.textSecondary)
                            Text(formatted(item.values.last ?? 0))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                        }
                    }
                    Spacer()
                    if !axisLabel.isEmpty {
                        Text(axisLabel)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
    }

    private var chart: some View {
        Canvas { context, size in
            let rightInset: CGFloat = 34
            let bottomInset: CGFloat = 16
            let plotWidth = max(1, size.width - rightInset)
            let plotHeight = max(1, size.height - bottomInset)
            let lineCount = 4

            for i in 0...lineCount {
                let fraction = CGFloat(i) / CGFloat(lineCount)
                let y = plotHeight - fraction * plotHeight
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: plotWidth, y: y))
                context.stroke(line, with: .color(Color.white.opacity(i == 0 ? 0.12 : 0.055)),
                               style: StrokeStyle(lineWidth: 1, dash: i == 0 ? [] : [3, 4]))
                let value = axisMax * Double(i) / Double(lineCount)
                let label = axisText(value)
                context.draw(
                    Text(label)
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary),
                    at: CGPoint(x: size.width - 2, y: y - 1),
                    anchor: .trailing
                )
            }

            for item in series {
                let values = item.values
                guard values.count > 1 else { continue }
                let step = plotWidth / CGFloat(values.count - 1)
                var path = Path()
                for (index, value) in values.enumerated() {
                    let normalized = max(0, min(1, value / max(axisMax, 0.0001)))
                    let point = CGPoint(x: CGFloat(index) * step,
                                        y: plotHeight - CGFloat(normalized) * plotHeight)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                if item.id == series.first?.id {
                    var fill = path
                    fill.addLine(to: CGPoint(x: plotWidth, y: plotHeight))
                    fill.addLine(to: CGPoint(x: 0, y: plotHeight))
                    fill.closeSubpath()
                    context.fill(fill, with: .linearGradient(
                        Gradient(colors: [item.color.opacity(0.18), item.color.opacity(0.0)]),
                        startPoint: .init(x: 0, y: 0),
                        endPoint: .init(x: 0, y: plotHeight)
                    ))
                }
                context.stroke(path, with: .color(item.color),
                               style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }

            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: plotHeight))
            baseline.addLine(to: CGPoint(x: plotWidth, y: plotHeight))
            context.stroke(baseline, with: .color(Color.white.opacity(0.14)), lineWidth: 1)
        }
    }

    private func axisText(_ value: Double) -> String {
        if axisMax >= 100 { return String(format: "%.0f", value) }
        if axisMax >= 10 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    private func formatted(_ value: Double) -> String {
        if axisMax >= 100 { return String(format: "%.0f", value) }
        if axisMax >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}

struct ScoreTile: View {
    let label: String
    let value: String
    let unit: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.11)))
                Spacer()
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textTertiary)
            }
            Text(detail)
                .font(.system(size: 9.5, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.045))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(color.opacity(0.14), lineWidth: 1)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = Palette.textPrimary
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                if let detail {
                    Text(detail)
                        .font(.system(size: 8.5, weight: .regular))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(.vertical, 7)
    }
}

struct ProgressTrack: View {
    let progress: Double
    var color: Color = Palette.cyan

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * max(0.006, min(1, progress)))
                    .shadow(color: color.opacity(0.35), radius: 6)
            }
        }
        .frame(height: 6)
    }
}

struct QuickActionCard: View {
    let tab: AppTab
    let detail: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textTertiary)
                }
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .frame(height: 26, alignment: .top)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.032))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.065), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
