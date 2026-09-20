import Foundation
import Darwin

/// Opt-in, local diagnostics for the device validation run; no network transmission.
enum CrackMetrics {
    static func record(_ values: [String:Any]) {
        guard UserDefaults.standard.bool(forKey:"studyMetrics") else { return }
        var values=values
        values["uptime"]=ProcessInfo.processInfo.systemUptime
        values["thermalState"]=ProcessInfo.processInfo.thermalState.rawValue
        var info=mach_task_basic_info()
        var count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size/MemoryLayout<natural_t>.size)
        let result=withUnsafeMutablePointer(to:&info) { pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {
                task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)
            }
        }
        if result==KERN_SUCCESS { values["residentMB"]=Double(info.resident_size)/1048576 }
        guard var data=try? JSONSerialization.data(withJSONObject:values,options:.sortedKeys),
              let directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        data.append(10)
        let path=directory.appendingPathComponent("network-metrics.jsonl")
        if !FileManager.default.fileExists(atPath:path.path) { FileManager.default.createFile(atPath:path.path,contents:nil) }
        if let handle=try? FileHandle(forWritingTo:path) {
            defer { try? handle.close() }
            do { try handle.seekToEnd(); try handle.write(contentsOf:data) } catch { }
        }
    }
}
