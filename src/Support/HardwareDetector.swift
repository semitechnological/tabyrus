//
//  HardwareDetector.swift
//  Tabyrus
//
//  Detects hardware capabilities for adaptive model selection
//

import Foundation

struct HardwareInfo {
    let totalRAM: UInt64 // in bytes
    let availableRAM: UInt64 // in bytes
    let cpuCount: Int
    let cpuFrequency: Double? // in GHz
    let hasAppleSilicon: Bool
    let modelName: String
    
    // Computed properties for easy classification
    var ramGB: Double { Double(totalRAM) / (1024 * 1024 * 1024) }
    var availableRamGB: Double { Double(availableRAM) / (1024 * 1024 * 1024) }
    
    var canRunLargeModels: Bool {
        // Can run models requiring 8GB+ RAM
        return ramGB >= 16.0 && hasAppleSilicon
    }
    
    var canRunMediumModels: Bool {
        // Can run models requiring 4GB+ RAM
        return ramGB >= 8.0
    }
    
    var recommendedModelSize: String {
        if canRunLargeModels {
            return "large"
        } else if canRunMediumModels {
            return "medium"
        } else {
            return "small"
        }
    }
}

class HardwareDetector {
    static func detectHardware() -> HardwareInfo {
        let totalRAM = getTotalRAM()
        let availableRAM = getAvailableRAM()
        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        let cpuFrequency = getCPUFrequency()
        let hasAppleSilicon = isAppleSilicon()
        let modelName = getModelName()
        
        return HardwareInfo(
            totalRAM: totalRAM,
            availableRAM: availableRAM,
            cpuCount: cpuCount,
            cpuFrequency: cpuFrequency,
            hasAppleSilicon: hasAppleSilicon,
            modelName: modelName
        )
    }
    
    private static func getTotalRAM() -> UInt64 {
        return ProcessInfo.processInfo.physicalMemory
    }
    
    private static func getAvailableRAM() -> UInt64 {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &size)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let freePages = UInt64(stats.free_count)
            let inactivePages = UInt64(stats.inactive_count)
            return (freePages + inactivePages) * pageSize
        }
        
        // Fallback: estimate 75% of total RAM as available
        return UInt64(Double(getTotalRAM()) * 0.75)
    }
    
    private static func getCPUFrequency() -> Double? {
        // Try to get CPU frequency from sysctl
        var size = size_t(MemoryLayout<UInt32>.size)
        var freq: UInt32 = 0
        
        let result = sysctlbyname("hw.cpufrequency", &freq, &size, nil, 0)
        if result == 0 {
            return Double(freq) / 1_000_000_000.0 // Convert Hz to GHz
        }
        
        return nil
    }
    
    private static func isAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
    
    private static func getModelName() -> String {
        var size = size_t(MemoryLayout<UInt32>.size)
        var model = [CChar](repeating: 0, count: 256)
        size = model.count
        
        let result = sysctlbyname("hw.model", &model, &size, nil, 0)
        if result == 0, let modelString = String(cString: model, encoding: .utf8) {
            return modelString
        }
        
        return "Unknown"
    }
}