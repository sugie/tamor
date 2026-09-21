import Foundation
import simd
var checks=0
func check(_ value:@autoclosure()->Bool,_ message:String) { checks+=1;if !value() { fatalError(message) } }
check(JewelKind.worldOne.count==4,"Four original kinds")
for count in [4,12] {
    for angle in [-31.7,-1.4,0,0.4,43.9] {
        check(RingLayoutMath.hit(point:.zero,count:count,angle:angle)==nil,"Center must stay empty")
        for i in 0..<count {
            let p=RingLayoutMath.position(index:i,count:count,angle:angle)
            check(RingLayoutMath.hit(point:p,count:count,angle:angle)==i,"Rendered position must match tap")
        }
        let snapped=RingLayoutMath.snapTarget(count:count,angle:angle)
        let selected=RingLayoutMath.nearest(count:count,angle:snapped)
        let p=RingLayoutMath.position(index:selected,count:count,angle:snapped)
        check(abs(p.x)<0.00001 && p.y < -0.65,"Selected jewel snaps to bottom marker")
        check(abs(snapped-angle)<=Double.pi/Double(count),"Nearest snap only")
    }
}
check(ObservationLevel.resolved(zoom:0.60,previous:.whole) == .whole,"Zoom boundary hysteresis")
check(ObservationLevel.resolved(zoom:0.64,previous:.whole) == .surface,"Zoom advances")
check(ObservationLevel.resolved(zoom:0.40,previous:.surface) == .surface,"No boundary flicker")
check(ObservationLevel.resolved(zoom:0.37,previous:.surface) == .whole,"Zoom reverses")
check(ObservationLevel.resolved(zoom:3,previous:.whole) == .atoms,"Fast pinch crosses levels")
check(ObservationLevel.resolved(zoom:0,previous:.atoms) == .whole,"Fast pinch returns")
let lattice=CrystalLattice.diamond()
check(lattice.atoms.count==512,"Bounded lattice")
check(lattice.bonds.count<1024,"Bounded bond instances")
var degree=Array(repeating:0,count:lattice.atoms.count)
var unique=Set<String>()
for b in lattice.bonds {
    check(b.first<b.second,"Unique undirected edges")
    check(unique.insert("\(b.first)-\(b.second)").inserted,"No duplicate edges")
    degree[b.first]+=1;degree[b.second]+=1
    let a=lattice.atoms[b.first].position,c=lattice.atoms[b.second].position
    check(abs(simd_distance(a,c)-sqrt(Float(3))/4)<0.00001,"Diamond nearest-neighbor length")
    let m=JewelMatrices.bond(from:a,to:c,radius:0.032)
    let lo=m*SIMD4<Float>(0,-0.5,0,1),hi=m*SIMD4<Float>(0,0.5,0,1)
    check(simd_distance(SIMD3(lo.x,lo.y,lo.z),a)<0.00001,"Bond first endpoint")
    check(simd_distance(SIMD3(hi.x,hi.y,hi.z),c)<0.00001,"Bond second endpoint")
}
check(degree.max()==4,"Carbon has four neighbors")
check(degree.min()!>0,"No floating atoms")
print("PASS: \(checks) checks; \(lattice.atoms.count) atoms, \(lattice.bonds.count) bonds")
