import Foundation
import simd

/// Shared triangle geometry for the simulator's BVH and Metal acceleration structures.
struct GlassRayTriangle {
    var a, b, c: SIMD4<Float>
    var na, nb, nc: SIMD4<Float>
    var minimum: SIMD3<Float> { simd_min(a.xyz, simd_min(b.xyz, c.xyz)) }
    var maximum: SIMD3<Float> { simd_max(a.xyz, simd_max(b.xyz, c.xyz)) }
    var center: SIMD3<Float> { (a.xyz+b.xyz+c.xyz)/3 }
}

struct GlassRayNode {
    var minimum, maximum: SIMD4<Float>
    // Leaf: first triangle, count, 0, 0. Branch: left node, 0, right node, 0.
    var links: SIMD4<UInt32>
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x,y,z) }
}

struct GlassRayScene {
    var triangles: [GlassRayTriangle] = []
    var nodes: [GlassRayNode] = []
    var maximumDepth = 0

    static func height(_ p: SIMD2<Float>, amplitude: Float) -> Float {
        amplitude * (0.5*sin(p.x*0.037+p.y*0.012+0.8)*cos(p.y*0.029-0.4)
                     + 0.3*sin(p.x*0.018-p.y*0.043+1.7) + 0.2*cos(p.x*0.061+p.y*0.021))
    }

    init(object: GlassObject = GlassObject(), amplitude: Float) {
        let half = object.size/2, radius = object.bevelMM
        let inner = half-SIMD3(repeating: radius)
        func coordinates(_ half: Float, steps: Int) -> [Float] {
            // Extra samples around the bevel preserve polished edges and shared seams.
            let core = half-radius
            return [-half, -half+radius*0.30] + (0...steps).map { -core+2*core*Float($0)/Float(steps) }
                + [half-radius*0.30,half]
        }
        let coordinates = [coordinates(half.x, steps: 28), coordinates(half.y, steps: 48), coordinates(half.z, steps: 2)]
        func vertex(_ raw: SIMD3<Float>) -> (SIMD4<Float>,SIMD4<Float>) {
            let core = simd_clamp(raw, -inner, inner)
            let n = simd_normalize(raw-core)
            var p = core+n*radius
            let xy = SIMD2(p.x,p.y), h = Self.height(xy,amplitude: amplitude)
            let t = min(1,max(0,(p.z+half.z)/(2*half.z)))
            let weight = t*t*(3-2*t)
            let dw = 6*t*(1-t)/(2*half.z)
            let e: Float = 0.05
            let dx = (Self.height(xy+SIMD2(e,0),amplitude: amplitude)-Self.height(xy-SIMD2(e,0),amplitude: amplitude))/(2*e)
            let dy = (Self.height(xy+SIMD2(0,e),amplitude: amplitude)-Self.height(xy-SIMD2(0,e),amplitude: amplitude))/(2*e)
            // Inverse-transpose of the surface displacement Jacobian.
            let nz = n.z/(1+h*dw)
            let normal = simd_normalize(SIMD3(n.x-dx*weight*nz,n.y-dy*weight*nz,nz))
            p.z += h*weight
            return (SIMD4(p,1),SIMD4(normal,0))
        }
        var source: [GlassRayTriangle] = []
        for axis in 0..<3 {
            let u = (axis+1)%3, v = (axis+2)%3
            for sign: Float in [-1,1] {
                for j in 0..<(coordinates[v].count-1) { for i in 0..<(coordinates[u].count-1) {
                    var corners: [(SIMD4<Float>,SIMD4<Float>)] = []
                    for (di,dj) in [(0,0),(1,0),(1,1),(0,1)] {
                        var raw = SIMD3<Float>.zero
                        raw[axis] = half[axis]*sign
                        raw[u] = coordinates[u][i+di]; raw[v] = coordinates[v][j+dj]
                        corners.append(vertex(raw))
                    }
                    for ids in sign > 0 ? [[0,1,2],[0,2,3]] : [[0,2,1],[0,3,2]] {
                        let a = corners[ids[0]], b = corners[ids[1]], c = corners[ids[2]]
                        source.append(.init(a:a.0,b:b.0,c:c.0,na:a.1,nb:b.1,nc:c.1))
                    }
                } }
            }
        }
        _ = build(source, depth: 0)
    }

    init(triangles: [GlassRayTriangle]) {
        if !triangles.isEmpty { _ = build(triangles, depth: 0) }
    }

    private mutating func build(_ source: [GlassRayTriangle], depth: Int) -> UInt32 {
        maximumDepth = max(maximumDepth,depth)
        let index = UInt32(nodes.count)
        var low = SIMD3<Float>(repeating: .infinity), high = -low
        for t in source { low = simd_min(low,t.minimum); high = simd_max(high,t.maximum) }
        nodes.append(.init(minimum: SIMD4(low,0),maximum: SIMD4(high,0),links:.zero))
        if source.count <= 4 {
            nodes[Int(index)].links = SIMD4(UInt32(triangles.count),UInt32(source.count),0,0)
            triangles.append(contentsOf: source)
        } else {
            let size = high-low
            let axis = size.x >= size.y && size.x >= size.z ? 0 : size.y >= size.z ? 1 : 2
            let sorted = source.sorted { $0.center[axis] < $1.center[axis] }
            let mid = sorted.count/2
            let left = build(Array(sorted[..<mid]),depth:depth+1)
            let right = build(Array(sorted[mid...]),depth:depth+1)
            nodes[Int(index)].links = SIMD4(left,0,right,0)
        }
        return index
    }
}
