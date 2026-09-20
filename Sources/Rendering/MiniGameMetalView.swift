import SwiftUI
import MetalKit
import simd

struct MiniGameMetalView:UIViewRepresentable {
    @ObservedObject var session:JewelMiniSession
    func makeCoordinator()->MiniGameRenderer? {
        do { return try MiniGameRenderer(session) } catch { DispatchQueue.main.async{session.renderError=error.localizedDescription};return nil }
    }
    func makeUIView(context:Context)->MiniTouchView {
        let v=MiniTouchView(frame:.zero,device:context.coordinator?.device);v.session=session
        v.delegate=context.coordinator;v.colorPixelFormat = .bgra8Unorm_srgb;v.depthStencilPixelFormat = .depth32Float
        v.clearColor=MTLClearColorMake(0,0,0,0);v.isOpaque=false;v.backgroundColor = .clear
        v.preferredFramesPerSecond=60;v.accessibilityIdentifier="mini.canvas";return v
    }
    func updateUIView(_ v:MiniTouchView,context:Context) { v.isPaused=session.engine.phase == .paused;v.refresh() }
    static func dismantleUIView(_ v:MiniTouchView,coordinator:MiniGameRenderer?) { v.isPaused=true;v.delegate=nil }
}
final class MiniCell:UIAccessibilityElement {
    weak var session:JewelMiniSession?
    var index=0
    override func accessibilityActivate()->Bool { session?.cell(index);return true }
}
final class MiniTouchView:MTKView {
    weak var session:JewelMiniSession?
    private var primary:UITouch?
    private var items:[MiniCell]=[]
    private var ids:[Int]=[]
    private var marker:UIAccessibilityElement?
    private let picking=GlassRayScene(amplitude:0)
    required init(coder:NSCoder) { fatalError() }
    override init(frame:CGRect,device:MTLDevice?) { super.init(frame:frame,device:device);isMultipleTouchEnabled=true }
    override func layoutSubviews() { super.layoutSubviews();session?.viewport=bounds.size;refresh() }
    private func point(_ t:UITouch)->SIMD2<Double>? {
        guard let s=session else { return nil };let p=t.location(in:self)
        if s.kind.game == .kurukuru { return SIMD2(Double(p.x/bounds.width),Double(p.y/bounds.height)) }
        return GlassCrackPicking.point(at:.init(Float(p.x),Float(p.y)),viewport:.init(Float(bounds.width),Float(bounds.height)),settings:s.glass,scene:picking).map { SIMD2($0.x/210,1-$0.y/360) }
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard primary==nil,let t=touches.first,let s=session else { return };primary=t
        if s.kind.game == .kurukuru {
            guard let p=point(t),p.x>=0.05,p.x<0.95,p.y>=0.05,p.y<0.95 else { return }
            let n=s.engine.board.size,c=Int((p.x-0.05)/0.9*Double(n)),r=Int((p.y-0.05)/0.9*Double(n))
            s.cell(r*n+c,at:t.timestamp)
        } else { s.touch(point(t),down:true,at:t.timestamp) }
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let t=primary,touches.contains(t),let s=session,s.kind.game == .grassTrace else { return }
        for sample in event?.coalescedTouches(for:t) ?? [t] { s.touch(point(sample) ?? .init(-10,-10),down:true,at:sample.timestamp) }
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let t=primary,touches.contains(t) else { return };session?.touch(nil,down:false,at:t.timestamp);primary=nil
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) { primary=nil;session?.pause() }
    func refresh() {
        guard let s=session else { return }
        if s.kind.game != .kurukuru {
            guard [.ready,.playing].contains(s.engine.phase),s.inputReady else { accessibilityElements=[];return }
            let e=marker ?? UIAccessibilityElement(accessibilityContainer:self);marker=e
            e.accessibilityIdentifier="mini.target";e.accessibilityLabel=s.kind.game == .grassTrace ? "緑の点":"赤い点"
            e.accessibilityTraits = .button
            let rotation=GlassFraming.rotation(yaw:s.glass.yaw,pitch:s.glass.pitch),aspect=Float(bounds.width/max(1,bounds.height))
            let half=GlassFraming.halfHeight(object:GlassObject(),aspect:aspect,rotation:rotation,amplitude:0)
            let p=rotation*SIMD3<Float>(Float((s.engine.target.x-0.5)*210),Float((0.5-s.engine.target.y)*360),6)
            e.accessibilityFrameInContainerSpace=CGRect(x:Double((p.x/(half*aspect)+1)/2)*bounds.width-22,y:Double((1-p.y/half)/2)*bounds.height-22,width:44,height:44)
            accessibilityElements=[e];return
        }
        let current=s.engine.phase == .playing ? s.engine.board.cells.indices.filter{s.engine.board.cells[$0] != nil}:[]
        if current != ids {
            ids=current;items=current.map { i in let e=MiniCell(accessibilityContainer:self);e.index=i;e.session=s;e.accessibilityIdentifier="mini.cell.\(i)";e.accessibilityTraits = .button;return e };accessibilityElements=items
        }
        let n=s.engine.board.size,side=bounds.width*0.9/Double(n)
        for e in items {
            e.accessibilityLabel="\(s.kind.name) \(e.index+1)";e.accessibilityValue=s.engine.board.cells[e.index]?.spin.title
            e.accessibilityFrameInContainerSpace=CGRect(x:bounds.width*0.05+Double(e.index%n)*side,y:bounds.height*0.05+Double(e.index/n)*side,width:side,height:side)
        }
    }
}
@MainActor final class MiniGameRenderer:NSObject,MTKViewDelegate {
    let device:MTLDevice
    let queue:MTLCommandQueue
    let pipeline:MTLRenderPipelineState
    let backSurface:GemBackSurface
    let markerPipeline:MTLRenderPipelineState
    let markerDepth:MTLDepthStencilState
    let quad:JewelMesh
    let bg:MTLRenderPipelineState
    let depth:MTLDepthStencilState
    let gem:JewelMesh
    let sphere:JewelMesh
    let session:JewelMiniSession
    let buffers:[MTLBuffer]
    let semaphore=DispatchSemaphore(value:3)
    var slot=0
    init(_ s:JewelMiniSession)throws {
        session=s
        guard let d=MTLCreateSystemDefaultDevice(),let q=d.makeCommandQueue(),let lib=d.makeDefaultLibrary() else { throw SaveFailure.unreadable }
        device=d;queue=q
        backSurface=try GemBackSurface(device:d,library:lib)
        func make(_ vertex:String,_ fragment:String,blend:Bool=false)throws->MTLRenderPipelineState {
            let p=MTLRenderPipelineDescriptor();p.vertexFunction=lib.makeFunction(name:vertex);p.fragmentFunction=lib.makeFunction(name:fragment)
            p.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb;p.depthAttachmentPixelFormat = .depth32Float
            if blend {
                let a=p.colorAttachments[0]!
                a.isBlendingEnabled=true;a.sourceRGBBlendFactor = .one;a.destinationRGBBlendFactor = .oneMinusSourceAlpha
                a.sourceAlphaBlendFactor = .one;a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try d.makeRenderPipelineState(descriptor:p)
        }
        markerPipeline=try make("jewelVertex","soulTargetFragment",blend:true)
        let noDepth=MTLDepthStencilDescriptor();noDepth.depthCompareFunction = .always;noDepth.isDepthWriteEnabled=false;markerDepth=d.makeDepthStencilState(descriptor:noDepth)!
        quad=try JewelGeometry.mesh([SIMD2<Float>(-1,-1),.init(1,-1),.init(1,1),.init(-1,-1),.init(1,1),.init(-1,1)].map{.init(position:.init($0.x,$0.y,0,1),normal:.init(0,0,1,0))},device:d)
        pipeline=try make("jewelVertex","jewelFragment");bg=try make("jewelBackgroundVertex","miniBoardBackground")
        let dd=MTLDepthStencilDescriptor();dd.depthCompareFunction = .less;dd.isDepthWriteEnabled=true;depth=d.makeDepthStencilState(descriptor:dd)!
        gem=try JewelGeometry.mesh(JewelGeometry.gem(s.kind),device:d);sphere=try JewelGeometry.mesh(JewelGeometry.sphere(),device:d)
        buffers=(0..<3).map{_ in d.makeBuffer(length:8192*MemoryLayout<JewelInstance>.stride,options:.storageModeShared)!}
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    func draw(in v:MTKView) {
        let started=CACurrentMediaTime()
        session.tick()
        let fps=session.tier == .low ? 30:60
        if v.preferredFramesPerSecond != fps {v.preferredFramesPerSecond=fps}
        (v as? MiniTouchView)?.refresh()
        guard let pass=v.currentRenderPassDescriptor,let drawable=v.currentDrawable,semaphore.wait(timeout:.now()) == .success else { return }
        guard let c=queue.makeCommandBuffer() else { semaphore.signal();return }
        let s=session,n=s.engine.board.size,time=s.engine.activeTime
        var gems:[JewelInstance]=[],dots:[JewelInstance]=[]
        var marker:JewelInstance?
        func item(_ p:SIMD3<Float>,_ scale:SIMD3<Float>,_ color:SIMD3<Float>,_ kind:Float,_ rotation:Float=0,_ visibility:Float=1)->JewelInstance {
            .init(model:JewelMatrices.translate(p)*JewelMatrices.rotate(rotation,.init(0,0,1))*JewelMatrices.rotate(-0.3,.init(1,0,0))*JewelMatrices.scale(scale),color:.init(color,1),material:.init(kind,Float(s.kind.rawValue),visibility,0))
        }
        if s.kind.game == .kurukuru {
            let cell=Float(1.8)/Float(n)
            for i in s.engine.board.cells.indices {
                guard let piece=s.engine.board.cells[i] else { continue }
                let center=SIMD2<Float>(-0.9+(Float(i%n)+0.5)*cell,0.9-(Float(i/n)+0.5)*cell)
                let a = -Float(time*Double.pi*Double(piece.spin.rawValue))
                for opposite:Float in [0,.pi] {
                    let angle=a+opposite,p=center+SIMD2(cos(angle),sin(angle))*cell*0.22
                    let tint=s.engine.selected==i ? simd_min(s.kind.tint+SIMD3(repeating:0.25),SIMD3(repeating:1)):s.kind.tint
                    gems.append(item(.init(p.x,p.y,0),.init(repeating:cell*0.16),tint,0,angle))
                }
            }
            for (i,birth) in s.engine.fadeEvents.suffix(16) where time-birth<0.6 {
                let t=Float(time-birth),p=SIMD3<Float>(-0.9+(Float(i%n)+0.5)*cell,0.9-(Float(i/n)+0.5)*cell+t*0.2,0.3)
                dots.append(item(p,.init(repeating:cell*0.12),.init(0.95,0.8,0.45),1,0,max(0,1-t/0.6)))
            }
        } else if [.ready,.playing].contains(s.engine.phase) {
            let rotation=GlassFraming.rotation(yaw:s.glass.yaw,pitch:s.glass.pitch),aspect=Float(v.bounds.width/max(1,v.bounds.height))
            let half=GlassFraming.halfHeight(object:GlassObject(),aspect:aspect,rotation:rotation,amplitude:0)
            let target=s.engine.target
            let p=rotation*SIMD3<Float>(Float((target.x-0.5)*210),Float((0.5-target.y)*360),6)
            let radius=max(Float(s.requestedTolerance)*210,Float(22/max(1,v.bounds.width))*half*2*aspect)
            let x=p.x/(half*aspect),y=p.y/half
            let tint:SIMD3<Float>=s.kind.game == .grassTrace ? .init(0.10,1,0.42):.init(1,0.12,0.14)
            let remaining=Float(s.engine.deadline.map{max(0,min(1,($0-s.engine.activeTime)/1.5))} ?? 1)
            marker = .init(model:JewelMatrices.translate(.init(x,y,0.9))*JewelMatrices.scale(.init(radius/(half*aspect)*1.6,radius/half*1.6,1)),color:.init(tint,1),material:.init(3,0,1,remaining))
            // Use the same radius in the logical glass-plane metric.
            s.engine.tolerance=Double(radius/210)
        }
        if s.engine.phase == .won,s.canCelebrate {
            let t=Float(s.celebration),scale:Float=(0.12+0.36*t)*Float(sqrt(s.rewardSize))
            gems.append(item(.init(0,0,1.0),.init(repeating:scale),s.kind.tint,0,Float(time)*0.5))
            for i in 0..<s.tier.particles {
                let a=Float(i)*2.39996,r=0.15+t*0.72,p=SIMD3<Float>(cos(a)*r,sin(a)*r,0.7)
                dots.append(item(p,.init(repeating:0.01+0.005*sin(a+Float(time)*3)),.init(1,0.8,0.43),1,0,max(0.1,1-t*0.6)))
            }
        }
        var frame=JewelFrame(values:.init(Float(time),Float(n),0,0),dimensions:.init(Float(v.drawableSize.width),Float(v.drawableSize.height),0,0))
        let all=gems+dots+(marker.map{[$0]} ?? []),b=buffers[slot];slot=(slot+1)%3
        all.withUnsafeBytes { if let p=$0.baseAddress { memcpy(b.contents(),p,$0.count) } }
        frame.scene.x=s.kind.game == .kurukuru ? 1:2
        do {try backSurface.encode(command:c,size:v.drawableSize,frame:frame,buffer:b,draws:[(gem,gems.count,0)])}
        catch {semaphore.signal();s.renderError="宝石の透過描画を準備できませんでした。";return}
        guard let e=c.makeRenderCommandEncoder(descriptor:pass) else {semaphore.signal();return}
        e.setFragmentTexture(backSurface.texture,index:0)
        e.setDepthStencilState(depth);e.setVertexBytes(&frame,length:MemoryLayout<JewelFrame>.stride,index:2);e.setFragmentBytes(&frame,length:MemoryLayout<JewelFrame>.stride,index:0)
        if s.kind.game == .kurukuru { e.setRenderPipelineState(bg);e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3) }
        e.setRenderPipelineState(pipeline);e.setVertexBuffer(b,offset:0,index:1)
        if !gems.isEmpty { e.setVertexBuffer(gem.buffer,offset:0,index:0);e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:gem.count,instanceCount:gems.count) }
        if !dots.isEmpty { e.setVertexBuffer(sphere.buffer,offset:0,index:0);e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:sphere.count,instanceCount:dots.count,baseInstance:gems.count) }
        if marker != nil {
            e.setRenderPipelineState(markerPipeline);e.setDepthStencilState(markerDepth);e.setVertexBuffer(quad.buffer,offset:0,index:0)
            e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:quad.count,instanceCount:1,baseInstance:gems.count+dots.count)
        }
        e.endEncoding();let id=s.engine.targetID,semaphore=self.semaphore,epoch=s.presentationEpoch
        let cpuMS=(CACurrentMediaTime()-started)*1000
        #if !targetEnvironment(simulator)
        drawable.addPresentedHandler { d in
            let stamp=d.presentedTime
            if stamp>0 { DispatchQueue.main.async { s.presented(id,at:stamp,epoch:epoch) } }
        }
        #endif
        c.addCompletedHandler { command in semaphore.signal();DispatchQueue.main.async { if let error=command.error { s.renderError=error.localizedDescription } else {
            if s.kind.game == .kurukuru {s.observeFrame(cpuMS:cpuMS,gpuMS:max(0,command.gpuEndTime-command.gpuStartTime)*1000)}
            s.rendererReady=true
            #if targetEnvironment(simulator)
            // The simulator SDK lacks presentation feedback. Wait for GPU completion plus
            // a display interval, never start the deadline when encoding the target.
            DispatchQueue.main.asyncAfter(deadline:.now()+1.0/60) { s.presented(id,at:CACurrentMediaTime(),epoch:epoch) }
            #endif
        } } }
        c.present(drawable);c.commit()
    }
}
