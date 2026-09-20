import Foundation

enum JewelGame: String, Codable { case kurukuru, grassTrace, grassBreak
    var title:String { self == .kurukuru ? "クルクルワールド" : self == .grassTrace ? "Glass Trace" : "Glass Break" }
}
struct JewelHolding: Codable, Equatable {
    var size:Double
    var acquiredAt:Date
}
struct JewelReward: Codable, Equatable, Identifiable {
    let id:UUID
    let gemID:String
    let size:Double
    let boardSize:Int
    let seconds:Double
    let acquiredAt:Date
}
struct JewelSave: Codable, Equatable {
    var schemaVersion=2
    var decorationStyle:Int?=1
    var journal:[GameResultEvent]?=[]
    var earnedTitles:[String]?=[]
    var rulesBestTimes:[String:Double]?=[:]
    var revision=0
    var rotation:Double=0
    var selectedID:String?
    var slots:[String:Int]=["diamond":0,"blackOnyx":3,"emerald":6,"ruby":9]
    var inventory:[String:JewelHolding]=[:]
    var progress:[String:Int]=[:]
    var rewards:[JewelReward]=[]
    var bestTimes:[String:Double]=[:]
    mutating func validate() throws {
        guard [1,2].contains(schemaVersion),revision>=0,rotation.isFinite,
              Set(slots.values).count==slots.count,slots.values.allSatisfy({(0..<12).contains($0)}),
              inventory.values.allSatisfy({$0.size.isFinite && $0.size>0}),
              progress.values.allSatisfy({[4,6,8,10,12].contains($0)}),
              bestTimes.values.allSatisfy({$0.isFinite && $0>=0}),
              Set(rewards.map(\.id)).count==rewards.count,
              rewards.allSatisfy({$0.size.isFinite && $0.size>0 && $0.seconds.isFinite && $0.seconds>=0}) else {
            throw SaveFailure.invalid
        }
        schemaVersion=2
        guard (0...3).contains(decorationStyle ?? 1) else {throw SaveFailure.invalid}
        let ids=Set(["diamond","blackOnyx","emerald","ruby","blackPhonix"])
        guard Set(inventory.keys).isSubset(of:ids),Set(slots.keys).isSubset(of:ids),
              inventory.values.allSatisfy({$0.size<=1.8}),
              (rulesBestTimes ?? [:]).values.allSatisfy({$0.isFinite && $0>=0}),
              (journal ?? []).allSatisfy({ids.contains($0.gemID) && $0.seconds.isFinite && $0.seconds>=0 && $0.traceTolerance.isFinite && $0.traceTolerance>=0 && $0.verification=="localOnly"}) else {throw SaveFailure.invalid}
        // Old display-only enum spelling is an alias, not a new possession.
        if slots["blackOnyx"]==nil,let old=slots.removeValue(forKey:"blackPhonix") { slots["blackOnyx"]=old }
        if inventory["blackOnyx"]==nil,let old=inventory.removeValue(forKey:"blackPhonix") { inventory["blackOnyx"]=old }
    }
    @discardableResult mutating func award(_ reward:JewelReward)->Bool {
        guard !rewards.contains(where:{$0.id==reward.id}) else { return false }
        rewards.append(reward)
        if reward.size > (inventory[reward.gemID]?.size ?? 0) { inventory[reward.gemID] = .init(size:reward.size,acquiredAt:reward.acquiredAt) }
        if reward.boardSize>0 {
            progress[reward.gemID]=max(progress[reward.gemID] ?? 4,min(12,reward.boardSize+2))
            let key="\(reward.gemID).\(reward.boardSize).v2"
            bestTimes[key]=min(bestTimes[key] ?? .infinity,reward.seconds)
        }
        return true
    }
}
enum SaveFailure:LocalizedError { case invalid,unreadable
    var errorDescription:String? { self == .invalid ? "保存データの形式を確認できません。元データを保持しています。" : "保存データを読み込めません。元データを保持しています。" }
}
struct JewelSaveFiles {
    let directory:URL
    var primary:URL { directory.appendingPathComponent("save-v1.json") }
    var backup:URL { directory.appendingPathComponent("save-v1.backup.json") }
    static var standard:Self {
        let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test"),let id=ProcessInfo.processInfo.environment["JEWEL_TEST_ID"],UUID(uuidString:id) != nil {
            return .init(directory:support.appendingPathComponent("JewelRingUITests/"+id,isDirectory:true))
        }
        #endif
        return .init(directory:support.appendingPathComponent("Tamor",isDirectory:true))
    }
    func decode(_ url:URL)throws->JewelSave {
        var data=try JSONDecoder().decode(JewelSave.self,from:Data(contentsOf:url));try data.validate();return data
    }
    func load()throws->(JewelSave,Bool) {
        let fm=FileManager.default
        if !fm.fileExists(atPath:primary.path) && !fm.fileExists(atPath:backup.path) { return (.init(),false) }
        if let save=try? decode(primary) { return (save,false) }
        // Never downgrade an unknown future format by replacing it with an older backup.
        if let bytes=try? Data(contentsOf:primary),let json=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any],let version=json["schemaVersion"] as? Int,![1,2].contains(version) { throw SaveFailure.invalid }
        if let save=try? decode(backup) { return (save,true) }
        throw SaveFailure.unreadable
    }
    func write(_ raw:JewelSave)throws {
        var save=raw;try save.validate()
        let fm=FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(save)
        if let old=try? Data(contentsOf:primary), (try? decode(primary)) != nil { try old.write(to:backup,options:.atomic) }
        try data.write(to:primary,options:.atomic)
    }
}
actor JewelDiskWriter: PlayerRepository {
    func load() throws -> JewelSave { try files.load().0 }
    let files:JewelSaveFiles
    var highest = -1
    init(_ files:JewelSaveFiles) { self.files=files }
    func write(_ save:JewelSave)throws {
        guard save.revision>=highest else { return }
        try files.write(save);highest=save.revision
    }
}
