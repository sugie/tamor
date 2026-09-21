import XCTest
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
        let s=scene();s.rendererReady=true
        for j in JewelKind.allCases {s.setVisible(j,true);s.inspect(j.rawValue);s.setZoom(3)
            XCTAssertEqual(s.atomCount,0);s.back()
        }
        XCTAssertEqual(GlassObject().depthMM,12)
    }
}
