import Foundation
import simd

struct GlassStudySettings: Equatable {
    var renderPixelLimit:Int=512
    var amplitude: Float = 0.48
    var yaw: Float = -0.23
    var pitch: Float = 0.10
    var pattern: Int = 0
    var visible = true
    var rayTracing = true
    var lightAngle: Float = 0
    var internalReflections = true
    var dispersion = false
    var cracks: [GlassCrack] = []
    var impacts: [CrackImpact] = []
    var fracture: GlassBreakSnapshot?
    var animationPaused = false
    var networkMode = true
    var crackDensity: CrackDensity = .standard
    var networkEdgeCount: Int { impacts.reduce(0) { $0 + $1.edges.count } }
}

struct GlassRayStatus: Equatable {
    var gpuMS:Double=0
    var cpuMS:Double=0
    var backend = "準備中"
    var samples = 0
    var target = 48
    var error: String?
}

/// Physical model. Every length in the material study, including the shader, is in mm.
struct GlassObject {
    let widthMM: Float = 210
    let heightMM: Float = 360
    #if TAMOR
    let depthMM: Float = 12
    #else
    let depthMM: Float = 14.5
    #endif
    let refractiveIndex: Float = 1.52
    let bevelMM: Float = 1.4
    var size: SIMD3<Float> { SIMD3(widthMM, heightMM, depthMM) }
}

enum GlassFraming {
    static func rayTextureSize(width: Double, height: Double) -> SIMD2<Int> {
        let scale=min(1,768/max(max(width,height),1))
        return SIMD2(max(1,Int(width*scale)),max(1,Int(height*scale)))
    }
    static func rotation(yaw: Float, pitch: Float) -> simd_float3x3 {
        let y = simd_float3x3(columns: (SIMD3(cos(yaw), 0, -sin(yaw)),
                                      SIMD3(0, 1, 0), SIMD3(sin(yaw), 0, cos(yaw))))
        let x = simd_float3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, cos(pitch), sin(pitch)),
                                      SIMD3(0, -sin(pitch), cos(pitch))))
        return y * x
    }

    /// Orthographic aspect-fit of all eight corners, including surface displacement.
    /// No device-name or pixel-density lookup: the actual available viewport determines the scale.
    static func halfHeight(object: GlassObject, aspect: Float, rotation: simd_float3x3,
                           amplitude: Float) -> Float {
        let half = object.size / 2 + SIMD3(0, 0, amplitude)
        var extent = SIMD2<Float>.zero
        for x: Float in [-1, 1] { for y: Float in [-1, 1] { for z: Float in [-1, 1] {
            let p = rotation * (half * SIMD3(x, y, z))
            extent = simd_max(extent, abs(SIMD2(p.x, p.y)))
        } } }
        return max(extent.y, extent.x / max(aspect, 0.01)) / 0.79
    }
}
