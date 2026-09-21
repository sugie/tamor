import Foundation

enum GemScale {
    static func width(centicarats: Int, viewport: Double = 375) -> Double {
        17 * pow(Double(centicarats) / 100, 1.0 / 3) * viewport / 375
    }
    static func label(_ value: Int) -> String { String(format: "%.2f ct", Double(value) / 100) }
    static func legacy(_ size: Double) -> Int { min(2000, max(10, Int((pow(size, 3) * 100).rounded()))) }
}
struct GemInstance: Codable, Equatable, Identifiable {
    let id: String
    let gemID: String
    let centicarats: Int
    let acquiredAt: Date
    let resultID: String
    let migrated: Bool
    var worldID: String { ["blackOnyx", "emerald"].contains(gemID) ? "legacy" : "world1" }
}
enum GemGrade: String, Codable { case b = "B", a = "A", s = "S", failed = "失敗" }
struct DepthOutcome: Codable, Equatable, Identifiable {
    let id: String
    let gemID: String
    let depth: Int
    let grade: GemGrade
    let seconds: Double
    let date: Date
    let rulesVersion: Int
    var plates:Int? = nil
    var weakHits:Int? = nil
    var score:Int? = nil
}
struct DepthRules {
    let depth: Int
    init(_ value: Int) { depth = min(6, max(1, value)) }
    var boardSize: Int { [4,6,8,10,12,12][depth-1] }
    var crusherBudget: Double { [60,30,15,7.5,4.5,3][depth-1] }
    var breakDuration: Double { [1.5,1.3,1.1,0.9,0.75,0.6][depth-1] }
    var breakHits: Int { [3,4,5,6,6,6][depth-1] }
    var traceDuration: Double { [15,14,13,12,11,10][depth-1] }
    var traceTolerance: Double { [0.09,0.08,0.07,0.06,0.05,0.04][depth-1] }
    var minimum: Int { [10,50,150,301,601,1201][depth-1] }
    func reward(_ grade: GemGrade, streak: Int) -> Int {
        switch grade {
        case .failed: return 0
        case .b: return minimum
        case .a: return [30,100,225,450,900,1600][depth-1]
        case .s: return depth == 6 ? (streak >= 3 ? 2000 : 1999) : [49,149,300,600,1200][depth-1]
        }
    }
    func grade(game: JewelGame, seconds: Double, mistakes: Int, cracks: Int, won: Bool) -> GemGrade {
        guard won else { return .failed }
        switch game {
        case .grassTrace: return cracks == 0 ? .s : cracks == 1 ? .a : .b
        case .kurukuru:
            let perPair = seconds / Double(boardSize * boardSize / 2)
            if mistakes == 0 && perPair <= (depth == 6 ? 1.25 : 2.5) { return .s }
            return mistakes <= 2 && perPair <= (depth == 6 ? 2.5 : 4) ? .a : .b
        case .grassBreak:
            let ratio = seconds / (Double(breakHits) * breakDuration)
            return ratio <= 0.5 && mistakes == 0 ? .s : ratio <= 0.75 ? .a : .b
        case .crusher:
            return seconds <= crusherBudget * 0.5 ? .s : seconds <= crusherBudget * 0.75 ? .a : .b
        }
    }
}
extension JewelSave {
    var gems: [GemInstance] { specimens ?? [] }
    var outcomes: [DepthOutcome] { depthOutcomes ?? [] }
    func representative(_ gemID: String) -> GemInstance? {
        gems.filter { $0.gemID == gemID }.sorted {
            if $0.centicarats != $1.centicarats { return $0.centicarats > $1.centicarats }
            if $0.acquiredAt != $1.acquiredAt { return $0.acquiredAt < $1.acquiredAt }
            return $0.id < $1.id
        }.first
    }
    func unlockedDepth(_ gemID: String) -> Int {
        min(6, (outcomes.filter { $0.gemID == gemID && $0.grade != .failed }.map(\.depth).max() ?? 0) + 1)
    }
    func streak(_ gemID: String, rulesVersion:Int? = nil) -> Int {
        let history = outcomes.filter { $0.gemID == gemID && $0.depth == 6 && (rulesVersion == nil || $0.rulesVersion == rulesVersion) }.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }
        return history.reversed().prefix { $0.grade == .s }.count
    }
    @discardableResult mutating func apply(_ result: DepthOutcome) -> GemInstance? {
        guard !outcomes.contains(where: { $0.id == result.id }) else { return gems.first { $0.resultID == result.id } }
        depthOutcomes = outcomes + [result]
        guard result.grade != .failed else { return nil }
        let weight = DepthRules(result.depth).reward(result.grade, streak: streak(result.gemID,rulesVersion:result.rulesVersion))
        let gem = GemInstance(id:result.id,gemID:result.gemID,centicarats:weight,acquiredAt:result.date,resultID:result.id,migrated:false)
        specimens = gems + [gem]
        return gem
    }
    mutating func migrateCollection() {
        guard schemaVersion < 3 else { return }
        var items: [GemInstance] = []
        for reward in rewards {
            let key = reward.gemID == "blackPhonix" ? "blackOnyx" : reward.gemID
            items.append(.init(id:reward.id.uuidString,gemID:key,centicarats:GemScale.legacy(reward.size),acquiredAt:reward.acquiredAt,resultID:reward.id.uuidString,migrated:true))
        }
        for (key, holding) in inventory {
            let weight = GemScale.legacy(holding.size)
            if !(items.contains { $0.gemID == key && $0.centicarats >= weight }) {
                let id = "legacy.\(key).\(weight).\(holding.acquiredAt.timeIntervalSinceReferenceDate)"
                items.append(.init(id:id,gemID:key,centicarats:weight,acquiredAt:holding.acquiredAt,resultID:id,migrated:true))
            }
        }
        specimens = items; depthOutcomes = []
        slots = ["diamond":0,"sapphire":3,"obsidian":6,"ruby":9]
        schemaVersion = 3
    }
    /// Cloud data only adds immutable events. Device layout never participates in merging.
    mutating func mergeCollection(_ other: JewelSave) throws {
        var copy = other; try copy.validate()
        var byID = Dictionary(uniqueKeysWithValues:gems.map { ($0.id,$0) })
        for gem in copy.gems {
            if let existing=byID[gem.id],existing != gem { throw SaveFailure.invalid }
            byID[gem.id]=gem
        }
        var events=Dictionary(uniqueKeysWithValues:outcomes.map { ($0.id,$0) })
        for event in copy.outcomes {
            if let existing=events[event.id],existing != event { throw SaveFailure.invalid }
            events[event.id]=event
        }
        specimens=byID.values.sorted{$0.id<$1.id};depthOutcomes=events.values.sorted{$0.id<$1.id}
        earnedTitles=Array(Set((earnedTitles ?? [])+(copy.earnedTitles ?? []))).sorted()
        var best=rulesBestTimes ?? [:]
        for (key,value) in copy.rulesBestTimes ?? [:] { best[key]=min(best[key] ?? .infinity,value) };rulesBestTimes=best
        var records=Dictionary(uniqueKeysWithValues:(journal ?? []).map{($0.id,$0)})
        for event in copy.journal ?? [] { records[event.id]=event };journal=records.values.sorted{$0.id.uuidString<$1.id.uuidString}
        // Keep the original legacy data as well, for export and future migrations.
        for (key,value) in copy.inventory where value.size > (inventory[key]?.size ?? 0) {inventory[key]=value}
        var oldRewards=Dictionary(uniqueKeysWithValues:rewards.map{($0.id,$0)})
        for reward in copy.rewards {oldRewards[reward.id]=reward};rewards=oldRewards.values.sorted{$0.id.uuidString<$1.id.uuidString}
    }
}
