import MetalKit
import simd

@MainActor final class JewelRenderer:NSObject,MTKViewDelegate {
    let device:MTLDevice
    let queue:MTLCommandQueue
    let pipeline:MTLRenderPipelineState
    let backSurface:GemBackSurface
    let background:MTLRenderPipelineState
    let depth:MTLDepthStencilState
    let backgroundDepth:MTLDepthStencilState
    let gems:[JewelMesh]
    var rayPipeline:MTLRenderPipelineState?
    var rays:GemRayResources?
    var raysReady=false
    var quality=RenderQualityPolicy()
    let sphere:JewelMesh
    let cylinder:JewelMesh
    let instanceBuffers:[MTLBuffer]
    let semaphore=DispatchSemaphore(value:3)
    let state:JewelSceneState
    let latticeModels:[simd_float4x4]
    let bondModels:[simd_float4x4]
    var slot=0
    var windowTime:Float=0
    var last:CFTimeInterval=0
    var ready=false
    let capacity=8192
    init(state:JewelSceneState) throws {
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue(),let library=device.makeDefaultLibrary() else {
            throw NSError(domain:"JewelRing",code:2,userInfo:[NSLocalizedDescriptionKey:"Metalを初期化できませんでした。"])
        }
        self.device=device;self.queue=queue;self.state=state
        backSurface=try GemBackSurface(device:device,library:library)
        func make(_ vertex:String,_ fragment:String) throws -> MTLRenderPipelineState {
            let p=MTLRenderPipelineDescriptor();p.vertexFunction=library.makeFunction(name:vertex);p.fragmentFunction=library.makeFunction(name:fragment)
            p.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb;p.depthAttachmentPixelFormat = .depth32Float
            return try device.makeRenderPipelineState(descriptor:p)
        }
        pipeline=try make("jewelVertex","jewelFragment");background=try make("jewelBackgroundVertex","jewelBackgroundFragment")
        let d=MTLDepthStencilDescriptor();d.depthCompareFunction = .less;d.isDepthWriteEnabled=true
        guard let depth=device.makeDepthStencilState(descriptor:d) else { throw NSError(domain:"JewelRing",code:3) }
        self.depth=depth
        let noDepth=MTLDepthStencilDescriptor();noDepth.depthCompareFunction = .always;noDepth.isDepthWriteEnabled=false
        guard let backgroundDepth=device.makeDepthStencilState(descriptor:noDepth) else { throw NSError(domain:"JewelRing",code:3) }
        self.backgroundDepth=backgroundDepth
        gems=try JewelKind.allCases.map{try JewelGeometry.mesh(JewelGeometry.gem($0),device:device)}
        sphere=try JewelGeometry.mesh(JewelGeometry.sphere(),device:device)
        cylinder=try JewelGeometry.mesh(JewelGeometry.cylinder(),device:device)
        var buffers:[MTLBuffer]=[]
        for _ in 0..<3 {
            guard let b=device.makeBuffer(length:MemoryLayout<JewelInstance>.stride*8192,options:.storageModeShared) else { throw NSError(domain:"JewelRing",code:4) }
            buffers.append(b)
        }
        instanceBuffers=buffers
        latticeModels=[];bondModels=[]
        super.init()
        #if targetEnvironment(simulator)
        state.rayStatus=L("シミュレーターではOFF。実機の対応GPUで利用できます。")
        #else
        if device.supportsRaytracingFromRender && device.supportsFamily(.apple9) {
            do {
                rayPipeline=try make("jewelVertex","jewelRayFragment")
                rays=try GemRayResources(device:device,queue:queue,meshes:gems) { [weak self] success in
                    DispatchQueue.main.async {
                        self?.raysReady=success;self?.state.rayAvailable=success
                        self?.state.rayStatus=L(success ? "対応GPU · 選択中の宝石の内部光線を追跡":"レイトレーシングの準備に失敗。通常描画を利用します。")
                    }
                }
            } catch {state.rayStatus=L("RT初期化失敗。通常描画を利用します。")}
        } else {state.rayStatus=L("このGPUは対象外です。通常描画を利用します。")}
        #endif
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    func draw(in view:MTKView) {
        let now=CACurrentMediaTime(),dt=last==0 ? 0:now-last;last=now
        state.tick(dt)
        quality.preference=state.quality
        let tier=quality.effective(thermal:ProcessInfo.processInfo.thermalState,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)
        let fps=tier == .low ? 30:(tier == .high && state.quality == .high ? min(120,UIScreen.main.maximumFramesPerSecond):60)
        if view.preferredFramesPerSecond != fps {view.preferredFramesPerSecond=fps}
        if state.actualQuality != tier.title {DispatchQueue.main.async {self.state.actualQuality=tier.title}}
        (view as? JewelTouchView)?.refreshAccessibility()
        guard !state.paused,let descriptor=view.currentRenderPassDescriptor,let drawable=view.currentDrawable,
              semaphore.wait(timeout:.now()) == .success else { return }
        var committed=false
        defer { if !committed { semaphore.signal() } }
        let groups=instances()
        let all=groups.gems+groups.atoms+groups.bonds
        guard all.count<=capacity,let command=queue.makeCommandBuffer() else { return }
        let buffer=instanceBuffers[slot];slot=(slot+1)%3
        all.withUnsafeBytes { if let base=$0.baseAddress { memcpy(buffer.contents(),base,$0.count) } }
        var frame=JewelFrame(values:.init(Float(state.time),Float(state.inspectionProgress),Float(state.renderedZoom),Float(state.ringAngle)),dimensions:.init(Float(view.drawableSize.width),Float(view.drawableSize.height),state.reduceMotion ? 1:0,Float(state.decoratedSlots+state.decoration*4096)))
        if state.windowLightMotion,!state.reduceMotion,tier != .low {
            windowTime+=Float(min(0.1,max(0,dt)))
        }
        frame.scene.y=windowTime
        frame.scene.z=state.displayedTilt.x;frame.scene.w=state.displayedTilt.y
        let focus=state.displayPosition(state.kind)
        frame.focus = .init(Float(focus.x),Float(focus.y),0,0)
        do {
            try backSurface.encode(command:command,size:view.drawableSize,frame:frame,buffer:buffer,draws:groups.gems.enumerated().map{(gems[Int($0.element.material.y)],1,$0.offset)})
        } catch {state.error=L("宝石の透過描画を準備できませんでした。");return}
        guard let encoder=command.makeRenderCommandEncoder(descriptor:descriptor) else {return}
        encoder.setFragmentTexture(backSurface.texture,index:0)
        encoder.setVertexBytes(&frame,length:MemoryLayout<JewelFrame>.stride,index:2)
        encoder.setFragmentBytes(&frame,length:MemoryLayout<JewelFrame>.stride,index:0)
        encoder.setRenderPipelineState(background);encoder.setDepthStencilState(backgroundDepth)
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth);encoder.setCullMode(.none)
        encoder.setVertexBuffer(buffer,offset:0,index:1)
        func draw(_ mesh:JewelMesh,_ count:Int,_ base:Int) {
            guard count>0 else { return }
            encoder.setVertexBuffer(mesh.buffer,offset:0,index:0)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:mesh.count,instanceCount:count,baseInstance:base)
        }
        for (index,instance) in groups.gems.enumerated() {
            let kind=Int(instance.material.y)
            if state.rayTracing,raysReady,tier != .low,state.kind.rawValue==kind,let rayPipeline,let rays {
                encoder.setRenderPipelineState(rayPipeline)
                encoder.setFragmentAccelerationStructure(rays.structures[kind],bufferIndex:1)
                encoder.setFragmentBuffer(gems[kind].buffer,offset:0,index:2)
            } else {encoder.setRenderPipelineState(pipeline)}
            draw(gems[kind],1,index)
        }
        encoder.setRenderPipelineState(pipeline)
        draw(sphere,groups.atoms.count,groups.gems.count)
        draw(cylinder,groups.bonds.count,groups.gems.count+groups.atoms.count)
        encoder.endEncoding();command.present(drawable)
        let semaphore=self.semaphore,state=self.state,notify = !ready;ready=true
        let cpuMS=(CACurrentMediaTime()-now)*1000
        command.addCompletedHandler { [weak self] c in
            semaphore.signal()
            let failed=c.status == .error,message=c.error?.localizedDescription
            DispatchQueue.main.async {
                self?.quality.observe(cpuMS:cpuMS,gpuMS:max(0,c.gpuEndTime-c.gpuStartTime)*1000)
                if failed { state.error=L(message ?? "描画に失敗しました。") }
                else if notify { state.rendererReady=true }
            }
        }
        committed=true;command.commit()
    }
    private func instances() -> (gems:[JewelInstance],atoms:[JewelInstance],bonds:[JewelInstance]) {
        var gems:[JewelInstance]=[],atoms:[JewelInstance]=[],bonds:[JewelInstance]=[]
        for jewel in state.displayedJewels {
            // Mesh diameter is two model units. NDC diameter two maps to viewport width.
            let model=state.gemModel(jewel)
            gems.append(.init(model:model,color:SIMD4(jewel.tint,state.gemVisibility(jewel)),material:.init(0,Float(jewel.rawValue),1,jewel==state.kind ? -Float(state.inspectionProgress):0)))
        }
        return (gems,atoms,bonds)
    }
}
