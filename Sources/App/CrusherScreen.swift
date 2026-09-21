import SwiftUI
import QuartzCore

@MainActor final class CrusherSession:ObservableObject,Identifiable {
    let id=UUID()
    @Published var engine:CrusherEngine
    @Published var glass=GlassStudySettings()
    @Published var status=GlassRayStatus()
    @Published var error:String?
    @Published var lastReward:String?
    private let checkpoint:URL
    private var work:Task<Void,Never>?
    private var epoch=0
    var policy=RenderQualityPolicy()
    var tier:QualityTier {policy.effective(thermal:ProcessInfo.processInfo.thermalState,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)}
    static func pendingDepth(files:JewelSaveFiles)->Int? {
        let url=files.directory.appendingPathComponent("crusher-timed-checkpoint.json")
        guard let data=try? Data(contentsOf:url),let saved=try? JSONDecoder().decode(CrusherEngine.self,from:data),
              saved.valid else {return nil}
        return saved.depth
    }
    init(depth:Int,files:JewelSaveFiles,quality:QualityPreference) {
        checkpoint=files.directory.appendingPathComponent("crusher-timed-checkpoint.json")
        let now=CACurrentMediaTime()
        if let bytes=try? Data(contentsOf:checkpoint),var saved=try? JSONDecoder().decode(CrusherEngine.self,from:bytes),saved.depth==depth,
           saved.valid {
            saved.lastStamp=now
            if saved.phase == .shattering {saved.nextPlate(at:now)}
            saved.pause(at:now);engine=saved
        } else {engine=CrusherEngine(depth:depth,now:now)}
        policy.preference=quality
        glass.amplitude=0;glass.yaw = -0.08;glass.pitch=0.04;glass.pattern=0;glass.rayTracing=false
        glass.renderPixelLimit=tier.glassPixels
    }
    var outcome:DepthOutcome {
        .init(id:engine.resultID,gemID:"obsidian",depth:engine.depth,grade:engine.grade,seconds:engine.totalElapsed,date:engine.resultDate,rulesVersion:5,plates:engine.plates,weakHits:engine.weakHits,score:engine.score)
    }
    var failureOutcome:DepthOutcome {
        .init(id:engine.resultID,gemID:"obsidian",depth:engine.depth,grade:.failed,seconds:engine.totalElapsed,date:engine.resultDate,rulesVersion:5,plates:engine.plates,weakHits:engine.weakHits,score:engine.score)
    }
    func saveCheckpoint() {
        do {try FileManager.default.createDirectory(at:checkpoint.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(engine).write(to:checkpoint,options:.atomic)}
        catch {self.error=L("中断記録を保存できません：")+error.localizedDescription;engine.pause(at:CACurrentMediaTime())}
    }
    func discardCheckpoint() {work?.cancel();try? FileManager.default.removeItem(at:checkpoint)}
    func retryCheckpoint() {error=nil;saveCheckpoint()}
    func tick() {
        var next=engine;next.advance(CACurrentMediaTime(),renderReady:status.samples>0)
        if next.phase != engine.phase {engine=next;saveCheckpoint()} else {engine=next}
        if engine.phase == .shattering,CACurrentMediaTime()-engine.phaseStamp>0.4 {finishShatter()}
        let limit=tier.glassPixels;if glass.renderPixelLimit != limit {glass.renderPixelLimit=limit}
    }
    func touch(_ point:SIMD2<Double>?,down:Bool,at time:Double) {
        guard status.samples>0,error==nil else {return}
        let old=engine.phase
        if engine.touch(point,down:down,at:time) {
            saveCheckpoint();let impact=engine.impact,index=engine.hits,generation=epoch,tier=self.tier
            work?.cancel()
            work=Task {
                let data=await Task.detached(priority:.userInitiated) { () -> (CrackImpact?,GlassBreakGeometry.Result?) in
                    let crack=CrackNetworkGenerator.generate(at:.init(impact.x*210,(1-impact.y)*360),seed:UInt64(index*8191+generation+1),parameters:CrackParameters(density:.sparse))
                    if index<3 {return (crack,nil)}
                    let result=tier == .low ? GlassBreakGeometry.coarse() : ((try? GlassBreakGeometry.build(impacts:[crack].compactMap{$0},cracks:[],amplitude:0,budgetSeconds:0.15)) ?? GlassBreakGeometry.coarse())
                    return (crack,result)
                }.value
                guard !Task.isCancelled,epoch==generation else {return}
                if let crack=data.0 {glass.impacts.append(crack)}
                if let geometry=data.1 {glass.fracture=GlassBreakSnapshot(geometry:geometry,impact:.init(Float(impact.x*210),Float((1-impact.y)*360)),seed:UInt64(generation+1))}
            }
        } else if engine.phase != old {saveCheckpoint()}
    }
    func finishShatter() {
        guard engine.phase == .shattering else {return}
        engine.nextPlate(at:CACurrentMediaTime());resetGlass();saveCheckpoint()
    }
    func nextBatch(reward:String?) {
        lastReward=reward;engine.nextBatch(at:CACurrentMediaTime());resetGlass();saveCheckpoint()
    }
    private func resetGlass() {
        epoch+=1;work?.cancel();glass.fracture=nil;glass.impacts=[];glass.visible=true;status.samples=0
        // A small pose change invalidates the previous plate even when both have no impacts.
        glass.yaw = epoch % 2 == 0 ? -0.08 : -0.0801
    }
    func pause() {engine.pause(at:CACurrentMediaTime());glass.animationPaused=true;saveCheckpoint()}
    func resume() {engine.resume(at:CACurrentMediaTime());glass.animationPaused=false;saveCheckpoint()}
}

struct CrusherInput:UIViewRepresentable {
    @ObservedObject var run:CrusherSession
    func makeUIView(context:Context)->CrusherTouchView {let v=CrusherTouchView();v.run=run;v.isMultipleTouchEnabled=true;v.isAccessibilityElement=true;v.accessibilityTraits = .button;v.accessibilityLabel=L("ガラス");v.accessibilityIdentifier="crusher.glass";return v}
    func updateUIView(_ view:CrusherTouchView,context:Context) {view.run=run;view.accessibilityValue="\(run.engine.plates):\(run.engine.hits):\(run.engine.phase.rawValue)"}
}
final class CrusherTouchView:UIView {
    weak var run:CrusherSession?
    private var finger:UITouch?
    private let scene=GlassRayScene(amplitude:0)
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard finger==nil,let touch=touches.first,let run else {return};finger=touch
        let p=touch.location(in:self)
        let point=GlassCrackPicking.point(at:.init(Float(p.x),Float(p.y)),viewport:.init(Float(bounds.width),Float(bounds.height)),settings:run.glass,scene:scene).map{SIMD2($0.x/210,1-$0.y/360)}
        run.touch(point,down:true,at:touch.timestamp)
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard let finger,touches.contains(finger) else {return};run?.touch(nil,down:false,at:finger.timestamp);self.finger=nil
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) {finger=nil;run?.pause()}
}

