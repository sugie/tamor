import SwiftUI

struct MiniGameScreen:View {
    @ObservedObject var state:JewelSceneState
    @ObservedObject var session:JewelMiniSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared=false
    @State private var exitPrompt=false
    var body:some View {
        GeometryReader { geo in
            let boardSide=min(480,min(geo.size.width,geo.size.height*0.62))
            VStack(spacing:12) {
                HStack {
                    Button { if session.readyForResult { state.finishGame() } else { session.pause();exitPrompt=true } } label:{Image(systemName:"xmark").frame(width:44,height:40)}.accessibilityLabel("ゲームを終了").accessibilityIdentifier("mini.close")
                    Spacer();VStack(spacing:3){Text(L(session.kind.game.title)).font(.system(size:18,weight:.light));Text(L(session.kind.name)+(session.preview ? L(" · 練習"):"")).font(.system(size:10)).foregroundStyle(jewelGold)};Spacer()
                    Button { session.pause() } label:{Image(systemName:"pause").frame(width:44,height:40)}.accessibilityIdentifier("mini.pause").disabled(session.readyForResult)
                }
                stats.padding(.horizontal,24)
                ZStack {
                    if session.kind.game != .kurukuru {
                        GlassStudyMetalView(settings:session.glass,error:$session.renderError,status:$session.glassStatus,onBreakFinished:{_ in session.finishShatter()},onBreakFailed:{message in session.finishShatter(error:message)})
                            .accessibilityHidden(true)
                            .opacity(appeared ? 1:0).scaleEffect(appeared ? 1:(reduceMotion ? 1:0.78))
                            .animation(.easeOut(duration:reduceMotion ? 0.2:0.8),value:appeared)
                    }
                    MiniGameMetalView(session:session)
                    if session.engine.phase == .paused || session.engine.phase == .countdown {
                        jewelBackground.opacity(0.88)
                        VStack(spacing:20) {
                            Text(session.engine.phase == .paused ? L("一時停止"):"\(session.engine.countdown)").font(.system(size:38,weight:.ultraLight)).accessibilityIdentifier("mini.paused")
                            if session.engine.phase == .countdown {Text(session.kind.game == .grassBreak ? String(format:L("赤い点を%.2f秒以内にタップ"),session.engine.breakDuration):session.kind.game == .kurukuru ? L("同じ方向に回る宝石を2つ選ぶ"):L("まもなく再開します")).font(.footnote)}
                            if session.engine.phase == .paused { Button("再開する"){session.resume()}.tint(jewelGold).accessibilityIdentifier("mini.resume") }
                        }
                    }
                    if let error=session.renderError { Text(L(error)).padding().background(jewelBackground).accessibilityIdentifier("mini.error") }
                }.frame(maxWidth:session.kind.game == .kurukuru ? boardSide:480).frame(height:session.kind.game == .kurukuru ? boardSide:geo.size.height*0.62)
                    .anchorPreference(key:TraceCanvasBounds.self,value:.bounds){$0}
                controls.padding(.horizontal,24)
                Spacer(minLength:0)
            }.padding(.top,6).frame(maxWidth:.infinity)
        }.overlayPreferenceValue(TraceCanvasBounds.self) {anchor in
            GeometryReader {geo in
                if let anchor,session.kind.game == .grassTrace,[.ready,.playing].contains(session.engine.phase),session.inputReady {
                    let canvas=geo[anchor]
                    let local=GlassTargetProjection.point(session.engine.target,size:canvas.size,settings:session.glass)
                    TraceGuides(center:CGPoint(x:canvas.minX+local.x,y:canvas.minY+local.y))
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }.background(jewelBackground.ignoresSafeArea()).foregroundStyle(jewelWhite).preferredColorScheme(.dark)
            .onAppear { appeared=true }
            .onDisappear { if state.game?.id != session.id {session.stop()} }
            .onChange(of:session.glassStatus) { _,status in if status.gpuMS>0 || status.cpuMS>0 {session.observeFrame(cpuMS:status.cpuMS,gpuMS:status.gpuMS)} }
            .onChange(of:scenePhase) { _,v in if v != .active {session.pause()} }
            .confirmationDialog("リングに戻りますか？",isPresented:$exitPrompt,titleVisibility:.visible) {
                Button("報酬なしで終了",role:.destructive){state.finishGame()};Button("プレイに戻る",role:.cancel){session.resume()}
            }
            .task(id:session.engine.phase) {
                if session.engine.phase == .won {
                    await state.claim(session)
                    if session.claimed {
                        while !session.canCelebrate && !Task.isCancelled {try? await Task.sleep(for:.milliseconds(100))}
                        guard !Task.isCancelled else {return}
                        try? await Task.sleep(for:.seconds(4))
                        if !Task.isCancelled,state.game?.id==session.id {state.finishGame()}
                    }
                }
            }
    }
    private var stats:some View {
        HStack {
            if session.kind.game == .kurukuru {
                Label("\(session.engine.board.size)×\(session.engine.board.size)",systemImage:"square.grid.2x2").accessibilityIdentifier("mini.size")
                Spacer();Text("残り \(session.engine.remaining)").accessibilityIdentifier("mini.remaining")
            } else {
                Text("GLASS 12 mm").accessibilityIdentifier("mini.thickness").accessibilityValue(L(session.shatterFinished ? "破砕完了":"ガラスあり"));Spacer()
                Text(session.kind.game == .grassTrace ? String(format:L("ヒビ %lld / 3"),session.engine.cracks.count):"\(session.engine.hits) / \(session.engine.requiredHits) HIT").accessibilityIdentifier("mini.count")
            }
            Spacer();Text(GameClock.display(session.engine.elapsed)).monospacedDigit().accessibilityIdentifier("mini.time")
        }.font(.system(size:11,design:.monospaced)).foregroundStyle(jewelGold)
    }
    private var controls:some View {
        VStack(spacing:12) {
            switch session.engine.phase {
            case .intro:Text("光を集めています…").font(.callout).foregroundStyle(.secondary)
            case .ready:
                if session.kind.game == .grassTrace {
                    Text("緑の点に指を合わせてスタート").font(.system(size:16,weight:.medium)).accessibilityIdentifier("mini.traceReady")
                    Text("縦横のガイドが交わる緑の点を追跡。終点で0.3秒保持。ヒビ3つで失敗。").font(.system(size:11)).foregroundStyle(.secondary)
                } else if session.kind.game == .grassBreak {
                    Text("ガラスを準備中。3秒後に自動で始まります。").font(.footnote)
                } else {
                    Text("盤面を準備中。3秒後に自動で始まります。").font(.footnote)
                }
            case .playing:
                Text(L(session.kind.game == .kurukuru ? "対象の宝石が対になって回転しています。" : session.kind.game == .grassTrace ? "緑の点を追いかけてください。":"赤い点をタップして、ガラスを割ろう。")).font(.system(size:12)).foregroundStyle(.secondary)
                if session.kind.game == .grassTrace {ProgressView(value:min(1,session.engine.elapsed/(session.engine.traceDuration+0.3))).tint(.green)}
                if session.kind.game == .grassBreak {ProgressView(value:max(0,min(1,((session.engine.deadline ?? session.engine.activeTime+session.engine.breakDuration)-session.engine.activeTime)/session.engine.breakDuration))).tint(.red)}
            case .won:
                if !session.canCelebrate {ProgressView("ガラスを砕いています…").tint(jewelGold)}
                else {
                Text(session.preview ? L("練習クリア"):String(format:L("%@を獲得！"),L(session.kind.name))).font(.system(size:25,weight:.light,design:.serif)).foregroundStyle(jewelGold).accessibilityIdentifier("reward.title")
                Text(GemScale.label(session.rewardCarats)+" · "+L(session.grade.rawValue)).font(.system(size:16,design:.monospaced)).accessibilityIdentifier("reward.size")
                if session.claimed { Text(L(session.preview ? "プレビューのため所持は変わりません。":"保存しました。まもなくリングへ戻ります。")).font(.system(size:11)).foregroundStyle(.secondary).accessibilityIdentifier("reward.saved");Button("リングに戻る"){state.finishGame()}.accessibilityIdentifier("reward.back") }
                else if state.savingReward {ProgressView("報酬を保存中")}
                else {Text(L(state.saveMessage ?? "報酬を保存してください。")).font(.footnote);Button("保存を再試行"){Task{await state.claim(session)}}.accessibilityIdentifier("reward.retry")}
                }
            case .lost:
                Text("チャレンジ失敗").font(.title2).accessibilityIdentifier("mini.failure")
                Text(L(session.engine.failure ?? "")+L("。報酬はありません。")).font(.footnote).foregroundStyle(.secondary)
                Button {state.finishGame()} label:{goldButton(L("リングに戻る"),icon:"arrow.left")}.accessibilityIdentifier("failure.back")
            case .paused,.countdown:EmptyView()
            }
        }.multilineTextAlignment(.center)
    }
}

/// Display-only lookup in Localizable.xcstrings. Keys are the existing Japanese strings, so a missing
/// entry (or an unregistered catalog) shows the Japanese text unchanged. Never pass saved IDs through this.
func L(_ key:String)->String {key.isEmpty ? key:Bundle.main.localizedString(forKey:key,value:key,table:nil)}

private struct TraceCanvasBounds:PreferenceKey {
    static var defaultValue:Anchor<CGRect>?
    static func reduce(value:inout Anchor<CGRect>?,nextValue:()->Anchor<CGRect>?) {value=nextValue() ?? value}
}
private struct TraceGuides:View {
    let center:CGPoint
    var body:some View {
        Canvas {context,size in
            var lines=Path()
            lines.move(to:CGPoint(x:0,y:center.y));lines.addLine(to:CGPoint(x:size.width,y:center.y))
            lines.move(to:CGPoint(x:center.x,y:0));lines.addLine(to:CGPoint(x:center.x,y:size.height))
            context.stroke(lines,with:.color(.black.opacity(0.35)),lineWidth:3)
            context.stroke(lines,with:.color(.green.opacity(0.60)),lineWidth:1)
            var cross=Path()
            for sign:CGFloat in [-1,1] {
                cross.move(to:CGPoint(x:center.x+sign*12,y:center.y));cross.addLine(to:CGPoint(x:center.x+sign*30,y:center.y))
                cross.move(to:CGPoint(x:center.x,y:center.y+sign*12));cross.addLine(to:CGPoint(x:center.x,y:center.y+sign*30))
            }
            context.stroke(cross,with:.color(.black.opacity(0.8)),lineWidth:5)
            context.stroke(cross,with:.color(.white.opacity(0.95)),lineWidth:2)
            let ring=Path(ellipseIn:CGRect(x:center.x-10,y:center.y-10,width:20,height:20))
            context.stroke(ring,with:.color(.green),lineWidth:2)
            for p in [CGPoint(x:5,y:center.y),CGPoint(x:size.width-5,y:center.y),CGPoint(x:center.x,y:5),CGPoint(x:center.x,y:size.height-5)] {
                context.fill(Path(ellipseIn:CGRect(x:p.x-3,y:p.y-3,width:6,height:6)),with:.color(.green))
            }
        }.accessibilityIdentifier("trace.guides")
    }
}
