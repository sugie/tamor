import XCTest
import MetalKit
@testable import Tamor

@MainActor final class GemTransmissionTests:XCTestCase {
    func testBackPassContainsBackFacetDepthAndRejectsBackground() throws {
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue=try XCTUnwrap(device.makeCommandQueue())
        let library=try XCTUnwrap(device.makeDefaultLibrary())
        let pass=try GemBackSurface(device:device,library:library)
        let gem=try JewelGeometry.mesh(JewelGeometry.gem(.diamond),device:device)
        var thicknesses:[Float]=[]
        for scale:Float in [0.45,0.8] {
            var instance=JewelInstance(model:JewelMatrices.scale(.init(repeating:scale)),color:.init(1,1,1,1),material:.init(0,0,1,0))
            let instances=try XCTUnwrap(device.makeBuffer(bytes:&instance,length:MemoryLayout<JewelInstance>.stride,options:.storageModeShared))
            let frame=JewelFrame(values:.init(0,1,0,0),dimensions:.init(128,128,0,0))
            let c=try XCTUnwrap(queue.makeCommandBuffer())
            try pass.encode(command:c,size:.init(width:128,height:128),frame:frame,buffer:instances,draws:[(gem,1,0)])
            let texture=try XCTUnwrap(pass.texture)
            let bytes=try XCTUnwrap(device.makeBuffer(length:512,options:.storageModeShared))
            let blit=try XCTUnwrap(c.makeBlitCommandEncoder())
            for (offset,origin) in [(0,MTLOrigin(x:64,y:64,z:0)),(256,MTLOrigin(x:0,y:0,z:0))] {
                blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:origin,sourceSize:.init(width:1,height:1,depth:1),to:bytes,destinationOffset:offset,destinationBytesPerRow:256,destinationBytesPerImage:256)
            }
            blit.endEncoding();c.commit();c.waitUntilCompleted()
            XCTAssertEqual(c.status,.completed)
            let values=bytes.contents().bindMemory(to:UInt16.self,capacity:256)
            func component(_ i:Int)->Float {Float(Float16(bitPattern:values[i]))}
            let normal=SIMD3(component(0),component(1),component(2))
            XCTAssertEqual(simd_length(normal),1,accuracy:0.003,"Normal magnitude encodes the object's identity")
            XCTAssertLessThan(normal.z,0,"Front facets must not enter the back-surface map")
            XCTAssertGreaterThan(component(3),0.5,"Depth must be behind the gem center")
            XCTAssertEqual(component(128),0);XCTAssertEqual(component(131),1,"Background remains invalid")
            let backZ=(0.5-component(3))/0.2
            thicknesses.append((0.38*scale-backZ)/scale)
        }
        XCTAssertEqual(thicknesses[0],thicknesses[1],accuracy:0.04,"Zoom cannot change the physical optical thickness")
    }
    func testWindowPatternAndItsLightReachTheGem() throws {
        let device=try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue=try XCTUnwrap(device.makeCommandQueue()),library=try XCTUnwrap(device.makeDefaultLibrary())
        let backs=try GemBackSurface(device:device,library:library)
        let mesh=try JewelGeometry.mesh(JewelGeometry.gem(.diamond),device:device)
        func pipeline(_ vertex:String,_ fragment:String)throws->MTLRenderPipelineState {
            let p=MTLRenderPipelineDescriptor();p.vertexFunction=library.makeFunction(name:vertex);p.fragmentFunction=library.makeFunction(name:fragment)
            p.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb;p.depthAttachmentPixelFormat = .depth32Float
            return try device.makeRenderPipelineState(descriptor:p)
        }
        let background=try pipeline("jewelBackgroundVertex","jewelBackgroundFragment")
        let gem=try pipeline("jewelVertex","jewelFragment")
        let depth=MTLDepthStencilDescriptor();depth.depthCompareFunction = .less;depth.isDepthWriteEnabled=true
        let depthState=try XCTUnwrap(device.makeDepthStencilState(descriptor:depth))
        var instance=JewelInstance(model:JewelMatrices.rotate(-0.3,.init(1,0,0))*JewelMatrices.rotate(0.25,.init(0,1,0))*JewelMatrices.scale(.init(repeating:0.76)),color:.init(1,1,1,1),material:.init(0,0,1,0))
        let buffer=try XCTUnwrap(device.makeBuffer(bytes:&instance,length:MemoryLayout<JewelInstance>.stride,options:.storageModeShared))
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm_srgb,width:128,height:128,mipmapped:false)
        descriptor.storageMode = .private;descriptor.usage = [.renderTarget]
        let color=try XCTUnwrap(device.makeTexture(descriptor:descriptor))
        descriptor.pixelFormat = .depth32Float
        let depthTexture=try XCTUnwrap(device.makeTexture(descriptor:descriptor))
        func render(time:Float,withGem:Bool,visibility:Float=1)throws->[UInt8] {
            instance.material.z=visibility
            withUnsafeBytes(of:&instance) {memcpy(buffer.contents(),$0.baseAddress!,$0.count)}
            var frame=JewelFrame(values:.init(0,1,0,0),dimensions:.init(128,128,0,0),scene:.init(0,time,0,0))
            let command=try XCTUnwrap(queue.makeCommandBuffer())
            try backs.encode(command:command,size:.init(width:128,height:128),frame:frame,buffer:buffer,draws:[(mesh,1,0)])
            let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
            let e=try XCTUnwrap(command.makeRenderCommandEncoder(descriptor:pass))
            e.setVertexBytes(&frame,length:MemoryLayout<JewelFrame>.stride,index:2);e.setFragmentBytes(&frame,length:MemoryLayout<JewelFrame>.stride,index:0)
            e.setRenderPipelineState(background);e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            if withGem {
                e.setDepthStencilState(depthState);e.setRenderPipelineState(gem);e.setFragmentTexture(backs.texture,index:0)
                e.setVertexBuffer(mesh.buffer,offset:0,index:0);e.setVertexBuffer(buffer,offset:0,index:1)
                e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:mesh.count)
            }
            e.endEncoding()
            let result=try XCTUnwrap(device.makeBuffer(length:128*128*4,options:.storageModeShared))
            let b=try XCTUnwrap(command.makeBlitCommandEncoder())
            b.copy(from:color,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:128,height:128,depth:1),to:result,destinationOffset:0,destinationBytesPerRow:512,destinationBytesPerImage:65536)
            b.endEncoding();command.commit();command.waitUntilCompleted();XCTAssertEqual(command.status,.completed)
            return Array(UnsafeBufferPointer(start:result.contents().assumingMemoryBound(to:UInt8.self),count:65536))
        }
        let wall=try render(time:0,withGem:false),stone=try render(time:0,withGem:true)
        let shifted=try render(time:9,withGem:true),still=try render(time:0,withGem:true)
        // Central crop stays inside the gem: lighting must affect the actual material, not just the background.
        let center=(48..<80).flatMap {y in (48..<80).map {x in (y*128+x)*4+1}}
        let values=center.map{Int(wall[$0])}
        XCTAssertGreaterThan(values.max()!-values.min()!,35,"Window panes must have visible light/dark boundaries")
        let refracted=center.filter {abs(Int(stone[$0])-Int(wall[$0]))>12}.count
        XCTAssertGreaterThan(refracted,center.count/4,"Gem pixels cannot simply show the unrefracted backdrop")
        XCTAssertGreaterThan(center.filter {abs(Int(stone[$0])-Int(shifted[$0]))>1}.count,30,"Moving light must also change the gem")
        XCTAssertEqual(stone,still,"A frozen light clock must produce a stable image")
        let hidden=try render(time:0,withGem:true,visibility:0)
        XCTAssertEqual(hidden,wall,"Fully faded gems must not leave dither dots against the bright window")
    }

}
