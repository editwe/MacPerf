import Foundation
import Darwin
import Combine

enum DiskBenchError: LocalizedError {
    case unavailableSpace(required: Int, available: Int)
    case openFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case fsyncFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailableSpace(let required, let available):
            return "可用空间不足：需要约 \(required) MB，当前仅 \(available) MB。"
        case .openFailed(let message): return "无法创建测试文件：\(message)"
        case .writeFailed(let message): return "写入失败：\(message)"
        case .readFailed(let message): return "读取失败：\(message)"
        case .fsyncFailed(let message): return "落盘失败：\(message)"
        }
    }
}

enum DiskEngine {
    static func run(sizeMB: Int,
                    flag: CancellationFlag,
                    progress: @escaping (Double, String) -> Void) throws -> DiskRunResult {
        let started = Date()
        let totalBytes = UInt64(sizeMB) * 1_024 * 1_024
        let tempDirectory = FileManager.default.temporaryDirectory
        if let values = try? tempDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = values.volumeAvailableCapacityForImportantUsage {
            let availableMB = Int(free / 1_048_576)
            if availableMB < sizeMB + 768 {
                throw DiskBenchError.unavailableSpace(required: sizeMB + 768, available: availableMB)
            }
        }

        let fileURL = tempDirectory.appendingPathComponent("MacPerf-\(UUID().uuidString).tmp")
        let path = fileURL.path
        let fd = open(path, O_CREAT | O_TRUNC | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw DiskBenchError.openFailed(String(cString: strerror(errno)))
        }
        defer {
            close(fd)
            unlink(path)
        }
        _ = fcntl(fd, F_NOCACHE, 1)

        let blockBytes = 8 * 1_024 * 1_024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: blockBytes, alignment: 4_096)
        defer { buffer.deallocate() }

        var x: UInt64 = 0x9E37_79B9_7F4A_7C15
        let words = buffer.bindMemory(to: UInt64.self, capacity: blockBytes / 8)
        for i in 0..<(blockBytes / 8) {
            x ^= x << 13
            x ^= x >> 7
            x ^= x << 17
            words[i] = x
        }
        var checksum: UInt64 = 0

        progress(0.02, "顺序写入")
        let writeBegin = DispatchTime.now().uptimeNanoseconds
        var remaining = totalBytes
        while remaining > 0 {
            if flag.isCancelled { throw CancellationError() }
            let chunk = Int(min(UInt64(blockBytes), remaining))
            var written = 0
            while written < chunk {
                let result = Darwin.write(fd, buffer + written, chunk - written)
                if result <= 0 {
                    throw DiskBenchError.writeFailed(String(cString: strerror(errno)))
                }
                written += result
            }
            remaining -= UInt64(chunk)
            let done = Double(totalBytes - remaining) / Double(totalBytes)
            progress(0.02 + done * 0.42, "顺序写入")
        }
        if fsync(fd) != 0 {
            throw DiskBenchError.fsyncFailed(String(cString: strerror(errno)))
        }
        let writeElapsed = Double(DispatchTime.now().uptimeNanoseconds - writeBegin) / 1_000_000_000.0

        if flag.isCancelled { throw CancellationError() }
        progress(0.47, "顺序读取")
        _ = lseek(fd, 0, SEEK_SET)
        let readBegin = DispatchTime.now().uptimeNanoseconds
        var readRemaining = totalBytes
        while readRemaining > 0 {
            if flag.isCancelled { throw CancellationError() }
            let chunk = Int(min(UInt64(blockBytes), readRemaining))
            let count = Darwin.read(fd, buffer, chunk)
            if count < 0 {
                throw DiskBenchError.readFailed(String(cString: strerror(errno)))
            }
            if count == 0 { break }
            checksum &+= UInt64(count)
            readRemaining -= UInt64(count)
            let done = Double(totalBytes - readRemaining) / Double(totalBytes)
            progress(0.47 + done * 0.36, "顺序读取")
        }
        let readElapsed = Double(DispatchTime.now().uptimeNanoseconds - readBegin) / 1_000_000_000.0

        if flag.isCancelled { throw CancellationError() }
        progress(0.84, "4K 随机读取")
        let randomOps = 2_000
        let blocks = max(1, totalBytes / 4_096)
        var seed: UInt64 = 0x1234_5678_9ABC_DEF0
        let randomBegin = DispatchTime.now().uptimeNanoseconds
        for i in 0..<randomOps {
            if flag.isCancelled { throw CancellationError() }
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let offset = off_t((seed % blocks) * 4_096)
            let count = pread(fd, buffer, 4_096, offset)
            guard count > 0 else {
                throw DiskBenchError.readFailed(String(cString: strerror(errno)))
            }
            checksum &+= UInt64(count)
            if i % 40 == 0 {
                progress(0.84 + Double(i) / Double(randomOps) * 0.15, "4K 随机读取")
            }
        }
        let randomElapsed = Double(DispatchTime.now().uptimeNanoseconds - randomBegin) / 1_000_000_000.0

        _ = checksum
        progress(1.0, "测试完成")
        return DiskRunResult(
            writeBytesPerSecond: Double(totalBytes) / max(writeElapsed, 0.001),
            readBytesPerSecond: Double(totalBytes - readRemaining) / max(readElapsed, 0.001),
            randomReadIOPS: Double(randomOps) / max(randomElapsed, 0.001),
            sizeMB: sizeMB,
            duration: Date().timeIntervalSince(started),
            date: Date()
        )
    }
}

@MainActor
final class DiskBenchmarkRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var phase: String = "就绪"
    @Published private(set) var result: DiskRunResult?
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
        phase = "准备测试文件"
        result = nil
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let outcome = try DiskEngine.run(sizeMB: sizeMB, flag: newFlag) { [weak self] p, phase in
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
