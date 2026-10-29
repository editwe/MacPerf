import SwiftUI
import Combine

extension AppTab {
    var accent: Color {
        switch self {
        case .overview: return Palette.cyan
        case .cpu: return Palette.cyan
        case .disk: return Palette.orange
        case .memory: return Palette.violet
        case .screen: return Palette.blue
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @StateObject private var viewState = ContentViewState()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppBackground()
            HStack(spacing: 0) {
                SidebarView(selection: $viewState.selection)
                VStack(spacing: 0) {
                    liveHeader
                    liveStrip
                    ScrollView(.vertical, showsIndicators: false) {
                        pageContent
                            .padding(.horizontal, 26)
                            .padding(.top, 22)
                            .padding(.bottom, 34)
                    }
                    .id(viewState.selection)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1060, minHeight: 700)
        .background(Color.clear)
        .onAppear {
            WindowStyler.configureIfNeeded()
            monitor.refresh()
            if CommandLine.arguments.contains("--screen-test") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    viewState.selection = .screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NotificationCenter.default.post(name: .macPerfShowScreenTest, object: "graySteps")
                    }
                }
            }
        }
        .onReceive(timer) { _ in monitor.refresh() }
        .onOpenURL { url in handleURL(url) }
        .ignoresSafeArea(edges: .top)
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "macperf" else { return }
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        func flag(_ name: String) -> Bool {
            query.contains(where: { $0.name == name && ($0.value == "1" || $0.value == "true") })
        }
        if host == "screentest" {
            if flag("close") {
                NotificationCenter.default.post(name: .macPerfCloseScreenTest, object: nil)
                return
            }
            viewState.selection = .screen
            let pattern = query.first(where: { $0.name == "pattern" })?.value ?? "white"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NotificationCenter.default.post(name: .macPerfShowScreenTest, object: pattern)
            }
            return
        }
        if let tab = AppTab(rawValue: host) {
            viewState.selection = tab
            guard flag("run") else { return }
            let name: Notification.Name?
            switch tab {
            case .cpu: name = .macPerfStartCPUBench
            case .disk: name = .macPerfStartDiskBench
            case .memory: name = .macPerfStartMemoryBench
            default: name = nil
            }
            if let name {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    NotificationCenter.default.post(name: name, object: nil)
                }
            }
        }
    }

    private var liveHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            StatusDot(color: Palette.green)
            Text("实时监测")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.textPrimary)
            Text(monitor.lastRefresh, style: .time)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
            Spacer()
            HStack(spacing: 8) {
                SmallTag(text: monitor.smcAvailable ? "SMC 在线" : "SMC 不可用",
                         color: monitor.smcAvailable ? Palette.green : Palette.orange)
                SmallTag(text: "1s 刷新", color: Palette.textTertiary)
                SmallTag(text: monitor.thermalState, color: thermalColor)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 44)
        .padding(.bottom, 10)
    }

    private var liveStrip: some View {
        HStack(spacing: 8) {
            LiveMetricPill(
                icon: "cpu",
                label: "CPU",
                value: Fmt.percent(monitor.cpuUsage),
                unit: "%",
                color: Palette.cyan,
                values: monitor.cpuHistory,
                fixedMax: 100,
                accessory: "\(SystemInfo.totalCores) 核"
            )
            LiveMetricPill(
                icon: "square.stack.3d.up",
                label: "GPU",
                value: Fmt.percent(monitor.gpuUsage),
                unit: "%",
                color: Palette.blue,
                values: monitor.gpuHistory,
                fixedMax: 100,
                accessory: "GPU"
            )
            LiveMetricPill(
                icon: "memorychip",
                label: "内存",
                value: Fmt.memoryGB(monitor.memoryUsed),
                unit: "GB",
                color: Palette.violet,
                values: monitor.memoryHistory,
                fixedMax: 100,
                accessory: Fmt.percent(monitor.memoryUsed / max(monitor.memoryTotal, 1) * 100) + "%"
            )
            LiveMetricPill(
                icon: "thermometer.medium",
                label: "温度",
                value: Fmt.temperature(max(monitor.cpuTemperature, monitor.gpuTemperature)),
                unit: "°C",
                color: temperatureColor,
                values: monitor.temperatureHistory,
                fixedMax: 125,
                accessory: monitor.cpuTemperature > 0 ? "MAX" : "N/A"
            )
            LiveMetricPill(
                icon: "bolt.fill",
                label: "整机功耗",
                value: Fmt.watts(monitor.systemPower),
                unit: "W",
                color: Palette.orange,
                values: monitor.powerHistory,
                fixedMax: 35,
                accessory: monitor.powerSource == "电池遥测" ? "电池" : "SMC"
            )
            LiveMetricPill(
                icon: "internaldrive",
                label: "磁盘",
                value: Fmt.rateValue(monitor.diskReadRate + monitor.diskWriteRate),
                unit: Fmt.rateUnit(monitor.diskReadRate + monitor.diskWriteRate),
                color: Palette.green,
                values: zip(monitor.diskReadHistory, monitor.diskWriteHistory).map(+),
                fixedMax: 600,
                accessory: "R+W"
            )
        }
        .padding(.horizontal, 26)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch viewState.selection {
        case .overview:
            OverviewView(selection: $viewState.selection)
        case .cpu:
            CPUBenchView()
        case .disk:
            DiskBenchView()
        case .memory:
            MemoryBenchView()
        case .screen:
            ScreenTestView()
        }
    }

    private var temperatureColor: Color {
        let temp = max(monitor.cpuTemperature, monitor.gpuTemperature)
        if temp >= 90 { return Palette.red }
        if temp >= 75 { return Palette.orange }
        return Palette.green
    }

    private var thermalColor: Color {
        switch monitor.thermalState {
        case "正常": return Palette.textTertiary
        case "偏热": return Palette.orange
        default: return Palette.red
        }
    }
}

struct SidebarView: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.cyan, Palette.blue],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "speedometer")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "071018"))
                }
                .frame(width: 36, height: 36)
                .shadow(color: Palette.cyan.opacity(0.25), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MacPerf")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text("性能测评")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(Palette.cyan.opacity(0.7))
                }
            }
            .padding(.top, 54)
            .padding(.horizontal, 20)

            Text("WORKSPACE")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 34)
                .padding(.leading, 22)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(AppTab.allCases) { tab in
                    SidebarButton(tab: tab,
                                  selected: selection == tab,
                                  action: {
                        selection = tab
                    })
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    StatusDot(color: Palette.green)
                    Text("传感器在线")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(SystemInfo.chip)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(SystemInfo.coreSummary)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                Text(SystemInfo.memorySummary)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(Palette.textTertiary)
                HStack {
                    Text("v1.0")
                    Spacer()
                    Text(SystemInfo.modelIdentifier)
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.032))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background {
            LinearGradient(colors: [Color(hex: "0A111C").opacity(0.96),
                                    Color(hex: "080D16").opacity(0.92)],
                           startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.055)).frame(width: 1)
        }
    }
}

struct SidebarButton: View {
    let tab: AppTab
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? tab.accent : Palette.textSecondary)
                    .frame(width: 22)
                Text(tab.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                Spacer()
                if selected {
                    Circle()
                        .fill(tab.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: tab.accent.opacity(0.8), radius: 5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [tab.accent.opacity(0.16),
                                                                 tab.accent.opacity(0.04)],
                                                         startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(hover.isHovering ? Color.white.opacity(0.045) : Color.clear))
            }
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(tab.accent)
                        .frame(width: 3, height: 18)
                        .shadow(color: tab.accent.opacity(0.45), radius: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover.isHovering = $0 }
    }
}
