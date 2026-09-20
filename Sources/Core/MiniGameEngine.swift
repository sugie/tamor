import Foundation
import simd

enum MiniPhase: String { case intro,ready,playing,paused,countdown,won,lost }
struct MiniCrack:Identifiable {
    let id:UUID
    let ordinal:Int
    let point:SIMD2<Double>
    let birth:Double
    let seed:UInt64
}
struct MiniGameEngine {
    let type:JewelGame
    var board:Board
    var phase:MiniPhase = .intro
    var elapsed:Double=0
    var activeTime:Double=0
    var selected:Int?
    var mistakes=0
    var matched=0
    var cracks:[MiniCrack]=[]
    var pointer:SIMD2<Double>?
    var pointerDown=false
    var target=SIMD2<Double>(0.22,0.22)
    var targetID=0
    var deadline:Double?
    var requiredHits:Int
    var hits=0
    var tolerance:Double
    var failure:String?
    var fadeEvents:[(Int,Double)]=[]
    private var random:SeededRNG
    private var lastWall:Double
    private var began:Double=0
    private var episodeSince:Double?
    private var nextMiss:Double?
    private var traceChecked:Double=0
    private var endpointSince:Double?
    private var autoStarting=false
    private var savedPhase:MiniPhase = .ready
    private var countdownStart:Double=0
    private var pausedAt:Double=0
    private var waitingRelease=false
    private var pendingTimeout:Double?
    var countdown:Int { max(1,Int(ceil(3-(lastWall-countdownStart)))) }
    var remaining:Int { board.count }
    var tracePoint:SIMD2<Double> { Self.course(elapsed) }
    init(type:JewelGame,size:Int,seed:UInt64,tolerance:Double,now:Double) {
        self.type=type;self.tolerance=tolerance;lastWall=now
        var rng=SeededRNG(state:seed);requiredHits=Int.random(in:3...6,using:&rng);random=rng
        var settings=GameSettings();settings.size=size;settings.seed=seed;board=BoardGenerator.generate(settings)
    }
    static func course(_ time:Double)->SIMD2<Double> {
        let points:[SIMD2<Double>]=[.init(0.22,0.22),.init(0.76,0.27),.init(0.25,0.5),.init(0.74,0.70),.init(0.5,0.82)]
        let t=min(4,max(0,time/15*4)),i=min(3,Int(t)),f=t-Double(i),smooth=f*f*(3-2*f)
        return points[i]+(points[i+1]-points[i])*smooth
    }
    static func distance(_ a:SIMD2<Double>,_ b:SIMD2<Double>)->Double {
        simd_length((a-b)*SIMD2(1,360.0/210))
    }
    mutating func advance(to now:Double) {
        let dt=max(0,now-lastWall);lastWall=max(lastWall,now)
        if phase == .paused { return }
        if phase == .countdown {
            if now-countdownStart>=3 {
                phase=savedPhase;lastWall=now
                if autoStarting { autoStarting=false;phase = .ready;begin(at:now) }
            }
            return
        }
        if phase == .playing && dt>0.6 { pause(at:now);return }
        activeTime+=dt
        if phase == .intro,activeTime>=0.8 { phase = .ready }
        guard phase == .playing else { return }
        elapsed=max(0,activeTime-began)
        if type == .grassTrace {
            // Evaluate a fixed temporal grid independent of display refresh. Input events advance
            // this grid before replacing the latest measured pointer position.
            let end=elapsed
            while traceChecked+1.0/120 <= end+1e-9 && phase == .playing {
                traceChecked+=1.0/120
                let distance=pointer.map{Self.distance($0,Self.course(traceChecked))} ?? .infinity
                if distance>tolerance {
                    if episodeSince==nil { episodeSince=traceChecked;nextMiss=traceChecked+0.15 }
                    if let due=nextMiss,traceChecked+1e-9>=due {
                        addCrack(at:Self.course(traceChecked));nextMiss=due+0.75
                        if cracks.count>=3 { phase = .lost;failure="ヒビが3つ入りました" }
                    }
                } else { episodeSince=nil;nextMiss=nil }
                if traceChecked+1e-9>=15,pointerDown,distance<=tolerance {
                    if endpointSince==nil {endpointSince=traceChecked}
                    if let since=endpointSince,traceChecked-since+1e-9>=0.3,phase == .playing {elapsed=traceChecked;phase = .won}
                } else {endpointSince=nil}
            }
            target=Self.course(elapsed)
        } else if type == .grassBreak,let deadline,activeTime>=deadline {
            // A small delivery window allows a touch timestamped before the deadline to arrive.
            if pendingTimeout==nil { pendingTimeout=deadline }
            if activeTime>deadline+0.10 { phase = .lost;failure="赤い点の時間切れです" }
        }
    }
    mutating func autoStart(at now:Double) {
        guard type != .grassTrace,phase == .ready else { return }
        autoStarting=true;savedPhase = .ready;phase = .countdown;countdownStart=now;lastWall=now
    }
    mutating func begin(at now:Double) {
        advance(to:now);guard phase == .ready else { return }
        phase = .playing;began=activeTime;elapsed=0;traceChecked=0
        if type == .grassBreak { newTarget() }
    }
    mutating func tapCell(_ index:Int,at now:Double) {
        let eventTime=activeTime+now-lastWall
        advance(to:now);guard type == .kurukuru,phase == .playing,board.cells.indices.contains(index),board.cells[index] != nil else { return }
        guard let first=selected else { selected=index;return }
        guard first != index else { return }
        selected=nil
        if board.removePair(first,index) {
            matched+=1;fadeEvents += [(first,activeTime),(index,activeTime)]
            if remaining==0 { elapsed=max(0,eventTime-began);phase = .won }
        } else { mistakes+=1 }
    }
    mutating func touch(_ point:SIMD2<Double>?,down:Bool,at now:Double) {
        // Capture event time before advance moves the clock. Clamp only stale dispatch lag.
        let eventTime=activeTime+now-lastWall
        advance(to:now)
        guard type != .kurukuru else { return }
        if !down { pointerDown=false;waitingRelease=false;return }
        guard let point else { return }
        let beganTouch = !pointerDown
        pointerDown=true
        if type == .grassTrace {
            if phase == .ready,Self.distance(point,target)<=tolerance { begin(at:now) }
            if phase == .playing || phase == .countdown { pointer=point }
        } else if phase == .playing,beganTouch,!waitingRelease,let deadline,eventTime<deadline,Self.distance(point,target)<=max(0.075,tolerance) {
            hits+=1;addCrack(at:target);waitingRelease=true;pendingTimeout=nil
            if hits==requiredHits { phase = .won } else { newTarget() }
        } else if type == .grassBreak,phase == .playing,beganTouch,deadline != nil {
            mistakes+=1
        }
    }
    mutating func presented(_ id:Int,at now:Double) {
        guard type == .grassBreak,phase == .playing,targetID==id,deadline==nil else { return }
        advance(to:now);guard phase == .playing else {return};deadline=activeTime+1.5
    }
    mutating func newTarget() {
        var p=target
        for _ in 0..<20 {
            p=SIMD2(Double.random(in:0.16...0.84,using:&random),Double.random(in:0.12...0.88,using:&random))
            if Self.distance(p,target)>0.25 { break }
        }
        target=p;targetID+=1;deadline=nil;pendingTimeout=nil
    }
    private mutating func addCrack(at p:SIMD2<Double>) {
        cracks.append(.init(id:UUID(),ordinal:cracks.count+1,point:p,birth:activeTime,seed:random.next()))
    }
    mutating func pause(at now:Double) {
        guard [.intro,.ready,.playing,.countdown].contains(phase) else { return }
        if phase != .countdown { savedPhase=phase }
        phase = .paused;pausedAt=now;lastWall=now;pointerDown=false;endpointSince=nil
    }
    mutating func resume(at now:Double) {
        guard phase == .paused else { return }
        phase = .countdown;countdownStart=now;lastWall=now
    }
}
