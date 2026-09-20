import SwiftUI
import UniformTypeIdentifiers

let jewelBackground=Color(red:0.025,green:0.043,blue:0.063)
let jewelGold=Color(red:0.80,green:0.68,blue:0.46)
let jewelWhite=Color(red:0.93,green:0.93,blue:0.89)
@main struct TamorApp:App {
    var body:some Scene { WindowGroup { JewelHome() } }
}
struct JewelHome:View {
    @StateObject private var state=JewelSceneState()
    @State private var settings=false
    @State private var games=false
    @State private var pendingGame:JewelKind?
    @State private var importing=false
    @State private var achievements=false
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing:0) {
                    HStack {
                        if state.inspecting {
                            Button { state.back() } label:{Image(systemName:"arrow.left").frame(width:42,height:42)}.accessibilityIdentifier("inspector.back").accessibilityLabel("リングに戻る")
                        } else { Image(systemName:"sparkle").foregroundStyle(jewelGold).frame(width:42,height:42) }
                        Text("T A M O R").font(.system(size:10,weight:.medium)).foregroundStyle(jewelGold)
                        Spacer()
                        Button { settings=true } label:{Image(systemName:"slider.horizontal.3").frame(width:42,height:42)}.accessibilityIdentifier("jewel.settings").accessibilityLabel("表示設定")
                    }.padding(.horizontal,20).padding(.top,8)
                    VStack(alignment:.leading,spacing:7) {
                        HStack {
                            Text(state.inspecting ? state.kind.name:"ジュエルリング").font(.system(size:28,weight:.light,design:.serif)).accessibilityIdentifier(state.inspecting ? "inspector.name":"ring.title")
                            Spacer()
                            Text(state.inspecting ? state.kind.composition:"\(state.ownedCount) / 4").font(.system(size:12,design:.monospaced)).foregroundStyle(jewelGold).accessibilityIdentifier("ring.count")
                        }
                        Text(state.inspecting ? "ピンチで内側へ。ドラッグで角度を変える。":"集めた光を、あなたの軌道に。").font(.system(size:11)).foregroundStyle(.secondary)
                    }.frame(height:90).padding(.horizontal,24)
                    ZStack {
                        JewelMetalView(state:state)
                        if let error=state.error { Text(error).padding().accessibilityIdentifier("render.error") }
                        if state.count==0 && !state.inspecting {
                            VStack(spacing:14) { Image(systemName:"sparkles").font(.system(size:34,weight:.ultraLight)).foregroundStyle(jewelGold);Text("最初の宝石を見つけよう").font(.system(size:16,weight:.light));Text("ミニゲームをクリアすると\nこのリングに宝石が現れます。").font(.system(size:11)).foregroundStyle(.secondary).multilineTextAlignment(.center) }.padding(18).background(jewelBackground.opacity(0.85),in:RoundedRectangle(cornerRadius:16)).allowsHitTesting(false).accessibilityIdentifier("ring.empty")
                        }
                    }.frame(width:min(geo.size.width,480),height:min(geo.size.width,480))
                    if state.inspecting { inspector.padding(.horizontal,24) } else { collection.padding(.horizontal,24) }
                    if let message=state.saveMessage { Text(message).font(.footnote).foregroundStyle(.orange).padding().accessibilityIdentifier("save.message");Button("保存を再試行") { state.persist() }.font(.footnote) }
                    HStack {Text("COLLECTION / LOCAL SAVE");Spacer();Text("EARLY ACCESS")}.font(.system(size:8,design:.monospaced)).foregroundStyle(.secondary).padding(24)
                }.frame(maxWidth:528).frame(maxWidth:.infinity)
            }.scrollBounceBehavior(.basedOnSize)
        }.background(jewelBackground.ignoresSafeArea()).foregroundStyle(jewelWhite).preferredColorScheme(.dark)
            .sheet(isPresented:$settings) { settingsView }
            .sheet(isPresented:$games,onDismiss:{
                if let jewel=pendingGame {pendingGame=nil;state.startGame(jewel)}
            }) { gamePicker }
            .sheet(isPresented:$achievements) { progressView }
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json]) { result in
                if case .success(let url)=result {Task {await state.importSave(url)}}
                else if case .failure(let error)=result {state.saveMessage=error.localizedDescription}
            }
            .fullScreenCover(item:$state.game) { session in MiniGameScreen(state:state,session:session) }
            .onChange(of:settings) { _,_ in syncPause() }.onChange(of:games) { _,_ in syncPause() }
            .onChange(of:achievements) { _,_ in syncPause() }
            .onChange(of:state.game?.id) { _,_ in syncPause() }
            .onChange(of:phase) { _,v in if v != .active { state.persist();state.game?.pause() };syncPause() }
            .onChange(of:reduceMotion) { _,v in state.reduceMotion=v }
            .onAppear { state.reduceMotion=reduceMotion;syncPause();state.persist() }
    }
    private func syncPause() { state.paused=settings || games || achievements || state.game != nil || phase != .active }
    private var collection:some View {
        VStack(spacing:16) {
            if !state.visible.isEmpty {
                HStack {
                    Button { state.selectNext(-1) } label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.accessibilityIdentifier("ring.previous")
                    Spacer()
                    VStack(spacing:6) {
                        Text(state.kind.english).font(.system(size:9,design:.monospaced)).tracking(2).foregroundStyle(jewelGold)
                        Text(state.kind.name).font(.system(size:22,weight:.light)).accessibilityIdentifier("ring.selection")
                        Text(state.save.inventory[state.kind.key].map{String(format:"代表サイズ ×%.1f",$0.size)} ?? "開発プレビュー・未所持").font(.system(size:10)).foregroundStyle(.secondary)
                    }
                    Spacer();Button { state.selectNext(1) } label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.accessibilityIdentifier("ring.next")
                }
                Button { state.inspect(state.selected) } label:{goldButton("宝石を観察する",icon:"arrow.up.right")}.disabled(!state.rendererReady || !state.visible.contains(state.kind)).accessibilityIdentifier("ring.inspect")
                Text("スワイプで回転 · タップで拡大 · ダブルタップでゲーム").font(.system(size:9)).foregroundStyle(.secondary)
            }
            Button { games=true } label:{goldButton("ミニゲームを選ぶ",icon:"play")}.accessibilityIdentifier("ring.games")
            Button {achievements=true} label:{Label("コレクションと自己ベスト",systemImage:"laurel.leading")}.font(.footnote).foregroundStyle(jewelGold).accessibilityIdentifier("ring.progress")
            #if DEBUG
            Button(state.visible.count==4 ? "開発プレビューを終了":"開発用：4つの宝石を比較") {
                if state.visible.count==4 {state.normalVisibility()} else {for jewel in JewelKind.allCases {state.setVisible(jewel,true)}}
            }.font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("ring.preview")
            #endif
        }
    }
    private var inspector:some View {
        VStack(spacing:14) {
            HStack(spacing:6) { ForEach(ObservationLevel.allCases) { level in
                Button { state.setLevel(level) } label:{Text(level.title).font(.system(size:13)).frame(maxWidth:.infinity).padding(.vertical,14).background(state.level==level ? jewelGold.opacity(0.18):Color.white.opacity(0.035),in:RoundedRectangle(cornerRadius:4)).foregroundStyle(state.level==level ? jewelGold:jewelWhite)}.accessibilityIdentifier("level.\(level.rawValue)")
            } }
            Slider(value:Binding(get:{state.zoom},set:{state.setZoom($0)}),in:0...3).tint(jewelGold).accessibilityIdentifier("inspector.zoom").accessibilityLabel("観察倍率")
            HStack {Text("連続ズーム");Spacer();Text(state.level.title).accessibilityIdentifier("inspector.level")}.font(.system(size:10)).foregroundStyle(.secondary)
            Text(state.kind.structureNote).font(.system(size:11)).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("inspector.structure")
            if state.atomCount>0 { Text("\(state.atomCount) 原子 / \(state.bondCount) 結合").font(.system(size:10,design:.monospaced)).foregroundStyle(jewelGold).accessibilityIdentifier("inspector.atoms") }
            Button { state.startGame(state.kind,previewOnly:state.save.inventory[state.kind.key]==nil) } label:{goldButton("\(state.kind.game.title)を始める",icon:"play.fill")}.accessibilityIdentifier("inspector.play")
        }
    }
    private var gamePicker:some View {
        NavigationStack {
            List { Section("挑戦する宝石") { ForEach(JewelKind.allCases) { jewel in
                Button {
                    pendingGame=jewel;games=false
                } label:{HStack {Circle().fill(Color(red:Double(jewel.tint.x),green:Double(jewel.tint.y),blue:Double(jewel.tint.z))).frame(width:18,height:18);VStack(alignment:.leading,spacing:5){Text(jewel.name);Text(jewel.game.title+(jewel.game == .kurukuru ? " · \(state.save.progress[jewel.key] ?? 4)×\(state.save.progress[jewel.key] ?? 4)":" · 初級")).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"play.circle")}}.accessibilityIdentifier("game.pick.\(jewel.key)")
            } } }.navigationTitle("ミニゲーム").toolbar {ToolbarItem(placement:.confirmationAction){Button("閉じる"){games=false}}}
        }.tint(jewelGold)
    }
    private var progressView:some View {
        NavigationStack {List {
            Section("四つの光 · \(state.ownedCount) / 4") {ForEach(JewelKind.allCases) {jewel in
                VStack(alignment:.leading,spacing:5) {
                    Text(jewel.name).foregroundStyle(jewelGold)
                    if let holding=state.save.inventory[jewel.key] {
                        Text(String(format:"SIZE ×%.1f / 1.8",holding.size)).font(.caption.monospaced())
                        ProgressView(value:min(1,(holding.size-1)/0.8)).tint(jewelGold)
                        Text(jewel.game == .kurukuru ? "次の挑戦：\(state.save.progress[jewel.key] ?? 4)×\(state.save.progress[jewel.key] ?? 4)":"サイズ成長の拡張は今後追加予定").font(.caption).foregroundStyle(.secondary)
                    } else {Text("未獲得 · "+jewel.game.title).font(.caption).foregroundStyle(.secondary)}
                }.padding(.vertical,6)
            }}
            Section("石座と仕上げ") {
                Picker("スタイル",selection:Binding(get:{state.decoration},set:{state.setDecoration($0)})) {
                    Text("基本の石座").tag(0)
                    Text("達成の月桂冠").tag(1)
                    if state.hasMaximumGem {Text("光輪").tag(2);Text("高研磨").tag(3)}
                }
                Text(state.hasMaximumGem ? "サイズ1.8の達成で光輪・高研磨を解放しました。":"称号を得た宝石の石座に月桂冠を表示。サイズ1.8で光輪・高研磨を解放します。").font(.caption).foregroundStyle(.secondary)
            }
            Section("獲得した称号") {
                if (state.save.earnedTitles ?? []).isEmpty {Text("収集・無傷のトレース・ミスなしの破砕で称号を獲得").font(.caption)}
                ForEach(state.save.earnedTitles ?? [],id:\.self) {Text($0.replacingOccurrences(of:"blackOnyx",with:"オニキス").replacingOccurrences(of:"emerald",with:"エメラルド"))}
            }
            Section("自己ベスト · 同じルールの成功記録") {
                if (state.save.rulesBestTimes ?? [:]).isEmpty {Text("クリアすると記録されます。旧版のタイムとは比較しません。").font(.caption)}
                ForEach((state.save.rulesBestTimes ?? [:]).keys.sorted(),id:\.self) {key in
                    if let event=(state.save.journal ?? []).first(where:{$0.recordKey==key}) {
                        VStack(alignment:.leading,spacing:4) {
                            Text((JewelKind.allCases.first(where:{$0.key==event.gemID})?.name ?? event.gemID)+" · "+event.game.title)
                            Text(event.boardSize>0 ? "\(event.boardSize)×\(event.boardSize)":event.game == .grassTrace ? String(format:"許容距離 %.1f%%",event.traceTolerance*100):"\(event.targetCount)点・各1.5秒").font(.caption).foregroundStyle(.secondary)
                            Text(GameClock.display(state.save.rulesBestTimes?[key] ?? 0)).monospacedDigit().foregroundStyle(jewelGold)
                        }
                    }
                }
            }
            Section {Text("オフライン記録です。ランキング・期限付き目標・課金はまだありません。").font(.caption).foregroundStyle(.secondary)}
        }.navigationTitle("光の記録").toolbar {ToolbarItem(placement:.confirmationAction){Button("閉じる"){achievements=false}}}}.tint(jewelGold)
    }
    private var settingsView:some View {
        NavigationStack { Form {
            Section("光と描画品質") {
                Toggle("窓からの光をゆっくり動かす",isOn:$state.windowLightMotion).accessibilityIdentifier("settings.windowMotion")
                Text("光の窓格子が宝石の中で屈折します。OFF・省電力・視差効果を減らす設定では背景の光が静止します。").font(.caption).foregroundStyle(.secondary)
                Toggle("レイトレーシング",isOn:$state.rayTracing).disabled(!state.rayAvailable).accessibilityIdentifier("settings.rayTracing")
                Text(state.rayStatus).font(.caption)
                Text("ON時は宝石の詳細観察で内部反射を計算します。省電力・高温時と原子表示時は通常描画になります。").font(.caption).foregroundStyle(.secondary)
                Picker("描画品質",selection:$state.quality) {ForEach(QualityPreference.allCases) {Text($0.title).tag($0)}}.accessibilityIdentifier("settings.quality")
                Text("現在："+state.actualQuality+"。CPU/GPUの処理時間と温度で演出を調整します。ゲームの判定と報酬は同じです。").font(.caption)
            }
            Section("Glass Traceの距離") {
                Text("緑の点から離れてよい距離を調整します。初期値は短辺の6%。画面上の半径は22pt以上です。").font(.footnote)
                Slider(value:$state.traceTolerance,in:0.025...0.2,step:0.005).accessibilityIdentifier("settings.tolerance")
                Text(String(format:"許容距離：短辺の%.1f%%",state.traceTolerance*100))
            }
            #if DEBUG
            Section("開発用の表示・非表示") {
                Text("表示だけを変更します。所持と報酬は変わりません。未所持のプレビューから始めたゲームは練習扱いです。").font(.footnote)
                Button("すべて表示") { for j in JewelKind.allCases {state.setVisible(j,true)} }.accessibilityIdentifier("preview.all")
                Button("通常表示に戻す") {state.normalVisibility()}.accessibilityIdentifier("preview.normal")
                ForEach(JewelKind.allCases){j in Toggle(j.name,isOn:Binding(get:{state.visible.contains(j)},set:{state.setVisible(j,$0)})).accessibilityIdentifier("preview.\(j.key)")}
            }
            #endif
            Section("保存") {
                Text("所持・位置・進行はこの端末に保存されます。リングの各種類には取得済みの最大サイズを表示します。").font(.footnote)
                Text(state.files.primary.path).font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                ShareLink("保存ファイルを書き出す",item:state.files.primary)
                Button("旧JewelRingの保存JSONを取り込む") {importing=true}.disabled(!state.save.inventory.isEmpty).accessibilityIdentifier("save.import")
                Text("旧アプリの設定からJSONを書き出し、空のTamorへ取り込みます。現在の保存はバックアップされます。").font(.caption)
                Text("サーバー同期は準備段階です。現在は端末内のみ。将来はサインインした所有者が正本の端末を選択し、CloudKitへ保存します。").font(.caption)
            }
        }.navigationTitle("設定").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.confirmationAction){Button("閉じる"){state.saveTolerance();settings=false}.accessibilityIdentifier("settings.done")}} }.tint(jewelGold)
    }
}
func goldButton(_ text:String,icon:String)->some View {
    HStack{Text(text);Spacer();Image(systemName:icon)}.font(.system(size:14,weight:.medium)).padding(17).foregroundStyle(jewelBackground).background(jewelGold,in:RoundedRectangle(cornerRadius:5))
}
