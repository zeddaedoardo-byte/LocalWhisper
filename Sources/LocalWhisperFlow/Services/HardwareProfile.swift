import Foundation
import Darwin

struct HardwareProfile {
    let isAppleSilicon: Bool
    let physicalMemoryGB: Int
    let activeProcessorCount: Int

    static let current: HardwareProfile = {
        let info = ProcessInfo.processInfo
        let memBytes = info.physicalMemory
        let memGB = Int(memBytes / (1024 * 1024 * 1024))
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0)
        return HardwareProfile(
            isAppleSilicon: arm == 1,
            physicalMemoryGB: memGB,
            activeProcessorCount: info.activeProcessorCount
        )
    }()

    var suggestedPreset: PerformancePreset {
        if !isAppleSilicon { return .speed }
        if physicalMemoryGB >= 16 { return .quality }
        if physicalMemoryGB >= 8 { return .balanced }
        return .speed
    }
}
