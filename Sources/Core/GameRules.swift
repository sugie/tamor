import Foundation

enum Spin: Int, Codable, CaseIterable {
    case clockwise = 1, counterclockwise = -1
    var symbol: String { self == .clockwise ? "↻" : "↺" }
    var title: String { self == .clockwise ? "時計回り" : "反時計回り" }
}
enum SoulStrength: String, Codable, CaseIterable, Identifiable {
    case weak, strong
    var id: String { rawValue }
    var title: String { self == .weak ? "弱い" : "強い" }
}
struct GameSettings: Equatable, Codable {
    var size = 8
    var seed: UInt64 = 918
    var soulStrength: SoulStrength = .weak
    var pieceCount: Int { size * size }
    mutating func sanitize() { if ![4,6,8,10,12].contains(size) { size = 8 } }
}
struct Piece: Equatable, Codable { let id: Int; let spin: Spin }
struct Board: Equatable, Codable {
    let size: Int
    var cells: [Piece?]
    init(size: Int) { self.size = size; cells = Array(repeating: nil, count: size * size) }
    var count: Int { cells.compactMap { $0 }.count }
    func index(row: Int, column: Int) -> Int? {
        guard row >= 0, row < size, column >= 0, column < size else { return nil }
        return row * size + column
    }
    func isPair(_ first: Int, _ second: Int) -> Bool {
        guard first != second, cells.indices.contains(first), cells.indices.contains(second),
              let a = cells[first], let b = cells[second] else { return false }
        return a.spin == b.spin
    }
    mutating func removePair(_ first: Int, _ second: Int) -> Bool {
        guard isPair(first, second) else { return false }
        cells[first] = nil; cells[second] = nil
        return true
    }
}
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var x = state
        x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
        x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
        return x ^ (x >> 31)
    }
}
enum BoardGenerator {
    static func generate(_ raw: GameSettings) -> Board {
        var settings = raw; settings.sanitize()
        let count = settings.pieceCount
        var rng = SeededRNG(state: settings.seed)
        // Every supported even N has N² divisible by 4: each direction has an even count.
        // Position is random; the parity guarantee means all pieces can always be paired.
        var pieces = (0..<count).map { Piece(id: $0, spin: $0 < count/2 ? .clockwise : .counterclockwise) }
        pieces.shuffle(using: &rng)
        var board = Board(size: settings.size); board.cells = pieces.map(Optional.some)
        return board
    }
}
/// The score uses continuous monotonic time, never the renderer's capped frame delta.
struct GameClock {
    private(set) var startedAt: TimeInterval?
    private(set) var result: TimeInterval?
    mutating func start(at now: TimeInterval) { startedAt = now; result = nil }
    func elapsed(at now: TimeInterval) -> TimeInterval {
        if let result { return result }
        guard let startedAt else { return 0 }
        return max(0, now-startedAt)
    }
    mutating func finish(at now: TimeInterval) {
        guard startedAt != nil, result == nil else { return }
        result = elapsed(at: now)
    }
    static func display(_ seconds: TimeInterval) -> String {
        let tenths = Int(max(0, seconds)*10)
        return String(format: "%02d:%02d.%01d", tenths/600,(tenths/10)%60,tenths%10)
    }
}
