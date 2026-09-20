import Foundation
import simd

/// One straight crack on the glass. Coordinates and lengths are millimetres.
/// Origin: bottom-left. crad: radians counterclockwise from +X.
struct GlassCrack: Identifiable, Equatable {
    let id: UUID
    let ccx: Double
    let ccy: Double
    let requestedH: Double
    let H: Double
    let crad: Double
    let cex: Double
    let cey: Double

    var center: SIMD2<Double> { SIMD2(ccx,ccy) }
    var end: SIMD2<Double> { SIMD2(cex,cey) }
    var wasClipped: Bool { H < requestedH-1e-8 }
    static let randomLengthMM: ClosedRange<Double> = 10...180

    /// Rounded footprint of the existing beveled pane. Also rejects nonfinite/outside input.
    static func contains(_ point: SIMD2<Double>, object: GlassObject = GlassObject()) -> Bool {
        let width=Double(object.widthMM), height=Double(object.heightMM), r=Double(object.bevelMM)
        guard point.x.isFinite, point.y.isFinite,
              point.x>=0, point.x<=width, point.y>=0, point.y<=height else { return false }
        let q=abs(point-SIMD2(width,height)/2)-(SIMD2(width,height)/2-SIMD2(repeating:r))
        return simd_length(simd_max(q,.zero))+min(max(q.x,q.y),0) <= r
    }

    init?(center: SIMD2<Double>, H requestedH: Double, crad: Double,
          object: GlassObject = GlassObject(), id: UUID = UUID()) {
        guard Self.contains(center,object:object), requestedH.isFinite, requestedH>=0, crad.isFinite else { return nil }
        let fullTurn=2*Double.pi
        let normalized=crad.truncatingRemainder(dividingBy:fullTurn)
        let angle=normalized<0 ? normalized+fullTurn : normalized
        let direction=SIMD2(cos(angle),sin(angle))
        let bounds=SIMD2(Double(object.widthMM),Double(object.heightMM))
        var length=requestedH
        // Clip the ray's distance, never clamp X and Y independently (which changes crad).
        for axis in 0..<2 {
            let d=direction[axis]
            if d>1e-14 { length=min(length,(bounds[axis]-center[axis])/d) }
            else if d < -1e-14 { length=min(length,-center[axis]/d) }
        }
        length=max(0,length)
        if !Self.contains(center+direction*length,object:object) {
            // The rounded rectangle is convex: inside distances form one interval [0, H].
            var inside=0.0, outside=length
            for _ in 0..<64 {
                let middle=inside+(outside-inside)/2
                if Self.contains(center+direction*middle,object:object) { inside=middle }
                else { outside=middle }
            }
            length=inside
        }
        let endpoint=center+direction*length
        self.id=id; ccx=center.x; ccy=center.y
        self.requestedH=requestedH; H=length; self.crad=angle
        cex=endpoint.x; cey=endpoint.y
    }

    static func random<R: RandomNumberGenerator>(at center: SIMD2<Double>,
                                                  object: GlassObject = GlassObject(),
                                                  using rng: inout R) -> GlassCrack? {
        GlassCrack(center:center,H:Double.random(in:randomLengthMM,using:&rng),
                   crad:Double.random(in:0..<(2*Double.pi),using:&rng),object:object)
    }

    var shaderSegment: SIMD4<Float> {
        let half=SIMD2(GlassObject().widthMM,GlassObject().heightMM)/2
        return SIMD4(Float(ccx)-half.x,Float(ccy)-half.y,Float(cex)-half.x,Float(cey)-half.y)
    }
}

enum GlassCrackPicking {
    /// Nearest visible surface intersection with the same triangle geometry used by RT.
    /// A background tap returns nil instead of being moved onto the glass edge.
    static func point(at position: SIMD2<Float>, viewport: SIMD2<Float>,
                      cameraAspect: Float? = nil, settings: GlassStudySettings,
                      scene: GlassRayScene) -> SIMD2<Double>? {
        guard settings.visible, viewport.x>0,viewport.y>0,
              all(position .>= .zero), all(position .<= viewport) else { return nil }
        let object=GlassObject()
        let rotation=GlassFraming.rotation(yaw:settings.yaw,pitch:settings.pitch)
        let aspect=cameraAspect ?? viewport.x/viewport.y
        let halfHeight=GlassFraming.halfHeight(object:object,aspect:aspect,rotation:rotation,amplitude:settings.amplitude)
        let xy=(position/viewport-SIMD2(repeating:0.5))*SIMD2(2*aspect,-2)*halfHeight
        let origin=rotation.transpose*SIMD3(xy.x,xy.y,600)
        let direction=rotation.transpose*SIMD3<Float>(0,0,-1)
        var nearest=Float.infinity
        for triangle in scene.triangles {
            let edge1=triangle.b.xyz-triangle.a.xyz, edge2=triangle.c.xyz-triangle.a.xyz
            let p=simd_cross(direction,edge2), determinant=simd_dot(edge1,p)
            if abs(determinant)<1e-9 { continue }
            let delta=origin-triangle.a.xyz
            let u=simd_dot(delta,p)/determinant
            if u<0 || u>1 { continue }
            let q=simd_cross(delta,edge1)
            let v=simd_dot(direction,q)/determinant
            let t=simd_dot(edge2,q)/determinant
            if v>=0 && u+v<=1 && t>=0 { nearest=min(nearest,t) }
        }
        guard nearest.isFinite else { return nil }
        let hit=origin+direction*nearest
        let center=SIMD2(Double(hit.x)+Double(object.widthMM)/2,Double(hit.y)+Double(object.heightMM)/2)
        return GlassCrack.contains(center) ? center : nil
    }
}
