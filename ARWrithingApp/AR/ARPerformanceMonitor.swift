//
//  ARPerformanceMonitor.swift
//  ARWrithingApp
//
//  Created by Airi Nakanishi on 2026/07/14.
//

import RealityKit
import Foundation

class ARPerformanceMonitor {
    static func reportPerformance(root: Entity, duration: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let memoryUsed = kerr == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0.0
        
        let cpuUsage = getCPUUsage()
        
        func countEntities(_ entity: Entity) -> Int {
            return 1 + entity.children.reduce(0) { $0 + countEntities($1) }
        }
        let entityCount = countEntities(root)
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 [AR Monitor] システム負荷状況")
        print("  🔸 CPU 使用率           : \(String(format: "%.1f", cpuUsage)) %")
        print("  🔸 メモリ使用量 (RAM)   : \(String(format: "%.2f", memoryUsed)) MB / 3072.00 MB")
        print("  🔸 AR空間のオブジェクト数: \(entityCount) 個")
        print("  🔸 処理時間 (メインスレッド): \(String(format: "%.4f", duration)) ms")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
    
    private static func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                guard infoResult == KERN_SUCCESS else { continue }
                let isIdle = threadInfo.flags & TH_FLAGS_IDLE != 0
                if !isIdle {
                    totalUsageOfCPU += (Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }
        return totalUsageOfCPU
    }
}
