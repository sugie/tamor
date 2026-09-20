import Foundation
import simd

enum CrackDensity: Int, CaseIterable, Equatable {
    case sparse, standard, dense
    var title: String { ["疎", "標準", "密"][rawValue] }
}

struct CrackParameters: Equatable {
    var density: CrackDensity = .standard
    static let maximumEdges = 600
    static let maximumTotalEdges = 3_000
    var mainCount: Int { [12, 16, 20][density.rawValue] }
    var ringCount: Int { [2, 4, 5][density.rawValue] }
    var coreCount: Int { [18, 36, 58][density.rawValue] }
    var connectionChance: Double { [0.45, 0.62, 0.75][density.rawValue] }
}

enum CrackKind: Int, CaseIterable { case main, branch, connection, core }
struct CrackNetworkNode: Equatable { var positionMM: SIMD2<Double> }
struct CrackNetworkEdge: Equatable {
    var start: Int
    var end: Int
    var kind: CrackKind
    var widthStartMM: Float
    var widthEndMM: Float
    var roughness: Float
    var facetDirection: Float
}
struct CrackNetworkPath: Equatable {
    var edgeIDs: [Int] = []
    var parentPathID: Int?
    var requestedLengthMM: Double
}
struct CrackImpact: Identifiable, Equatable {
    let id: UUID
    let centerMM: SIMD2<Double>
    let seed: UInt64
    let generatorVersion = 1
    let parameters: CrackParameters
    var nodes: [CrackNetworkNode]
    var edges: [CrackNetworkEdge]
    var paths: [CrackNetworkPath]
    func length(of path: CrackNetworkPath) -> Double {
        path.edgeIDs.reduce(0) { $0 + simd_distance(nodes[edges[$1].start].positionMM, nodes[edges[$1].end].positionMM) }
    }
}

/// Explicit integer algorithm; no dependence on Swift's randomized Hasher or collection order.
struct CrackNetworkRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func value(_ low: Double, _ high: Double) -> Double {
        low + Double(next() >> 11) * (1.0 / 9007199254740992.0) * (high - low)
    }
}

enum CrackNetworkGenerator {
    static func generate(at center: SIMD2<Double>, seed: UInt64,
                         parameters: CrackParameters = CrackParameters(), id: UUID = UUID()) -> CrackImpact? {
        guard GlassCrack.contains(center) else { return nil }
        var builder = Builder(center: center, seed: seed, parameters: parameters, id: id)
        return builder.build()
    }

