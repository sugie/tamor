import Foundation
import Metal
import simd

private struct FragmentInstance {
    var transform:simd_float4x4
    var originalCenter:SIMD4<Float>
    var links:SIMD4<UInt32>
}
private struct FragmentUniforms {
    var viewport,optics:SIMD4<Float>
    var sampling:SIMD4<UInt32>
    var rotation:simd_float4x4
    var effect:SIMD4<Float>
}
/// Static local meshes/BLAS, moving instances. No parent glass geometry is registered here.
final class GlassFragmentEngine {
    let snapshot:GlassBreakSnapshot
    let device:MTLDevice
    let hardware:Bool
    let pipeline:MTLComputePipelineState
    private var triangles:MTLBuffer
    private var nodes:MTLBuffer
    private var instances:[FragmentInstance]=[]
    private var bounds:[(SIMD3<Float>,SIMD3<Float>)]=[]
    private var meshes:[[GlassRayTriangle]]=[]
    private var bottom:[MTLAccelerationStructure]=[]
    private var acceleration:MTLAccelerationStructure?
    private var hardwareReady=false
    private(set) var texture:MTLTexture?
    var backend:String { hardware ? "破片 / Metal RT API":"破片 / GPUソフトウェアRT" }

    init(snapshot:GlassBreakSnapshot,device:MTLDevice,library:MTLLibrary,forceSoftware:Bool=false) throws {
        self.snapshot=snapshot; self.device=device
        #if targetEnvironment(simulator)
        hardware=false
        #else
        hardware=device.supportsRaytracing && !forceSoftware
        #endif
        guard let function=library.makeFunction(name:hardware ? "glassFragmentsHardware":"glassFragmentsSoftware") else {
            throw GlassRayEngine.failure("ガラスの破片の描画に必要な Metal 機能を準備できませんでした。")
        }
        pipeline=try device.makeComputePipelineState(function:function)
        var ts:[GlassRayTriangle]=[],ns:[GlassRayNode]=[]
        for f in snapshot.geometry.fragments {
            let scene=GlassRayScene(triangles:f.triangles),to=UInt32(ts.count),no=UInt32(ns.count)
            instances.append(.init(transform:matrix_identity_float4x4,originalCenter:SIMD4(f.center,0),links:SIMD4(no,to,0,0)))
            bounds.append((scene.nodes[0].minimum.xyz,scene.nodes[0].maximum.xyz))
            meshes.append(scene.triangles)
            ts += scene.triangles
            ns += scene.nodes.map { node in
                var n=node
                if n.links.y>0 { n.links.x += to } else { n.links.x += no; n.links.z += no }
                return n
            }
        }
        triangles=try Self.buffer(ts,device:device); nodes=try Self.buffer(ns,device:device)
    }
    private static func buffer<T>(_ values:[T],device:MTLDevice) throws -> MTLBuffer {
        guard !values.isEmpty,let b=values.withUnsafeBytes({ device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared) }) else { throw GlassRayEngine.failure("破片のGPUメモリを確保できません。") }; return b
    }
    func encode(command:MTLCommandBuffer,size:SIMD2<Int>,settings:GlassStudySettings,time:Float,material:MTLTexture?) throws {
        if texture?.width != size.x || texture?.height != size.y {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:size.x,height:size.y,mipmapped:false)
            d.usage=[.shaderWrite,.shaderRead]; d.storageMode = .private
            guard let t=device.makeTexture(descriptor:d) else { throw GlassRayEngine.failure("破片画像を確保できません。") }; texture=t
        }
        let pane=GlassFraming.rotation(yaw:settings.yaw,pitch:settings.pitch)
        let poses=GlassBreakMotion.poses(snapshot,time:time,paneRotation:pane)
        var transformedBounds:[(SIMD3<Float>,SIMD3<Float>)]=[]
        for i in poses.indices {
            let p=poses[i],r=p.rotation
            instances[i].transform=simd_float4x4(columns:(SIMD4(r.columns.0,0),SIMD4(r.columns.1,0),SIMD4(r.columns.2,0),SIMD4(p.translation,1)))
            let (low,high)=bounds[i],c=(low+high)/2,h=(high-low)/2
            let center=r*c+p.translation
            let extent=abs(r.columns.0)*h.x+abs(r.columns.1)*h.y+abs(r.columns.2)*h.z
            transformedBounds.append((center-extent,center+extent))
        }
        let instanceBuffer=try Self.buffer(instances,device:device)
        var top:[GlassRayNode]=[]
        func build(_ ids:[Int])->UInt32 {
            let index=UInt32(top.count)
            var low=SIMD3<Float>(repeating:.infinity),high=SIMD3<Float>(repeating:-.infinity)
            for i in ids { low=simd_min(low,transformedBounds[i].0); high=simd_max(high,transformedBounds[i].1) }
            top.append(.init(minimum:SIMD4(low,0),maximum:SIMD4(high,0),links:.zero))
            if ids.count==1 { top[Int(index)].links=SIMD4(UInt32(ids[0]),1,0,0) }
            else {
                let d=high-low,axis=d.x>d.y ? (d.x>d.z ? 0:2):(d.y>d.z ? 1:2)
                let sorted=ids.sorted { transformedBounds[$0].0[axis]+transformedBounds[$0].1[axis] < transformedBounds[$1].0[axis]+transformedBounds[$1].1[axis] }
                let mid=ids.count/2,l=build(Array(sorted[..<mid])),r=build(Array(sorted[mid...]))
                top[Int(index)].links=SIMD4(l,0,r,0)
            }
            return index
        }
        _=build(Array(poses.indices))
        let topBuffer=try Self.buffer(top,device:device)
        #if !targetEnvironment(simulator)
        if hardware {
            if !hardwareReady {
                for mesh in meshes {
                    let vertices=try Self.buffer(mesh.flatMap{[$0.a,$0.b,$0.c]},device:device)
                    let g=MTLAccelerationStructureTriangleGeometryDescriptor(); g.vertexBuffer=vertices
                    g.vertexStride=MemoryLayout<SIMD4<Float>>.stride; g.vertexFormat = .float3
                    g.triangleCount=mesh.count; g.opaque=true
                    let d=MTLPrimitiveAccelerationStructureDescriptor(); d.geometryDescriptors=[g]
                    let sizes=device.accelerationStructureSizes(descriptor:d)
                    guard let b=device.makeAccelerationStructure(size:sizes.accelerationStructureSize),let scratch=device.makeBuffer(length:sizes.buildScratchBufferSize,options:.storageModePrivate),let e=command.makeAccelerationStructureCommandEncoder() else { throw GlassRayEngine.failure("破片のRT形状を構築できません。") }
                    e.build(accelerationStructure:b,descriptor:d,scratchBuffer:scratch,scratchBufferOffset:0); e.endEncoding(); bottom.append(b)
                }
                hardwareReady=true
            }
            let descriptors: [MTLAccelerationStructureInstanceDescriptor]=instances.enumerated().map { i,instance in
                var d=MTLAccelerationStructureInstanceDescriptor()
                let m=instance.transform
                d.transformationMatrix=MTLPackedFloat4x3(columns:(MTLPackedFloat3Make(m.columns.0.x,m.columns.0.y,m.columns.0.z),MTLPackedFloat3Make(m.columns.1.x,m.columns.1.y,m.columns.1.z),MTLPackedFloat3Make(m.columns.2.x,m.columns.2.y,m.columns.2.z),MTLPackedFloat3Make(m.columns.3.x,m.columns.3.y,m.columns.3.z)))
                d.accelerationStructureIndex=UInt32(i); d.mask=0xff; d.options = .opaque
                return d
            }
            let d=MTLInstanceAccelerationStructureDescriptor(); d.instancedAccelerationStructures=bottom
            d.instanceCount=instances.count; d.instanceDescriptorBuffer=try Self.buffer(descriptors,device:device)
            let sizes=device.accelerationStructureSizes(descriptor:d)
            if acceleration==nil || acceleration!.size<sizes.accelerationStructureSize { acceleration=device.makeAccelerationStructure(size:sizes.accelerationStructureSize) }
            guard let acceleration,let scratch=device.makeBuffer(length:sizes.buildScratchBufferSize,options:.storageModePrivate),let e=command.makeAccelerationStructureCommandEncoder() else { throw GlassRayEngine.failure("破片の配置を更新できません。") }
            e.build(accelerationStructure:acceleration,descriptor:d,scratchBuffer:scratch,scratchBufferOffset:0); e.endEncoding()
        }
        #endif
        guard let encoder=command.makeComputeCommandEncoder(),let texture else { throw GlassRayEngine.failure("破片の描画を開始できません。") }
        let height=GlassFraming.halfHeight(object:GlassObject(),aspect:Float(size.x)/Float(size.y),rotation:pane,amplitude:settings.amplitude)
        var u=FragmentUniforms(viewport:SIMD4(Float(size.x),Float(size.y),height,Float(settings.pattern)),optics:SIMD4(1.52,1,settings.lightAngle,settings.rayTracing ? 16:8),sampling:SIMD4(0,settings.internalReflections ? 1:0,settings.rayTracing && settings.dispersion ? 1:0,UInt32(settings.cracks.count)),rotation:simd_float4x4(columns:(SIMD4(pane.columns.0,0),SIMD4(pane.columns.1,0),SIMD4(pane.columns.2,0),SIMD4(0,0,0,1))),effect:SIMD4(GlassBreakMotion.visibility(at:time),time==0 ? 1:0,0,0))
        let segments=settings.cracks.map(\.shaderSegment)
        let crackBuffer=try Self.buffer(segments.isEmpty ? [SIMD4<Float>.zero]:segments,device:device)
        encoder.setBuffer(crackBuffer,offset:0,index:5)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture,index:0); encoder.setTexture(material,index:1)
        encoder.setBytes(&u,length:MemoryLayout<FragmentUniforms>.stride,index:0)
        encoder.setBuffer(triangles,offset:0,index:1); encoder.setBuffer(nodes,offset:0,index:2)
        encoder.setBuffer(topBuffer,offset:0,index:3); encoder.setBuffer(instanceBuffer,offset:0,index:4)
        #if !targetEnvironment(simulator)
        if hardware { encoder.setAccelerationStructure(acceleration,bufferIndex:3); for b in bottom { encoder.useResource(b,usage:.read) } }
        #endif
        let w=pipeline.threadExecutionWidth
        let h=min(4,pipeline.maxTotalThreadsPerThreadgroup/w)
        // Match the bounded kernels without requiring nonuniform-threadgroup support.
        encoder.dispatchThreadgroups(MTLSize(width:(size.x+w-1)/w,height:(size.y+h-1)/h,depth:1),threadsPerThreadgroup:MTLSize(width:w,height:h,depth:1))
        encoder.endEncoding()
    }
}
