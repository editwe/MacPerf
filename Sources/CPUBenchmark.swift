import Foundation
import Combine

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

enum CPUEngine {
    static func run(flag: CancellationFlag,
                    progress: @escaping (Double, String) -> Void) -> CPURunResult? {
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let start = DispatchTime.now().uptimeNanoseconds

        progress(0.02, "预热中")
        _ = measure(threads: 1, duration: 0.35, seed: 0xA5A5_1234, flag: flag) { p in
            progress(0.02 + p * 0.04, "预热中")
        }
        if flag.isCancelled { return nil }

        progress(0.08, "单核测试")
        guard let single = measure(threads: 1, duration: 2.4, seed: 0x1357_9BDF, flag: flag, progress: { p in
            progress(0.08 + p * 0.32, "单核测试")
        }) else { return nil }
        if flag.isCancelled { return nil }

        progress(0.42, "多核测试")
        guard let multi = measure(threads: threads, duration: 4.0, seed: 0x2468_ACE0, flag: flag, progress: { p in
            progress(0.42 + p * 0.53, "多核测试")
        }) else { return nil }
        if flag.isCancelled { return nil }

        let singleOps = Double(single.ops) / max(single.elapsed, 0.001)
        let multiOps = Double(multi.ops) / max(multi.elapsed, 0.001)
        let efficiency = singleOps > 0
            ? multiOps / (singleOps * Double(threads)) * 100.0
            : 0

        let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000.0
        progress(1.0, "测试完成")
        return CPURunResult(
            singleScore: singleOps / 1_000_000.0,
            multiScore: multiOps / 1_000_000.0,
            threads: threads,
            efficiency: efficiency,
            duration: duration,
            date: Date()
        )
    }

    private static func measure(threads: Int,
                                duration: TimeInterval,
                                seed: UInt64,
                                flag: CancellationFlag,
                                progress: (Double) -> Void) -> (ops: UInt64, elapsed: TimeInterval)? {
        let begin = DispatchTime.now().uptimeNanoseconds
        let deadline = begin + UInt64(duration * 1_000_000_000)
        let chunk = 160_000
        var totalOps: UInt64 = 0

        if threads == 1 {
            var ops: UInt64 = 0
            var checksum: UInt64 = 0
            var lastReport = begin
            while DispatchTime.now().uptimeNanoseconds < deadline {
                if flag.isCancelled { return nil }
                checksum ^= performChunk(iterations: chunk, seed: seed &+ ops)
                ops &+= UInt64(chunk)
                let now = DispatchTime.now().uptimeNanoseconds
                if now &- lastReport > 120_000_000 {
                    lastReport = now
                    let fraction = Double(now - begin) / Double(deadline - begin)
                    progress(min(0.99, fraction))
                }
            }
            BenchmarkSink.consume(checksum)
            totalOps = ops
        } else {
            let counts = UnsafeMutablePointer<UInt64>.allocate(capacity: threads)
            counts.initialize(repeating: 0, count: threads)
            defer {
                counts.deinitialize(count: threads)
                counts.deallocate()
            }
            DispatchQueue.concurrentPerform(iterations: threads) { index in
                var ops: UInt64 = 0
                var checksum: UInt64 = 0
                var localLastReport = begin
                while DispatchTime.now().uptimeNanoseconds < deadline {
                    if flag.isCancelled { break }
                    checksum ^= performChunk(iterations: chunk, seed: seed &+ UInt64(index &+ 1) &* 0x0000_0000_0000_9E37 &+ ops)
                    ops &+= UInt64(chunk)
                    let now = DispatchTime.now().uptimeNanoseconds
                    if index == 0, now &- localLastReport > 120_000_000 {
                        localLastReport = now
                        let fraction = Double(now - begin) / Double(deadline - begin)
                        progress(min(0.99, fraction))
                    }
                }
                BenchmarkSink.consume(checksum)
                counts[index] = ops
            }
            if flag.isCancelled { return nil }
            for i in 0..<threads { totalOps &+= counts[i] }
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000_000.0
        progress(1.0)
        guard elapsed > 0.05, totalOps > 0 else { return nil }
        return (totalOps, elapsed)
    }

    @inline(never)
    private static func performChunk(iterations: Int, seed: UInt64) -> UInt64 {
        var x = seed | 1
        var accumulator = 0.0
        for i in 0..<iterations {
            x ^= x << 13
            x ^= x >> 7
            x ^= x << 17
            x &+= 0x9E37_79B9_7F4A_7C15
            let a = Double((x >> 11) & 0xFFFF) + 1.0
            let b = Double((x >> 27) & 0xFFFF) + 1.0
            accumulator += a / b
            if (i & 15) == 0 {
                accumulator *= 0.999_999_9
            }
        }
        return x ^ UInt64(accumulator.rounded(.towardZero)) & 0xFFFF
    }
}

@MainActor
final class CPUBenchmarkRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var phase: String = "就绪"
    @Published private(set) var result: CPURunResult?
    @Published private(set) var errorMessage: String?

    private var flag = CancellationFlag()
    private var token = UUID()

    func start() {
        guard !running else { return }
        let newFlag = CancellationFlag()
        flag = newFlag
        let newToken = UUID()
        token = newToken
        running = true
        progress = 0
        phase = "预热中"
        errorMessage = nil
        result = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let outcome = CPUEngine.run(flag: newFlag) { [weak self] newProgress, newPhase in
                Task { @MainActor [weak self] in
                    guard let self, self.token == newToken else { return }
                    self.progress = newProgress
                    self.phase = newPhase
                }
            }
            await MainActor.run { [weak self] in
                guard let self, self.token == newToken else { return }
                self.running = false
                if let outcome {
                    self.result = outcome
                    self.progress = 1.0
                    self.phase = "测试完成"
                } else {
                    self.phase = newFlag.isCancelled ? "已取消" : "未完成"
                }
            }
        }
    }

    func cancel() {
        guard running else { return }
        flag.cancel()
        token = UUID()
        running = false
        phase = "已取消"
    }
}
