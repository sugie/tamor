import Foundation
import Metal
import simd

struct GlassRayUniforms {
    var viewport: SIMD4<Float>
    var optics: SIMD4<Float>
    var sampling: SIMD4<UInt32>
    var rotation: simd_float4x4
}

/// Metal-only renderer shared by iOS and the macOS hardware/software comparison harness.
final class GlassRayEngine {
    let device: MTLDevice
    let pipeline: MTLComputePipelineState
    let material: CrackMaterialRenderer
    let hardware: Bool
    var texture: MTLTexture?
    private var previousTexture: MTLTexture?
    private var triangleBuffer: MTLBuffer?
    private var nodeBuffer: MTLBuffer?
    private var vertexBuffer: MTLBuffer?
    private var acceleration: MTLAccelerationStructure?
    private var geometryAmplitude: Float?
    private var crackBuffer: MTLBuffer?
    private var uploadedCracks: [GlassCrack]?
    private let object = GlassObject()

    var backend: String {
        #if targetEnvironment(simulator)
        return "シミュレーター / GPUソフトウェアRT"
        #else
        return hardware ? "Metal RT API" : "GPUソフトウェアRT"
        #endif
    }

    init(device: MTLDevice, library: MTLLibrary, forceSoftware: Bool = false) throws {
        self.device = device
        material=try CrackMaterialRenderer(device:device,library:library)
        #if targetEnvironment(simulator)
        hardware = false
        #else
        hardware = device.supportsRaytracing && !forceSoftware
        #endif
        let name = hardware ? "glassTraceHardware" : "glassTraceSoftware"
        guard let function = library.makeFunction(name: name) else {
            throw Self.failure("\(name)が見つかりません。")
        }
        pipeline = try device.makeComputePipelineState(function: function)
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "GlassRayEngine", code: 1, userInfo: [NSLocalizedDescriptionKey:message])
    }

    private func buffer<T>(_ values: [T]) throws -> MTLBuffer {
        let allocation = values.withUnsafeBytes { bytes in
            device.makeBuffer(bytes:bytes.baseAddress!,length:bytes.count,options:.storageModeShared)
        }
        guard let buffer = allocation else {
            throw Self.failure("レイトレーシング用メモリを確保できません。")
        }
        return buffer
    }

    func prepare(command: MTLCommandBuffer, size: SIMD2<Int>, amplitude: Float) throws {
        if texture?.width != size.x || texture?.height != size.y {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                                                                       width: size.x,height: size.y,mipmapped: false)
            descriptor.usage = [.shaderRead,.shaderWrite]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor),let previous = device.makeTexture(descriptor: descriptor) else { throw Self.failure("描画画像を確保できません。") }
            self.texture = texture;self.previousTexture=previous
        }
        if geometryAmplitude != amplitude {
            let scene = GlassRayScene(object: object,amplitude: amplitude)
            triangleBuffer = try buffer(scene.triangles)
            nodeBuffer = try buffer(scene.nodes)
            #if !targetEnvironment(simulator)
            if hardware {
                vertexBuffer = try buffer(scene.triangles.flatMap { [$0.a,$0.b,$0.c] })
                let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
                geometry.vertexBuffer = vertexBuffer
                geometry.vertexStride = MemoryLayout<SIMD4<Float>>.stride
                geometry.vertexFormat = .float3
                geometry.triangleCount = scene.triangles.count
                geometry.opaque = true
                let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
                descriptor.geometryDescriptors = [geometry]
                let sizes = device.accelerationStructureSizes(descriptor: descriptor)
                guard let acceleration = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
                      let scratch = device.makeBuffer(length: sizes.buildScratchBufferSize,options:.storageModePrivate),
                      let encoder = command.makeAccelerationStructureCommandEncoder() else {
                    throw Self.failure("Metalレイトレーシング用の形状構築に失敗しました。")
                }
                encoder.build(accelerationStructure:acceleration,descriptor:descriptor,scratchBuffer:scratch,scratchBufferOffset:0)
                encoder.endEncoding()
                self.acceleration = acceleration
            }
            #endif
            geometryAmplitude = amplitude
        }
    }

    func encode(command: MTLCommandBuffer, settings: GlassStudySettings, sample: Int, target: Int) throws {
        try material.prepare(command:command,impacts:settings.impacts)
        if uploadedCracks != settings.cracks {
            let segments=settings.cracks.map(\.shaderSegment)
            crackBuffer=try buffer(segments.isEmpty ? [SIMD4<Float>.zero] : segments)
            uploadedCracks=settings.cracks
        }
        // Separate read and write textures avoid unsupported read_write formats on Simulator.
        swap(&texture,&previousTexture)
        guard let texture, let previousTexture, let triangleBuffer, let nodeBuffer,
              let encoder = command.makeComputeCommandEncoder() else { throw Self.failure("光線の計算を開始できません。") }
        let rotation = GlassFraming.rotation(yaw:settings.yaw,pitch:settings.pitch)
        let aspect = Float(texture.width)/Float(texture.height)
        let height = GlassFraming.halfHeight(object:object,aspect:aspect,rotation:rotation,amplitude:settings.amplitude)
        var uniforms = GlassRayUniforms(
            viewport:SIMD4(Float(texture.width),Float(texture.height),height,Float(settings.pattern)),
            optics:SIMD4(object.refractiveIndex,settings.visible ? 1 : 0,settings.lightAngle,settings.internalReflections ? 8 : 1),
            sampling:SIMD4(UInt32(sample),UInt32(target),settings.dispersion ? 1 : 0,UInt32(settings.cracks.count)),
            rotation:simd_float4x4(columns:(SIMD4(rotation.columns.0,0),SIMD4(rotation.columns.1,0),
                                           SIMD4(rotation.columns.2,0),SIMD4(0,0,0,1))))
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture,index:0)
        encoder.setTexture(material.texture,index:1)
        encoder.setTexture(previousTexture,index:2)
        encoder.setBytes(&uniforms,length:MemoryLayout<GlassRayUniforms>.stride,index:0)
        encoder.setBuffer(triangleBuffer,offset:0,index:1)
        encoder.setBuffer(nodeBuffer,offset:0,index:2)
        encoder.setBuffer(crackBuffer,offset:0,index:4)
        #if !targetEnvironment(simulator)
        if hardware { encoder.setAccelerationStructure(acceleration,bufferIndex:3) }
        #endif
        let width = pipeline.threadExecutionWidth
        let groupHeight = min(4,pipeline.maxTotalThreadsPerThreadgroup/width)
        // Uniform groups also work on Simulator. Kernels discard out-of-bounds pixels.
        encoder.dispatchThreadgroups(MTLSize(width:(texture.width+width-1)/width,height:(texture.height+groupHeight-1)/groupHeight,depth:1),
                                     threadsPerThreadgroup:MTLSize(width:width,height:groupHeight,depth:1))
        encoder.endEncoding()
    }
}
