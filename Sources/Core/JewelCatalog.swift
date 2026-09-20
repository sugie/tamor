import Foundation
import simd

enum JewelKind: Int, CaseIterable, Identifiable {
    case diamond, blackOnyx, emerald, ruby
    var id: Int { rawValue }
    var key: String { ["diamond","blackOnyx","emerald","ruby"][rawValue] }
    var slot: Int { rawValue*3 }
    var game: JewelGame { self == .diamond ? .grassBreak : self == .ruby ? .grassTrace : .kurukuru }
    var composition: String { ["C","SiO₂","Be₃Al₂Si₆O₁₈","Al₂O₃"][rawValue] }
    var name: String { ["ダイヤモンド", "ブラックオニキス", "エメラルド", "ルビー"][rawValue] }
    var subtitle: String { ["静けさの中に、すべての光。", "深い闇が、光を際立たせる。", "やわらかな光を、ひとつ。", "小さな宇宙に、赤い鼓動。"][rawValue] }
    var english: String { ["DIAMOND", "BLACK ONYX", "EMERALD", "RUBY"][rawValue] }
    var tint: SIMD3<Float> {
        [SIMD3<Float>(0.64,0.84,0.97), SIMD3<Float>(0.20,0.19,0.32),
         SIMD3<Float>(0.35,0.85,0.72), SIMD3<Float>(0.88,0.15,0.29)][rawValue]
    }
    var structureNote: String {
        switch self {
        case .diamond: return "炭素のダイヤモンド型格子。原子の大きさ・色は模式表現です。"
        case .ruby: return "Al₂O₃ · コランダム。結晶構造を準備中です。"
        case .blackOnyx: return "SiO₂ · カルセドニー（玉髄）。結晶構造を準備中です。"
        case .emerald: return "Be₃Al₂Si₆O₁₈ · ベリル。結晶構造を準備中です。"
        }
    }
    var hasKurukuru: Bool { self == .blackOnyx || self == .emerald }
}

enum ObservationLevel: Int, CaseIterable, Identifiable {
    case whole, surface, interior, atoms
    var id: Int { rawValue }
    var title: String { ["全体", "表面", "内部", "原子"][rawValue] }
    var caption: String { ["光をまとった、ひとつの宝石。", "カットが生む光の面を観察。", "外側をほどいて、内側へ。", "規則正しくつながる、小さな世界。"][rawValue] }
    static func resolved(zoom: Double, previous: Self) -> Self {
        // Hysteresis keeps a pinch near a boundary from repeatedly changing geometry.
        var value=previous.rawValue
        while value<3 && zoom>Double(value)+0.62 { value+=1 }
        while value>0 && zoom<Double(value)-0.62 { value-=1 }
        return Self(rawValue:value)!
    }
}

struct RingLayoutMath {
    static let radius: Double = 0.66
    static func position(index:Int,count:Int,angle:Double) -> SIMD2<Double> {
        let a=Double(index)*2 * .pi/Double(count)+angle
        return SIMD2(sin(a)*radius,-cos(a)*radius)
    }
    static func nearest(count:Int,angle:Double) -> Int {
        let i=Int((-angle/(2 * .pi)*Double(count)).rounded())
        return (i%count+count)%count
    }
    static func wrapped(_ angle:Double) -> Double { atan2(sin(angle),cos(angle)) }
    static func snapTarget(count:Int,angle:Double) -> Double {
        let step=2 * Double.pi/Double(count)
        return (angle/step).rounded()*step
    }
    static func hit(point:SIMD2<Double>,count:Int,angle:Double) -> Int? {
        guard simd_length(point)>0.35 else { return nil }
        return (0..<count).min { simd_distance(point,position(index:$0,count:count,angle:angle)) < simd_distance(point,position(index:$1,count:count,angle:angle)) }
            .flatMap { simd_distance(point,position(index:$0,count:count,angle:angle)) < (count==4 ? 0.23:0.145) ? $0:nil }
    }
}

struct LatticeAtom { let position:SIMD3<Float>; let species:Int }
struct LatticeBond { let first:Int;let second:Int }
struct CrystalLattice {
    let atoms:[LatticeAtom]
    let bonds:[LatticeBond]
    static func diamond(cells:Int=4) -> Self {
        // Integer quarter-cell coordinates make adjacency exact and O(number of atoms).
        let basis:[SIMD3<Int32>]=[.init(0,0,0),.init(0,2,2),.init(2,0,2),.init(2,2,0),
                                 .init(1,1,1),.init(1,3,3),.init(3,1,3),.init(3,3,1)]
        var points:[SIMD3<Int32>]=[]
        for z in 0..<cells { for y in 0..<cells { for x in 0..<cells {
            for b in basis { points.append(b &+ SIMD3(Int32(x*4),Int32(y*4),Int32(z*4))) }
        } } }
        let indices=Dictionary(uniqueKeysWithValues:points.enumerated().map{($0.element,$0.offset)})
        var bonds:[LatticeBond]=[]
        for (i,p) in points.enumerated() {
            for x:Int32 in [-1,1] { for y:Int32 in [-1,1] { for z:Int32 in [-1,1] {
                if let j=indices[p &+ SIMD3(x,y,z)], j>i { bonds.append(.init(first:i,second:j)) }
            } } }
        }
        let center=Float(cells*4-1)/2
        let atoms=points.map { p in
            LatticeAtom(position:(SIMD3(Float(p.x),Float(p.y),Float(p.z))-SIMD3(repeating:center))/4,
                        species:Int((p.x+p.y+p.z)%3))
        }
        return Self(atoms:atoms,bonds:bonds)
    }
}

enum JewelMatrices {
    static func translate(_ p:SIMD3<Float>) -> simd_float4x4 {
        var m=matrix_identity_float4x4;m.columns.3=SIMD4(p,1);return m
    }
    static func scale(_ s:SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal:SIMD4(s,1))
    }
    static func rotate(_ angle:Float, _ axis:SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle:angle,axis:axis))
    }
    static func bond(from a:SIMD3<Float>,to b:SIMD3<Float>,radius:Float) -> simd_float4x4 {
        let delta=b-a, length=simd_length(delta),y=delta/max(length,0.0001)
        let reference:SIMD3<Float>=abs(y.z)>0.9 ? .init(1,0,0):.init(0,0,1)
        let x=simd_normalize(simd_cross(y,reference)),z=simd_cross(x,y)
        return simd_float4x4(SIMD4(x*radius,0),SIMD4(y*length,0),SIMD4(z*radius,0),SIMD4((a+b)/2,1))
    }
}
