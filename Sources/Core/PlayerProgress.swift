import Foundation

/// Immutable outcome, ready for a future authenticated uploader. Offline results are never trusted leaderboard entries.
struct GameResultEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let game: JewelGame
    let gemID: String
    let rulesVersion: String
    let boardSize: Int
    let targetCount: Int
    let traceTolerance: Double
    let seconds: Double
    let mistakes: Int
    let cracks: Int
    let hits: Int
    let won: Bool
    let finishedAt: Date
    let deviceID: String
    var verification: String = "localOnly"
    var recordKey: String { "\(gemID).\(game.rawValue).\(rulesVersion).\(boardSize).\(targetCount).\(Int((traceTolerance*10000).rounded()))" }
}

/// Future account snapshot deliberately excludes this device's rotation, preview and quality preferences.
/// R20: an explicitly selected authoritative device replaces a server snapshot; never merge maxima.
struct PlayerCloudSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let revision: Int
    let decorationStyle:Int
    let authoritativeDeviceID: String
    let inventory: [String:JewelHolding]
    let progress: [String:Int]
    let records: [String:Double]
    let titles: [String]
    let results: [GameResultEvent]
    init(save: JewelSave, deviceID: String) {
        decorationStyle=save.decorationStyle ?? 1
        schemaVersion=1;revision=save.revision;authoritativeDeviceID=deviceID
        inventory=save.inventory;progress=save.progress;records=save.rulesBestTimes ?? [:]
        titles=save.earnedTitles ?? [];results=save.journal ?? []
    }
}
struct PublicRingSnapshot: Codable {
    struct Gem: Codable { let id:String;let size:Double;let appearanceSeed:UInt64 }
    let version:Int
    let ownerAlias:String
    let gems:[Gem]
    // This DTO is the boundary for a future Laravel API; it never exposes result events or account identifiers.
}
protocol PlayerRepository: Sendable {
    func load() async throws -> JewelSave
    func write(_ save:JewelSave) async throws
}
protocol PlayerCloudTransport: Sendable {
    // Future CloudKit adapter requires sign-in and optimistic revision matching, with user-selected authority.
    func replace(_ snapshot:PlayerCloudSnapshot, accountID:String, expectedRevision:Int) async throws
}

extension JewelSave {
    mutating func record(_ event:GameResultEvent) {
        guard !(journal ?? []).contains(where:{$0.id==event.id}) else { return }
        journal=(journal ?? [])+[event]
        guard event.won else { return }
        var best=rulesBestTimes ?? [:]
        best[event.recordKey]=min(best[event.recordKey] ?? .infinity,event.seconds);rulesBestTimes=best
        var titles=Set(earnedTitles ?? [])
        if inventory.count>=4 { titles.insert("四つの光") }
        if event.game == .grassTrace && event.cracks==0 { titles.insert("傷なき軌跡") }
        if event.game == .grassBreak && event.mistakes==0 { titles.insert("一閃の破砕") }
        if event.game == .kurukuru { titles.insert("\(event.gemID)・\(event.boardSize)×\(event.boardSize)") }
        earnedTitles=titles.sorted()
    }
}
