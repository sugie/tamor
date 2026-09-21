import Foundation
import simd
var checks=0
func check(_ yes:Bool,_ message:String) { checks+=1;precondition(yes,message) }
let dir=FileManager.default.temporaryDirectory.appendingPathComponent("jewel-tests-\(UUID().uuidString)")
let files=JewelSaveFiles(directory:dir)
var save=JewelSave()
check(try files.load().0.inventory.isEmpty,"No possessions on first launch")
save.rotation=0.234567;save.selectedID="emerald";try files.write(save)
check(try files.load().0.rotation==save.rotation,"Exact saved angle")
let reward=JewelReward(id:UUID(),gemID:"blackOnyx",size:1,boardSize:4,seconds:7.2,acquiredAt:Date())
check(save.award(reward),"First reward");check(!save.award(reward),"No duplicate reward")
check(save.inventory["blackOnyx"]?.size==1 && save.progress["blackOnyx"]==6,"Reward and next stage together")
check(save.progress["emerald"]==nil,"Independent gem progression")
save.award(.init(id:UUID(),gemID:"blackOnyx",size:1.2,boardSize:6,seconds:8,acquiredAt:Date()))
save.award(.init(id:UUID(),gemID:"blackOnyx",size:1,boardSize:4,seconds:4,acquiredAt:Date()))
check(save.inventory["blackOnyx"]?.size==1.2,"Largest representative remains")
try files.write(save);check(try files.load().0.rewards.count==3,"Ledger persists")
try Data("bad json".utf8).write(to:files.primary)
check(try files.load().1,"Corrupt primary recovers backup")
check(try files.load().0.rotation==0.234567,"Backup position preserved")
try Data("{\"schemaVersion\":999}".utf8).write(to:files.primary)
do { _=try files.load();fatalError("Future version overwritten") }catch {checks+=1}
try? FileManager.default.removeItem(at:dir)
for n in [4,6,8,10,12] {
 var e=MiniGameEngine(type:.kurukuru,size:n,seed:123,tolerance:0.06,now:0)
 e.advance(to:1);e.begin(at:1)
 for spin in Spin.allCases {
  let cells=e.board.cells.indices.filter{e.board.cells[$0]?.spin==spin}
  check(cells.count%2==0,"Pairable board")
  for i in stride(from:0,to:cells.count,by:2) { e.tapCell(cells[i],at:1.1);e.tapCell(cells[i],at:1.1);e.tapCell(cells[i+1],at:1.2) }
 }
 check(e.phase == .won && e.remaining==0,"Whole board clear")
 check(abs(e.elapsed-0.2)<0.00001,"Final input timestamp defines Kurukuru score")
}
for fps in [30,60,120] {
 var e=MiniGameEngine(type:.grassTrace,size:4,seed:42,tolerance:0.06,now:0)
 e.advance(to:1);e.touch(e.target,down:true,at:1)
 for frame in 1...Int(15.4*Double(fps)) {
  let t=Double(frame)/Double(fps)
  e.touch(MiniGameEngine.course(t),down:true,at:1+t)
 }
 check(e.phase == .won && e.cracks.isEmpty,"Trace perfect success at \(fps)Hz")
 check(abs(e.elapsed-15.3)<0.01,"Exact finish time")
}
var hold=MiniGameEngine(type:.grassTrace,size:4,seed:42,tolerance:0.06,now:0)
hold.advance(to:1);hold.touch(hold.target,down:true,at:1)
for i in 1...908 {let t=Double(i)/60;hold.touch(MiniGameEngine.course(t),down:true,at:1+t)}
hold.touch(nil,down:false,at:16.14)
hold.advance(to:16.4);check(hold.phase == .playing,"Endpoint needs continuous hold")
hold.touch(hold.target,down:true,at:16.4);hold.advance(to:16.6)
check(hold.phase == .playing,"Restart endpoint hold after lifting")
hold.advance(to:16.8);check(hold.phase == .won,"Endpoint hold eventually succeeds")
var trace=MiniGameEngine(type:.grassTrace,size:4,seed:42,tolerance:0.06,now:0)
trace.advance(to:1);trace.touch(trace.target,down:true,at:1)
trace.touch(nil,down:false,at:1.01)
check(trace.cracks.isEmpty,"Finger lift itself does not crack")
trace.touch(.init(0.9,0.9),down:true,at:1.02)
for i in 1...120 {trace.advance(to:1.02+Double(i)/60)}
check(trace.phase == .lost && trace.cracks.count==3,"Distance departure makes exactly 3 cracks")
for seed:UInt64 in 1...40 {
 var b=MiniGameEngine(type:.grassBreak,size:4,seed:seed,tolerance:0.06,now:0)
 b.advance(to:1);b.begin(at:1);check((3...6).contains(b.requiredHits),"3–6 hits")
 var t=1.0
 for hit in 1...b.requiredHits {
  b.presented(b.targetID,at:t);t+=0.2;let point=b.target
  b.touch(point,down:true,at:t)
  check(b.hits==hit,"One target consumes one tap")
  b.touch(b.target,down:true,at:t+0.01);check(b.hits==hit,"Hold cannot hit next target")
  b.touch(nil,down:false,at:t+0.02);t+=0.1
 }
 check(b.phase == .won,"Break succeeds")
}
var timeout=MiniGameEngine(type:.grassBreak,size:4,seed:3,tolerance:0.06,now:0)
timeout.advance(to:1);timeout.begin(at:1);timeout.presented(timeout.targetID,at:1)
for i in 1...90 {timeout.advance(to:1+Double(i)/60)}
timeout.touch(timeout.target,down:true,at:2.5001)
check(timeout.hits==0,"An input after the deadline is too late")
timeout.advance(to:2.7);check(timeout.phase == .lost,"Timeout fails")
var pause=MiniGameEngine(type:.kurukuru,size:4,seed:1,tolerance:0.06,now:0)
pause.advance(to:1);pause.begin(at:1);pause.advance(to:1.2);pause.pause(at:1.2)
pause.advance(to:20);check(abs(pause.elapsed-0.2)<0.001,"Pause freezes game time")
pause.resume(at:20);pause.advance(to:22.9);check(pause.phase == .countdown,"3 second resume")
pause.advance(to:23);pause.advance(to:23.1);check(abs(pause.elapsed-0.3)<0.001,"Resume excludes pause and countdown")
pause.pause(at:23.1);pause.resume(at:24);pause.advance(to:25);pause.pause(at:25)
check(pause.phase == .paused,"OS interruption also pauses countdown")
pause.resume(at:30);pause.advance(to:32.9);check(pause.phase == .countdown,"Interrupted countdown restarts all 3 seconds")
pause.advance(to:33);check(pause.phase == .playing,"Interrupted countdown preserves original playing phase")
print("PASS: \(checks) save, reward, game, deadline, and pause assertions")
