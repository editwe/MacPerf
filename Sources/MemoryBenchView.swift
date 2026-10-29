import SwiftUI

struct MemoryBenchView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @StateObject private var runner = MemoryBenchmarkRunner()
    @StateObject private var viewState = MemoryBenchViewState()

    private let sizes = [128, 256, 512]

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(tab: .memory) {
                SmallTag(text: "\(monitor.memoryPressure) · 已用 \(Fmt.percent(monitor.memoryUsed / max(monitor.memoryTotal, 1) * 100))%",
                         color: monitor.memoryPressure == "正常" ? Palette.violet : Palette.orange)
            }

            HStack(alignment: .top, spacing: 14) {
                controlCard.frame(width: 316)
                VStack(spacing: 14) {
                    resultGrid
                    LiveChartCard(
                        title: "内存与 CPU 实时曲线",
                        subtitle: "测试时观察内存占用和处理器配合",
                        series: [
                            ChartSeries(name: "内存占用", color: Palette.violet, values: monitor.memoryHistory, fixedMax: 100),
                            ChartSeries(name: "CPU", color: Palette.cyan, values: monitor.cpuHistory, fixedMax: 100)
                        ],
                        height: 184,
                        axisLabel: "%",
                        trailing: AnyView(
                            HStack(spacing: 7) {
                                peakChip(label: "延迟", value: runner.result.map { String(format: "%.0f ns", $0.latencyNanoseconds) } ?? "--")
                                peakChip(label: "交换", value: monitor.swapUsed > 0 ? Fmt.memoryGB(monitor.swapUsed) + "G" : "0G")
                            }
                        )
                    )
                }
            }

            HStack(alignment: .top, spacing: 14) {
                methodCard
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.violet)
                            Text("测试说明")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.textPrimary)
                        }
                        Text("测试会按所选容量分配三块缓冲区（Triad 需要三路数据），默认 256MB，共约 768MB 临时内存。测试结束立即释放，不会写入磁盘。若系统内存紧张，建议选择 128MB。")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPerfStartMemoryBench)) { _ in
            guard !runner.running else { return }
            runner.start(sizeMB: viewState.sizeMB)
        }
    }

    private var controlCard: some View {
        Card(padding: 18, accent: runner.running ? Palette.violet : nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "memorychip")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.violet)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.violet.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel(text: "MEMORY BENCHMARK", color: Palette.violet.opacity(0.8))
                        Text(runner.running ? runner.phase : (runner.result == nil ? "准备就绪" : "测试完成"))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer()
                }

                Text("测试容量")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.textSecondary)
                HStack(spacing: 6) {
                    ForEach(sizes, id: \.self) { size in
                        Button {
                            viewState.sizeMB = size
                        } label: {
                            Text("\(size) MB")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(viewState.sizeMB == size ? Color(hex: "071018") : Palette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(viewState.sizeMB == size ? Palette.violet : Color.white.opacity(0.045))
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(runner.running)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(runner.running ? runner.phase : "进度")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text("\(Int((runner.progress * 100).rounded()))%")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.violet)
                    }
                    ProgressTrack(progress: runner.running ? runner.progress : (runner.result == nil ? 0 : 1),
                                  color: Palette.violet)
                }

                Button {
                    if runner.running {
                        runner.cancel()
                    } else {
                        runner.start(sizeMB: viewState.sizeMB)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: runner.running ? "stop.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(runner.running ? "停止测试" : "开始内存测速")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: Palette.violet, destructive: runner.running))

                if let error = runner.errorMessage {
                    Text(error)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Palette.hairline)

                HStack {
                    metricMini(label: "缓存块", value: "\(viewState.sizeMB * 3) MB")
                    Spacer()
                    metricMini(label: "内存压力", value: monitor.memoryPressure)
                    Spacer()
                    metricMini(label: "线程", value: "\(min(4, ProcessInfo.processInfo.activeProcessorCount))")
                }
            }
        }
    }

    private var resultGrid: some View {
        HStack(spacing: 12) {
            ScoreTile(
                label: "顺序读取",
                value: runner.result.map { Fmt.throughputGB($0.readBytesPerSecond) } ?? "--",
                unit: "GB/s",
                detail: "多线程双流",
                icon: "arrow.up.from.line",
                color: Palette.violet
            )
            ScoreTile(
                label: "顺序写入",
                value: runner.result.map { Fmt.throughputGB($0.writeBytesPerSecond) } ?? "--",
                unit: "GB/s",
                detail: "多线程写入",
                icon: "arrow.down.to.line",
                color: Palette.blue
            )
            ScoreTile(
                label: "拷贝带宽",
                value: runner.result.map { Fmt.throughputGB($0.copyBytesPerSecond) } ?? "--",
                unit: "GB/s",
                detail: "多线程读写",
                icon: "doc.on.doc",
                color: Palette.cyan
            )
            ScoreTile(
                label: "Triad",
                value: runner.result.map { Fmt.throughputGB($0.triadBytesPerSecond) } ?? "--",
                unit: "GB/s",
                detail: "多线程三路",
                icon: "function",
                color: Palette.orange
            )
        }
    }

    private var methodCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "MEMORY")
                    Spacer()
                    SmallTag(text: "统一内存", color: Palette.violet)
                }
                InfoRow(icon: "memorychip", label: "物理内存", value: Fmt.memoryGB(monitor.memoryTotal) + " GB")
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "chart.bar", label: "已用 / 压力", value: "\(Fmt.memoryGB(monitor.memoryUsed)) GB · \(monitor.memoryPressure)")
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "arrow.triangle.2.circlepath", label: "交换空间", value: monitor.swapUsed > 0 ? Fmt.memoryGB(monitor.swapUsed) + " GB" : "0 GB")
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "timer", label: "随机延迟", value: runner.result.map { String(format: "%.0f ns", $0.latencyNanoseconds) } ?? "--",
                        detail: "100 万次指针追逐 · 32MB")
            }
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
}
