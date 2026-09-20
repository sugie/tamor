import Metal

/// The same triangle buffer is used for rasterization and acceleration structure construction.
/// Builds once, asynchronously on the renderer queue; never blocks the main actor for GPU completion.
final class GemRayResources {
    let structures:[MTLAccelerationStructure]
    let scratch:[MTLBuffer]
    init(device:MTLDevice,queue:MTLCommandQueue,meshes:[JewelMesh],completion:@escaping(Bool)->Void) throws {
        guard let command=queue.makeCommandBuffer(),let encoder=command.makeAccelerationStructureCommandEncoder() else {throw SaveFailure.unreadable}
        var structures:[MTLAccelerationStructure]=[],scratch:[MTLBuffer]=[]
        for mesh in meshes {
            let triangle=MTLAccelerationStructureTriangleGeometryDescriptor()
            triangle.vertexBuffer=mesh.buffer;triangle.vertexStride=MemoryLayout<JewelVertex>.stride;triangle.vertexFormat = .float3
            triangle.triangleCount=mesh.count/3;triangle.opaque=true
            let descriptor=MTLPrimitiveAccelerationStructureDescriptor();descriptor.geometryDescriptors=[triangle]
            let sizes=device.accelerationStructureSizes(descriptor:descriptor)
            guard let structure=device.makeAccelerationStructure(size:sizes.accelerationStructureSize),let work=device.makeBuffer(length:sizes.buildScratchBufferSize,options:.storageModePrivate) else {throw SaveFailure.unreadable}
            encoder.build(accelerationStructure:structure,descriptor:descriptor,scratchBuffer:work,scratchBufferOffset:0)
            structures.append(structure);scratch.append(work)
        }
        self.structures=structures;self.scratch=scratch
        encoder.endEncoding();command.addCompletedHandler {completion($0.status == .completed)};command.commit()
    }
}
