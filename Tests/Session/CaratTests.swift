import XCTest
@testable import Tamor

final class CaratTests:XCTestCase {
    func outcome(_ id:String,_ gem:String="sapphire",_ depth:Int=1,_ grade:GemGrade = .s,_ date:Double=1)->DepthOutcome {
        .init(id:id,gemID:gem,depth:depth,grade:grade,seconds:1,date:Date(timeIntervalSince1970:date),rulesVersion:4)
    }
    func testWeightScaleAndExactRange() {
        XCTAssertEqual(GemScale.width(centicarats:10),7.8907,accuracy:0.001)
        XCTAssertEqual(GemScale.width(centicarats:2000),46.1451,accuracy:0.001)
        XCTAssertEqual(GemScale.legacy(1.8),583)
        for d in 1...6 {for grade in [GemGrade.b,.a,.s] {XCTAssertTrue((10...2000).contains(DepthRules(d).reward(grade,streak:3)))}}
    }
    func testRewardsKeepSmallerIndividualsAndDeduplicate() throws {
        var save=JewelSave()
        save.apply(outcome("large"));save.apply(outcome("small","sapphire",1,.b));save.apply(outcome("large"))
        XCTAssertEqual(save.gems.count,2);XCTAssertEqual(save.representative("sapphire")?.id,"large")
        XCTAssertEqual(save.unlockedDepth("sapphire"),2);XCTAssertEqual(save.unlockedDepth("ruby"),1)
        try save.validate()
    }
    func testMaximumRequiresThreeConsecutiveSAndFailureResets() {
        var save=JewelSave()
        save.apply(outcome("a","ruby",6,.s,1));save.apply(outcome("b","ruby",6,.s,2))
        XCTAssertEqual(save.representative("ruby")?.centicarats,1999)
        save.apply(outcome("c","ruby",6,.s,3));XCTAssertEqual(save.representative("ruby")?.centicarats,2000)
        save.apply(outcome("d","ruby",6,.failed,4));XCTAssertEqual(save.streak("ruby"),0)
        XCTAssertEqual(save.gems.count,3)
    }
    func testRepresentativeTieIsStable() {
        var save=JewelSave();save.apply(outcome("b","ruby",1,.s,1));save.apply(outcome("a","ruby",1,.s,1))
        XCTAssertEqual(save.representative("ruby")?.id,"a")
    }
    func testMigrationReconstructsHistoryAndRetainsLegacySpecies() throws {
        var old=JewelSave();old.schemaVersion=2;old.specimens=nil;old.depthOutcomes=nil
        let date=Date(timeIntervalSince1970:10),id=UUID()
        old.rewards=[.init(id:id,gemID:"emerald",size:1.2,boardSize:6,seconds:20,acquiredAt:date)]
        old.inventory=["emerald":.init(size:1.2,acquiredAt:date),"blackOnyx":.init(size:1.8,acquiredAt:date)]
        try old.validate();XCTAssertEqual(old.schemaVersion,3);XCTAssertEqual(old.gems.count,2)
        XCTAssertEqual(old.representative("blackOnyx")?.centicarats,583)
        XCTAssertEqual(old.representative("emerald")?.worldID,"legacy")
        XCTAssertNil(old.representative("obsidian"));XCTAssertEqual(old.unlockedDepth("sapphire"),1)
        let migrated=old;try old.validate();XCTAssertEqual(old,migrated)
    }
    func testMergeUnionPreservesRotationAndIsIdempotent() throws {
        var first=JewelSave(),second=JewelSave();first.rotation=1.23;second.rotation=5
        first.apply(outcome("a"));second.apply(outcome("b","ruby"))
        try first.mergeCollection(second);try first.mergeCollection(second)
        XCTAssertEqual(first.gems.count,2);XCTAssertEqual(first.rotation,1.23)
        XCTAssertEqual(first.unlockedDepth("ruby"),2)
    }
    func testCloudRejectsContradictoryIdentity() {
        var a=JewelSave(),b=JewelSave();a.apply(outcome("same"));b.apply(outcome("same","ruby"))
        XCTAssertThrowsError(try a.mergeCollection(b))
    }
    func testInvalidCaratsAndUnknownVersionFailClosed() {
        for value in [9,2001] {var s=JewelSave();s.specimens=[.init(id:"bad",gemID:"ruby",centicarats:value,acquiredAt:Date(),resultID:"bad",migrated:false)];XCTAssertThrowsError(try s.validate())}
        var s=JewelSave();s.schemaVersion=99;XCTAssertThrowsError(try s.validate())
    }
    func testTenThousandSpecimensRoundTrip() throws {
        var s=JewelSave()
        s.specimens=(0..<10000).map{.init(id:"\($0)",gemID:"ruby",centicarats:10+$0%1991,acquiredAt:Date(timeIntervalSince1970:Double($0)),resultID:"\($0)",migrated:false)}
        let files=JewelSaveFiles(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try files.write(s);XCTAssertEqual(try files.load().0.gems.count,10000)
    }
}

final class CrusherTests:XCTestCase {
    func ready(_ depth:Int=1)->CrusherEngine {
        var e=CrusherEngine(depth:depth,now:0,seed:42);e.advance(3);e.advance(3.2);return e
    }
    @discardableResult func hit(_ e:inout CrusherEngine,_ t:Double,weak:Bool=true)->Bool {
        let result=e.touch(weak ? e.weakPoint:.init(0.01,0.01),down:true,at:t)
        _=e.touch(nil,down:false,at:t+0.001);return result
    }
    func testAutomaticStartAndTenSecondDeadline() {
        var e=ready();XCTAssertEqual(e.phase,.active);XCTAssertEqual(e.remaining,10)
        e.advance(13.2);XCTAssertEqual(e.phase,.failed);XCTAssertEqual(e.remaining,0)
        XCTAssertFalse(hit(&e,13.21));XCTAssertEqual(e.plates,0)
    }
    func testWeakHitsIncreaseGradeForSamePlateCount() {
        var normal=ready(),weak=ready()
        for t in [3.3,3.43,3.56] {XCTAssertTrue(hit(&normal,t,weak:false));XCTAssertTrue(hit(&weak,t))}
        XCTAssertEqual(normal.plates,weak.plates);XCTAssertEqual(normal.score,100);XCTAssertEqual(weak.score,175)
        XCTAssertEqual(normal.grade,.b);XCTAssertEqual(weak.grade,.a)
        let target=weak.weakPoint;weak.nextPlate(at:4);XCTAssertNotEqual(weak.weakPoint,target)
        normal.advance(13.2);XCTAssertEqual(normal.phase,.award)
    }
    func testIncompletePlateCannotAddScoreAndRoundHasStableID() {
        var e=ready();_=hit(&e,4);_=hit(&e,4.2)
        XCTAssertEqual(e.weakHits,2);XCTAssertEqual(e.score,0)
        e.advance(13.2);XCTAssertEqual(e.grade,.failed)
        let id=e.resultID;e.nextBatch(at:20);XCTAssertNotEqual(e.resultID,id)
        XCTAssertEqual(e.score,0);XCTAssertEqual(e.weakHits,0);XCTAssertEqual(e.phase,.countdown)
    }
    func testRejectsHeldFastAndLateTouches() {
        var e=ready();XCTAssertTrue(e.touch(e.weakPoint,down:true,at:4))
        XCTAssertFalse(e.touch(e.weakPoint,down:true,at:4.2))
        _=e.touch(nil,down:false,at:4.21);XCTAssertFalse(hit(&e,4.05))
        XCTAssertTrue(hit(&e,4.13));XCTAssertFalse(hit(&e,13.2))
        XCTAssertEqual(e.plates,0);XCTAssertEqual(e.phase,.failed)
    }
    func testPauseAndRebootExcludeTimeAndKeepCooldown() throws {
        var e=ready();_=hit(&e,4);e.pause(at:4.05)
        e=try JSONDecoder().decode(CrusherEngine.self,from:JSONEncoder().encode(e))
        e.resume(at:100);e.advance(103)
        XCTAssertEqual(e.totalElapsed,0.85,accuracy:0.001)
        XCTAssertFalse(hit(&e,103.01));XCTAssertTrue(hit(&e,103.08))
    }
    func testClockIncludesTransitionsAndDeepTargetsAreSmaller() {
        var e=ready();for t in [3.3,3.43,3.56] {_=hit(&e,t)}
        e.nextPlate(at:4);e.advance(4.2)
        XCTAssertEqual(e.totalElapsed,1,accuracy:0.001);XCTAssertEqual(e.phase,.active)
        XCTAssertGreaterThan(e.weakRadius,ready(6).weakRadius)
        XCTAssertLessThan(e.sThreshold,ready(6).sThreshold)
        e.pause(at:13.2);XCTAssertEqual(e.phase,.award)
    }
    func testRoundVersionDoesNotUseOldCrusherStreak() {
        var save=JewelSave()
        for i in 1...2 {save.apply(.init(id:"old\(i)",gemID:"obsidian",depth:6,grade:.s,seconds:1,date:Date(timeIntervalSince1970:Double(i)),rulesVersion:4))}
        let first=save.apply(.init(id:"new",gemID:"obsidian",depth:6,grade:.s,seconds:10,date:Date(timeIntervalSince1970:3),rulesVersion:5,plates:7,weakHits:21,score:1225))
        XCTAssertEqual(first?.centicarats,1999)
        XCTAssertEqual(save.streak("obsidian",rulesVersion:5),1)
    }
    func testDeepStageRequiresMoreThanOnePlateAndAccuracyCanReachGoal() {
        var e=ready(6);e.plates=5
        XCTAssertEqual(e.grade,.failed)
        e.scoredWeakHits=15
        XCTAssertEqual(e.grade,.a)
        e.advance(13.2);XCTAssertEqual(e.phase,.award)
    }
}

@MainActor final class CaratTransactionTests:XCTestCase {
    func testGuideProjectionMatchesGlassTouchOnSmallAndLargeScreens() {
        var settings=GlassStudySettings();settings.yaw = -0.08;settings.pitch=0.04;settings.amplitude=0
        let scene=GlassRayScene(amplitude:0)
        for size in [CGSize(width:335,height:400),CGSize(width:480,height:600)] {
            for target in [SIMD2<Double>(0.25,0.2),SIMD2(0.5,0.5),SIMD2(0.75,0.8)] {
                let pixel=GlassTargetProjection.point(target,size:size,settings:settings)
                let hit=GlassCrackPicking.point(at:.init(Float(pixel.x),Float(pixel.y)),viewport:.init(Float(size.width),Float(size.height)),settings:settings,scene:scene)
                XCTAssertNotNil(hit)
                XCTAssertEqual((hit?.x ?? -1)/210,target.x,accuracy:0.001)
                XCTAssertEqual(1-(hit?.y ?? -1)/360,target.y,accuracy:0.001)
            }
        }
    }
    func testInterruptedCrusherIsNotOverwrittenByAnotherDepth() throws {
        let files=JewelSaveFiles(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let pending=CrusherSession(depth:2,files:files,quality:.automatic)
        pending.engine.plates=2;pending.saveCheckpoint()
        let state=JewelSceneState(files:files,defaults:nil)
        state.selectedDepth=1;state.startGame(.obsidian)
        XCTAssertEqual(state.crusher?.engine.depth,2);XCTAssertEqual(state.crusher?.engine.plates,2)
        XCTAssertEqual(state.crusher?.engine.phase,.paused)
        state.crusher?.discardCheckpoint()
    }
    func testFailedDiskWriteDoesNotGrantReward() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state=JewelSceneState(files:.init(directory:directory),defaults:nil)
        try Data("not a directory".utf8).write(to:directory)
        let event=DepthOutcome(id:"reward",gemID:"ruby",depth:1,grade:.s,seconds:1,date:Date(),rulesVersion:4)
        let succeeded=await state.commit(event)
        XCTAssertFalse(succeeded);XCTAssertTrue(state.save.gems.isEmpty);XCTAssertTrue(state.save.outcomes.isEmpty)
        try FileManager.default.removeItem(at:directory)
        let retried=await state.commit(event)
        XCTAssertTrue(retried);XCTAssertEqual(state.save.gems.count,1)
    }
    func testPaidGateDoesNotComeFromLargeMigratedGem() {
        let state=JewelSceneState(files:.init(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),defaults:nil)
        state.save.apply(.init(id:"previous",gemID:"sapphire",depth:3,grade:.s,seconds:1,date:Date(),rulesVersion:4))
        state.selectedDepth=4;state.startGame(.sapphire)
        XCTAssertNil(state.game);XCTAssertTrue(state.paywallRequested)
        state.fullDepthAccess=true;state.startGame(.sapphire)
        XCTAssertEqual(state.game?.depth,4);XCTAssertEqual(state.game?.engine.board.size,10)
        state.game?.stop()
    }
}
