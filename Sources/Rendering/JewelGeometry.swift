import Metal
import simd

struct JewelVertex { var position:SIMD4<Float>;var normal:SIMD4<Float> }
struct JewelInstance { var model:simd_float4x4;var color:SIMD4<Float>;var material:SIMD4<Float> }
struct JewelFrame { var values:SIMD4<Float>;var dimensions:SIMD4<Float>;var scene:SIMD4<Float> = .zero;var focus:SIMD4<Float> = .zero }
struct JewelMesh { let buffer:MTLBuffer;let count:Int }

enum JewelGeometry {
    static func gem() -> [JewelVertex] {
        var v:[JewelVertex]=[]
        func triangle(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>) {
            var n=simd_normalize(simd_cross(b-a,c-a))
            if simd_dot(n,(a+b+c)/3)<0 { n = -n }
            for p in [a,b,c] { v.append(.init(position:SIMD4(p,1),normal:SIMD4(n,0))) }
        }
        func p(_ i:Int,_ r:Float,_ z:Float) -> SIMD3<Float> {
            let t=Float(i)*2 * .pi/8 + .pi/8
            return .init(cos(t)*r,sin(t)*r,z)
        }
        for i in 0..<8 {
            triangle(.init(0,0,0.38),p(i,0.48,0.38),p(i+1,0.48,0.38))
            let middle=p(i,1,0),next=p(i+1,1,0),top=p(i,0.48,0.38),topNext=p(i+1,0.48,0.38)
            let crown=(top+topNext+middle+next)/4+SIMD3<Float>(0,0,0.035)
            triangle(top,middle,crown);triangle(middle,next,crown)
            triangle(next,topNext,crown);triangle(topNext,top,crown)
            triangle(middle,p(i,1,-0.06),p(i+1,1,-0.06))
            triangle(middle,p(i+1,1,-0.06),next)
            triangle(p(i,1,-0.06),.init(0,0,-0.85),p(i+1,1,-0.06))
        }
        return v
    }
    static func sphere() -> [JewelVertex] {
        var v:[JewelVertex]=[]
        func point(_ i:Int,_ j:Int)->SIMD3<Float> {
            let t=Float(i)*Float.pi/8,a=Float(j)*2 * Float.pi/12
            return SIMD3(sin(t)*cos(a),cos(t),sin(t)*sin(a))
        }
        for i in 0..<8 { for j in 0..<12 {
            for p in [point(i,j),point(i+1,j),point(i+1,j+1),point(i,j),point(i+1,j+1),point(i,j+1)] {
                v.append(.init(position:SIMD4(p,1),normal:SIMD4(p,0)))
            }
        } }
        return v
    }
    static func cylinder() -> [JewelVertex] {
        var v:[JewelVertex]=[]
        func point(_ i:Int,_ y:Float) -> JewelVertex {
            let a=Float(i)*2 * Float.pi/8,n=SIMD3<Float>(cos(a),0,sin(a))
            return .init(position:SIMD4(n.x,y,n.z,1),normal:SIMD4(n,0))
        }
        for i in 0..<8 {
            v += [point(i,-0.5),point(i,0.5),point(i+1,0.5),point(i,-0.5),point(i+1,0.5),point(i+1,-0.5)]
        }
        return v
    }
    static func mesh(_ vertices:[JewelVertex],device:MTLDevice) throws -> JewelMesh {
        guard let buffer=vertices.withUnsafeBytes({ device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared) }) else {
            throw NSError(domain:"JewelRing",code:1,userInfo:[NSLocalizedDescriptionKey:"描画用メモリーを確保できませんでした。"])
        }
        return .init(buffer:buffer,count:vertices.count)
    }
}

extension JewelGeometry {
    static func gem(_ kind:JewelKind)->[JewelVertex] {
        if kind == .diamond {return gem()}
        if kind == .blackOnyx || kind == .obsidian {
            var v:[JewelVertex]=[]
            func point(_ i:Int,_ j:Int)->SIMD3<Float> {
                let t=Float(i)*Float.pi/24,a=Float(j)*2*Float.pi/48
                return SIMD3(sin(t)*cos(a)*0.82,sin(t)*sin(a),cos(t)*0.5)
            }
            for i in 0..<24 {for j in 0..<48 {for p in [point(i,j),point(i+1,j),point(i+1,j+1),point(i,j),point(i+1,j+1),point(i,j+1)] {
                let n=simd_normalize(p/SIMD3(0.82*0.82,1,0.25))
                v.append(.init(position:SIMD4(p,1),normal:SIMD4(n,0)))
            }}}
            return v
        }
        let emerald=kind == .emerald
        let contour:[SIMD2<Float>]=emerald ? [.init(-0.60,-1),.init(0.60,-1),.init(0.82,-0.78),.init(0.82,0.78),.init(0.60,1),.init(-0.60,1),.init(-0.82,0.78),.init(-0.82,-0.78)] : (0..<12).map {let a=Float($0)*2*Float.pi/12;return SIMD2(cos(a)*0.86,sin(a))}
        let rings:[(Float,Float)]=emerald ? [(0.56,0.35),(0.78,0.22),(1,0.02),(1,-0.045),(0.70,-0.32),(0.36,-0.60)] : [(0.49,0.39),(0.74,0.24),(1,0),(1,-0.05),(0.58,-0.40),(0.08,-0.76)]
        var v:[JewelVertex]=[]
        func p(_ i:Int,_ r:(Float,Float))->SIMD3<Float> {let q=contour[i%contour.count]*r.0;return SIMD3(q.x,q.y,r.1)}
        func tri(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>) {
            var n=simd_normalize(simd_cross(b-a,c-a));if simd_dot(n,(a+b+c)/3)<0 {n = -n}
            for point in [a,b,c] {v.append(.init(position:SIMD4(point,1),normal:SIMD4(n,0)))}
        }
        for i in contour.indices {
            tri(.init(0,0,rings[0].1),p(i,rings[0]),p(i+1,rings[0]))
            for j in 0..<rings.count-1 {
                tri(p(i,rings[j]),p(i,rings[j+1]),p(i+1,rings[j+1]))
                tri(p(i,rings[j]),p(i+1,rings[j+1]),p(i+1,rings[j]))
            }
            tri(p(i,rings.last!),.init(0,0,-0.8),p(i+1,rings.last!))
        }
        return v
    }
}
