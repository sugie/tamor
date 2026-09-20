import SwiftUI
import MetalKit
import simd

struct JewelMetalView:UIViewRepresentable {
    @ObservedObject var state:JewelSceneState
    func makeCoordinator()->JewelRenderer? {
        do { return try JewelRenderer(state:state) }
        catch { DispatchQueue.main.async { state.error=error.localizedDescription };return nil }
    }
    func makeUIView(context:Context)->JewelTouchView {
        let view=JewelTouchView(frame:.zero,device:context.coordinator?.device)
        view.state=state;view.delegate=context.coordinator;view.preferredFramesPerSecond=60
        view.colorPixelFormat = .bgra8Unorm_srgb;view.depthStencilPixelFormat = .depth32Float
        view.clearColor=MTLClearColor(red:0.025,green:0.043,blue:0.063,alpha:1)
        view.isOpaque=true;view.accessibilityIdentifier="jewel.scene"
        return view
    }
    func updateUIView(_ view:JewelTouchView,context:Context) { view.isPaused=state.paused;view.refreshAccessibility() }
}

final class JewelAccessibilityElement:UIAccessibilityElement {
    weak var state:JewelSceneState?
    var index=0
    override func accessibilityActivate()->Bool { state?.activate(index);return true }
}

final class JewelTouchView:MTKView {
    weak var state:JewelSceneState?
    private var panStarted=false
    private var angle:Double=0
    private var timestamp:CFTimeInterval=0
    private var initialYaw:Float=0
    private var initialPitch:Float=0
    private var initialZoom:Double=0
    private var axItems:[JewelAccessibilityElement]=[]
    private var axKeys = ""
    private var labels:[Int:UILabel]=[:]
    private lazy var tap=UITapGestureRecognizer(target:self,action:#selector(tapped(_:)))
    private lazy var doubleTap=UITapGestureRecognizer(target:self,action:#selector(doubleTapped(_:)))
    private lazy var pan=UIPanGestureRecognizer(target:self,action:#selector(panned(_:)))
    private lazy var pinch=UIPinchGestureRecognizer(target:self,action:#selector(pinched(_:)))
    override init(frame:CGRect,device:MTLDevice?) {
        super.init(frame:frame,device:device)
        pan.maximumNumberOfTouches=1
        doubleTap.numberOfTapsRequired=2
        addGestureRecognizer(tap);addGestureRecognizer(doubleTap);addGestureRecognizer(pan);addGestureRecognizer(pinch)
        tap.require(toFail:doubleTap);doubleTap.require(toFail:pan);doubleTap.require(toFail:pinch)
        tap.require(toFail:pan);tap.require(toFail:pinch)
    }
    required init(coder:NSCoder) { fatalError("Programmatic view") }
    override func didMoveToWindow() {
        super.didMoveToWindow();var parent=superview
        while let v=parent {
            if let scroll=v as? UIScrollView { scroll.panGestureRecognizer.require(toFail:pan);break }
            parent=v.superview
        }
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) {
        if let state,!state.inspecting { state.stopMotionForTouch() }
        super.touchesBegan(touches,with:event)
    }
    override func layoutSubviews() { super.layoutSubviews();refreshAccessibility() }
    private func normalized(_ p:CGPoint)->SIMD2<Double> {
        SIMD2(2*Double(p.x/max(1,bounds.width))-1,1-2*Double(p.y/max(1,bounds.height)))
    }
    @objc private func tapped(_ g:UITapGestureRecognizer) {
        guard let state,!state.paused,!state.inspecting else { return }
        if let jewel=state.hit(normalized(g.location(in:self))) { state.activate(jewel.rawValue) }
    }
    @objc private func doubleTapped(_ g:UITapGestureRecognizer) {
        guard let state,!state.paused else { return }
        if state.inspecting { state.startGame(state.kind,previewOnly:state.save.inventory[state.kind.key]==nil);return }
        if let jewel=state.hit(normalized(g.location(in:self))) { state.startGame(jewel,previewOnly:state.visible.contains(jewel) && state.save.inventory[jewel.key]==nil) }
    }
    @objc private func panned(_ g:UIPanGestureRecognizer) {
        guard let state,!state.paused else { return }
        let point=normalized(g.location(in:self)),now=CACurrentMediaTime()
        if state.inspecting {
            if g.state == .began { initialYaw=state.yaw;initialPitch=state.pitch }
            let t=g.translation(in:self)
            state.yaw=initialYaw+Float(t.x)*0.009
            state.pitch=min(1.2,max(-1.2,initialPitch+Float(t.y)*0.009));return
        }
        switch g.state {
        case .began:
            let t=g.translation(in:self),p=g.location(in:self)
            let origin=normalized(CGPoint(x:p.x-t.x,y:p.y-t.y))
            panStarted=simd_length(origin)>0.35
            guard panStarted else { return }
            state.dragging=true;state.snap=nil;state.velocity=0
            angle=atan2(point.x,-point.y);timestamp=now
        case .changed:
            guard panStarted,simd_length(point)>0.25 else { return }
            let a=atan2(point.x,-point.y),delta=RingLayoutMath.wrapped(a-angle)
            state.ringAngle+=delta
            state.velocity=min(6,max(-6,delta/max(0.008,now-timestamp)))
            state.moved()
            angle=a;timestamp=now
        case .ended,.cancelled,.failed:
            state.dragging=false;panStarted=false
            if g.state != .ended || state.reduceMotion || now-timestamp>0.1 { state.velocity=0 }
            if state.reduceMotion { state.ringAngle=RingLayoutMath.snapTarget(count:12,angle:state.ringAngle) }
        default: break
        }
    }
    @objc private func pinched(_ g:UIPinchGestureRecognizer) {
        guard let state,state.inspecting,!state.paused else { return }
        if g.state == .began { initialZoom=state.zoom }
        state.setZoom(initialZoom+log2(max(0.01,Double(g.scale)))*1.2)
    }
    func refreshAccessibility() {
        guard let state else { return }
        let list=state.inspecting ? []:JewelKind.allCases
        let keys=list.map(\.key).joined(separator:",")
        if axKeys != keys {
            axItems=list.map { jewel in
                let e=JewelAccessibilityElement(accessibilityContainer:self);e.state=state;e.index=jewel.rawValue
                e.accessibilityIdentifier="jewel.\(jewel.key)";e.accessibilityLabel=jewel.name
                e.accessibilityHint="観察する。ゲームは詳細の開始ボタンからも起動できます。";return e
            };accessibilityElements=axItems;axKeys=keys
        }
        for jewel in JewelKind.allCases {
            let label=labels[jewel.rawValue] ?? UILabel()
            if labels[jewel.rawValue]==nil {label.font = .systemFont(ofSize:9,weight:.medium);label.textAlignment = .center;label.numberOfLines=2;label.isUserInteractionEnabled=false;label.isAccessibilityElement=false;addSubview(label);labels[jewel.rawValue]=label}
            let owned=state.save.inventory[jewel.key] != nil
            label.text=state.visible.contains(jewel) ? "":jewel.name+"\n"+jewel.game.title
            label.textColor=UIColor(red:0.8,green:0.7,blue:0.52,alpha:owned ? 0.6:0.9)
            label.alpha=1-state.inspectionProgress
            let p=state.position(jewel)
            label.frame=CGRect(x:(p.x+1)*bounds.width/2-55,y:(1-p.y)*bounds.height/2+bounds.width*0.058,width:110,height:30)
        }
        for e in axItems {
            guard let jewel=JewelKind(rawValue:e.index) else { continue }
            let p=state.position(jewel),size=max(44,bounds.width*0.22*min(1.8,state.save.inventory[jewel.key]?.size ?? 1))
            e.accessibilityFrameInContainerSpace=CGRect(x:(p.x+1)*Double(bounds.width)/2-Double(size)/2,y:(1-p.y)*Double(bounds.height)/2-Double(size)/2,width:Double(size),height:Double(size))
            let frame=e.accessibilityFrameInContainerSpace
            e.accessibilityActivationPoint=UIAccessibility.convertToScreenCoordinates(CGRect(x:frame.midX,y:frame.midY,width:0,height:0),in:self).origin
            e.accessibilityLabel=jewel.name+(state.visible.contains(jewel) ? "":"・未獲得・"+jewel.game.title+"を開始")
            e.accessibilityTraits=state.selected==e.index ? [.button,.selected]:[.button]
        }
    }
}
