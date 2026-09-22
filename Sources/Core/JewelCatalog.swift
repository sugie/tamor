import Foundation
import simd

enum JewelKind: Int, CaseIterable, Identifiable {
    // Never reorder the first four IDs: old saves and shaders depend on them.
    case diamond, blackOnyx, emerald, ruby, sapphire, obsidian
    static let worldOne: [Self] = [.diamond,.sapphire,.obsidian,.ruby]
    var id: Int { rawValue }
    var key: String { ["diamond","blackOnyx","emerald","ruby","sapphire","obsidian"][rawValue] }
    var slot: Int { [0,3,6,9,3,6][rawValue] }
    var game: JewelGame { self == .diamond ? .grassBreak : self == .ruby ? .grassTrace : self == .obsidian ? .crusher : .kurukuru }
    var composition: String { ["C","SiO₂","Be₃Al₂Si₆O₁₈","Al₂O₃","Al₂O₃","火山ガラス"][rawValue] }
    var name: String { ["ダイヤモンド","ブラックオニキス","エメラルド","ルビー","サファイア","黒曜石"][rawValue] }
    var subtitle: String { "光を集めて、次の深度へ。" }
    var english: String { ["DIAMOND","BLACK ONYX","EMERALD","RUBY","SAPPHIRE","OBSIDIAN"][rawValue] }
    var tint: SIMD3<Float> {
        [SIMD3<Float>(0.64,0.84,0.97), .init(0.20,0.19,0.32), .init(0.35,0.85,0.72),
         .init(0.88,0.15,0.29), .init(0.18,0.42,0.97), .init(0.16,0.19,0.23)][rawValue]
    }
    var structureNote: String { composition }
    var hasKurukuru: Bool { game == .kurukuru }
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

// Orthographic projection shared by the renderer, labels and hit testing.
enum RingTiltMath {
    static let limit:Float=0.4
    static func angles(gravity:SIMD3<Double>)->SIMD2<Double>? {
        guard gravity.x.isFinite,gravity.y.isFinite,gravity.z.isFinite,simd_length(gravity)>0.5 else {return nil}
        return .init(atan2(-gravity.y,-gravity.z),atan2(gravity.x,hypot(gravity.y,gravity.z)))
    }
    static func relative(_ angles:SIMD2<Double>,to reference:SIMD2<Double>)->SIMD2<Float> {
        let delta=SIMD2(RingLayoutMath.wrapped(angles.x-reference.x),RingLayoutMath.wrapped(angles.y-reference.y))*0.7
        return .init(min(limit,max(-limit,Float(delta.x))),min(limit,max(-limit,Float(delta.y))))
    }
    static func transform(_ tilt:SIMD2<Float>)->simd_float4x4 {
        JewelMatrices.rotate(tilt.x,.init(1,0,0))*JewelMatrices.rotate(tilt.y,.init(0,1,0))
    }
    static func project(_ point:SIMD2<Double>,tilt:SIMD2<Float>)->SIMD2<Double> {
        let p=transform(tilt)*SIMD4(Float(point.x),Float(point.y),0,1)
        return .init(Double(p.x),Double(p.y))
    }
    static func unproject(_ point:SIMD2<Double>,tilt:SIMD2<Float>)->SIMD2<Double> {
        let x=Double(tilt.x),y=Double(tilt.y)
        let localX=point.x/cos(y)
        return .init(localX,(point.y-sin(x)*sin(y)*localX)/cos(x))
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
