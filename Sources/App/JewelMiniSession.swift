import SwiftUI
import QuartzCore
import simd

@MainActor final class JewelMiniSession:ObservableObject,Identifiable {
    let id=UUID()
    let kind:JewelKind
    let preview:Bool
    let requestedTolerance:Double
    var qualityPolicy=RenderQualityPolicy()
    private(set) var stopped=false
    private(set) var presentationEpoch=0
    private var cancelWorker:(()->Void)?
    var tier:QualityTier {qualityPolicy.effective(thermal:ProcessInfo.processInfo.thermalState,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)}
    func result(deviceID:String)->GameResultEvent {
        .init(id:id,game:kind.game,gemID:kind.key,rulesVersion:kind.game == .kurukuru ? "tamor.4":"tamor.3",boardSize:kind.game == .kurukuru ? engine.board.size:0,targetCount:kind.game == .grassBreak ? engine.requiredHits:0,traceTolerance:kind.game == .grassTrace ? engine.tolerance:0,seconds:engine.elapsed,mistakes:engine.mistakes,cracks:engine.cracks.count,hits:engine.hits,won:engine.phase == .won,finishedAt:Date(),deviceID:deviceID)
    }
    func observeFrame(cpuMS:Double,gpuMS:Double) {
        qualityPolicy.observe(cpuMS:cpuMS,gpuMS:gpuMS)
        if glass.renderPixelLimit != tier.glassPixels {glass.renderPixelLimit=tier.glassPixels}
    }
    var engine:MiniGameEngine
    @Published var claimed=false
    @Published var shatterFinished=false
    var canCelebrate:Bool { kind.game != .grassBreak || shatterFinished }
    @Published var renderError:String?
    @Published var glass=GlassStudySettings()
    @Published var glassStatus=GlassRayStatus()
    var rendererReady=false
    var inputReady:Bool { rendererReady && renderError==nil && (kind.game == .kurukuru || glassStatus.samples>0) }
    var viewport=CGSize(width:360,height:500)
    var now:()->Double
    private var publishedBucket = -1
    private var builtCracks=0
    private var generating=false
    private var broken=false
    private var geometryTask:Task<Void,Never>?
    private var fractureRequested=false
    private var finishedAt:Double?
    var rewardSize:Double { kind.game == .kurukuru ? 1+Double(engine.board.size-4)*0.1:1 }
    var celebration:Double { guard let finishedAt else { return 0 };return min(1,max(0,(now()-finishedAt)/1.2)) }
    var readyForResult:Bool { engine.phase == .won || engine.phase == .lost }
    init(kind:JewelKind,size:Int,preview:Bool,tolerance:Double,quality:QualityPreference = .automatic,now:@escaping()->Double={CACurrentMediaTime()},seed:UInt64=UInt64.random(in:1...UInt64.max)) {
        self.kind=kind;self.preview=preview;self.now=now;requestedTolerance=tolerance
        qualityPolicy.preference=quality
        engine=MiniGameEngine(type:kind.game,size:size,seed:seed,tolerance:tolerance,now:now())
        glass.renderPixelLimit=tier.glassPixels
        glass.amplitude=0;glass.yaw = -0.08;glass.pitch=0.04;glass.rayTracing=false;glass.pattern=0
    }
    func notify() { objectWillChange.send() }
    func tick() {
        guard !stopped else {return}
        if glass.renderPixelLimit != tier.glassPixels {glass.renderPixelLimit=tier.glassPixels}
        let oldPhase=engine.phase,oldCracks=engine.cracks.count
        engine.advance(to:now())
        if inputReady,engine.phase == .ready,kind.game != .grassTrace { engine.autoStart(at:now()) }
        let paused=engine.phase == .paused
        if glass.animationPaused != paused {glass.animationPaused=paused}
        if oldPhase != engine.phase || oldCracks != engine.cracks.count { syncEffects();notify() }
        let bucket=Int(engine.activeTime*10)
        if bucket != publishedBucket { publishedBucket=bucket;notify() }
    }
    func begin() { guard inputReady else { return };engine.begin(at:now());notify() }
    func cell(_ i:Int,at time:Double?=nil) { engine.tapCell(i,at:time ?? now());syncEffects();notify() }
    func touch(_ p:SIMD2<Double>?,down:Bool,at time:Double) {
        guard inputReady else { return }
        engine.touch(p,down:down,at:time);syncEffects();notify()
    }
    func presented(_ target:Int,at time:Double,epoch:Int?=nil) {
        guard !stopped,epoch==nil || epoch==presentationEpoch else {return}
        engine.presented(target,at:time)
    }
    func pause() {
        presentationEpoch+=1
        engine.pause(at:now())
        // A late cancelled touch must not freeze the animation of an already finished game.
        glass.animationPaused=engine.phase == .paused;notify()
    }
    func resume() { presentationEpoch+=1;engine.resume(at:now());glass.animationPaused=false;notify() }
    func stop() { stopped=true;presentationEpoch+=1;geometryTask?.cancel();cancelWorker?();cancelWorker=nil;glass.animationPaused=true }
    func finishShatter(error:String?=nil) {
        glass.visible=false;glass.fracture=nil;shatterFinished=true
        if let error {renderError=error}
        if engine.phase == .won {finishedAt=now()}
    }
    func syncEffects() {
        guard !stopped else {return}
        if readyForResult,canCelebrate,finishedAt==nil { finishedAt=now() }
        if kind.game == .kurukuru { return }
        guard !generating else { return }
        if builtCracks<engine.cracks.count {
            let pending=Array(engine.cracks.dropFirst(builtCracks));generating=true
            geometryTask=Task {
                guard !Task.isCancelled,!stopped else {return}
                let worker=Task.detached(priority:.userInitiated) {
                    pending.compactMap { c -> CrackImpact? in guard !Task.isCancelled else {return nil};return CrackNetworkGenerator.generate(at:SIMD2(c.point.x*210,(1-c.point.y)*360),seed:c.seed,parameters:CrackParameters(density:.sparse)) }
                }
                cancelWorker={worker.cancel()}
                let impacts=await worker.value
                guard !Task.isCancelled,!stopped else { return }
                cancelWorker=nil
                glass.impacts+=impacts;builtCracks+=pending.count;generating=false;syncEffects()
            }
        } else if readyForResult,!broken,!fractureRequested,(kind.game == .grassBreak && engine.phase == .won || kind.game == .grassTrace && engine.phase == .lost) {
            fractureRequested=true;let impacts=glass.impacts,quality=tier
            geometryTask=Task {
                guard !Task.isCancelled,!stopped else {return}
                let worker=Task.detached(priority:.userInitiated) { () -> GlassBreakGeometry.Result? in
                    guard !Task.isCancelled else {return nil}
                    if quality == .low {return GlassBreakGeometry.coarse()}
                    do {return try GlassBreakGeometry.build(impacts:impacts,cracks:[],amplitude:0,budgetSeconds:0.30)}
                    catch {return Task.isCancelled ? nil:GlassBreakGeometry.coarse()}
                }
                cancelWorker={worker.cancel()}
                let result=await worker.value
                guard !Task.isCancelled,!stopped else { return }
                cancelWorker=nil
                if let result { glass.fracture=GlassBreakSnapshot(geometry:result,impact:SIMD2(Float(engine.target.x*210),Float((1-engine.target.y)*360)),seed:engine.cracks.last?.seed ?? 1) }
                else { finishShatter(error:"破片を生成できませんでした。獲得結果は保存されます。");broken=true }
            }
        }
    }
}
