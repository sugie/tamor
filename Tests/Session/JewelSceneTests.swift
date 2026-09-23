import XCTest
import simd
@testable import Tamor

@MainActor final class JewelSceneTests:XCTestCase {
    func scene() -> JewelSceneState {
        JewelSceneState(files:.init(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),defaults:nil)
    }
    func testExactReturnAndColdLoad() async throws {
        let s=scene();s.rendererReady=true
        for j in JewelKind.allCases {s.setVisible(j,true)}
        s.ringAngle=1.234567;s.inspect(JewelKind.sapphire.rawValue);s.setZoom(3)
        for _ in 0..<100 {s.tick(1.0/60)}
        s.back()
        for _ in 0..<300 {s.tick(1.0/60)}
        XCTAssertEqual(s.ringAngle,1.234567,accuracy:1e-10)
        XCTAssertEqual(s.kind,.sapphire)
        try await s.writer.write(s.save)
        let loaded=JewelSceneState(files:s.files,defaults:nil)
        XCTAssertEqual(loaded.ringAngle,s.ringAngle,accuracy:1e-10)
        XCTAssertEqual(loaded.kind,.sapphire)
        XCTAssertTrue(loaded.visible.isEmpty,"Preview never becomes ownership")
    }
    func testFixedSlotsAndTapStopsInertia() {
        let s=scene();s.setVisible(.ruby,true);s.setVisible(.diamond,true)
        let point=s.position(.ruby);s.setVisible(.diamond,false)
        XCTAssertEqual(s.position(.ruby),point)
        XCTAssertEqual(s.hit(s.position(.diamond)),.diamond,"Empty collectible seat starts its game")
        s.ringAngle=0.321;s.velocity=3;s.moved();s.stopMotionForTouch()
        for _ in 0..<100 {s.tick(1.0/60)}
        XCTAssertEqual(s.ringAngle,0.321,accuracy:1e-10)
    }
    func testSingleGemKeepsScaleAndOrientationWithoutZoom() {
        let s=scene();s.rendererReady=true;s.ringAngle=0.73
        for jewel in JewelKind.worldOne {s.setVisible(jewel,true)}
        let before=s.gemModel(.sapphire)
        s.inspect(JewelKind.sapphire.rawValue)
        for _ in 0..<50 {s.tick(1.0/60)}
        XCTAssertEqual(s.displayedJewels,[.sapphire])
        XCTAssertEqual(s.displayPosition(.sapphire),.zero)
        let centered=s.gemModel(.sapphire)
        for column in 0..<3 {XCTAssertEqual(simd_length(before[column]-centered[column]),0,accuracy:0.00001)}
        XCTAssertEqual(centered.columns.3,SIMD4<Float>(0,0,0,1))
        s.setZoom(3);XCTAssertEqual(s.zoom,0);XCTAssertEqual(s.renderedZoom,0)
        s.back();for _ in 0..<50 {s.tick(1.0/60)};XCTAssertEqual(s.displayedJewels.count,4);XCTAssertEqual(s.ringAngle,0.73)
    }
    func testInspectionRotationDoesNotMoveRingOrSaveProgress() {
        let s=scene();s.rendererReady=true;s.setVisible(.ruby,true);s.setVisible(.diamond,true)
        s.ringAngle=1.23;s.inspect(JewelKind.ruby.rawValue)
        for _ in 0..<50 {s.tick(1.0/60)}
        let before=s.gemModel(.ruby),revision=s.save.revision
        s.rotateInspection(yaw:1.1,pitch:0.6)
        let after=s.gemModel(.ruby)
        XCTAssertGreaterThan(simd_length(before.columns.0-after.columns.0),0.001)
        XCTAssertEqual(simd_length(before.columns.0),simd_length(after.columns.0),accuracy:0.00001)
        XCTAssertEqual(after.columns.3,SIMD4<Float>(0,0,0,1))
        XCTAssertEqual(s.ringAngle,1.23);XCTAssertEqual(s.save.revision,revision)
        s.selectNext(1);XCTAssertNil(s.snap);XCTAssertEqual(s.ringAngle,1.23)
        s.back();XCTAssertEqual(s.ringAngle,1.23)
    }
    func testSpotlightTravelAndReverseKeepScaleAndExactRingPosition() {
        let s=scene();s.rendererReady=true;s.ringAngle=0.72
        for j in JewelKind.worldOne {s.setVisible(j,true)}
        let start=s.gemModel(.ruby),position=s.displayPosition(.ruby)
        s.inspect(JewelKind.ruby.rawValue)
        XCTAssertEqual(s.inspectionProgress,0)
        XCTAssertEqual(s.displayPosition(.ruby),position)
        var last=0.0
        for _ in 0..<21 {
            s.tick(1.0/60)
            XCTAssertGreaterThanOrEqual(s.inspectionProgress,last);last=s.inspectionProgress
            XCTAssertEqual(simd_length(s.gemModel(.ruby).columns.0),simd_length(start.columns.0),accuracy:0.000001)
        }
        XCTAssertEqual(s.inspectionProgress,0.5,accuracy:0.00001)
        XCTAssertLessThan(simd_distance(s.displayPosition(.ruby),position*0.5),0.00001)
        XCTAssertGreaterThan(s.gemVisibility(.diamond),0);XCTAssertLessThan(s.gemVisibility(.diamond),1)
        for _ in 0..<30 {s.tick(1.0/60)}
        XCTAssertTrue(s.inspectionSettled);XCTAssertEqual(s.displayPosition(.ruby),.zero)
        s.rotateInspection(yaw:1.2,pitch:0.8)
        let turned=s.gemModel(.ruby)
        s.activate(JewelKind.ruby.rawValue) // Same action as a single tap / VoiceOver activation.
        XCTAssertTrue(s.returningToRing)
        XCTAssertEqual(s.gemModel(.ruby),turned,"Starting the return must not jump")
        for _ in 0..<50 {s.tick(1.0/60)}
        XCTAssertFalse(s.inspecting);XCTAssertEqual(s.ringAngle,0.72)
        XCTAssertLessThan(simd_distance(s.displayPosition(.ruby),position),0.00001)
        for i in 0..<3 {XCTAssertLessThan(simd_length(s.gemModel(.ruby)[i]-start[i]),0.001)}
    }
    func testSpotlightCanReverseMidFlightAndHonorsPauseAndReduceMotion() {
        let s=scene();s.rendererReady=true;s.setVisible(.diamond,true)
        s.inspect(0);for _ in 0..<12 {s.tick(1.0/60)}
        let p=s.inspectionProgress
        s.paused=true;s.tick(0.04);XCTAssertEqual(s.inspectionProgress,p)
        s.paused=false;s.back();s.tick(1.0/60);XCTAssertLessThan(s.inspectionProgress,p)
        for _ in 0..<20 {s.tick(1.0/60)}
        XCTAssertFalse(s.inspecting)
        s.reduceMotion=true;s.inspect(0)
        XCTAssertTrue(s.inspectionSettled);XCTAssertEqual(s.displayPosition(.diamond),.zero)
        s.back();XCTAssertFalse(s.inspecting);XCTAssertEqual(s.inspectionProgress,0)
    }
    func testTiltProjectionPreservesTapTargetsAtAllRingAngles() {
        for tx:Float in [-0.4,0,0.4] {for ty:Float in [-0.4,0,0.4] {for angle in [0.0,0.8,2.2] {
            let tilt=SIMD2(tx,ty)
            for slot in 0..<12 {
                let p=RingLayoutMath.position(index:slot,count:12,angle:angle)
                let rendered=RingTiltMath.project(p,tilt:tilt)
                let recovered=RingTiltMath.unproject(rendered,tilt:tilt)
                XCTAssertLessThan(simd_distance(p,recovered),0.000001)
                XCTAssertEqual(RingLayoutMath.hit(point:recovered,count:12,angle:angle),slot)
            }
        }}}
    }
    func testGravityTiltHasNeutralPoseLimitsAndNoInvalidSamples() throws {
        let neutral=try XCTUnwrap(RingTiltMath.angles(gravity:.init(0,-0.8,-0.6)))
        XCTAssertEqual(RingTiltMath.relative(neutral,to:neutral),.zero)
        let right=try XCTUnwrap(RingTiltMath.angles(gravity:.init(0.3,-0.8,-0.6)))
        XCTAssertGreaterThan(RingTiltMath.relative(right,to:neutral).y,0)
        let left=try XCTUnwrap(RingTiltMath.angles(gravity:.init(-0.3,-0.8,-0.6)))
        XCTAssertLessThan(RingTiltMath.relative(left,to:neutral).y,0)
        let flat=try XCTUnwrap(RingTiltMath.angles(gravity:.init(0,0,-1)))
        XCTAssertLessThan(RingTiltMath.relative(flat,to:neutral).x,0)
        XCTAssertEqual(RingTiltMath.relative(.init(2,2),to:.zero),.init(0.4,0.4))
        XCTAssertNil(RingTiltMath.angles(gravity:.zero))
        XCTAssertNil(RingTiltMath.angles(gravity:.init(.nan,0,-1)))
    }
    func testAcquisitionAndIndependentProgress() async throws {
        let s=scene();var time=0.0
        let run=JewelMiniSession(kind:.sapphire,size:4,preview:false,tolerance:0.06,now:{time},seed:1)
        time=1;run.engine.advance(to:time);run.engine.begin(at:time)
        for spin in [Spin.clockwise,Spin.counterclockwise] {
            let indices=run.engine.board.cells.indices.filter{run.engine.board.cells[$0]?.spin==spin}
            for i in indices {time+=0.01;run.engine.tapCell(i,at:time)}
        }
        XCTAssertEqual(run.engine.phase,.won)
        await s.claim(run);await s.claim(run)
        XCTAssertTrue(run.claimed);XCTAssertEqual(s.save.gems.count,1)
        XCTAssertEqual(s.kind,.sapphire);XCTAssertEqual(s.ownedCount,1)
        XCTAssertEqual(s.save.unlockedDepth("sapphire"),2);XCTAssertNil(s.save.progress["emerald"])
        let disk=try s.files.load().0
        XCTAssertEqual(disk.representative("sapphire")?.centicarats,49)
    }
    func testTerminalInputCancellationKeepsShatterRunning() {
        for phase in [MiniPhase.won,.lost] {
            let run=JewelMiniSession(kind:.ruby,size:4,preview:false,tolerance:0.06,now:{1},seed:1)
            run.engine.phase=phase;run.pause()
            XCTAssertEqual(run.engine.phase,phase)
            XCTAssertFalse(run.glass.animationPaused,"Late input cancellation cannot freeze a terminal animation")
        }
    }
    func testNoFakeMineralLatticeAndPhysicalThickness() {
        let s=scene();s.rendererReady=true;s.reduceMotion=true
        for j in JewelKind.allCases {s.setVisible(j,true);s.inspect(j.rawValue);s.setZoom(3)
            XCTAssertEqual(s.atomCount,0);s.back()
        }
        XCTAssertEqual(GlassObject().depthMM,12)
    }
}
