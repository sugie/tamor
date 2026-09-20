import MetalKit

/// Rasterize the actual back facets before shading the front. This is a bounded,
/// screen-space transmission approximation, available without hardware ray tracing.
final class GemBackSurface {
    private let device:MTLDevice
    private let pipeline:MTLRenderPipelineState
    private let depthState:MTLDepthStencilState
    private(set) var texture:MTLTexture?
    private var depthTexture:MTLTexture?
    init(device:MTLDevice,library:MTLLibrary) throws {
        self.device=device
        let p=MTLRenderPipelineDescriptor()
        p.vertexFunction=library.makeFunction(name:"jewelVertex")
        p.fragmentFunction=library.makeFunction(name:"jewelBackFragment")
        p.colorAttachments[0].pixelFormat = .rgba16Float
        p.depthAttachmentPixelFormat = .depth32Float
        pipeline=try device.makeRenderPipelineState(descriptor:p)
        let d=MTLDepthStencilDescriptor();d.depthCompareFunction = .less;d.isDepthWriteEnabled=true
        guard let state=device.makeDepthStencilState(descriptor:d) else {throw SaveFailure.unreadable}
        depthState=state
    }
    func encode(command:MTLCommandBuffer,size:CGSize,frame:JewelFrame,buffer:MTLBuffer,draws:[(JewelMesh,Int,Int)]) throws {
        // The map only needs facet boundaries, not full display resolution. At most 12 MB.
        let scale=min(1,1024/max(1,max(size.width,size.height)))
        let width=max(1,Int(size.width*scale)),height=max(1,Int(size.height*scale))
        if texture?.width != width || texture?.height != height {
            let color=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:width,height:height,mipmapped:false)
            color.usage=[.renderTarget,.shaderRead];color.storageMode = .private
            let depth=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:width,height:height,mipmapped:false)
            depth.usage = .renderTarget;depth.storageMode = .private
            texture=device.makeTexture(descriptor:color);depthTexture=device.makeTexture(descriptor:depth)
        }
        guard let texture,let depthTexture else {throw SaveFailure.unreadable}
        let pass=MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture=texture;pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1)
        pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        guard let e=command.makeRenderCommandEncoder(descriptor:pass) else {throw SaveFailure.unreadable}
        e.label="Gem back facets and thickness"
        e.setRenderPipelineState(pipeline);e.setDepthStencilState(depthState);e.setCullMode(.none)
        e.setVertexBuffer(buffer,offset:0,index:1)
        var frame=frame;e.setVertexBytes(&frame,length:MemoryLayout<JewelFrame>.stride,index:2)
        for (mesh,count,base) in draws where count>0 {
            e.setVertexBuffer(mesh.buffer,offset:0,index:0)
            e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:mesh.count,instanceCount:count,baseInstance:base)
        }
        e.endEncoding()
    }
}
