import Metal
import simd

private struct CrackMaterialSegment {
    var endpoints: SIMD4<Float>
    var appearance: SIMD4<Float> // start/end width, roughness, facet rotation
}

/// Bake only when geometry changes. Runtime shading reads one material texel, not every edge.
final class CrackMaterialRenderer {
    private let device: MTLDevice
    private let pipeline: MTLRenderPipelineState
    private var uploaded: [CrackImpact]?
    private var segments: MTLBuffer?
    private(set) var texture: MTLTexture!
    init(device: MTLDevice, library: MTLLibrary) throws {
        self.device=device
        let descriptor=MTLRenderPipelineDescriptor()
        descriptor.vertexFunction=library.makeFunction(name:"crackMaterialVertex")
        descriptor.fragmentFunction=library.makeFunction(name:"crackMaterialFragment")
        let color=descriptor.colorAttachments[0]!
        color.pixelFormat = .rgba16Float
        color.isBlendingEnabled=true
        color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .one
        pipeline=try device.makeRenderPipelineState(descriptor:descriptor)
    }
    func prepare(command: MTLCommandBuffer, impacts: [CrackImpact]) throws {
        guard uploaded != impacts else { return }
        let size=impacts.isEmpty ? SIMD2(1,1) : SIMD2(840,1440)
        if texture?.width != size.x || texture?.height != size.y {
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:size.x,height:size.y,mipmapped:false)
            descriptor.storageMode = .private; descriptor.usage = [.shaderRead,.renderTarget]
            guard let target=device.makeTexture(descriptor:descriptor) else { throw GlassRayEngine.failure("亀裂テクスチャを作成できません。") }
            texture=target
        }
        let values=impacts.flatMap { impact in impact.edges.map { edge in
            let a=impact.nodes[edge.start].positionMM,b=impact.nodes[edge.end].positionMM
            return CrackMaterialSegment(endpoints:SIMD4(Float(a.x),Float(a.y),Float(b.x),Float(b.y)),
                                        appearance:SIMD4(edge.widthStartMM,edge.widthEndMM,edge.roughness,edge.facetDirection))
        } }
        if !values.isEmpty {
            segments=values.withUnsafeBytes { device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared) }
            guard segments != nil else { throw GlassRayEngine.failure("亀裂データを転送できません。") }
        }
        let pass=MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture=texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
        guard let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { throw GlassRayEngine.failure("亀裂テクスチャを描画できません。") }
        encoder.setRenderPipelineState(pipeline)
        if !values.isEmpty {
            encoder.setVertexBuffer(segments,offset:0,index:0)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:values.count)
        }
        encoder.endEncoding()
        uploaded=impacts
    }
}
