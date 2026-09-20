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
            VStack(spacing:12) {
                HStack {
                    Button { if session.readyForResult { state.finishGame() } else { session.pause();exitPrompt=true } } label:{Image(systemName:"xmark").frame(width:44,height:40)}.accessibilityLabel("ゲームを終了").accessibilityIdentifier("mini.close")
                    Spacer();VStack(spacing:3){Text(session.kind.game.title).font(.system(size:18,weight:.light));Text(session.kind.name+(session.preview ? " · 練習":"")).font(.system(size:10)).foregroundStyle(jewelGold)};Spacer()
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
                            Text(session.engine.phase == .paused ? "一時停止":"\(session.engine.countdown)").font(.system(size:38,weight:.ultraLight)).accessibilityIdentifier("mini.paused")
                            if session.engine.phase == .countdown {Text(session.kind.game == .grassBreak ? "赤い点を1.5秒以内にタップ":"まもなく再開します").font(.footnote)}
                            if session.engine.phase == .paused { Button("再開する"){session.resume()}.tint(jewelGold).accessibilityIdentifier("mini.resume") }
                        }
                    }
                    if let error=session.renderError { Text(error).padding().background(jewelBackground).accessibilityIdentifier("mini.error") }
                }.frame(maxWidth:480).frame(height:session.kind.game == .kurukuru ? min(geo.size.width,geo.size.height*0.62):geo.size.height*0.62)
                controls.padding(.horizontal,24)
                Spacer(minLength:0)
            }.padding(.top,6).frame(maxWidth:.infinity)
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
                Text("GLASS 12 mm").accessibilityIdentifier("mini.thickness").accessibilityValue(session.shatterFinished ? "破砕完了":"ガラスあり");Spacer()
                Text(session.kind.game == .grassTrace ? "ヒビ \(session.engine.cracks.count) / 3":"\(session.engine.hits) / \(session.engine.requiredHits) HIT").accessibilityIdentifier("mini.count")
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
                    Text("15秒追跡して終点で0.3秒保持。ヒビ3つで失敗。距離は設定で調整できます。").font(.system(size:11)).foregroundStyle(.secondary)
                } else if session.kind.game == .grassBreak {
                    Text("ガラスを準備中。3秒後に自動で始まります。").font(.footnote)
                } else {
                    Text(session.kind.game == .kurukuru ? "同じ方向に回る宝石を2つ選ぶ":"赤く光る点を1.5秒以内にタップ").font(.system(size:12)).foregroundStyle(.secondary)
                    Button {session.begin()} label:{goldButton("スタート",icon:"play.fill")}.accessibilityIdentifier("mini.start").disabled(!session.inputReady)
                }
            case .playing:
                Text(session.kind.game == .kurukuru ? "対象の宝石が対になって回転しています。" : session.kind.game == .grassTrace ? "緑の点を追いかけてください。":"赤い点をタップして、ガラスを割ろう。").font(.system(size:12)).foregroundStyle(.secondary)
                if session.kind.game == .grassTrace {ProgressView(value:min(1,session.engine.elapsed/15.3)).tint(.green)}
                if session.kind.game == .grassBreak {ProgressView(value:max(0,min(1,((session.engine.deadline ?? session.engine.activeTime+1.5)-session.engine.activeTime)/1.5))).tint(.red)}
            case .won:
                if !session.canCelebrate {ProgressView("ガラスを砕いています…").tint(jewelGold)}
                else {
                Text(session.preview ? "練習クリア":"\(session.kind.name)を獲得！").font(.system(size:25,weight:.light,design:.serif)).foregroundStyle(jewelGold).accessibilityIdentifier("reward.title")
                Text(String(format:"SIZE ×%.1f",session.rewardSize)).font(.system(size:16,design:.monospaced)).accessibilityIdentifier("reward.size")
                if session.claimed { Text(session.preview ? "プレビューのため所持は変わりません。":"保存しました。まもなくリングへ戻ります。").font(.system(size:11)).foregroundStyle(.secondary).accessibilityIdentifier("reward.saved");Button("リングに戻る"){state.finishGame()}.accessibilityIdentifier("reward.back") }
                else if state.savingReward {ProgressView("報酬を保存中")}
                else {Text(state.saveMessage ?? "報酬を保存してください。").font(.footnote);Button("保存を再試行"){Task{await state.claim(session)}}.accessibilityIdentifier("reward.retry")}
                }
            case .lost:
                Text("チャレンジ失敗").font(.title2).accessibilityIdentifier("mini.failure")
                Text((session.engine.failure ?? "")+"。報酬はありません。").font(.footnote).foregroundStyle(.secondary)
                Button {state.finishGame()} label:{goldButton("リングに戻る",icon:"arrow.left")}.accessibilityIdentifier("failure.back")
            case .paused,.countdown:EmptyView()
            }
        }.multilineTextAlignment(.center)
    }
}
