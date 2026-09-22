import SwiftUI
import QuartzCore
import simd
import CoreMotion

@MainActor final class JewelSceneState: ObservableObject {
    @Published var save=JewelSave()
    @Published var selected:Int=0
    @Published var inspecting=false
    @Published var zoom:Double=0
    @Published var error:String?
    @Published var rendererReady=false
    @Published var paused=false {didSet {syncMotion()}}
    @Published var reduceMotion=false {didSet {syncMotion()}}
    @Published var ringTiltEnabled=true {didSet {defaults?.set(ringTiltEnabled,forKey:"tamor.ringTilt");syncMotion()}}
    @Published var preview:Set<String>=[]
    @Published var hidden:Set<String>=[]
    @Published var game:JewelMiniSession?
    @Published var saveMessage:String?
    @Published var savingReward=false
    @Published var crusher:CrusherSession?
    @Published var paywallRequested=false
    @Published var fullDepthAccess=false
    @Published var selectedDepth=1
    func weight(_ jewel:JewelKind)->Int {save.representative(jewel.key)?.centicarats ?? 100}
    var collectionCount:Int {save.gems.count}
    func allowedDepth(_ jewel:JewelKind)->Int {min(save.unlockedDepth(jewel.key),fullDepthAccess ? 6:3)}

