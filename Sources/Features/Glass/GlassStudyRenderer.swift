import MetalKit
import SwiftUI

final class GlassStudyRenderer: NSObject, MTKViewDelegate {
    private let queue: MTLCommandQueue
    private let rayDisplay: MTLRenderPipelineState
    private let rayEngine: GlassRayEngine
    private var fragments:GlassFragmentEngine?
    private var fragmentTime:Float=0
    private var fragmentMetricBucket = -1
    private var fragmentTick:Double?
    private let onBreakFinished:(UUID)->Void
    private let onBreakFailed:(String)->Void
    private let onStatus: (GlassRayStatus) -> Void
    private let inFlight = DispatchSemaphore(value: 1)
    private var generation = 0
    private var sample = 0
    private var convergenceStart = ProcessInfo.processInfo.systemUptime
    private var lastSize = CGSize.zero
    private let sampleTarget = 48
    private let object = GlassObject()
    private(set) var settings = GlassStudySettings()

    init(device: MTLDevice, onStatus: @escaping (GlassRayStatus) -> Void, onBreakFinished: @escaping (UUID)->Void, onBreakFailed: @escaping (String)->Void) throws {
        self.onBreakFinished=onBreakFinished; self.onBreakFailed=onBreakFailed
        self.onStatus = onStatus
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "GlassStudy", code: 1, userInfo: [NSLocalizedDescriptionKey: "描画キューを作成できませんでした。"])
        }
        self.queue = queue
        let library = try device.makeDefaultLibrary(bundle: .main)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "studyVertex")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.fragmentFunction = library.makeFunction(name: "glassTraceDisplay")
        rayDisplay = try device.makeRenderPipelineState(descriptor: descriptor)
        rayEngine = try GlassRayEngine(device:device,library:library)
        super.init()
        NSLog("Glass Ray Tracing: device=%@ supportsRaytracing=%@ backend=%@",device.name,
              device.supportsRaytracing.description,rayEngine.backend)
    }

    func update(_ settings: GlassStudySettings, view: MTKView) {
        guard self.settings != settings else { return }
        if self.settings.fracture?.id != settings.fracture?.id {
            fragments=nil; fragmentTime=0; fragmentTick=nil; fragmentMetricBucket = -1
        }
        if self.settings.animationPaused != settings.animationPaused { fragmentTick=nil }
        self.settings = settings
        restart(view)
    }

    private func restart(_ view: MTKView) {
        generation += 1; sample = 0
        convergenceStart=ProcessInfo.processInfo.systemUptime
        let animate=settings.fracture != nil && !settings.animationPaused
        view.enableSetNeedsDisplay = !settings.rayTracing && !animate
        view.isPaused = settings.animationPaused || (!settings.rayTracing && !animate)
        view.setNeedsDisplay()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        restart(view)
    }

    func draw(in view: MTKView) {
        if settings.fracture != nil { drawFragments(in:view); return }
        drawRayTracing(in:view)
    }

    private func drawFragments(in view:MTKView) {
        guard !settings.animationPaused,let snapshot=settings.fracture,
              inFlight.wait(timeout:.now()) == .success else { return }
        guard let pass=view.currentRenderPassDescriptor,let drawable=view.currentDrawable,
              let command=queue.makeCommandBuffer() else { inFlight.signal(); return }
        let epoch=generation,encodeStart=ProcessInfo.processInfo.systemUptime
        do {
            if fragments==nil {
                fragments=try GlassFragmentEngine(snapshot:snapshot,device:queue.device,library:queue.device.makeDefaultLibrary(bundle:.main))
            }
            guard let fragments else { throw GlassRayEngine.failure("破片を準備できません。") }
            let now=ProcessInfo.processInfo.systemUptime
            if let tick=fragmentTick { fragmentTime += Float(min(0.05,max(0,now-tick))) * max(0.1,min(1,UserDefaults.standard.string(forKey:"studyAnimationRate").flatMap(Float.init) ?? 1)) }
            fragmentTick=now
            let time=fragmentTime
            let scale=min(1,Double(settings.renderPixelLimit)/max(1,max(view.drawableSize.width,view.drawableSize.height)))
            let size=SIMD2(max(1,Int(view.drawableSize.width*scale)),max(1,Int(view.drawableSize.height*scale)))
            try rayEngine.material.prepare(command:command,impacts:settings.impacts)
            try fragments.encode(command:command,size:size,settings:settings,time:time,material:rayEngine.material.texture)
            guard let e=command.makeRenderCommandEncoder(descriptor:pass) else { throw GlassRayEngine.failure("破片を表示できません。") }
            e.setRenderPipelineState(rayDisplay); e.setFragmentTexture(fragments.texture,index:0)
            e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3); e.endEncoding()
            command.present(drawable)
            let cpuMS=(ProcessInfo.processInfo.systemUptime-encodeStart)*1000
            command.addCompletedHandler { [weak self,weak view] buffer in
                guard let self else { return }; self.inFlight.signal()
                DispatchQueue.main.async {
                    guard self.settings.fracture?.id==snapshot.id,self.generation==epoch else { return }
                    if let error=buffer.error { view?.isPaused=true; self.onBreakFailed(error.localizedDescription); return }
                    if time==0 { self.fragmentTick=ProcessInfo.processInfo.systemUptime }
                    let bucket=Int(time*4)
                    if bucket != self.fragmentMetricBucket {
                        self.fragmentMetricBucket=bucket
                        CrackMetrics.record(["event":"fragmentRender","backend":fragments.backend,"time":time,"gpuMS":max(0,buffer.gpuEndTime-buffer.gpuStartTime)*1000,"fragments":snapshot.geometry.fragments.count])
                    }
                    self.onStatus(.init(gpuMS:max(0,buffer.gpuEndTime-buffer.gpuStartTime)*1000,cpuMS:cpuMS,backend:fragments.backend,samples:1,target:1))
                    if time>=GlassBreakMotion.duration {
                        view?.isPaused=true
                        CrackMetrics.record(["event":"shatterFinished","fragments":snapshot.geometry.fragments.count])
                        self.onBreakFinished(snapshot.id)
                    }
                }
            }
            command.commit()
        } catch {
            inFlight.signal(); view.isPaused=true; onBreakFailed(error.localizedDescription)
        }
    }

    private func drawRayTracing(in view: MTKView) {
        guard view.drawableSize.width>0, view.drawableSize.height>0 else { return }
        if lastSize != view.drawableSize { lastSize=view.drawableSize; sample=0; generation += 1 }
        let target=settings.rayTracing ? sampleTarget:1
        guard sample < target, inFlight.wait(timeout:.now()) == .success else { return }
        guard let pass=view.currentRenderPassDescriptor,let drawable=view.currentDrawable,
              let command=queue.makeCommandBuffer() else { inFlight.signal(); return }
        let epoch=generation, currentSample=sample
        let started=convergenceStart, groupCount=settings.impacts.count, edgeCount=settings.networkEdgeCount
        do {
            // Bound simulator work by pixel count; progressive jitter smooths the final image.
            let size=GlassFraming.rayTextureSize(width:view.drawableSize.width,height:view.drawableSize.height)
            try rayEngine.prepare(command:command,size:size,amplitude:settings.amplitude)
            var opticalSettings=settings
            if !settings.rayTracing { opticalSettings.internalReflections=false; opticalSettings.dispersion=false }
            try rayEngine.encode(command:command,settings:opticalSettings,sample:sample,target:target)
            guard let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { throw GlassRayEngine.failure("表示を開始できません。") }
            encoder.setRenderPipelineState(rayDisplay)
            encoder.setFragmentTexture(rayEngine.texture,index:0)
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            encoder.endEncoding()
            sample += 1
            command.present(drawable)
            command.addCompletedHandler { [weak self, weak view] buffer in
                guard let self else { return }
                self.inFlight.signal()
                let error=buffer.error?.localizedDescription
                DispatchQueue.main.async {
                    guard self.generation==epoch else { return }
                    if currentSample==0 || currentSample+1==target {
                        CrackMetrics.record(["event":"render","groups":groupCount,"edges":edgeCount,
                                             "sample":currentSample+1,"elapsedMS":(ProcessInfo.processInfo.systemUptime-started)*1000,
                                             "gpuMS":max(0,buffer.gpuEndTime-buffer.gpuStartTime)*1000])
                    }
                    self.onStatus(GlassRayStatus(backend:self.rayEngine.backend,samples:currentSample+1,target:target,error:error))
                    if error != nil || currentSample+1>=target { view?.isPaused=true }
                }
            }
            command.commit()
        } catch {
            inFlight.signal(); view.isPaused=true
            onStatus(GlassRayStatus(backend:rayEngine.backend,error:error.localizedDescription))
        }
    }
}

struct GlassStudyMetalView: UIViewRepresentable {
    var settings: GlassStudySettings
    @Binding var error: String?
    @Binding var status: GlassRayStatus
    var onBreakFinished:(UUID)->Void
    var onBreakFailed:(String)->Void

    final class Coordinator {
        var renderer: GlassStudyRenderer?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.92, green: 0.93, blue: 0.89, alpha: 1)
        // A static object only redraws when a control, gesture or viewport changes.
        view.isPaused = !settings.rayTracing
        view.enableSetNeedsDisplay = !settings.rayTracing
        view.preferredFramesPerSecond = 60
        view.isOpaque = true
        view.accessibilityLabel = "210 × 360 × 12ミリメートルのガラス"
        do {
            guard let device = view.device else {
                throw NSError(domain: "GlassStudy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metalを利用できません。"])
            }
            let renderer = try GlassStudyRenderer(device: device, onStatus: { status in
                self.status=status
                if let message=status.error { self.error=message }
            }, onBreakFinished:onBreakFinished,onBreakFailed:onBreakFailed)
            renderer.update(settings,view:view)
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { self.error = message }
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.update(settings,view:view)
        if !settings.rayTracing { view.setNeedsDisplay() }
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.renderer = nil
    }
}
