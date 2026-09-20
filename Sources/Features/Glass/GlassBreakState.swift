import Foundation
import simd

struct GlassBreakContext {
    var acceptedTapCount: Int
    var totalCrackLengthMM: Double
    var lastImpactMM: SIMD2<Double>
}
struct GlassBreakPolicy {
    var requiredTapCount: (GlassBreakContext) -> Int = { _ in 3 }
    private(set) var lastValidThreshold = 3
    mutating func shouldBreak(_ context:GlassBreakContext)->Bool {
        let proposed=requiredTapCount(context)
        if proposed>0 && proposed<=100 { lastValidThreshold=proposed }
        return context.acceptedTapCount>=lastValidThreshold
    }
}
/// Immutable geometry snapshot. Identity comparison avoids comparing every vertex in SwiftUI.
final class GlassBreakSnapshot: Equatable {
    let id=UUID()
    let geometry:GlassBreakGeometry.Result
    let impact:SIMD2<Float>
    let seed:UInt64
    init(geometry:GlassBreakGeometry.Result,impact:SIMD2<Float>,seed:UInt64) {
        self.geometry=geometry; self.impact=impact-SIMD2(105,180); self.seed=seed
    }
    static func == (a:GlassBreakSnapshot,b:GlassBreakSnapshot)->Bool { a.id==b.id }
}
struct GlassFragmentPose {
    var rotation:simd_float3x3
    var translation:SIMD3<Float>
}
enum GlassBreakMotion {
    static let duration:Float=0.85
    static func visibility(at time:Float)->Float {
        let t=min(1,max(0,(time-0.15)/0.70)); return 1-t*t*(3-2*t)
    }
    /// Closed-form ballistic motion is frame-rate independent; world gravity is transformed
    /// into pane coordinates. Lengths here remain mm, velocities are explicitly mm/second.
    static func poses(_ snapshot:GlassBreakSnapshot,time:Float,paneRotation:simd_float3x3)->[GlassFragmentPose] {
        var rng=CrackRNG(seed:snapshot.seed)
        let gravity=paneRotation.transpose*SIMD3<Float>(0,-980,0)
        return snapshot.geometry.fragments.map { f in
            let delta=SIMD2(f.center.x,f.center.y)-snapshot.impact
            let angle=Float(rng.unit())*2*Float.pi
            let radial=length(delta)>0.001 ? normalize(delta):SIMD2(cos(angle),sin(angle))
            let speed=Float(300+550*rng.unit())
            let velocity=SIMD3(radial.x*speed,radial.y*speed,Float(-180+360*rng.unit()))
            var axis=SIMD3<Float>(Float(rng.unit()-0.5),Float(rng.unit()-0.5),Float(rng.unit()-0.5))
            if length(axis)<0.001 { axis=SIMD3(0,1,0) }; axis=normalize(axis)
            let spin=Float(1+7*rng.unit())
            return .init(rotation:simd_float3x3(simd_quatf(angle:spin*time,axis:axis)),translation:f.center+velocity*time+gravity*(0.5*time*time))
        }
    }
}
private struct CrackRNG {
    var seed:UInt64
    mutating func unit()->Double {
        seed &+= 0x9e3779b97f4a7c15
        var z=seed; z=(z^(z>>30)) &* 0xbf58476d1ce4e5b9; z=(z^(z>>27)) &* 0x94d049bb133111eb
        return Double((z^(z>>31))>>11)/9007199254740992
    }
}
