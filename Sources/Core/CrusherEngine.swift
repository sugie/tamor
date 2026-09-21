import Foundation
import simd

struct CrusherEngine: Codable, Equatable {
    enum Phase:String,Codable {case countdown,appearing,ready,active,shattering,award,failed,paused}
    var rulesVersion:Int = 5
    let sessionID:String
    let depth:Int
    var phase:Phase = .countdown
    var resumePhase:Phase = .appearing
    var batch=0
    var plates=0
    var hits=0
    var weakHits=0
    var plateWeakHits=0
    var scoredWeakHits=0
    var totalElapsed:Double=0
    var started=false
    var lastStamp:Double
    var phaseStamp:Double
    var lastHit:Double?
    var released=true
    var resultDate=Date()
    var impact=SIMD2<Double>(0.5,0.5)
    var weakPoint=SIMD2<Double>(0.5,0.5)
    var randomState:UInt64
    var duration:Double {10}
    var remaining:Double {max(0,duration-totalElapsed)}
    var score:Int {plates*100+scoredWeakHits*25}
    var weakRadius:Double {[0.16,0.14,0.12,0.10,0.085,0.07][depth-1]}
    var bThreshold:Int {[100,200,300,450,600,750][depth-1]}
    var aThreshold:Int {[175,275,400,525,650,775][depth-1]}
    var sThreshold:Int {[350,500,650,800,950,1100][depth-1]}
    var grade:GemGrade {score<bThreshold ? .failed:score>=sThreshold ? .s:score>=aThreshold ? .a:.b}
    var countdown:Int {max(1,Int(ceil(3-(lastStamp-phaseStamp))))}
    var resultID:String {"\(sessionID).\(batch)"}
    var terminal:Bool {phase == .award || phase == .failed}
    var valid:Bool {rulesVersion==5 && (1...6).contains(depth) && (0...100).contains(plates) && (0...3).contains(hits) && (0...hits).contains(plateWeakHits) && (0...300).contains(weakHits) && (0...plates*3).contains(scoredWeakHits) && totalElapsed.isFinite && (0...10).contains(totalElapsed) && lastStamp.isFinite && phaseStamp.isFinite && (0...1).contains(weakPoint.x) && (0...1).contains(weakPoint.y)}
    init(depth:Int,now:Double,sessionID:String=UUID().uuidString,seed:UInt64=UInt64.random(in:1...UInt64.max)) {
        self.depth=DepthRules(depth).depth;self.sessionID=sessionID;lastStamp=now;phaseStamp=now;randomState=seed
        newWeakPoint()
    }
    private mutating func newWeakPoint() {
        func unit(_ state:inout UInt64)->Double {state=state &* 6364136223846793005 &+ 1442695040888963407;return Double(state>>11)/9007199254740992}
        weakPoint = .init(0.20+unit(&randomState)*0.60,0.18+unit(&randomState)*0.64)
    }
    func isWeakHit(_ point:SIMD2<Double>)->Bool {
        let delta=(point-weakPoint)*SIMD2<Double>(1,360.0/210)
        return simd_length(delta)<=weakRadius
    }
    private mutating func finish() {totalElapsed=duration;phase=grade == .failed ? .failed:.award;resultDate=Date()}
    mutating func advance(_ stamp:Double,renderReady:Bool=true) {
        let dt=max(0,stamp-lastStamp);lastStamp=max(lastStamp,stamp)
        if phase == .countdown {
            if stamp-phaseStamp>=3,renderReady {phase=resumePhase;phaseStamp=stamp;released=true}
            return
        }
        guard !terminal,phase != .paused else {return}
        if started {
            totalElapsed=min(duration,totalElapsed+dt)
            if totalElapsed>=duration-1e-9 {finish();return}
        }
        if phase == .appearing,renderReady,stamp-phaseStamp>=0.15 {
            phase = .active
            if !started {started=true;totalElapsed=0;lastStamp=stamp}
        }
    }
    mutating func touch(_ point:SIMD2<Double>?,down:Bool,at stamp:Double)->Bool {
        if !down {released=true;return false}
        guard released else {return false};released=false
        guard phase == .active,let point,(0...1).contains(point.x),(0...1).contains(point.y) else {return false}
        let eventElapsed=max(0,totalElapsed+stamp-lastStamp)
        // A touch at or after TIME UP cannot award another plate.
        guard eventElapsed<duration-1e-9 else {finish();return false}
        guard lastHit.map({eventElapsed-$0>=0.120-1e-9}) ?? true else {return false}
        totalElapsed=max(totalElapsed,eventElapsed);lastStamp=max(lastStamp,stamp);lastHit=eventElapsed;impact=point
        hits+=1
        if isWeakHit(point) {weakHits+=1;plateWeakHits+=1}
        if hits==3 {
            plates+=1;scoredWeakHits+=plateWeakHits;phase = .shattering;phaseStamp=stamp
        }
        return true
    }
    mutating func nextPlate(at stamp:Double) {
        advance(stamp)
        guard phase == .shattering else {return}
        hits=0;plateWeakHits=0;released=true;phase = .appearing;phaseStamp=stamp;lastStamp=stamp;newWeakPoint()
    }
    mutating func nextBatch(at stamp:Double) {
        guard terminal else {return}
        batch+=1;plates=0;hits=0;weakHits=0;plateWeakHits=0;scoredWeakHits=0;totalElapsed=0;lastHit=nil;released=true;started=false
        phase = .countdown;resumePhase = .appearing;phaseStamp=stamp;lastStamp=stamp;newWeakPoint()
    }
    mutating func pause(at stamp:Double) {
        guard phase != .paused,!terminal else {return}
        advance(stamp)
        guard !terminal else {return}
        if phase != .countdown {resumePhase=phase}
        phase = .paused;lastStamp=stamp;released=true;resultDate=Date()
    }
    mutating func resume(at stamp:Double) {
        guard phase == .paused else {return}
        phase = .countdown;phaseStamp=stamp;lastStamp=stamp
    }
}
