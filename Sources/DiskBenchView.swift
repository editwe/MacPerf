import SwiftUI

struct DiskBenchView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @StateObject private var runner = DiskBenchmarkRunner()
    @StateObject private var viewState = DiskBenchViewState()

    private let sizes = [256, 512, 1024, 2048]

    var body: some View {
        VStack(spacing: 16) {
            PageHeader(tab: .disk) {
                SmallTag(text: "可用 \(freeSpaceText)", color: Palette.orange)
            }

            HStack(alignment: .top, spacing: 14) {
                controlCard.frame(width: 316)
                VStack(spacing: 14) {
                    resultGrid
                    LiveChartCard(
                        title: "磁盘实时吞吐",
                        subtitle: "测试期间读写速率，单位 MB/s",
                        series: [
                            ChartSeries(name: "读取", color: Palette.orange, values: monitor.diskReadHistory),
                            ChartSeries(name: "写入", color: Palette.cyan, values: monitor.diskWriteHistory)
                        ],
                        height: 184,
                        axisLabel: "MB/s",
                        trailing: AnyView(
                            HStack(spacing: 7) {
                                peakChip(label: "读速", value: Fmt.rate(monitor.diskReadRate))
                                peakChip(label: "写速", value: Fmt.rate(monitor.diskWriteRate))
                            }
                        )
                    )
                }
            }

            HStack(alignment: .top, spacing: 14) {
                detailCard
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.orange)
                            Text("测试说明")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.textPrimary)
                        }
                        Text("测试文件写入系统临时目录并自动删除。使用 F_NOCACHE 绕过文件缓存，写入阶段包含 fsync 落盘。建议关闭正在下载、同步或视频剪辑等磁盘任务。")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macPerfStartDiskBench)) { _ in
            guard !runner.running else { return }
            runner.start(sizeMB: viewState.sizeMB)
        }
    }

    private var controlCard: some View {
        Card(padding: 18, accent: runner.running ? Palette.orange : nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.orange)
                        .frame(width: 42, height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.orange.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel(text: "DISK BENCHMARK", color: Palette.orange.opacity(0.8))
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
                            Text(size >= 1024 ? String(format: "%.0fG", Double(size) / 1024.0) : "\(size)M")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(viewState.sizeMB == size ? Color(hex: "071018") : Palette.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(viewState.sizeMB == size ? Palette.orange : Color.white.opacity(0.045))
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
                            .foregroundStyle(Palette.orange)
                    }
                    ProgressTrack(progress: runner.running ? runner.progress : (runner.result == nil ? 0 : 1),
                                  color: Palette.orange)
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
                        Text(runner.running ? "停止测试" : "开始硬盘测速")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(color: Palette.orange, destructive: runner.running))

                if let error = runner.errorMessage {
                    Text(error)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Palette.hairline)

                HStack {
                    metricMini(label: "测试容量", value: "\(viewState.sizeMB) MB")
                    Spacer()
                    metricMini(label: "读取缓存", value: "已绕过")
                    Spacer()
                    metricMini(label: "随机块", value: "4 KB")
                }
            }
        }
    }

    private var resultGrid: some View {
        HStack(spacing: 12) {
            ScoreTile(
                label: "顺序写入",
                value: runner.result.map { Fmt.rateValue($0.writeBytesPerSecond) } ?? "--",
                unit: runner.result.map { Fmt.rateUnit($0.writeBytesPerSecond) } ?? "MB/s",
                detail: "含 fsync 落盘",
                icon: "arrow.down.to.line",
                color: Palette.cyan
            )
            ScoreTile(
                label: "顺序读取",
                value: runner.result.map { Fmt.rateValue($0.readBytesPerSecond) } ?? "--",
                unit: runner.result.map { Fmt.rateUnit($0.readBytesPerSecond) } ?? "MB/s",
                detail: "F_NOCACHE 直读",
                icon: "arrow.up.from.line",
                color: Palette.orange
            )
            ScoreTile(
                label: "4K 随机读",
                value: runner.result.map { String(format: "%.0f", $0.randomReadIOPS) } ?? "--",
                unit: "IOPS",
                detail: "2,000 次随机读取",
                icon: "square.grid.2x2",
                color: Palette.violet
            )
        }
    }

    private var detailCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: "DEVICE")
                    Spacer()
                    SmallTag(text: "APFS", color: Palette.orange)
                }
                InfoRow(icon: "internaldrive", label: "卷宗", value: "Macintosh HD")
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "externaldrive", label: "可用空间", value: freeSpaceText)
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "arrow.left.arrow.right", label: "总读写", value: "\(Fmt.rate(Double(monitor.diskReadTotal)))  /  \(Fmt.rate(Double(monitor.diskWriteTotal)))")
                Divider().overlay(Palette.hairline)
                InfoRow(icon: "timer", label: "上次耗时", value: runner.result.map { String(format: "%.1f s", $0.duration) } ?? "--")
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

    private var freeSpaceText: String {
        guard let storage = SystemInfo.storage else { return "--" }
        return String(format: "%.0f GB", Double(storage.free) / 1_073_741_824.0)
    }
}
