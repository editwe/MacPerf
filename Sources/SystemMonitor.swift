import Foundation
import Darwin
import IOKit
import Combine

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var tick: UInt64 = 0
    private(set) var cpuUsage: Double = 0
    private(set) var cpuPerCore: [Double] = []
    private(set) var gpuUsage: Double = 0
    private(set) var memoryUsed: Double = 0
    private(set) var memoryTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    private(set) var memoryPressure: String = "正常"
    private(set) var swapUsed: Double = 0
    private(set) var diskReadRate: Double = 0
    private(set) var diskWriteRate: Double = 0
    private(set) var diskReadTotal: UInt64 = 0
    private(set) var diskWriteTotal: UInt64 = 0
    private(set) var cpuTemperature: Double = 0
    private(set) var gpuTemperature: Double = 0
    private(set) var batteryTemperature: Double = 0
    private(set) var cpuSensorCount: Int = 0
    private(set) var gpuSensorCount: Int = 0
    private(set) var systemPower: Double = 0
    private(set) var powerSource: String = "--"
    private(set) var batteryPercent: Int? = nil
    private(set) var isCharging = false
    private(set) var isExternalPower = false
    private(set) var smcPower: Double = 0
    private(set) var smcAvailable = false
    private(set) var thermalState: String = SystemInfo.thermalStateText
    private(set) var lastRefresh = Date()

    private(set) var cpuHistory: [Double] = []
    private(set) var gpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var temperatureHistory: [Double] = []
    private(set) var powerHistory: [Double] = []
    private(set) var diskReadHistory: [Double] = []
    private(set) var diskWriteHistory: [Double] = []

    private let historyLimit = 90
    private var previousCPU: [(active: UInt64, total: UInt64)] = []
    private var previousDisk: (read: UInt64, write: UInt64)? = nil
    private var diskDrivers: [io_service_t] = []
    private var gpuEntry: io_registry_entry_t = 0
    private var batteryService: io_service_t = 0
    private var sampleBusy = false

    init() {
        smcAvailable = macperf_smc_available() != 0
        refresh()
    }

    deinit {
        if gpuEntry != 0 { IOObjectRelease(gpuEntry) }
        if batteryService != 0 { IOObjectRelease(batteryService) }
        for driver in diskDrivers { IOObjectRelease(driver) }
    }

    func refresh() {
        guard !sampleBusy else { return }
        sampleBusy = true
        defer { sampleBusy = false }

        let cpu = sampleCPU()
        cpuUsage = cpu.total
        cpuPerCore = cpu.cores

        gpuUsage = sampleGPU()
        sampleMemory()
        sampleDisk()
        sampleThermals()
        samplePower()

        thermalState = SystemInfo.thermalStateText
        lastRefresh = Date()

        append(cpuUsage, to: &cpuHistory)
        append(gpuUsage, to: &gpuHistory)
        append(memoryUsed / max(memoryTotal, 1) * 100.0, to: &memoryHistory)
        append(max(cpuTemperature, gpuTemperature), to: &temperatureHistory)
        append(systemPower, to: &powerHistory)
        append(diskReadRate / 1_000_000.0, to: &diskReadHistory)
        append(diskWriteRate / 1_000_000.0, to: &diskWriteHistory)
        tick &+= 1
    }

    private func append(_ value: Double, to array: inout [Double]) {
        guard value.isFinite else { return }
        array.append(value)
        if array.count > historyLimit {
            array.removeFirst(array.count - historyLimit)
        }
    }

    private func sampleCPU() -> (total: Double, cores: [Double]) {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &cpuInfo, &cpuInfoCount)
        guard result == KERN_SUCCESS, let cpuInfo else {
            return (0, [])
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: cpuInfo)),
                          vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let stride = Int(CPU_STATE_MAX)
        var samples: [(active: UInt64, total: UInt64)] = []
        samples.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * stride
            let user = UInt64(cpuInfo[base + Int(CPU_STATE_USER)])
            let system = UInt64(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(cpuInfo[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(cpuInfo[base + Int(CPU_STATE_IDLE)])
            samples.append((active: user + system + nice, total: user + system + nice + idle))
        }

        guard previousCPU.count == samples.count else {
            previousCPU = samples
            return (0, Array(repeating: 0, count: samples.count))
        }

        var perCore: [Double] = []
        perCore.reserveCapacity(samples.count)
        var activeDeltaTotal: Double = 0
        var totalDeltaTotal: Double = 0
        for i in 0..<samples.count {
            let activeDelta = Double(samples[i].active &- previousCPU[i].active)
            let totalDelta = Double(samples[i].total &- previousCPU[i].total)
            let usage = totalDelta > 0 ? max(0, min(100, activeDelta / totalDelta * 100)) : 0
            perCore.append(usage)
            activeDeltaTotal += activeDelta
            totalDeltaTotal += totalDelta
        }
        previousCPU = samples
        let total = totalDeltaTotal > 0 ? max(0, min(100, activeDeltaTotal / totalDeltaTotal * 100)) : 0
        return (total, perCore)
    }

    private func sampleGPU() -> Double {
        if gpuEntry == 0 {
            gpuEntry = findGPUEntry()
        }
        guard gpuEntry != 0 else { return 0 }
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            gpuEntry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
        ), let stats = unmanaged.takeRetainedValue() as? [String: Any] else {
            return 0
        }
        let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
            ?? (stats["Renderer Utilization %"] as? NSNumber)?.doubleValue
            ?? 0
        return max(0, min(100, value))
    }

    private func findGPUEntry() -> io_registry_entry_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let unmanaged = IORegistryEntryCreateCFProperty(
                entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
            ), unmanaged.takeRetainedValue() is [String: Any] {
                return entry
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return 0
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page = Double(vm_kernel_page_size)
        let internalPages = Double(stats.internal_page_count)
        let purgeable = Double(stats.purgeable_count)
        let wired = Double(stats.wire_count)
        let compressed = Double(stats.compressor_page_count)
        memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        memoryUsed = max(0, min(memoryTotal, (internalPages - purgeable + wired + compressed) * page))

        swapUsed = Self.swapUsedBytes()

        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 {
            switch pressureLevel {
            case 1: memoryPressure = "正常"
            case 2: memoryPressure = "警告"
            case 4: memoryPressure = "紧张"
            default: memoryPressure = "正常"
            }
        } else {
            memoryPressure = memoryUsed / max(memoryTotal, 1) > 0.9 ? "紧张" : "正常"
        }
    }

    private static func swapUsedBytes() -> Double {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Double(usage.xsu_used)
    }

    private func sampleDisk() {
        if diskDrivers.isEmpty {
            diskDrivers = findAllDiskDrivers()
        }
        var readTotal: UInt64 = 0
        var writeTotal: UInt64 = 0
        for driver in diskDrivers {
            guard let unmanaged = IORegistryEntryCreateCFProperty(
                driver, "Statistics" as CFString, kCFAllocatorDefault, 0
            ), let stats = unmanaged.takeRetainedValue() as? [String: Any] else {
                continue
            }
            readTotal += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            writeTotal += (stats["Bytes (Written)"] as? NSNumber)?.uint64Value ?? 0
        }
        diskReadTotal = readTotal
        diskWriteTotal = writeTotal

        if let previousDisk {
            let readDelta = readTotal >= previousDisk.read ? readTotal - previousDisk.read : 0
            let writeDelta = writeTotal >= previousDisk.write ? writeTotal - previousDisk.write : 0
            diskReadRate = Double(readDelta)
            diskWriteRate = Double(writeDelta)
        } else {
            diskReadRate = 0
            diskWriteRate = 0
        }
        previousDisk = (readTotal, writeTotal)
    }

    private func findAllDiskDrivers() -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var drivers: [io_service_t] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            drivers.append(entry)
            entry = IOIteratorNext(iterator)
        }
        return drivers
    }

    private func sampleThermals() {
        var cpu: Double = 0
        var gpu: Double = 0
        var battery: Double = 0
        var cpuCount: Int32 = 0
        var gpuCount: Int32 = 0
        let ok = macperf_smc_read_temps(&cpu, &gpu, &battery, &cpuCount, &gpuCount)
        smcAvailable = ok != 0
        if cpu > 0 && cpu < 125 { cpuTemperature = cpu }
        if gpu > 0 && gpu < 125 { gpuTemperature = gpu }
        if battery > 0 { batteryTemperature = battery }
        cpuSensorCount = Int(cpuCount)
        gpuSensorCount = Int(gpuCount)

        let pstr = macperf_smc_read_key("PSTR")
        if pstr.isFinite, pstr > 0.2, pstr < 500 {
            smcPower = pstr
        }
    }

    private func samplePower() {
        if batteryService == 0 {
            batteryService = IOServiceGetMatchingService(kIOMainPortDefault,
                                                         IOServiceMatching("AppleSmartBattery"))
        }

        guard batteryService != 0 else {
            if smcPower > 0 {
                systemPower = smcPower
                powerSource = "SMC 传感器"
            }
            return
        }

        let external = boolProperty("ExternalConnected", service: batteryService) ?? false
        let charging = boolProperty("IsCharging", service: batteryService) ?? false
        let percent = intProperty("CurrentCapacity", service: batteryService)
        isExternalPower = external
        isCharging = charging
        batteryPercent = percent

        var watts: Double? = nil
        var source = "SMC 传感器"

        if let telemetry = dictionaryProperty("PowerTelemetryData", service: batteryService) {
            let systemLoad = signedMilliwatts(telemetry["SystemLoad"])
            let batteryPower = signedMilliwatts(telemetry["BatteryPower"])
            let powerIn = signedMilliwatts(telemetry["SystemPowerIn"])

            if let load = systemLoad, load > 0.05 {
                watts = load
                source = "电池遥测"
            } else if external, let input = powerIn, input > 0.05 {
                watts = input
                source = "电源输入"
            } else if let battery = batteryPower, abs(battery) > 0.05 {
                watts = abs(battery)
                source = "电池遥测"
            }
        }

        if watts == nil, smcPower > 0.2 {
            watts = smcPower
            source = "SMC 传感器"
        }

        if watts == nil {
            let voltage = intProperty("Voltage", service: batteryService)
            let amperage = signedProperty("InstantAmperage", service: batteryService)
            if let voltage, let amperage, voltage > 0, amperage != 0 {
                watts = abs(Double(voltage) * Double(amperage) / 1_000_000.0)
                source = "电压 × 电流"
            }
        }

        systemPower = watts ?? 0
        powerSource = source
    }

    private func dictionaryProperty(_ key: String, service: io_service_t) -> [String: Any]? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return unmanaged.takeRetainedValue() as? [String: Any]
    }

    private func boolProperty(_ key: String, service: io_service_t) -> Bool? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        let value = unmanaged.takeRetainedValue()
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return value as? Bool
    }

    private func intProperty(_ key: String, service: io_service_t) -> Int? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return (unmanaged.takeRetainedValue() as? NSNumber)?.intValue
    }

    private func signedProperty(_ key: String, service: io_service_t) -> Int64? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        ), let number = unmanaged.takeRetainedValue() as? NSNumber else { return nil }
        return Int64(bitPattern: number.uint64Value)
    }

    private func signedMilliwatts(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.uint64Value
        let signed = Int64(bitPattern: raw)
        guard signed != Int64.min else { return nil }
        let absolute = abs(signed)
        guard absolute < 200_000 else { return nil }
        return Double(absolute) / 1000.0
    }
}