    private struct Builder {
        var impact: CrackImpact
        var random: CrackNetworkRandom
        let limit = CrackParameters.maximumEdges
        init(center: SIMD2<Double>, seed: UInt64, parameters: CrackParameters, id: UUID) {
            impact = CrackImpact(id: id, centerMM: center, seed: seed, parameters: parameters,
                                 nodes: [CrackNetworkNode(positionMM: center)], edges: [], paths: [])
            random = CrackNetworkRandom(state: seed)
        }
        func cross(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { a.x*b.y-a.y*b.x }
        mutating func node(_ p: SIMD2<Double>) -> Int {
            if let index = impact.nodes.firstIndex(where: { simd_distance($0.positionMM,p)<0.015 }) { return index }
            impact.nodes.append(CrackNetworkNode(positionMM:p)); return impact.nodes.count-1
        }
        mutating func split(_ edgeID: Int, at p: SIMD2<Double>) -> Int {
            let edge = impact.edges[edgeID]
            let a=impact.nodes[edge.start].positionMM, b=impact.nodes[edge.end].positionMM
            if simd_distance(a,p)<0.02 { return edge.start }
            if simd_distance(b,p)<0.02 { return edge.end }
            let index=impact.nodes.count, t=Float(simd_distance(a,p)/simd_distance(a,b))
            impact.nodes.append(CrackNetworkNode(positionMM:p))
            let width=edge.widthStartMM+(edge.widthEndMM-edge.widthStartMM)*t
            var tail=edge; tail.start=index; tail.widthStartMM=width
            impact.edges[edgeID].end=index; impact.edges[edgeID].widthEndMM=width
            let newID=impact.edges.count; impact.edges.append(tail)
            for path in impact.paths.indices {
                if let i=impact.paths[path].edgeIDs.firstIndex(of:edgeID) { impact.paths[path].edgeIDs.insert(newID,at:i+1) }
            }
            return index
        }
        /// Stop at the nearest existing segment; split it so the joint shares exactly one node.
        mutating func append(from start: Int, to target: SIMD2<Double>, kind: CrackKind,
                             width: Float, path: Int) -> (node: Int, stopped: Bool) {
            guard impact.edges.count < limit-2 else { return (start,true) }
            let a=impact.nodes[start].positionMM, delta=target-a
            let requested=simd_length(delta)
            guard requested>0.04,
                  let clipped=GlassCrack(center:a,H:requested,crad:atan2(delta.y,delta.x)),clipped.H>0.04 else { return (start,true) }
            let b=clipped.end, r=b-a
            var best=1.0, hit: Int?
            for (index,edge) in impact.edges.enumerated() {
                if edge.start==start || edge.end==start { continue }
                let c=impact.nodes[edge.start].positionMM, s=impact.nodes[edge.end].positionMM-c
                let denominator=cross(r,s)
                if abs(denominator)<1e-10 { continue }
                let t=cross(c-a,s)/denominator, u=cross(c-a,r)/denominator
                if t>0.0001 && t<=best && u>=0 && u<=1 { best=t; hit=index }
            }
            let end: Int
            if let hit { end=split(hit,at:a+r*best) } else { end=node(b) }
            guard end != start, simd_distance(a,impact.nodes[end].positionMM)>0.02 else { return (start,true) }
            if impact.edges.contains(where: { ($0.start==start && $0.end==end) || ($0.start==end && $0.end==start) }) { return (end,true) }
            let edge=CrackNetworkEdge(start:start,end:end,kind:kind,widthStartMM:width,
                               widthEndMM:width*Float(random.value(0.55,1.05)),roughness:Float(random.value(0.2,0.8)),
                               facetDirection:Float(random.value(-0.45,0.45)))
            impact.paths[path].edgeIDs.append(impact.edges.count); impact.edges.append(edge)
            return (end,hit != nil || clipped.wasClipped)
        }
        mutating func path(parent: Int? = nil, length: Double) -> Int {
            impact.paths.append(CrackNetworkPath(parentPathID:parent,requestedLengthMM:length)); return impact.paths.count-1
        }
        mutating func grow(start: Int, angle: Double, length: Double, kind: CrackKind, width: Float,
                           parent: Int? = nil) -> Int {
            let id=path(parent:parent,length:length)
            var current=start, remaining=length, heading=angle
            while remaining>0.1 && impact.edges.count<limit-2 {
                let step=min(remaining,random.value(kind == .core ? 1.2 : 8,kind == .core ? 5 : 24))
                heading += random.value(-0.085,0.085)
                let position=impact.nodes[current].positionMM
                let outward=position-impact.centerMM
                var direction=SIMD2(cos(heading),sin(heading))
                if kind == .main && simd_dot(outward,direction)<0 { direction=simd_normalize(outward) }
                let next=append(from:current,to:position+direction*step,kind:kind,width:width*Float(0.5+0.5*remaining/length),path:id)
                remaining -= step; current=next.node
                if next.stopped { break }
            }
            return id
        }
        mutating func atDistance(_ distance: Double, on path: Int) -> Int? {
            var walked=0.0
            for index in impact.paths[path].edgeIDs {
                let edge=impact.edges[index], a=impact.nodes[edge.start].positionMM, b=impact.nodes[edge.end].positionMM
                let length=simd_distance(a,b)
                if walked+length>=distance && impact.edges.count<limit-2 { return split(index,at:a+(b-a)*((distance-walked)/length)) }
                walked += length
            }
            return nil
        }
        mutating func build() -> CrackImpact {
            let p=impact.parameters, phase=random.value(0,2*Double.pi)
            var mains:[Int]=[]
            for i in 0..<p.mainCount {
                let angle=phase+(Double(i)+random.value(-0.27,0.27))*2*Double.pi/Double(p.mainCount)
                let length=random.value(70,240), width=Float(random.value(0.35,0.95))
                mains.append(grow(start:0,angle:angle,length:length,kind:.main,width:width))
            }
            // Rings are constructed before branches so they remain readable in the final silhouette.
            let radii:[Double]=[15,34,63,101,149]
            for ring in 0..<p.ringCount {
                let distances=mains.map { _ in radii[ring]*random.value(0.8,1.2) }
                for i in mains.indices where random.value(0,1)<p.connectionChance {
                    let j=(i+1)%mains.count
                    guard let a=atDistance(distances[i],on:mains[i]),let b=atDistance(distances[j],on:mains[j]),a != b else { continue }
                    let x=impact.nodes[a].positionMM,y=impact.nodes[b].positionMM
                    let id=path(length:simd_distance(x,y)), width=Float(random.value(0.16,0.5))
                    // A kink within the convex pane gives polygonal, irregular connections.
                    let mid=(x+y)*0.5+(impact.centerMM-(x+y)*0.5)*random.value(-0.04,0.04)
                    let first=append(from:a,to:mid,kind:.connection,width:width,path:id)
                    if !first.stopped { _=append(from:first.node,to:y,kind:.connection,width:width,path:id) }
                }
            }
            for main in mains {
                let length=impact.length(of:impact.paths[main])
                guard length>25 else { continue }
                let count=Int(random.next()%3)
                for _ in 0..<count {
                    guard let start=atDistance(length*random.value(0.2,0.7),on:main) else { continue }
                    let radial=impact.nodes[start].positionMM-impact.centerMM
                    let angle=atan2(radial.y,radial.x)+random.value(-0.7,0.7)
                    let branchLength=length*random.value(0.12,0.35)
                    _=grow(start:start,angle:angle,length:branchLength,kind:.branch,width:Float(random.value(0.08,0.24)),parent:main)
                }
            }
            // Short connected splinters fill only the central area, never a solid disc.
            for _ in 0..<p.coreCount {
                let main=mains[Int(random.next()%UInt64(mains.count))]
                guard let start=atDistance(random.value(0.8,14),on:main) else { continue }
                let angle=random.value(0,2*Double.pi), length=random.value(2,12)
                _=grow(start:start,angle:angle,length:length,kind:.core,width:Float(random.value(0.18,0.8)),parent:main)
            }
            return impact
        }
    }
}
