import SwiftUI
import QuartzCore
import simd

@MainActor final class JewelSceneState: ObservableObject {
    @Published var save=JewelSave()
    @Published var selected:Int=0
    @Published var inspecting=false
    @Published var zoom:Double=0
    @Published var error:String?
    @Published var rendererReady=false
    @Published var paused=false
    @Published var reduceMotion=false
    @Published var preview:Set<String>=[]
    @Published var hidden:Set<String>=[]
    @Published var game:JewelMiniSession?
    @Published var saveMessage:String?
    @Published var savingReward=false
    @Published var traceTolerance:Double=0.06
    @Published var quality:QualityPreference = .automatic { didSet { defaults?.set(quality.rawValue,forKey:"tamor.quality") } }
    @Published var rayTracing=false { didSet { defaults?.set(rayTracing,forKey:"tamor.rt") } }
    @Published var rayAvailable=false
    @Published var rayStatus="端末のMetal機能を確認中"
    @Published var actualQuality="標準"
    let deviceID:String
    let files:JewelSaveFiles
    let writer:JewelDiskWriter
    private var blocked=false
    private var defaults:UserDefaults?
    private var returnAngle:Double=0
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
    let lattice=CrystalLattice.diamond()
    var visible:[JewelKind] { JewelKind.allCases.filter{(save.inventory[$0.key] != nil || preview.contains($0.key)) && !hidden.contains($0.key)} }
    var count:Int { visible.count }
    var ownedCount:Int { JewelKind.allCases.filter{save.inventory[$0.key] != nil}.count }
    var hasMastery:Bool { !(save.earnedTitles ?? []).isEmpty }
    var hasMaximumGem:Bool { save.inventory.values.contains{$0.size>=1.8} }
    var decoration:Int {let style=save.decorationStyle ?? 1;return style>=2 && !hasMaximumGem ? 1:style}
    var decoratedSlots:Int {
        let titles=save.earnedTitles ?? []
        return JewelKind.allCases.reduce(0) {mask,jewel in
            let earned=jewel == .diamond ? titles.contains("一閃の破砕"):jewel == .ruby ? titles.contains("傷なき軌跡"):titles.contains(where:{$0.hasPrefix(jewel.key+"・")})
            return earned && save.inventory[jewel.key] != nil ? mask | (1 << (save.slots[jewel.key] ?? jewel.slot)):mask
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
        do { let (s,recovered)=try files.load();save=s;ringAngle=s.rotation
            selected=JewelKind.allCases.first(where:{$0.key==s.selectedID})?.rawValue ?? 0
            if recovered { saveMessage="バックアップから復元しました。" }
        } catch { blocked=true;saveMessage=error.localizedDescription }
        #if DEBUG
        preview=Set(defaults?.stringArray(forKey:"jewel.preview") ?? [])
        hidden=Set(defaults?.stringArray(forKey:"jewel.hidden") ?? [])
        #endif
        if let v=defaults?.object(forKey:"jewel.traceTolerance") as? Double { traceTolerance=min(0.2,max(0.025,v)) }
    }
    func position(_ jewel:JewelKind)->SIMD2<Double> {
        RingLayoutMath.position(index:save.slots[jewel.key] ?? jewel.slot,count:12,angle:ringAngle)
    }
    func hit(_ p:SIMD2<Double>)->JewelKind? {
        guard simd_length(p)>0.35 else { return nil }
        guard simd_length(p)<0.94 else { return nil }
        let nearest=(0..<12).min { simd_distance(p,RingLayoutMath.position(index:$0,count:12,angle:ringAngle)) < simd_distance(p,RingLayoutMath.position(index:$1,count:12,angle:ringAngle)) }!
        return JewelKind.allCases.first { (save.slots[$0.key] ?? $0.slot)==nearest }
    }
    func activate(_ index:Int) {
        guard let jewel=JewelKind(rawValue:index),rendererReady,!paused else { return }
        if visible.contains(jewel) { inspect(index) } else { startGame(jewel) }
    }
    func inspect(_ index:Int) {
        guard rendererReady,!paused,!inspecting,let jewel=JewelKind(rawValue:index),visible.contains(jewel) else { return }
        returnAngle=ringAngle;selected=index;velocity=0;snap=nil;dragging=false
        dirty=false;zoom=0;renderedZoom=0;yaw=0.25;pitch = -0.3;inspecting=true
        persist()
    }
    func back() { dirty=false;ringAngle=returnAngle;inspecting=false;velocity=0;snap=nil;dragging=false;persist() }
    func selectNext(_ delta:Int) {
        let list=visible;guard !list.isEmpty else { return }
        let i=list.firstIndex(of:kind) ?? 0
        selected=list[(i+delta+list.count)%list.count].rawValue
        let target = -Double(save.slots[kind.key] ?? kind.slot)*2 * .pi/12
        snap=ringAngle+RingLayoutMath.wrapped(target-ringAngle);velocity=0;dirty=true
        if reduceMotion { ringAngle=snap!;snap=nil;persist();dirty=false }
    }
    func moved() { dirty=true
        if let nearest=visible.min(by:{abs(RingLayoutMath.wrapped(atan2(position($0).x,-position($0).y)))<abs(RingLayoutMath.wrapped(atan2(position($1).x,-position($1).y)))}) { selected=nearest.rawValue }
    }
    func stopMotionForTouch() { velocity=0;snap=nil;if dirty {dirty=false;persist()} }
    func saveTolerance() { defaults?.set(traceTolerance,forKey:"jewel.traceTolerance") }
    func setZoom(_ value:Double) { zoom=min(3,max(0,value)) }
    func setLevel(_ value:ObservationLevel) { setZoom(Double(value.rawValue)) }
    func setVisible(_ jewel:JewelKind,_ yes:Bool) {
        #if DEBUG
        if yes { hidden.remove(jewel.key);preview.insert(jewel.key) } else { preview.remove(jewel.key);hidden.insert(jewel.key) }
        if !visible.contains(kind) { selected=visible.first?.rawValue ?? 0 }
        defaults?.set(Array(preview),forKey:"jewel.preview");defaults?.set(Array(hidden),forKey:"jewel.hidden")
        #endif
    }
    func normalVisibility() { preview=[];hidden=[];selected=visible.first?.rawValue ?? 0;defaults?.removeObject(forKey:"jewel.preview");defaults?.removeObject(forKey:"jewel.hidden") }
    func persist() {
        guard !blocked else { return }
        save.rotation=ringAngle;save.selectedID=kind.key;save.revision+=1
        let snapshot=save
        Task { do { try await writer.write(snapshot) } catch { saveMessage="保存できませんでした：\(error.localizedDescription)" } }
    }
    func startGame(_ jewel:JewelKind,previewOnly:Bool=false) {
        guard game==nil,!blocked else { return }
        if inspecting { back() }
        persist()
        let size=save.progress[jewel.key] ?? 4
        game=JewelMiniSession(kind:jewel,size:size,preview:previewOnly,tolerance:traceTolerance,quality:quality)
    }
    func claim(_ run:JewelMiniSession) async {
        guard run.engine.phase == .won,!run.claimed,!savingReward,!blocked else { return }
        savingReward=true
        defer { savingReward=false }
        if run.preview { run.claimed=true;return }
        let reward=JewelReward(id:run.id,gemID:run.kind.key,size:run.rewardSize,boardSize:run.kind.game == .kurukuru ? run.engine.board.size:0,seconds:run.engine.elapsed,acquiredAt:Date())
        save.award(reward)
        save.record(run.result(deviceID:deviceID))
        if !visible.contains(kind) { selected=run.kind.rawValue }
        save.rotation=ringAngle;save.selectedID=kind.key;save.revision+=1
        do { try await writer.write(save);run.claimed=true;saveMessage=nil }
        catch { saveMessage="報酬を保存できませんでした。再試行してください。\n\(error.localizedDescription)" }
    }
    func finishGame() {
        if let run=game,run.readyForResult,!run.preview { save.record(run.result(deviceID:deviceID)) }
        game?.stop();game=nil;persist()
    }
    func importSave(_ url:URL) async {
        guard !blocked,!savingReward,game==nil else {return}
        let access=url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}}
        do {
            guard try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0 < 20_000_000 else {throw SaveFailure.invalid}
            var incoming=try JSONDecoder().decode(JewelSave.self,from:Data(contentsOf:url));try incoming.validate()
            // Import is exposed only for an empty collection, and the existing primary is backed up atomically.
            guard save.inventory.isEmpty else { saveMessage="コレクションが空の端末で取り込んでください。現在の宝石は保持しています。";return }
            incoming.revision=max(save.revision,incoming.revision)+1
            try await writer.write(incoming);save=incoming;ringAngle=incoming.rotation;blocked=false
            selected=JewelKind.allCases.first(where:{$0.key==incoming.selectedID})?.rawValue ?? 0
            saveMessage="旧コレクションを取り込みました。旧記録はローカル専用です。"
        } catch {saveMessage="取り込めませんでした："+error.localizedDescription}
    }
    func tick(_ rawDT:Double) {
        guard !paused else { return }
        let dt=min(0.04,max(0,rawDT));time+=dt
        let goal=inspecting ? 1.0:0.0
        inspectionProgress += (goal-inspectionProgress)*min(1,dt*(reduceMotion ? 30:8))
        if abs(inspectionProgress-goal)<0.0001 { inspectionProgress=goal }
        renderedZoom += (zoom-renderedZoom)*min(1,dt*12)
        guard !inspecting,!dragging,inspectionProgress<0.001 else { return }
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