struct CrusherScreen:View {
    @ObservedObject var state:JewelSceneState
    @ObservedObject var run:CrusherSession
    @Environment(\.scenePhase) var phase
    @State private var exit=false
    private let timer=Timer.publish(every:1.0/60,on:.main,in:.common).autoconnect()
    var body:some View {
        GeometryReader {geo in
        VStack(spacing:12) {
            HStack {
                Button {if run.engine.terminal {Task{await state.finishCrusher()}} else {run.pause();exit=true}} label:{Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityIdentifier("crusher.close")
                Spacer();Text("Crusher Room").font(.title2.weight(.light));Spacer()
                Button {run.pause()} label:{Image(systemName:"pause").frame(width:44,height:44)}.disabled(run.engine.terminal)
            }
            HStack {Text("深度 \(run.engine.depth)");Spacer();Text("\(run.engine.plates) 枚 / \(run.engine.score) pt");Spacer();Text("弱点 \(run.engine.weakHits) HIT")}.font(.caption.monospaced()).accessibilityIdentifier("crusher.stats")
            ZStack {
                GlassStudyMetalView(settings:run.glass,error:$run.error,status:$run.status,onBreakFinished:{_ in},onBreakFailed:{_ in})
                CrusherWeakPoint(run:run).allowsHitTesting(false)
                CrusherInput(run:run)
                if run.engine.phase == .paused || run.engine.phase == .countdown {
                    jewelBackground.opacity(0.85)
                    VStack(spacing:20) {
                        Text(run.engine.phase == .paused ? L("一時停止"):"\(run.engine.countdown)").font(.largeTitle)
                        if run.engine.phase == .paused {Button("再開"){run.resume()}.accessibilityIdentifier("crusher.resume")}
                    }
                }
            }.frame(maxWidth:480).frame(height:geo.size.height*0.52)
            HStack {
                Text(String(format:L("残り %.1f 秒"),run.engine.remaining)).font(.title2.monospacedDigit()).foregroundStyle(run.engine.remaining<=3 ? .orange:jewelGold).accessibilityIdentifier("crusher.time")
                Spacer();Text("\(run.engine.hits) / 3 打").font(.caption.monospaced())
            }
            ProgressView(value:run.engine.remaining/10).tint(jewelGold)
            if run.engine.terminal {
                Text(String(format:L("TIME UP · %lld 枚 · %@"),run.engine.plates,L(run.engine.grade.rawValue))).font(.title3).accessibilityIdentifier("crusher.result")
                if let reward=run.lastReward {Text(L(reward)).foregroundStyle(jewelGold).accessibilityIdentifier("crusher.reward")}
                Button("もう一度・10秒") {run.nextBatch(reward:nil)}.disabled(run.lastReward==nil).accessibilityIdentifier("crusher.again")
            } else {
                Text("10秒で何枚割れる？ 1枚3タップ。光る弱点で評価アップ！").font(.footnote).accessibilityIdentifier("crusher.status")
            }
            Text("1枚100pt＋弱点1HITにつき25pt（破壊時に加算）\nB \(run.engine.bThreshold)pt / A \(run.engine.aThreshold)pt / S \(run.engine.sThreshold)pt").font(.caption2).foregroundStyle(.secondary)
            if let error=run.error ?? state.saveMessage {Text(L(error)).font(.caption).foregroundStyle(.orange);Button("保存を再試行"){run.retryCheckpoint();Task{await settle()}}}
            Spacer(minLength:0)
        }.padding(.horizontal,20)
        }.background(jewelBackground.ignoresSafeArea()).foregroundStyle(jewelWhite).tint(jewelGold)
            .onReceive(timer){_ in run.tick()}
            .onChange(of:run.status){_,s in run.policy.observe(cpuMS:s.cpuMS,gpuMS:s.gpuMS)}
            .onChange(of:phase){_,p in if p != .active {run.pause()}}
            .task(id:run.engine.phase){await settle()}
            .confirmationDialog("この10秒チャレンジを終了しますか？",isPresented:$exit,titleVisibility:.visible){
                Button("今回の報酬なしで戻る"){Task{await state.finishCrusher()}}
                Button("続ける",role:.cancel){run.resume()}
            }
    }
    private func settle() async {
        guard run.engine.terminal,run.lastReward==nil else {return}
        let success=run.engine.phase == .award,result=success ? run.outcome:run.failureOutcome
        if await state.commit(result) {
            let weight=state.save.gems.first{$0.resultID==result.id}?.centicarats
            run.lastReward=weight.map{String(format:L("黒曜石 %@ を保存しました"),GemScale.label($0))} ?? String(format:L("記録を保存しました。クリア目標は%lldptです。"),run.engine.bThreshold)
        }
    }
}

struct CrusherWeakPoint:View {
    @ObservedObject var run:CrusherSession
    var body:some View {
        GeometryReader {geo in
            if [.active,.appearing].contains(run.engine.phase) {
                let target=run.engine.weakPoint
                let center=GlassTargetProjection.point(target,size:geo.size,settings:run.glass)
                Canvas {context,size in
                    var ring=Path()
                    for i in 0...64 {
                        let angle=Double(i)*2*Double.pi/64,r=run.engine.weakRadius
                        let p=GlassTargetProjection.point(target+SIMD2(cos(angle)*r,sin(angle)*r*210/360),size:size,settings:run.glass)
                        if i==0 {ring.move(to:p)} else {ring.addLine(to:p)}
                    }
                    ring.closeSubpath()
                    context.fill(ring,with:.color(.orange.opacity(0.18)))
                    context.stroke(ring,with:.color(.black.opacity(0.55)),lineWidth:5)
                    context.stroke(ring,with:.color(.yellow.opacity(0.95)),lineWidth:2)
                    let dot=Path(ellipseIn:CGRect(x:center.x-4,y:center.y-4,width:8,height:8))
                    context.fill(dot,with:.color(.white))
                    context.draw(Text("WEAK POINT").font(.system(size:10,weight:.bold,design:.monospaced)).foregroundColor(.white),at:CGPoint(x:center.x,y:center.y-28))
                }.accessibilityIdentifier("crusher.weakPoint")
            }
        }.accessibilityHidden(true)
    }
}
