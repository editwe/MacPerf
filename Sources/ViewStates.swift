import SwiftUI
import Combine

final class ContentViewState: ObservableObject {
    @Published var selection: AppTab = .overview
}

final class PulseState: ObservableObject {
    @Published var pulse = false
}

final class HoverState: ObservableObject {
    @Published var isHovering = false
}

final class CPUBenchViewState: ObservableObject {
    @Published var peakTemperature: Double = 0
    @Published var peakPower: Double = 0
    @Published var peakCPU: Double = 0
}

final class DiskBenchViewState: ObservableObject {
    @Published var sizeMB = 512
}

final class MemoryBenchViewState: ObservableObject {
    @Published var sizeMB = 256
}

final class ScreenTestViewState: ObservableObject {
    @Published var displays: [DisplayDescriptor] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var hoveredPattern: String?
}

extension Notification.Name {
    static let macPerfShowScreenTest = Notification.Name("MacPerfShowScreenTest")
    static let macPerfCloseScreenTest = Notification.Name("MacPerfCloseScreenTest")
    static let macPerfStartCPUBench = Notification.Name("MacPerfStartCPUBench")
    static let macPerfStartDiskBench = Notification.Name("MacPerfStartDiskBench")
    static let macPerfStartMemoryBench = Notification.Name("MacPerfStartMemoryBench")
}