    @Published var traceTolerance:Double=0.06
    @Published var quality:QualityPreference = .automatic { didSet { defaults?.set(quality.rawValue,forKey:"tamor.quality") } }
    @Published var windowLightMotion=true { didSet { defaults?.set(windowLightMotion,forKey:"tamor.windowLightMotion") } }
    @Published var rayTracing=false { didSet { defaults?.set(rayTracing,forKey:"tamor.rt") } }
    @Published var rayAvailable=false
    @Published var rayStatus=L("端末のMetal機能を確認中")
    @Published var actualQuality="標準"
    let deviceID:String
    let files:JewelSaveFiles
    let writer:JewelDiskWriter
    private var blocked=false
    private var defaults:UserDefaults?
    private var motion:CMMotionManager?
    private var motionVisible=false
    private var motionReference:SIMD2<Double>?
    private(set) var ringTilt:SIMD2<Float> = .zero
    private var inspectionOrientation=matrix_identity_float4x4
    private var inspectionTilt:SIMD2<Float> = .zero
    private var inspectionPhase:Double=0
    private(set) var returningToRing=false
    var inspectionSettled:Bool {inspecting && !returningToRing && inspectionPhase>=1}
    private var dirty=false
    var ringAngle:Double=0
    var velocity:Double=0
    var snap:Double?
    var dragging=false
    var yaw:Float=0.25
    var pitch:Float = -0.3
    var time:Double=0
    var inspectionProgress:Double=0
    var renderedZoom:Double=0
    var level:ObservationLevel { ObservationLevel(rawValue:min(3,Int(zoom.rounded())))! }
    var kind:JewelKind { JewelKind(rawValue:selected) ?? .diamond }
    var lattice:CrystalLattice {CrystalLattice(atoms:[],bonds:[])}
    var visible:[JewelKind] { JewelKind.worldOne.filter{(save.representative($0.key) != nil || preview.contains($0.key)) && !hidden.contains($0.key)} }
    var count:Int { visible.count }
    var ownedCount:Int { JewelKind.worldOne.filter{save.representative($0.key) != nil}.count }
    var hasMastery:Bool { !(save.earnedTitles ?? []).isEmpty }
    var hasMaximumGem:Bool { save.gems.contains{$0.centicarats==2000} }
    var decoration:Int {let style=save.decorationStyle ?? 1;return style>=2 && !hasMaximumGem ? 1:style}
    var decoratedSlots:Int {
        let titles=save.earnedTitles ?? []
        return JewelKind.worldOne.reduce(0) {mask,jewel in
            let earned=jewel == .diamond ? titles.contains("一閃の破砕"):jewel == .ruby ? titles.contains("傷なき軌跡"):titles.contains(where:{$0.hasPrefix(jewel.key+"・")})
            return earned && save.representative(jewel.key) != nil ? mask | (1 << (save.slots[jewel.key] ?? jewel.slot)):mask
        }
    }
    func setDecoration(_ value:Int) {save.decorationStyle=value;persist()}
    var atomCount:Int { kind == .diamond && zoom>=1.6 ? lattice.atoms.count:0 }
    var bondCount:Int { kind == .diamond && zoom>=1.6 ? lattice.bonds.count:0 }
    nonisolated static var preferences:UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test"),let id=ProcessInfo.processInfo.environment["JEWEL_TEST_ID"],UUID(uuidString:id) != nil { return UserDefaults(suiteName:"JewelRingUITests."+id)! }
        #endif
        return .standard
    }
    init(files:JewelSaveFiles = .standard,defaults:UserDefaults? = JewelSceneState.preferences) {
        self.files=files;writer=JewelDiskWriter(files);self.defaults=defaults
        deviceID=defaults?.string(forKey:"tamor.deviceID") ?? UUID().uuidString
        defaults?.set(deviceID,forKey:"tamor.deviceID")
        quality=QualityPreference(rawValue:defaults?.string(forKey:"tamor.quality") ?? "") ?? .automatic
        rayTracing=defaults?.bool(forKey:"tamor.rt") ?? false
        windowLightMotion=defaults?.object(forKey:"tamor.windowLightMotion") as? Bool ?? true
        ringTiltEnabled=defaults?.object(forKey:"tamor.ringTilt") as? Bool ?? true
        do { let (s,recovered)=try files.load();save=s;ringAngle=s.rotation
            selected=JewelKind.worldOne.first(where:{$0.key==s.selectedID})?.rawValue ?? 0
            if recovered { saveMessage=L("バックアップから復元しました。") }
        } catch { blocked=true;saveMessage=L(error.localizedDescription) }
        #if DEBUG
        preview=Set(defaults?.stringArray(forKey:"jewel.preview") ?? [])
        hidden=Set(defaults?.stringArray(forKey:"jewel.hidden") ?? [])
        #endif
        if let v=defaults?.object(forKey:"jewel.traceTolerance") as? Double { traceTolerance=min(0.2,max(0.025,v)) }
    }
    func position(_ jewel:JewelKind)->SIMD2<Double> {
        RingLayoutMath.position(index:save.slots[jewel.key] ?? jewel.slot,count:12,angle:ringAngle)
    }
    var displayedJewels:[JewelKind] {inspectionProgress>=1 ? visible.filter{$0==kind}:visible}
    var displayedTilt:SIMD2<Float> {inspecting ? inspectionTilt:ringTilt}
    func gemVisibility(_ jewel:JewelKind)->Float {jewel==kind ? 1:Float(pow(1-inspectionProgress,2))}
    func displayPosition(_ jewel:JewelKind)->SIMD2<Double> {
        let p=RingTiltMath.project(position(jewel),tilt:displayedTilt)
        return inspecting && jewel==kind ? p*(1-inspectionProgress):p
    }
    var ringOrientation:simd_float4x4 {
        JewelMatrices.rotate(-0.38,.init(1,0,0))*JewelMatrices.rotate(Float(reduceMotion ? 0:sin(time*0.25)*0.12)+0.18,.init(0,1,0))
    }
    func gemModel(_ jewel:JewelKind)->simd_float4x4 {
        let size=Float(GemScale.width(centicarats:weight(jewel))/375)
        let scale=JewelMatrices.scale(.init(repeating:size))
        if inspecting {
            let p=position(jewel)
            var location=RingTiltMath.transform(inspectionTilt)*SIMD4<Float>(Float(p.x),Float(p.y),0,0)
            let amount=jewel==kind ? Float(inspectionProgress):0
            location *= 1-amount
            let rotation=jewel==kind ? JewelMatrices.rotate(pitch*amount,.init(1,0,0))*JewelMatrices.rotate(yaw*amount,.init(0,1,0)):matrix_identity_float4x4
            return JewelMatrices.translate(.init(location.x,location.y,location.z))*rotation*inspectionOrientation*scale
        }
        let p=position(jewel)
        return RingTiltMath.transform(ringTilt)*JewelMatrices.translate(.init(Float(p.x),Float(p.y),0))*ringOrientation*scale
    }
    func rotateInspection(yaw:Float,pitch:Float) {
        guard inspectionSettled,!paused,yaw.isFinite,pitch.isFinite else {return}
        self.yaw=Float(RingLayoutMath.wrapped(Double(yaw)))
        self.pitch=Float(RingLayoutMath.wrapped(Double(pitch)))
    }
    func setMotionVisible(_ visible:Bool) {motionVisible=visible;syncMotion()}
    private func syncMotion() {
        var enabled=motionVisible && !paused && !reduceMotion && ringTiltEnabled && !inspecting
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {enabled=false}
        #endif
        if enabled {
            if motion==nil {motion=CMMotionManager()}
            guard let motion,motion.isDeviceMotionAvailable else {return}
            if !motion.isDeviceMotionActive {
                motionReference=nil;motion.deviceMotionUpdateInterval=1.0/30
                motion.startDeviceMotionUpdates(using:.xArbitraryZVertical)
            }
        } else {
            motion?.stopDeviceMotionUpdates();motionReference=nil
            if !inspecting {ringTilt = .zero}
        }
    }
    private func updateTilt(_ dt:Double) {
        guard let sample=motion?.deviceMotion,motion?.isDeviceMotionActive==true,
              let angles=RingTiltMath.angles(gravity:.init(sample.gravity.x,sample.gravity.y,sample.gravity.z)) else {return}
        if motionReference==nil {motionReference=angles}
        guard let reference=motionReference else {return}
        let target=RingTiltMath.relative(angles,to:reference)
        ringTilt+=(target-ringTilt)*Float(1-exp(-dt*10))
    }
    func hit(_ p:SIMD2<Double>)->JewelKind? {
        guard !inspecting else {return nil}
        let p=RingTiltMath.unproject(p,tilt:ringTilt)
        guard simd_length(p)>0.35 else { return nil }
        guard simd_length(p)<0.94 else { return nil }
        let nearest=(0..<12).min { simd_distance(p,RingLayoutMath.position(index:$0,count:12,angle:ringAngle)) < simd_distance(p,RingLayoutMath.position(index:$1,count:12,angle:ringAngle)) }!
        return JewelKind.worldOne.first { (save.slots[$0.key] ?? $0.slot)==nearest }
    }
    func activate(_ index:Int) {
        guard let jewel=JewelKind(rawValue:index),rendererReady,!paused else { return }
        if inspecting {if jewel==kind {back()};return}
        if visible.contains(jewel) { inspect(index) } else { startGame(jewel) }
    }
    func inspect(_ index:Int) {
        guard rendererReady,!paused,!inspecting,let jewel=JewelKind(rawValue:index),visible.contains(jewel) else { return }
        inspectionTilt=ringTilt
        inspectionOrientation=RingTiltMath.transform(ringTilt)*ringOrientation
        selected=index;velocity=0;snap=nil;dragging=false
        dirty=false;zoom=0;renderedZoom=0;yaw=0;pitch=0;returningToRing=false
        inspectionPhase=reduceMotion ? 1:0;inspectionProgress=inspectionPhase;inspecting=true
        syncMotion()
        persist()
    }
    func back() {
        guard inspecting,!returningToRing else {return}
        dirty=false;velocity=0;snap=nil;dragging=false;returningToRing=true
        if reduceMotion || inspectionPhase==0 {finishInspection()}
    }
    private func finishInspection() {
        inspectionPhase=0;inspectionProgress=0;returningToRing=false;inspecting=false
        syncMotion();persist()
    }
    func selectNext(_ delta:Int) {
        let list=visible;guard !list.isEmpty,(!inspecting || inspectionSettled) else { return }
        let i=list.firstIndex(of:kind) ?? 0
        selected=list[(i+delta+list.count)%list.count].rawValue
        if inspecting {yaw=0;pitch=0;persist();return}
        let target = -Double(save.slots[kind.key] ?? kind.slot)*2 * .pi/12
        snap=ringAngle+RingLayoutMath.wrapped(target-ringAngle);velocity=0;dirty=true
        if reduceMotion { ringAngle=snap!;snap=nil;persist();dirty=false }
    }
    func moved() { dirty=true
        if let nearest=visible.min(by:{abs(RingLayoutMath.wrapped(atan2(position($0).x,-position($0).y)))<abs(RingLayoutMath.wrapped(atan2(position($1).x,-position($1).y)))}) { selected=nearest.rawValue }
    }
    func stopMotionForTouch() { velocity=0;snap=nil;if dirty {dirty=false;persist()} }
    func saveTolerance() { defaults?.set(traceTolerance,forKey:"jewel.traceTolerance") }
    func setZoom(_ value:Double) { zoom=0;renderedZoom=0 }
    func setLevel(_ value:ObservationLevel) { setZoom(Double(value.rawValue)) }
    func setVisible(_ jewel:JewelKind,_ yes:Bool) {
        #if DEBUG
        if yes { hidden.remove(jewel.key);preview.insert(jewel.key) } else { preview.remove(jewel.key);hidden.insert(jewel.key) }
        if inspecting && !visible.contains(kind) {back()}
        if !visible.contains(kind) { selected=visible.first?.rawValue ?? 0 }
        defaults?.set(Array(preview),forKey:"jewel.preview");defaults?.set(Array(hidden),forKey:"jewel.hidden")
        #endif
    }
    func normalVisibility() { if inspecting {back()};preview=[];hidden=[];selected=visible.first?.rawValue ?? 0;defaults?.removeObject(forKey:"jewel.preview");defaults?.removeObject(forKey:"jewel.hidden") }
    func persist() {
        guard !blocked,!savingReward else { return }
        save.rotation=ringAngle;save.selectedID=kind.key;save.revision+=1
        let snapshot=save
        Task { do { try await writer.write(snapshot) } catch { saveMessage=L("保存できませんでした：")+L(error.localizedDescription) } }
    }
    func startGame(_ jewel:JewelKind,previewOnly:Bool=false) {
        guard game==nil,crusher==nil,!savingReward,!blocked else { return }
        guard JewelKind.worldOne.contains(jewel) else {return}
        // Recover an interrupted batch before accepting a different depth; never overwrite it.
        let depth = jewel.game == .crusher ? (CrusherSession.pendingDepth(files:files) ?? min(selectedDepth,save.unlockedDepth(jewel.key))) : min(selectedDepth,save.unlockedDepth(jewel.key))
        if depth>3 && !fullDepthAccess {paywallRequested=true;return}
        if inspecting {finishInspection()}
        selected=jewel.rawValue;persist()
        if jewel.game == .crusher {
            crusher=CrusherSession(depth:depth,files:files,quality:quality)
        } else {
            game=JewelMiniSession(kind:jewel,size:DepthRules(depth).boardSize,preview:previewOnly,tolerance:DepthRules(depth).traceTolerance,quality:quality,depth:depth)
        }
    }
    func claim(_ run:JewelMiniSession) async {
        guard run.engine.phase == .won,!run.claimed,!savingReward,!blocked else {return}
        if run.preview {run.claimed=true;return}
        let outcome=run.outcome
        if await commit(outcome) {
            run.claimed=true;run.rewardCarats=save.gems.first{$0.resultID==outcome.id}?.centicarats ?? 10
        }
    }
    @discardableResult func commit(_ outcome:DepthOutcome) async -> Bool {
        guard !savingReward,!blocked else {return false}
        savingReward=true;defer {savingReward=false}
        var next=save;next.apply(outcome);next.revision+=1
        do {
            try await writer.write(next);save=next;saveMessage=nil
            if let jewel=JewelKind.allCases.first(where:{$0.key==outcome.gemID}) {selected=jewel.rawValue}
            return true
        } catch {saveMessage=L("報酬を保存できません。再試行してください：")+L(error.localizedDescription);return false}
    }
    func finishGame() {
        guard !savingReward else {return}
        if let run=game,!run.preview,!run.claimed {
            // Abandoning an active highest-depth run breaks the streak, but never grants a reward.
            var outcome=run.outcome
            if run.engine.phase != .won {
                outcome=DepthOutcome(id:run.id.uuidString,gemID:run.kind.key,depth:run.depth,grade:.failed,seconds:run.engine.elapsed,date:Date(),rulesVersion:4)
                save.apply(outcome)
            }
        }
        game?.stop();game=nil;persist()
    }
    func finishCrusher() async {
        guard !savingReward,let run=crusher else {return}
        run.pause()
        if run.engine.phase == .award {
            guard await commit(run.outcome) else {return}
        } else if run.engine.started || run.engine.hits>0 || run.engine.plates>0 {
            guard await commit(run.failureOutcome) else {return}
        }
        run.discardCheckpoint();crusher=nil;persist()
    }
    func importSave(_ url:URL) async {
        guard !blocked,!savingReward,game==nil,crusher==nil else {return}
        let access=url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
        do {
            guard try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0 < 20_000_000 else {throw SaveFailure.invalid}
            var incoming=try JSONDecoder().decode(JewelSave.self,from:Data(contentsOf:url));try incoming.validate()
            // Import is exposed only for an empty collection, and the existing primary is backed up atomically.
            guard save.gems.isEmpty else { saveMessage=L("コレクションが空の端末で取り込んでください。現在の宝石は保持しています。");return }
            incoming.revision=max(save.revision,incoming.revision)+1
            try await writer.write(incoming);save=incoming;ringAngle=incoming.rotation;blocked=false
            selected=JewelKind.worldOne.first(where:{$0.key==incoming.selectedID})?.rawValue ?? 0
            saveMessage=L("旧コレクションを取り込みました。旧記録はローカル専用です。")
        } catch {saveMessage=L("取り込めませんでした：")+L(error.localizedDescription)}
    }
    func tick(_ rawDT:Double) {
        guard !paused else { return }
        let dt=min(0.04,max(0,rawDT))
        if inspecting {
            inspectionPhase=reduceMotion ? (returningToRing ? 0:1):min(1,max(0,inspectionPhase+dt/0.7*(returningToRing ? -1:1)))
            // Quintic easing has zero velocity and acceleration at both endpoints.
            let t=inspectionPhase
            inspectionProgress=t*t*t*(t*(t*6-15)+10)
            if returningToRing && inspectionPhase==0 {finishInspection()}
            return
        }
        time+=dt
        updateTilt(dt)
        renderedZoom += (zoom-renderedZoom)*min(1,dt*12)
        guard !dragging,inspectionProgress<0.001 else { return }
        if let target=snap {
            ringAngle+=(target-ringAngle)*min(1,dt*13)
            if abs(target-ringAngle)<0.0005 { ringAngle=target;snap=nil;velocity=0;if dirty { persist();dirty=false } }
        } else if abs(velocity)>0.025 {
            ringAngle+=velocity*dt;velocity*=exp(-dt*5);moved()
        } else if dirty {
            velocity=0;snap=RingLayoutMath.snapTarget(count:12,angle:ringAngle)
        }
    }
}
