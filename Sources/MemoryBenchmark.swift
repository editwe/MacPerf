import Foundation
import Darwin
import Combine

enum BenchmarkSink {
    static var value: UInt64 = 0

    @inline(never)
    static func consume(_ input: UInt64) {
        value ^= input
    }
}

enum MemoryEngine {
    static func run(sizeMB: Int,
                    flag: CancellationFlag,
                    progress: @escaping (Double, String) -> Void) throws -> MemoryRunResult {
        let started = Date()
        let bytes = sizeMB * 1_024 * 1_024
        let words = bytes / 8
        let threads = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        guard words > 0 else { throw NSError(domain: "MacPerf", code: 1) }

        let a = UnsafeMutablePointer<UInt64>.allocate(capacity: words)
        let b = UnsafeMutablePointer<UInt64>.allocate(capacity: words)
        let c = UnsafeMutablePointer<UInt64>.allocate(capacity: words)
        defer {
            a.deallocate()
            b.deallocate()
            c.deallocate()
        }

        progress(0.02, "分配内存")
        var seed: UInt64 = 0x1234_5678_9ABC_DEF0
        for i in 0..<words {
            if (i & 0xFFFFF) == 0 && flag.isCancelled { throw CancellationError() }
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            a[i] = seed
            b[i] = seed ^ 0xA5A5_5A5A_1234_4321
        }
        c.initialize(repeating: 0, count: words)

        if flag.isCancelled { throw CancellationError() }
        progress(0.10, "顺序写入 · \(threads) 线程")
        var begin = DispatchTime.now().uptimeNanoseconds
        let writeSum = parallelChunks(words: words, threads: threads) { start, end, index in
            var localSeed = seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15
            var local: UInt64 = 0
            for i in start..<end {
                if (i & 0xFFFFF) == 0 && flag.isCancelled { return 0 }
                localSeed &+= 0x9E37_79B9
                a[i] = localSeed
                local ^= localSeed
            }
            return local
        }
        if flag.isCancelled { throw CancellationError() }
        let writeElapsed = seconds(since: begin)
        BenchmarkSink.consume(writeSum)

        progress(0.28, "双流读取 · \(threads) 线程")
        begin = DispatchTime.now().uptimeNanoseconds
        let readSum = parallelChunks(words: words, threads: threads) { start, end, _ in
            var local: UInt64 = 0
            for i in start..<end {
                if (i & 0xFFFFF) == 0 && flag.isCancelled { return 0 }
                local &+= a[i] &+ b[i]
            }
            return local
        }
        if flag.isCancelled { throw CancellationError() }
        let readElapsed = seconds(since: begin)
        BenchmarkSink.consume(readSum)

        progress(0.47, "内存拷贝 · \(threads) 线程")
        begin = DispatchTime.now().uptimeNanoseconds
        let copySum = parallelChunks(words: words, threads: threads) { start, end, _ in
            for i in start..<end {
                if (i & 0xFFFFF) == 0 && flag.isCancelled { return 0 }
                b[i] = a[i]
            }
            return b[start]
        }
        if flag.isCancelled { throw CancellationError() }
        let copyElapsed = seconds(since: begin)
        BenchmarkSink.consume(copySum)

        progress(0.66, "Triad 带宽 · \(threads) 线程")
        begin = DispatchTime.now().uptimeNanoseconds
        let triadSum = parallelChunks(words: words, threads: threads) { start, end, _ in
            var local: UInt64 = 0
            for i in start..<end {
                if (i & 0xFFFFF) == 0 && flag.isCancelled { return 0 }
                let value = a[i] &+ 3 &* b[i]
                c[i] = value
                local ^= value
            }
            return local
        }
        if flag.isCancelled { throw CancellationError() }
        let triadElapsed = seconds(since: begin)
        BenchmarkSink.consume(triadSum)

        if flag.isCancelled { throw CancellationError() }
        progress(0.84, "随机访问延迟")
        let latency = measureLatency(flag: flag) { p in
            progress(0.84 + p * 0.14, "随机访问延迟")
        }
        if flag.isCancelled { throw CancellationError() }

        progress(1.0, "测试完成")
        return MemoryRunResult(
            readBytesPerSecond: Double(bytes * 2) / max(readElapsed, 0.001),
            writeBytesPerSecond: Double(bytes) / max(writeElapsed, 0.001),
            copyBytesPerSecond: Double(bytes * 2) / max(copyElapsed, 0.001),
            triadBytesPerSecond: Double(bytes * 3) / max(triadElapsed, 0.001),
            latencyNanoseconds: latency,
            sizeMB: sizeMB,
            duration: Date().timeIntervalSince(started),
            date: Date()
        )
    }

    private static func parallelChunks(words: Int,
                                      threads: Int,
                                      body: (Int, Int, Int) -> UInt64) -> UInt64 {
        let checksums = UnsafeMutablePointer<UInt64>.allocate(capacity: threads)
        checksums.initialize(repeating: 0, count: threads)
        defer {
            checksums.deinitialize(count: threads)
            checksums.deallocate()
        }
        DispatchQueue.concurrentPerform(iterations: threads) { index in
            let start = words * index / threads
            let end = words * (index + 1) / threads
            checksums[index] = body(start, end, index)
        }
        var result: UInt64 = 0
        for i in 0..<threads { result ^= checksums[i] }
        return result
    }

    private static func seconds(since begin: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - begin) / 1_000_000_000.0
    }

    private static func measureLatency(flag: CancellationFlag,
                                       progress: (Double) -> Void) -> Double {
        let count = 1 << 23
        let indices = UnsafeMutablePointer<Int32>.allocate(capacity: count)
        defer { indices.deallocate() }
        for i in 0..<count {
            indices[i] = Int32(i)
        }
        var seed: UInt64 = 0xDEAD_BEEF_CAFE_BABE
        if count > 1 {
            for i in stride(from: count - 1, through: 1, by: -1) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                let j = Int(seed % UInt64(i + 1))
                let temp = indices[i]
                indices[i] = indices[j]
                indices[j] = temp
            }
        }

        let accesses = 1_000_000
        var index = 0
        let begin = DispatchTime.now().uptimeNanoseconds
        for i in 0..<accesses {
            if (i & 0x3FFFF) == 0 {
                if flag.isCancelled { return 0 }
                progress(Double(i) / Double(accesses))
            }
            index = Int(indices[index])
        }
        BenchmarkSink.consume(UInt64(index))
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - begin)
        return elapsed / Double(accesses)
    }
}

@MainActor
final class MemoryBenchmarkRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var phase: String = "就绪"
    @Published private(set) var result: MemoryRunResult?
    @Published private(set) var errorMessage: String?

    private var flag = CancellationFlag()
    private var token = UUID()

    func start(sizeMB: Int) {
        guard !running else { return }
        let newFlag = CancellationFlag()
        flag = newFlag
        let newToken = UUID()
        token = newToken
        running = true
        progress = 0
        phase = "分配内存"
        result = nil
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let outcome = try MemoryEngine.run(sizeMB: sizeMB, flag: newFlag) { [weak self] p, phase in
                    Task { @MainActor [weak self] in
                        guard let self, self.token == newToken else { return }
                        self.progress = p
                        self.phase = phase
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self, self.token == newToken else { return }
                    self.running = false
                    self.result = outcome
                    self.progress = 1
                    self.phase = "测试完成"
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.token == newToken else { return }
                    self.running = false
                    self.phase = "已取消"
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.token == newToken else { return }
                    self.running = false
                    self.errorMessage = error.localizedDescription
                    self.phase = "测试失败"
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
