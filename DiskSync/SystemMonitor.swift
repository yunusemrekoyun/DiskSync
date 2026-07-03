//
//  SystemMonitor.swift
//  DiskSync
//
//  Lightweight system stats (CPU / memory / disk / network) read from the
//  kernel-provided counters (mach host statistics, getifaddrs, volume
//  capacity). Sampled only while the System tab is visible. Fully local.
//

import Foundation
import Darwin

@MainActor
@Observable
final class SystemMonitor {
    static let shared = SystemMonitor()
    private init() { sampleDisk() }

    var cpuUsage: Double = 0          // 0…1
    var memoryUsed: Int64 = 0
    var memoryTotal: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var netDownBytesPerSec: Double = 0
    var netUpBytesPerSec: Double = 0

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var diskUsedFraction: Double { diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0 }

    private var prevCPUTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNet: (inBytes: UInt64, outBytes: UInt64)?
    private var prevNetTime: Date?

    func sample() {
        sampleCPU()
        sampleMemory()
        sampleDisk()
        sampleNetwork()
    }

    // MARK: - CPU

    private func sampleCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = info.cpu_ticks.0     // natural_t (UInt32)
        let system = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        if let prev = prevCPUTicks {
            let dUser = Double(user &- prev.user)
            let dSystem = Double(system &- prev.system)
            let dIdle = Double(idle &- prev.idle)
            let dNice = Double(nice &- prev.nice)
            let total = dUser + dSystem + dIdle + dNice
            if total > 0 { cpuUsage = (dUser + dSystem + dNice) / total }
        }
        prevCPUTicks = (user, system, idle, nice)
    }

    // MARK: - Memory

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let pageSize = Int64(sysconf(_SC_PAGESIZE))   // avoids the non-Sendable vm_page_size global
        // Match Activity Monitor's "Memory Used": app memory (anonymous, minus
        // purgeable) + wired + compressed — not raw active, which includes file
        // cache and overstates usage.
        let appMemory = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let used = appMemory + Int64(stats.wire_count) + Int64(stats.compressor_page_count)
        memoryUsed = max(0, used) * pageSize
    }

    // MARK: - Disk

    private func sampleDisk() {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) {
            diskTotal = Int64(values.volumeTotalCapacity ?? 0)
            diskFree = Int64(values.volumeAvailableCapacity ?? 0)
        }
    }

    // MARK: - Network

    private func sampleNetwork() {
        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr = ifaddrPtr
        while let addr = ptr {
            defer { ptr = addr.pointee.ifa_next }
            guard addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: addr.pointee.ifa_name)
            // Count only physical/cellular interfaces (skip lo/awdl/bridge/utun/vnic…).
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
            if let data = addr.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                inBytes += UInt64(data.pointee.ifi_ibytes)
                outBytes += UInt64(data.pointee.ifi_obytes)
            }
        }

        let now = Date()
        if let prev = prevNet, let prevTime = prevNetTime {
            let dt = now.timeIntervalSince(prevTime)
            if dt > 0 {
                netDownBytesPerSec = Double(inBytes &- prev.inBytes) / dt
                netUpBytesPerSec = Double(outBytes &- prev.outBytes) / dt
            }
        }
        prevNet = (inBytes, outBytes)
        prevNetTime = now
    }
}
