import SwiftUI

struct CPUBenchView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @StateObject private var runner = CPUBenchmarkRunner()
    @StateObject private var viewState = CPUBenchViewState()

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(tab: .cpu) {
                SmallTag(text: "单核 2.4s + 多核 4.0s", color: Palette.cyan)
            }

            HStack(alignment: .top, spacing: 14) {
                controlCard.frame(width: 316)
                VStack(spacing: 14) {
                    resultGrid
                    LiveChartCard(
                        title: "测试实时曲线",
                        subtitle: "观察负载、温度与频率受限时的表现",
                        series: [
                            ChartSeries(name: "CPU", color: Palette.cyan, values: monitor.cpuHistory, fixedMax: 100),
                            ChartSeries(name: "温度", color: Palette.orange, values: monitor.temperatureHistory, fixedMax: 125)
                        ],
                        height: 184,
                        axisLabel: "% / °C",
                        trailing: AnyView(
                            HStack(spacing: 7) {
                                peakChip(label: "峰值温度", value: viewState.peakTemperature > 0 ? "\(Int(viewState.peakTemperature.rounded()))°C" : "--")
                                peakChip(label: "峰值功耗", value: viewState.peakPower > 0 ? "\(Fmt.watts(viewState.peakPower))W" : "--")
                            }
                        )
                    )
                }
            }

            HStack(alignment: .top, spacing: 14) {
                infoCard(
                    icon: "function",
                    title: "负载构成",
                    body: "每轮执行 xorshift 整数混合、双精度除法与累加。单核固定 2.4 秒，多核使用全部 \(SystemInfo.totalCores) 个核心持续 4 秒，期间每秒刷新温度与功耗。"
                )
                infoCard(
                    icon: "chart.bar.xaxis",
                    title: "分数说明",
                    body: "分数单位为 Mops/s，即每秒完成的百万次工作单元。多核效率 = 多核吞吐 ÷（单核吞吐 × 核心数）。适合本机前后对比，不建议跨架构直接比较。"
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPerfStartCPUBench)) { _ in
            startBenchmark()
        }
        .onChange(of: monitor.cpuTemperature) { _, value in
            guard runner.running else { return }
            viewState.peakTemperature = max(viewState.peakTemperature, value)
        }
        .onChange(of: monitor.systemPower) { _, value in
            guard runner.running else { return }
            viewState.peakPower = max(viewState.peakPower, value)
        }
        .onChange(of: monitor.cpuUsage) { _, value in
            guard runner.running else { return }
            viewState.peakCPU = max(viewState.peakCPU, value)
        }
    }

    private func startBenchmark() {
        guard !runner.running else { return }
        viewState.peakTemperature = monitor.cpuTemperature
        viewState.peakPower = monitor.systemPower
        viewState.peakCPU = monitor.cpuUsage
        runner.start()
    }

    private var controlCard: some View {
        Card(padding: 18, accent: runner.running ? Palette.cyan : nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "cpu")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.cyan)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.cyan.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel(text: "CPU BENCHMARK", color: Palette.cyan.opacity(0.8))
                        Text(runner.running ? runner.phase : (runner.result == nil ? "准备就绪" : "测试完成"))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer()
                }

                Text("混合整数与浮点负载，分别测量单线程和多线程的持续吞吐。测试时请保持电源连接，并关闭占用 CPU 的后台任务。")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    SmallTag(text: "整数 ALU", color: Palette.cyan)
                    SmallTag(text: "双精度 FP", color: Palette.blue)
                    SmallTag(text: "全核心", color: Palette.violet)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(runner.running ? runner.phase : "进度")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text("\(Int((runner.progress * 100).rounded()))%")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.cyan)
                    }
                    ProgressTrack(progress: runner.running ? runner.progress : (runner.result == nil ? 0 : 1),
                                  color: Palette.cyan)
                }

                Button {
                    if runner.running {
                        runner.cancel()
                    } else {
                        startBenchmark()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: runner.running ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(runner.running ? "停止测试" : "开始 CPU 跑分")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: Palette.cyan, destructive: runner.running))
                .disabled(false)

                Divider().overlay(Palette.hairline)

                HStack {
                    metricMini(label: "线程", value: "\(runner.result?.threads ?? SystemInfo.totalCores)")
                    Spacer()
                    metricMini(label: "峰值负载", value: viewState.peakCPU > 0 ? "\(Int(viewState.peakCPU.rounded()))%" : "--")
                    Spacer()
                    metricMini(label: "耗时", value: runner.result.map { String(format: "%.1fs", $0.duration) } ?? "--")
                }
            }
        }
    }

    private var resultGrid: some View {
        HStack(spacing: 12) {
            ScoreTile(
                label: "单核分数",
                value: runner.result.map { Fmt.score($0.singleScore) } ?? "--",
                unit: "Mops/s",
                detail: "单线程持续吞吐",
                icon: "1.circle",
                color: Palette.cyan
            )
            ScoreTile(
                label: "多核分数",
                value: runner.result.map { Fmt.score($0.multiScore) } ?? "--",
                unit: "Mops/s",
                detail: "\(runner.result?.threads ?? SystemInfo.totalCores) 线程并行",
                icon: "square.grid.3x3.fill",
                color: Palette.blue
            )
            ScoreTile(
                label: "多核效率",
                value: runner.result.map { String(format: "%.0f", $0.efficiency) } ?? "--",
                unit: "%",
                detail: "并行扩展效率",
                icon: "arrow.up.right.circle",
                color: Palette.violet
            )
        }
    }

    private func peakChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .foregroundStyle(Palette.textPrimary)
                .monospacedDigit()
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.045)))
    }

    private func metricMini(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
        }
    }

    private func infoCard(icon: String, title: String, body: String) -> some View {
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.cyan.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.cyan.opacity(0.07)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text(body)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
