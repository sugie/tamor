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
        latticeModels=state.lattice.atoms.map { JewelMatrices.translate($0.position)*JewelMatrices.scale(.init(repeating:0.115)) }
        bondModels=state.lattice.bonds.map {
            JewelMatrices.bond(from:state.lattice.atoms[$0.first].position,to:state.lattice.atoms[$0.second].position,radius:0.032)
        }
        super.init()
        #if targetEnvironment(simulator)
        state.rayStatus="シミュレーターではOFF。実機の対応GPUで利用できます。"
        #else
        if device.supportsRaytracingFromRender && device.supportsFamily(.apple9) {
            do {
                rayPipeline=try make("jewelVertex","jewelRayFragment")
                rays=try GemRayResources(device:device,queue:queue,meshes:gems) { [weak self] success in
                    DispatchQueue.main.async {
                        self?.raysReady=success;self?.state.rayAvailable=success
                        self?.state.rayStatus=success ? "対応GPU · 詳細観察で内部光線を追跡":"レイトレーシングの準備に失敗。通常描画を利用します。"
                    }
                }
            } catch {state.rayStatus="RT初期化失敗。通常描画を利用します。"}
        } else {state.rayStatus="このGPUは対象外です。通常描画を利用します。"}
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
        do {
            try backSurface.encode(command:command,size:view.drawableSize,frame:frame,buffer:buffer,draws:groups.gems.enumerated().map{(gems[Int($0.element.material.y)],1,$0.offset)})
        } catch {state.error="宝石の透過描画を準備できませんでした。";return}
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
            if state.rayTracing,raysReady,tier != .low,state.inspectionProgress>0.99,state.kind.rawValue==kind,state.renderedZoom<1.6,let rayPipeline,let rays {
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
                if failed { state.error=message ?? "描画に失敗しました。" }
                else if notify { state.rendererReady=true }
            }
        }
        committed=true;command.commit()
    }
    private func instances() -> (gems:[JewelInstance],atoms:[JewelInstance],bonds:[JewelInstance]) {
        var gems:[JewelInstance]=[],atoms:[JewelInstance]=[],bonds:[JewelInstance]=[]
        let progress=Float(state.inspectionProgress),zoom=Float(state.renderedZoom)
        let reveal=state.kind == .diamond ? min(1,max(0,(zoom-1.05)/1.25)):0
        func instance(_ model:simd_float4x4,_ tint:SIMD3<Float>,_ kind:Float,_ style:Float=0,_ visibility:Float=1,_ clip:Float=0)->JewelInstance {
            .init(model:model,color:SIMD4(tint,1),material:.init(kind,style,visibility,clip))
        }
        let rotation=JewelMatrices.rotate(state.pitch,.init(1,0,0))*JewelMatrices.rotate(state.yaw,.init(0,1,0))
        for jewel in state.visible {
            let p=state.position(jewel),chosen=jewel == state.kind
            let blend:Float=chosen ? progress:0
            let ringSize=Float(0.18*min(1.8,state.save.inventory[jewel.key]?.size ?? 1))
            let size=ringSize+(0.61+min(zoom,1.6)*0.15-ringSize)*blend
            let ringRotation=JewelMatrices.rotate(-0.38,.init(1,0,0))*JewelMatrices.rotate(Float(state.reduceMotion ? 0:sin(state.time*0.25)*0.12)+0.18,.init(0,1,0))
            let orientation=simd_float4x4(simd_slerp(simd_quatf(ringRotation),simd_quatf(rotation),blend))
            let model=JewelMatrices.translate(.init(Float(p.x)*(1-blend),Float(p.y)*(1-blend),0))*orientation*JewelMatrices.scale(.init(repeating:size))
            gems.append(instance(model,jewel.tint,0,Float(jewel.rawValue),chosen ? 1:1-progress,chosen ? reveal*progress:0))
        }
        if reveal>0.001 && progress>0.001 {
            let scale:Float=0.13+zoom*0.077
            let p=state.position(state.kind)
            let root=JewelMatrices.translate(.init(Float(p.x)*(1-progress),Float(p.y)*(1-progress),0))*rotation*JewelMatrices.scale(.init(repeating:scale))
            for model in latticeModels { atoms.append(instance(root*model,.init(0.52,0.80,0.88),1,0,min(1,reveal*2)*progress)) }
            for model in bondModels { bonds.append(instance(root*model,.init(0.38,0.52,0.56),2,0,min(1,reveal*2)*progress)) }
        }
        return (gems,atoms,bonds)
    }
}
