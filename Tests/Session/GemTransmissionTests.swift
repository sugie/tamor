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
}
