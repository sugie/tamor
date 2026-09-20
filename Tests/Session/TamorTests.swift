import XCTest
@testable import Tamor

@MainActor final class TamorTests:XCTestCase {
    func testKurukuruStartsAutomaticallyOnlyAfterReadyAndCountdown() {
        for kind in [JewelKind.blackOnyx,.emerald] { for size in [4,6] {
            var time=0.0
            let run=JewelMiniSession(kind:kind,size:size,preview:false,tolerance:0.06,now:{time},seed:42)
            time=1;run.tick();XCTAssertEqual(run.engine.phase,.ready)
            run.rendererReady=true;run.tick();XCTAssertEqual(run.engine.phase,.countdown)
            run.cell(0);XCTAssertNil(run.engine.selected)
            time=3.99;run.tick();XCTAssertEqual(run.engine.phase,.countdown)
            time=4;run.tick();XCTAssertEqual(run.engine.phase,.playing);XCTAssertEqual(run.engine.elapsed,0)
            time=4.2;run.tick();XCTAssertEqual(run.engine.elapsed,0.2,accuracy:0.0001)
            run.cell(0);XCTAssertEqual(run.engine.selected,0)
        }}
    }
    func testAutoCountdownWaitsForGlassAndPresentation() {
        var time=0.0
        let run=JewelMiniSession(kind:.diamond,size:4,preview:false,tolerance:0.06,now:{time},seed:42)
        time=1;run.tick();XCTAssertEqual(run.engine.phase,.ready)
        run.rendererReady=true;run.glassStatus.samples=1;run.tick();XCTAssertEqual(run.engine.phase,.countdown)
        time=3.9;run.tick();XCTAssertEqual(run.engine.phase,.countdown)
        time=4;run.tick();XCTAssertEqual(run.engine.phase,.playing);XCTAssertNil(run.engine.deadline)
        run.presented(run.engine.targetID,at:4.1,epoch:run.presentationEpoch)
        XCTAssertEqual(run.engine.deadline!,run.engine.activeTime+1.5,accuracy:0.001)
    }
    func testStalePresentationAndStoppedSessionCannotStartDeadline() {
        var time=0.0
        let run=JewelMiniSession(kind:.diamond,size:4,preview:false,tolerance:0.06,now:{time},seed:42)
        time=1;run.engine.advance(to:time);run.engine.begin(at:time)
        let epoch=run.presentationEpoch
        run.pause();time=2;run.resume();time=5;run.tick()
        run.presented(run.engine.targetID,at:time,epoch:epoch);XCTAssertNil(run.engine.deadline)
        run.stop();run.presented(run.engine.targetID,at:time,epoch:run.presentationEpoch);XCTAssertNil(run.engine.deadline)
    }
    func testCountdownInterruptionRestartsThreeSeconds() {
        var e=MiniGameEngine(type:.grassBreak,size:4,seed:1,tolerance:0.06,now:0)
        e.advance(to:1);e.autoStart(at:1);e.advance(to:2);e.pause(at:2)
        e.resume(at:20);e.advance(to:22.99);XCTAssertEqual(e.phase,.countdown)
        e.advance(to:23);XCTAssertEqual(e.phase,.playing);XCTAssertEqual(e.elapsed,0)
    }
    func testMasterySeatAndMaximumSizeDecorations() {
        let s=JewelSceneState(files:.init(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),defaults:nil)
        s.save.inventory["emerald"] = .init(size:1.8,acquiredAt:Date())
        s.save.earnedTitles=["emerald・12×12"]
        XCTAssertTrue(s.hasMaximumGem);XCTAssertEqual(s.decoratedSlots,1<<6)
        s.save.decorationStyle=3;XCTAssertEqual(s.decoration,3)
        s.save.inventory["emerald"]?.size=1.6;XCTAssertEqual(s.decoration,1)
    }
    func testQualityHysteresisAndThermalCaps() {
        var q=RenderQualityPolicy()
        for _ in 0..<29 {q.observe(cpuMS:3,gpuMS:30)}
        XCTAssertEqual(q.effective(thermal:.nominal,lowPower:false),.standard)
        q.observe(cpuMS:3,gpuMS:30);XCTAssertEqual(q.effective(thermal:.nominal,lowPower:false),.low)
        for _ in 0..<240 {q.observe(cpuMS:3,gpuMS:4)}
        XCTAssertEqual(q.effective(thermal:.nominal,lowPower:false),.standard)
        q.preference = .high
        XCTAssertEqual(q.effective(thermal:.serious,lowPower:false),.low)
        XCTAssertEqual(q.effective(thermal:.nominal,lowPower:true),.low)
        XCTAssertEqual(q.effective(thermal:.fair,lowPower:false),.standard)
    }
    func testVersionOneImportPreservesCollectionAndPosition() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s=JewelSceneState(files:.init(directory:dir),defaults:nil)
        var old=JewelSave();old.schemaVersion=1;old.journal=nil;old.earnedTitles=nil;old.rulesBestTimes=nil;old.rotation=1.234
        old.inventory["emerald"] = .init(size:1.4,acquiredAt:Date());old.bestTimes["emerald.4.v2"]=15
        let file=dir.appendingPathComponent("import.json");try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        try JSONEncoder().encode(old).write(to:file)
        await s.importSave(file)
        XCTAssertEqual(s.save.schemaVersion,2);XCTAssertEqual(s.ringAngle,1.234);XCTAssertEqual(s.save.inventory["emerald"]?.size,1.4)
        XCTAssertEqual(s.save.bestTimes["emerald.4.v2"],15);XCTAssertTrue((s.save.rulesBestTimes ?? [:]).isEmpty)
        XCTAssertEqual(try s.files.load().0,s.save)
    }
    func testOutcomeIdempotenceRulesAndCloudSeparation() throws {
        var s=JewelSave()
        let e=GameResultEvent(id:UUID(),game:.grassTrace,gemID:"ruby",rulesVersion:"tamor.3",boardSize:0,targetCount:0,traceTolerance:0.06,seconds:15.3,mistakes:0,cracks:0,hits:0,won:true,finishedAt:Date(),deviceID:"test")
        s.record(e);s.record(e);XCTAssertEqual(s.journal?.count,1);XCTAssertEqual(s.earnedTitles,["傷なき軌跡"])
        s.rotation=2.456
        let json=String(decoding:try JSONEncoder().encode(PlayerCloudSnapshot(save:s,deviceID:"test")),as:UTF8.self)
        XCTAssertFalse(json.contains("rotation"));XCTAssertFalse(json.contains("quality"));XCTAssertTrue(json.contains("localOnly"))
    }
    func testEveryFutureSeatIsExcludedFromHitTesting() {
        let s=JewelSceneState(files:.init(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),defaults:nil)
        for angle in [0.0,0.73,-4.2] {
            s.ringAngle=angle
            for slot in 0..<12 {
                let p=RingLayoutMath.position(index:slot,count:12,angle:angle)
                XCTAssertEqual(s.hit(p) != nil,slot%3==0)
            }
        }
    }
    func testFallbackRetainsLargePhysicalFragmentsAndCancellation() throws {
        let result=GlassBreakGeometry.coarse()
        XCTAssertEqual(result.fragments.count,12)
        XCTAssertEqual(result.fragments.reduce(0){$0+$1.volume},210*360*12,accuracy:0.01)
        XCTAssertTrue(result.fragments.allSatisfy{$0.triangles.count==12})
        XCTAssertThrowsError(try GlassBreakGeometry.build(impacts:[],cracks:[],amplitude:0,budgetSeconds:-1))
    }
}
