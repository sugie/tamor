import Foundation
import simd

/// The geometry pipeline uses millimetres and Double until uploading to Metal.
enum GlassBreakGeometry {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    struct Segment { var a, b: SIMD2<Double> }
    struct Vertex {
        var p, n: SIMD3<Double>
        var surface: Bool = true
        static func mix(_ a: Self, _ b: Self, _ t: Double) -> Self {
            .init(p:a.p+(b.p-a.p)*t,n:simd_normalize(a.n+(b.n-a.n)*t),surface:a.surface)
        }
    }
    struct Triangle { var v: [Vertex] }
    struct Fragment {
        var triangles: [GlassRayTriangle]
        var center: SIMD3<Float>
        var volume: Double
    }
    struct Result {
        var fragments: [Fragment]
        var completion: [Segment]
        var sourceVolume: Double
        var volumeError: Double
    }
    private struct Key: Hashable, Comparable {
        var x,y,z: Int64
        init(_ p: SIMD3<Double>) { x=Int64((p.x*1e6).rounded()); y=Int64((p.y*1e6).rounded()); z=Int64((p.z*1e6).rounded()) }
        init(_ p: SIMD2<Double>) { self.init(SIMD3(p.x,p.y,0)) }
        static func < (a:Self,b:Self)->Bool { a.x != b.x ? a.x<b.x : a.y != b.y ? a.y<b.y : a.z<b.z }
    }
    private struct Edge: Hashable { var a,b: Int; init(_ a:Int,_ b:Int) { self.a=min(a,b); self.b=max(a,b) } }
    private static func cross(_ a:SIMD2<Double>,_ b:SIMD2<Double>)->Double { a.x*b.y-a.y*b.x }
    private static func cross(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->SIMD3<Double> { simd_cross(a,b) }
    private static func area(_ p:[SIMD2<Double>])->Double { p.indices.reduce(0) { $0+cross(p[$1],p[($1+1)%p.count]) }/2 }

    /// Ear clipping permits concave simple loops. Graph faces are split at repeated nodes first.
    static func triangulate(_ p:[SIMD2<Double>]) throws -> [[Int]] {
        var ids=Array(p.indices), result:[[Int]]=[]
        while ids.count>3 {
            try Task.checkCancellation()
            var found=false
            for k in ids.indices {
                let a=ids[(k+ids.count-1)%ids.count], b=ids[k], c=ids[(k+1)%ids.count]
                guard cross(p[b]-p[a],p[c]-p[b])>1e-10 else { continue }
                let blocked=ids.contains { j in
                    if j==a || j==b || j==c { return false }
                    if min(length_squared(p[j]-p[a]),min(length_squared(p[j]-p[b]),length_squared(p[j]-p[c])))<1e-16 { return false }
                    return cross(p[b]-p[a],p[j]-p[a]) >= -1e-10 && cross(p[c]-p[b],p[j]-p[b]) >= -1e-10 && cross(p[a]-p[c],p[j]-p[c]) >= -1e-10
                }
                if !blocked { result.append([a,b,c]); ids.remove(at:k); found=true; break }
            }
            if !found { throw Failure(message:"破片の境界を三角形に分割できませんでした。") }
        }
        if ids.count==3, abs(cross(p[ids[1]]-p[ids[0]],p[ids[2]]-p[ids[0]]))>1e-10 { result.append(ids) }
        return result
    }

    static func build(impacts:[CrackImpact], cracks:[GlassCrack], amplitude:Float,budgetSeconds:Double=0.30) throws -> Result {
        let deadline=ProcessInfo.processInfo.systemUptime+budgetSeconds
        func checkpoint() throws {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.systemUptime>deadline {throw Failure(message:"簡略破片に切り替えます")}
        }
        try checkpoint()
        var source:[Triangle]=[]
        for t in GlassRayScene(amplitude:amplitude).triangles {
            let positions=[t.a,t.b,t.c], normals=[t.na,t.nb,t.nc]
            var vertices:[Vertex]=[]
            for i in 0..<3 {
                let p=positions[i],n=normals[i]
                vertices.append(Vertex(p:SIMD3<Double>(Double(p.x),Double(p.y),Double(p.z)),n:SIMD3<Double>(Double(n.x),Double(n.y),Double(n.z))))
            }
            source.append(Triangle(v:vertices))
        }
        let sourceBounds=source.map { t -> (SIMD2<Double>,SIMD2<Double>) in
            let a=SIMD2(t.v[0].p.x,t.v[0].p.y),b=SIMD2(t.v[1].p.x,t.v[1].p.y),c=SIMD2(t.v[2].p.x,t.v[2].p.y)
            return (simd_min(a,simd_min(b,c)),simd_max(a,simd_max(b,c)))
        }
        var lines:[Segment]=[], completion:[Segment]=[]
        for impact in impacts {
            for edge in impact.edges {
                lines.append(.init(a:impact.nodes[edge.start].positionMM-SIMD2(105,180),b:impact.nodes[edge.end].positionMM-SIMD2(105,180)))
            }
        }
        for c in cracks { lines.append(.init(a:SIMD2(c.ccx-105,c.ccy-180),b:SIMD2(c.cex-105,c.cey-180))) }
        guard !lines.isEmpty else { throw Failure(message:"分割する亀裂がありません。") }
        // A bounding rectangle outside the true rounded mesh. Clipping later preserves the
        // authoritative bevel; external portions of these partition cells contain no glass.
        let boundary:[SIMD2<Double>]=[SIMD2(-105,-180),SIMD2(105,-180),SIMD2(105,180),SIMD2(-105,180)]
        // Extend main endpoints to the nearest crack or perimeter. Also connect isolated
        // components in both X directions below. Added segments retain explicit provenance.
        func extend(_ p:SIMD2<Double>,_ d:SIMD2<Double>,stopAtCrack:Bool=false) {
            guard length(d)>1e-7 else { return }
            var t=Double.infinity
            for axis in 0..<2 where abs(d[axis])>1e-12 {
                let limit=axis==0 ? 105.0:180.0
                let hit=((d[axis]>0 ? limit:-limit)-p[axis])/d[axis]
                if hit >= -1e-8 { t=min(t,max(0,hit)) }
            }
            if stopAtCrack {
                for line in lines+completion {
                    let q=line.b-line.a,den=cross(d,q)
                    if abs(den)<1e-10 { continue }
                    let hit=cross(line.a-p,q)/den,u=cross(line.a-p,d)/den
                    if hit>1e-5 && u>=0 && u<=1 { t=min(t,hit) }
                }
            }
            if t.isFinite, t>1e-8 { completion.append(.init(a:p,b:p+d*t)) }
        }
        for impact in impacts {
            for path in impact.paths {
                guard let first=path.edgeIDs.first, let last=path.edgeIDs.last,
                      impact.edges[first].kind == .main else { continue }
                let e=impact.edges[last], a=impact.nodes[e.start].positionMM-SIMD2(105,180), b=impact.nodes[e.end].positionMM-SIMD2(105,180)
                extend(b,b-a,stopAtCrack:true)
            }
        }
        for c in cracks { let a=SIMD2(c.ccx-105,c.ccy-180),b=SIMD2(c.cex-105,c.cey-180); extend(a,a-b); extend(b,b-a) }
        // Each original connected component receives two boundary connections. This eliminates
        // disconnected nested rings without inventing an unrelated fracture pattern.
        var originalNodes:[SIMD2<Double>]=[], nodeMap:[Key:Int]=[:], parent:[Int]=[]
        func node(_ p:SIMD2<Double>)->Int {
            let k=Key(p); if let n=nodeMap[k] { return n }
            let n=originalNodes.count; nodeMap[k]=n; originalNodes.append(p); parent.append(n); return n
        }
        func root(_ n:Int)->Int { var r=n; while parent[r] != r { r=parent[r] }; return r }
        for l in lines { let a=node(l.a),b=node(l.b); parent[root(a)]=root(b) }
        var representatives:[Int:Int]=[:]
        for i in originalNodes.indices { let r=root(i); if representatives[r]==nil { representatives[r]=i } }
        for i in representatives.values.sorted() {
            extend(originalNodes[i],SIMD2(-1,0)); extend(originalNodes[i],SIMD2(1,0))
        }
        lines += completion
        for i in boundary.indices { lines.append(.init(a:boundary[i],b:boundary[(i+1)%4])) }
        let faces=try partition(lines,deadline:deadline)
        guard faces.count>1 else { throw Failure(message:"独立した破片を作れませんでした。") }
        guard faces.count<=1600 else { throw Failure(message:"破片が多すぎます。密度を下げて再試行してください。") }
        var fragments:[Fragment]=[]
        struct WallKey:Hashable { var a,b:Key }
        var walls:[WallKey:[Triangle]]=[:]
        let originalVolume=volume(source)
        for polygon in faces {
            try checkpoint()
            let caps=try triangulate(polygon)
            var mesh:[Triangle]=[]
            // Exterior triangles are clipped without temporary caps. Internal triangulation
            // diagonals never become fracture walls. Build each real boundary wall directly.
            for cap in caps {
                let points=cap.map { polygon[$0] }
                let low=points.reduce(SIMD2<Double>(repeating:.infinity),simd_min)
                let high=points.reduce(SIMD2<Double>(repeating:-.infinity),simd_max)
                var cell:[Triangle]=[]
                for i in source.indices {
                    let (l,h)=sourceBounds[i]
                    if h.x>=low.x-1e-7 && l.x<=high.x+1e-7 && h.y>=low.y-1e-7 && l.y<=high.y+1e-7 { cell.append(source[i]) }
                }
                for k in 0..<3 {
                    let a=points[k],b=points[(k+1)%3],d=b-a
                    cell=try clip(cell,point:a,normal:normalize(SIMD2(-d.y,d.x)),cap:false)
                }
                mesh += cell
            }
            for k in polygon.indices {
                let a=polygon[k],b=polygon[(k+1)%polygon.count]
                if (abs(a.x-b.x)<1e-7 && abs(abs(a.x)-105)<1e-7) || (abs(a.y-b.y)<1e-7 && abs(abs(a.y)-180)<1e-7) { continue }
                let ka=Key(a),kb=Key(b),key=WallKey(a:min(ka,kb),b:max(ka,kb))
                let forward=ka<kb
                if walls[key]==nil {
                    let start=forward ? a:b,end=forward ? b:a,direction=end-start
                    walls[key]=try clip(source,point:start,normal:normalize(SIMD2(-direction.y,direction.x)),wallRange:(start,end))
                }
                let wall=walls[key]!
                if forward { mesh += wall }
                else { mesh += wall.map { t in Triangle(v:[t.v[0],t.v[2],t.v[1]].map { Vertex(p:$0.p,n: -$0.n,surface:false) }) } }
            }
            if mesh.isEmpty { continue }
            // A closed, consistently oriented surface has zero vector area. Together with
            // closed cut contours, planar coverage and volume conservation this catches missing
            // or reversed walls before the parent object can be removed.
            var vectorArea=SIMD3<Double>.zero, surfaceArea=0.0
            for t in mesh {
                let a=cross(t.v[1].p-t.v[0].p,t.v[2].p-t.v[0].p)/2
                vectorArea += a; surfaceArea += length(a)
            }
            guard length(vectorArea)<max(1e-6,surfaceArea*1e-6) else { throw Failure(message:"破片の面の接続を検証できませんでした。") }
            let v=volume(mesh)
            guard v>1e-8 else { throw Failure(message:"破片の体積が不正です。") }
            // Volume-weighted center using oriented tetrahedra.
            var center=SIMD3<Double>.zero
            for t in mesh { let a=t.v[0].p,b=t.v[1].p,c=t.v[2].p; center += (a+b+c)*(dot(a,cross(b,c))/24) }
            center /= v
            let c=SIMD3<Float>(center)
            let triangles=mesh.map { t -> GlassRayTriangle in
                let ps=t.v.map { SIMD4<Float>(SIMD3<Float>($0.p)-c,1) }
                let ns=t.v.map { SIMD4<Float>(SIMD3<Float>($0.n),$0.surface ? 1:0) }
                return .init(a:ps[0],b:ps[1],c:ps[2],na:ns[0],nb:ns[1],nc:ns[2])
            }
            fragments.append(.init(triangles:triangles,center:c,volume:v))
        }
        let error=abs(fragments.reduce(0){$0+$1.volume}-originalVolume)/originalVolume
        guard fragments.count>1,error<1e-4 else { throw Failure(message:"分割後の体積を検証できませんでした。 error=\(error), pieces=\(fragments.count)") }
        return .init(fragments:fragments,completion:completion,sourceVolume:originalVolume,volumeError:error)
    }

    private static func volume(_ triangles:[Triangle])->Double {
        triangles.reduce(0) { $0+dot($1.v[0].p,cross($1.v[1].p,$1.v[2].p))/6 }
    }

    /// All intersections (including collinear overlap endpoints) share one canonical vertex.
    private static func partition(_ segments:[Segment],deadline:Double) throws -> [[SIMD2<Double>]] {
        var cuts=Array(repeating:[0.0,1.0],count:segments.count)
        for i in segments.indices {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.systemUptime>deadline {throw Failure(message:"分割の時間上限")}
            let a=segments[i].a,r=segments[i].b-a,rr=length_squared(r)
            if rr<1e-16 { continue }
            for j in (i+1)..<segments.count {
                let b=segments[j].a,s=segments[j].b-b,ss=length_squared(s)
                if ss<1e-16 { continue }
                if max(a.x,a.x+r.x)+1e-7<min(b.x,b.x+s.x) || max(b.x,b.x+s.x)+1e-7<min(a.x,a.x+r.x) || max(a.y,a.y+r.y)+1e-7<min(b.y,b.y+s.y) || max(b.y,b.y+s.y)+1e-7<min(a.y,a.y+r.y) { continue }
                let den=cross(r,s)
                if abs(den)>1e-10 {
                    let t=cross(b-a,s)/den,u=cross(b-a,r)/den
                    if t >= -1e-8 && t<=1+1e-8 && u >= -1e-8 && u<=1+1e-8 { cuts[i].append(min(1,max(0,t))); cuts[j].append(min(1,max(0,u))) }
                } else if abs(cross(b-a,r))<1e-7 {
                    for p in [b,b+s] { let t=dot(p-a,r)/rr; if t>0 && t<1 { cuts[i].append(t) } }
                    for p in [a,a+r] { let t=dot(p-b,s)/ss; if t>0 && t<1 { cuts[j].append(t) } }
                }
            }
        }
        var nodes:[SIMD2<Double>]=[], map:[Key:Int]=[:], edges=Set<Edge>()
        func node(_ p:SIMD2<Double>)->Int { let k=Key(p); if let i=map[k] { return i }; let i=nodes.count; nodes.append(p); map[k]=i; return i }
        for i in segments.indices {
            let ts=cuts[i].sorted(),l=segments[i]
            for k in 1..<ts.count where ts[k]-ts[k-1]>1e-9 {
                let a=node(l.a+(l.b-l.a)*ts[k-1]),b=node(l.a+(l.b-l.a)*ts[k]); if a != b { edges.insert(Edge(a,b)) }
            }
        }
        guard edges.count<24000 else { throw Failure(message:"亀裂の交点が多すぎます。") }
        var adj=Array(repeating:[Int](),count:nodes.count)
        for e in edges { adj[e.a].append(e.b); adj[e.b].append(e.a) }
        // Prune dangling scars; they remain in the material map.
        var queue=nodes.indices.filter { adj[$0].count==1 }
        while let n=queue.popLast(),let b=adj[n].first {
            adj[n]=[]; adj[b].removeAll{$0==n}; if adj[b].count==1 { queue.append(b) }
        }
        for i in nodes.indices { adj[i].sort { let a=nodes[$0]-nodes[i],b=nodes[$1]-nodes[i]; return atan2(a.y,a.x)<atan2(b.y,b.x) } }
        var visited=Set<UInt64>(),faces:[[SIMD2<Double>]]=[]
        func key(_ a:Int,_ b:Int)->UInt64 { UInt64(a)<<32|UInt64(b) }
        func appendLoops(_ ids:[Int]) {
            var stack:[Int]=[],positions:[Int:Int]=[:]
            for n in ids+[ids[0]] {
                if let start=positions[n] {
                    let loop=Array(stack[start...]); if loop.count>=3 {
                        let p=loop.map{nodes[$0]}; if area(p)>1e-7 { faces.append(p) }
                    }
                    for id in stack[(start+1)...] { positions.removeValue(forKey:id) }
                    stack=Array(stack[...start])
                } else { positions[n]=stack.count; stack.append(n) }
            }
        }
        for a in nodes.indices { for b in adj[a] where !visited.contains(key(a,b)) {
            var u=a,v=b,loop:[Int]=[]
            repeat {
                if !visited.insert(key(u,v)).inserted { break }
                loop.append(u)
                guard let index=adj[v].firstIndex(of:u),!adj[v].isEmpty else { break }
                let next=adj[v][(index+adj[v].count-1)%adj[v].count]; u=v; v=next
            } while u != a || v != b
            if loop.count>=3 { appendLoops(loop) }
        } }
        let total=faces.reduce(0){$0+area($1)}
        guard abs(total-210*360)<0.01 else { throw Failure(message:"破片領域の面積を検証できませんでした。 area=\(total), faces=\(faces.count)") }
        return faces
    }

    /// Sutherland–Hodgman on each exterior face, followed by a shared cut cap.
    private static func clip(_ mesh:[Triangle],point:SIMD2<Double>,normal:SIMD2<Double>,cap:Bool=true,wallRange:(SIMD2<Double>,SIMD2<Double>)?=nil) throws -> [Triangle] {
        var result:[Triangle]=[], segments:[(SIMD3<Double>,SIMD3<Double>)]=[]
        func distance(_ v:Vertex)->Double { dot(SIMD2(v.p.x,v.p.y)-point,normal) }
        for tri in mesh {
            try Task.checkCancellation()
            let distances=tri.v.map(distance)
            if distances.allSatisfy({ $0 >= -1e-8 }) { if wallRange==nil { result.append(tri) }; continue }
            if distances.allSatisfy({ $0 < -1e-8 }) { continue }
            var out:[Vertex]=[], intersections:[SIMD3<Double>]=[]
            for k in 0..<3 {
                let a=tri.v[k],b=tri.v[(k+1)%3],da=distance(a),db=distance(b)
                let insideA=da >= -1e-8, insideB=db >= -1e-8
                if insideA { out.append(a) }
                if insideA != insideB {
                    let v=Vertex.mix(a,b,min(1,max(0,da/(da-db))))
                    out.append(v); intersections.append(v.p)
                }
            }
            if out.count>=3 && wallRange==nil {
                for k in 1..<(out.count-1) {
                    if length_squared(cross(out[k].p-out[0].p,out[k+1].p-out[0].p))>1e-18 { result.append(.init(v:[out[0],out[k],out[k+1]])) }
                }
            }
            if intersections.count==2,length_squared(intersections[0]-intersections[1])>1e-16 { segments.append((intersections[0],intersections[1])) }
        }
        if !cap { return result }
        if wallRange != nil { result=[] }
        if segments.isEmpty { return result }
        var ps:[SIMD3<Double>]=[],map:[Key:Int]=[:],adj:[Int:[Int]]=[:]
        func node(_ p:SIMD3<Double>)->Int { let k=Key(p); if let i=map[k] { return i }; let i=ps.count; ps.append(p); map[k]=i; return i }
        for (a,b) in segments { let i=node(a),j=node(b); if i != j { adj[i,default:[]].append(j); adj[j,default:[]].append(i) } }
        var used=Set<Edge>()
        let tangent=SIMD2(normal.y,-normal.x),outward=SIMD3(-normal.x,-normal.y,0.0)
        for start in adj.keys.sorted() { for next in adj[start,default:[]] where !used.contains(Edge(start,next)) {
            var ids=[start],a=start,b=next
            while b != start {
                guard used.insert(Edge(a,b)).inserted else { break }
                ids.append(b)
                guard let c=adj[b,default:[]].first(where: { $0 != a && !used.contains(Edge(b,$0)) }) else { break }
                a=b; b=c
            }
            guard b==start,ids.count>=3 else { throw Failure(message:"破断面を閉じられませんでした。") }
            used.insert(Edge(a,b))
            var vertices=ids.map { ps[$0] }
            if let (a,b)=wallRange {
                let dir=normalize(b-a)
                for (point,n) in [(a,dir),(b,-dir)] {
                    var clipped:[SIMD3<Double>]=[]
                    for i in vertices.indices {
                        let v=vertices[i],w=vertices[(i+1)%vertices.count]
                        let dv=dot(SIMD2(v.x,v.y)-point,n),dw=dot(SIMD2(w.x,w.y)-point,n)
                        if dv >= -1e-8 { clipped.append(v) }
                        if (dv >= -1e-8) != (dw >= -1e-8) { clipped.append(v+(w-v)*(dv/(dv-dw))) }
                    }
                    vertices=clipped
                }
            }
            // Remove duplicate consecutive intersections (including an endpoint on the plane).
            var clean:[SIMD3<Double>]=[]
            for v in vertices { if clean.last.map({length_squared(v-$0)>1e-14}) ?? true { clean.append(v) } }
            if clean.count>1,length_squared(clean[0]-clean.last!)<1e-14 { clean.removeLast() }
            vertices=clean
            if vertices.count<3 { continue }
            var poly=vertices.map { SIMD2(dot(SIMD2($0.x,$0.y),tangent),$0.z) }
            if abs(area(poly))<1e-10 { continue }
            if area(poly)<0 { vertices.reverse(); poly.reverse() }
            // Preserve all boundary vertices to avoid cracks between adjacent cut surfaces.
            for cap in try triangulate(poly) {
                var verts=cap.map { Vertex(p:vertices[$0],n:outward,surface:false) }
                if dot(cross(verts[1].p-verts[0].p,verts[2].p-verts[0].p),outward)<0 { verts.swapAt(1,2) }
                result.append(.init(v:verts))
            }
        } }
        return result
    }
}

extension GlassBreakGeometry {
    /// Bounded visual fallback: 12 large 12-mm fragments, independent of game scoring and crack count.
    /// Uses a rectangular proxy for the beveled pane only after destruction begins.
    static func coarse()->Result {
        var fragments:[Fragment]=[]
        let faces:[[Int]]=[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]]
        for row in 0..<4 {for col in 0..<3 {
            let center=SIMD3<Float>(Float(col)*70-70,Float(row)*90-135,0)
            var v:[SIMD3<Float>]=[]
            for z:Float in [-1,1] {for y:Float in [-1,1] {for x:Float in [-1,1] {v.append(SIMD3(x*35,y*45,z*6))}}}
            var triangles:[GlassRayTriangle]=[]
            for face in faces {for ids in [[face[0],face[1],face[2]],[face[0],face[2],face[3]]] {
                let a=v[ids[0]],b=v[ids[1]],c=v[ids[2]],n=simd_normalize(simd_cross(b-a,c-a))
                let surface:Float=abs(n.z)>0.9 ? 1:0
                triangles.append(.init(a:SIMD4(a,1),b:SIMD4(b,1),c:SIMD4(c,1),na:SIMD4(n,surface),nb:SIMD4(n,surface),nc:SIMD4(n,surface)))
            }}
            fragments.append(.init(triangles:triangles,center:center,volume:70*90*12))
        }}
        return .init(fragments:fragments,completion:[],sourceVolume:210*360*12,volumeError:0)
    }
}
