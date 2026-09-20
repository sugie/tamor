import Foundation

enum QualityPreference: String, CaseIterable, Identifiable {
    case automatic, lowPower, standard, high
    var id:String {rawValue}
    var title:String { switch self {case .automatic:"自動";case .lowPower:"省電力";case .standard:"標準";case .high:"高品質"} }
}
enum QualityTier:Int {case low,standard,high
    var glassPixels:Int { [320,512,768][rawValue] }
    var particles:Int { [12,24,36][rawValue] }
    var title:String { ["省電力","標準","高品質"][rawValue] }
}
struct RenderQualityPolicy {
    var preference:QualityPreference = .automatic
    private(set) var automaticTier:QualityTier = .standard
    private var slow=0,fast=0
    mutating func observe(cpuMS:Double,gpuMS:Double) {
        let duration=max(cpuMS,gpuMS)
        guard duration>0,duration.isFinite else {return}
        if duration>19 {slow+=1;fast=0} else if duration<10 {fast+=1;slow=max(0,slow-1)} else {slow=max(0,slow-1);fast=0}
        if slow>=30 {automaticTier=QualityTier(rawValue:max(0,automaticTier.rawValue-1))!;slow=0}
        if fast>=240 {automaticTier=QualityTier(rawValue:min(2,automaticTier.rawValue+1))!;fast=0}
    }
    func effective(thermal:ProcessInfo.ThermalState,lowPower:Bool)->QualityTier {
        if lowPower || thermal == .serious || thermal == .critical {return .low}
        let wanted:QualityTier
        switch preference {case .automatic:wanted=automaticTier;case .lowPower:wanted = .low;case .standard:wanted = .standard;case .high:wanted = .high}
        return thermal == .fair && wanted == .high ? .standard:wanted
    }
}
