import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @Binding var selection: AppTab

    private var storage: (total: UInt64, free: UInt64)? { SystemInfo.storage }

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(tab: .overview) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.textTertiary)
                    Text("已运行 \(uptimeText)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                deviceHero
                powerCard.frame(width: 274, height: 238)
            }

            HStack(spacing: 13) {
                gaugeCard(title: "CPU 占用", icon: "cpu", value: monitor.cpuUsage,
                          display: Fmt.percent(monitor.cpuUsage) + "%",
                          detail: SystemInfo.coreSummary,
                          color: Palette.cyan, maximum: 100)
                gaugeCard(title: "GPU 占用", icon: "square.stack.3d.up", value: monitor.gpuUsage,
                          display: Fmt.percent(monitor.gpuUsage) + "%",
                          detail: "Metal 图形负载",
                          color: Palette.blue, maximum: 100)
                gaugeCard(title: "内存占用", icon: "memorychip",
                          value: monitor.memoryUsed / max(monitor.memoryTotal, 1) * 100,
                          display: Fmt.percent(monitor.memoryUsed / max(monitor.memoryTotal, 1) * 100) + "%",
                          detail: "\(Fmt.memoryGB(monitor.memoryUsed)) / \(Fmt.memoryGB(monitor.memoryTotal)) GB",
                          color: Palette.violet, maximum: 100)
                gaugeCard(title: "存储使用", icon: "internaldrive",
                          value: storageUsagePercent,
                          display: Fmt.percent(storageUsagePercent) + "%",
                          detail: "可用 \(freeSpaceText)",
                          color: Palette.orange, maximum: 100)
            }

            HStack(alignment: .top, spacing: 14) {
                LiveChartCard(
                    title: "系统实时曲线",
                    subtitle: "最近 90 秒 · CPU / GPU / 温度",
                    series: [
                        ChartSeries(name: "CPU", color: Palette.cyan, values: monitor.cpuHistory, fixedMax: 100),
                        ChartSeries(name: "GPU", color: Palette.blue, values: monitor.gpuHistory, fixedMax: 100),
                        ChartSeries(name: "温度", color: Palette.orange, values: monitor.temperatureHistory, fixedMax: 125)
                    ],
                    height: 188,
                    axisLabel: "% / °C"
                )

                sensorCard.frame(width: 292)
            }

            HStack(spacing: 12) {
                QuickActionCard(tab: .cpu, detail: "单核 / 多核混合负载", color: Palette.cyan) {
                    selection = .cpu
                }
                QuickActionCard(tab: .disk, detail: "顺序读写 + 4K 随机", color: Palette.orange) {
                    selection = .disk
                }
                QuickActionCard(tab: .memory, detail: "读 / 写 / 拷贝 / 延迟", color: Palette.violet) {
                    selection = .memory
                }
                QuickActionCard(tab: .screen, detail: "纯色 · 灰阶 · 色域", color: Palette.blue) {
                    selection = .screen
                }
            }
        }
    }

    private var deviceHero: some View {
        Card(padding: 0, accent: Palette.cyan) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "THIS MACHINE", color: Palette.cyan.opacity(0.8))
                    Text(SystemInfo.chip)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(SystemInfo.deviceLine)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                    HStack(spacing: 7) {
                        SmallTag(text: SystemInfo.coreSummary, color: Palette.cyan)
                        SmallTag(text: SystemInfo.memorySummary, color: Palette.blue)
                        SmallTag(text: "硬件加速", color: Palette.violet)
                    }
                    Spacer(minLength: 2)
                    HStack(spacing: 18) {
                        miniStat(label: "架构", value: SystemInfo.architecture)
                        miniStat(label: "系统", value: SystemInfo.osVersion)
                        miniStat(label: "主机", value: SystemInfo.hostName)
                    }
                }
                Spacer(minLength: 12)
                ZStack {
                    ForEach(0..<3) { ring in
                        Circle()
                            .stroke(
                                LinearGradient(colors: [Palette.cyan.opacity(0.55 - Double(ring) * 0.14),
                                                        Palette.blue.opacity(0.05)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                            .frame(width: CGFloat(108 + ring * 32), height: CGFloat(108 + ring * 32))
                    }
                    Circle()
                        .fill(Palette.cyan.opacity(0.08))
                        .frame(width: 94, height: 94)
                        .blur(radius: 10)
                    Image(systemName: "cpu")
                        .font(.system(size: 54, weight: .ultraLight))
                        .foregroundStyle(
                            LinearGradient(colors: [Palette.cyan, Palette.blue],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: Palette.cyan.opacity(0.35), radius: 16)
                }
                .frame(width: 210, height: 160)
                .padding(.trailing, 12)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 238, alignment: .leading)
            .background {
                ZStack {
                    RadialGradient(colors: [Palette.cyan.opacity(0.08), .clear],
                                   center: .topTrailing, startRadius: 10, endRadius: 330)
                    LinearGradient(colors: [Color.white.opacity(0.02), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
    }

    private var powerCard: some View {
        Card(padding: 18, accent: Palette.orange) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "POWER", color: Palette.orange.opacity(0.8))
                    Spacer()
                    SmallTag(text: monitor.powerSource, color: Palette.orange)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Fmt.watts(monitor.systemPower))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                    Text("W")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textTertiary)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: monitor.isCharging ? "bolt.fill" : (monitor.isExternalPower ? "powerplug.fill" : "battery.75"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.orange)
                        Text(monitor.batteryPercent.map { "\($0)%" } ?? "--")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                    }
                }
                ProgressTrack(progress: min(1, monitor.systemPower / 35), color: Palette.orange)
                Spacer(minLength: 4)
                InfoRow(icon: "thermometer.medium", label: "电池温度", value: Fmt.temperature(monitor.batteryTemperature) + " °C")
                InfoRow(icon: "waveform.path.ecg", label: "热压状态", value: monitor.thermalState,
                        color: monitor.thermalState == "正常" ? Palette.green : Palette.orange)
                Spacer(minLength: 0)
                Text(monitor.smcAvailable ? "SMC 直读 · 无需管理员权限" : "未检测到 SMC 温度传感器")
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func gaugeCard(title: String,
                           icon: String,
                           value: Double,
                           display: String,
                           detail: String,
                           color: Color,
                           maximum: Double) -> some View {
        Card(padding: 15) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                }
                ZStack {
                    RingGauge(value: value, maximum: maximum, color: color, size: 82, lineWidth: 7)
                    Text(display)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textPrimary)
                        .minimumScaleFactor(0.7)
                }
                Text(detail)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sensorCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    SectionLabel(text: "SENSORS")
                    Spacer()
                    StatusDot(color: monitor.smcAvailable ? Palette.green : Palette.orange)
                }
                .padding(.bottom, 8)
                InfoRow(icon: "cpu", label: "CPU 核心温度", value: Fmt.temperature(monitor.cpuTemperature) + " °C",
                        color: temperatureColor(monitor.cpuTemperature),
                        detail: monitor.cpuSensorCount > 0 ? "\(monitor.cpuSensorCount) 个传感器 · 取最高" : nil)
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "square.stack.3d.up", label: "GPU 温度", value: Fmt.temperature(monitor.gpuTemperature) + " °C",
                        color: temperatureColor(monitor.gpuTemperature),
                        detail: monitor.gpuSensorCount > 0 ? "\(monitor.gpuSensorCount) 个传感器 · 取最高" : nil)
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "battery.75", label: "电池温度", value: Fmt.temperature(monitor.batteryTemperature) + " °C")
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "bolt.fill", label: "整机功耗", value: Fmt.watts(monitor.systemPower) + " W",
                        color: Palette.orange,
                        detail: monitor.smcPower > 0 ? "SMC PSTR \(Fmt.watts(monitor.smcPower)) W" : nil)
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "memorychip", label: "交换空间", value: monitor.swapUsed > 0 ? Fmt.memoryGB(monitor.swapUsed) + " GB" : "0 GB")
                Spacer(minLength: 0)
                Text("温度取对应传感器组最高值，功耗来自电池遥测 / SMC。")
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 8)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
    }

    private func temperatureColor(_ value: Double) -> Color {
        if value >= 90 { return Palette.red }
        if value >= 75 { return Palette.orange }
        return Palette.green
    }

    private var storageUsagePercent: Double {
        guard let storage, storage.total > 0 else { return 0 }
        return Double(storage.total - storage.free) / Double(storage.total) * 100
    }

    private var freeSpaceText: String {
        guard let storage else { return "--" }
        return String(format: "%.0f GB", Double(storage.free) / 1_073_741_824.0)
    }

    private var uptimeText: String {
        let total = Int(SystemInfo.uptime)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }
}
