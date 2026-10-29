import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case cpu
    case disk
    case memory
    case screen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .cpu: return "CPU 跑分"
        case .disk: return "硬盘测速"
        case .memory: return "内存测速"
        case .screen: return "屏幕检测"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .cpu: return "cpu"
        case .disk: return "internaldrive"
        case .memory: return "memorychip"
        case .screen: return "display"
        }
    }

    var kicker: String {
        switch self {
        case .overview: return "DASHBOARD"
        case .cpu: return "BENCHMARK 01"
        case .disk: return "BENCHMARK 02"
        case .memory: return "BENCHMARK 03"
        case .screen: return "DISPLAY LAB"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "实时掌握这颗芯片的负载、温度与功耗。"
        case .cpu: return "整数与浮点混合负载，观察单核与多核的持续输出。"
        case .disk: return "顺序读写与 4K 随机读取，测试本机存储的真实吞吐。"
        case .memory: return "读、写、拷贝与 Triad 带宽，检查统一内存的实际表现。"
        case .screen: return "纯色、灰阶、色域与均匀性，全屏手动切换检查。"
        }
    }
}

enum Fmt {
    static func percent(_ value: Double, digits: Int = 0) -> String {
        guard value.isFinite else { return "--" }
        return String(format: "%.\(digits)f", max(0, min(100, value)))
    }

    static func temperature(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "--" }
        return String(format: "%.0f", value)
    }

    static func watts(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "--" }
        if value < 10 { return String(format: "%.1f", value) }
        return String(format: "%.0f", value)
    }

    static func memoryGB(_ bytes: Double) -> String {
        guard bytes.isFinite, bytes > 0 else { return "--" }
        return String(format: "%.1f", bytes / 1_073_741_824.0)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "--" }
        let mb = bytesPerSecond / 1_000_000.0
        if mb >= 1000 { return String(format: "%.2f GB/s", mb / 1000.0) }
        if mb >= 100 { return String(format: "%.0f MB/s", mb) }
        if mb >= 10 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.2f MB/s", mb)
    }

    static func rateValue(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "--" }
        let mb = bytesPerSecond / 1_000_000.0
        if mb >= 1000 { return String(format: "%.2f", mb / 1000.0) }
        if mb >= 100 { return String(format: "%.0f", mb) }
        if mb >= 10 { return String(format: "%.1f", mb) }
        return String(format: "%.2f", mb)
    }

    static func rateUnit(_ bytesPerSecond: Double) -> String {
        bytesPerSecond / 1_000_000.0 >= 1000 ? "GB/s" : "MB/s"
    }

    static func score(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--" }
        if value >= 1000 { return String(format: "%.0f", value) }
        if value >= 100 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    static func throughputGB(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "--" }
        return String(format: "%.2f", bytesPerSecond / 1_000_000_000.0)
    }

    static func signed(_ value: Double, digits: Int = 1) -> String {
        guard value.isFinite else { return "--" }
        return String(format: "%.\(digits)f", value)
    }
}

enum SystemInfo {
    static let chip: String = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
    static let modelIdentifier: String = sysctlString("hw.model") ?? "Mac"
    static let architecture: String = sysctlString("hw.machine") ?? "arm64"
    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
    static let totalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    static let totalCores: Int = ProcessInfo.processInfo.activeProcessorCount
    static let performanceCores: Int = max(0, sysctlInt("hw.perflevel0.logicalcpu") ?? 0)
    static let efficiencyCores: Int = max(0, sysctlInt("hw.perflevel1.logicalcpu") ?? 0)
    static let hostName: String = ProcessInfo.processInfo.hostName
    static let uptime: TimeInterval = ProcessInfo.processInfo.systemUptime

    static var coreSummary: String {
        if performanceCores > 0 && efficiencyCores > 0 {
            return "\(performanceCores) 性能核 + \(efficiencyCores) 能效核"
        }
        return "\(totalCores) 核心"
    }

    static var memorySummary: String {
        let gb = Double(totalMemoryBytes) / 1_073_741_824.0
        return String(format: "%.0f GB 统一内存", gb.rounded())
    }

    static var deviceLine: String {
        "\(modelIdentifier) · \(osVersion)"
    }

    static var thermalStateText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "较热"
        case .critical: return "临界"
        @unknown default: return "未知"
        }
    }

    private static var storageCache: (date: Date, value: (total: UInt64, free: UInt64)?)?

    static var storage: (total: UInt64, free: UInt64)? {
        if let cache = storageCache, Date().timeIntervalSince(cache.date) < 30 {
            return cache.value
        }
        let value: (total: UInt64, free: UInt64)?
        if let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        ) {
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let free = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            value = total > 0 ? (total, free) : nil
        } else {
            value = nil
        }
        storageCache = (Date(), value)
        return value
    }

    static func sysctlString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(key, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }
}

struct CPURunResult: Equatable {
    let singleScore: Double
    let multiScore: Double
    let threads: Int
    let efficiency: Double
    let duration: TimeInterval
    let date: Date
}

struct DiskRunResult: Equatable {
    let writeBytesPerSecond: Double
    let readBytesPerSecond: Double
    let randomReadIOPS: Double
    let sizeMB: Int
    let duration: TimeInterval
    let date: Date
}

struct MemoryRunResult: Equatable {
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double
    let copyBytesPerSecond: Double
    let triadBytesPerSecond: Double
    let latencyNanoseconds: Double
    let sizeMB: Int
    let duration: TimeInterval
    let date: Date
}

struct PowerReading {
    let watts: Double?
    let source: String
    let batteryPercent: Int?
    let isCharging: Bool
    let isExternal: Bool
    let smcWatts: Double?
}
