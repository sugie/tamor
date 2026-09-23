import SwiftUI
import UniformTypeIdentifiers

let jewelBackground=Color(red:0.025,green:0.043,blue:0.063)
let jewelGold=Color(red:0.80,green:0.68,blue:0.46)
let jewelWhite=Color(red:0.93,green:0.93,blue:0.89)
@main struct TamorApp:App {var body:some Scene {WindowGroup {JewelHome()}}}

struct JewelHome:View {
    @StateObject private var state=JewelSceneState()
    @StateObject private var purchases=PurchaseStore()
    @State private var settings=false
    @State private var games=false
    @State private var inventory=false
    @State private var importing=false
    @State private var world=1
    @State private var pending:JewelKind?
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        GeometryReader {geo in
            ScrollView {
                VStack(spacing:18) {
                    HStack {
                        Text("T A M O R").font(.caption).tracking(3).foregroundStyle(jewelGold);Spacer()
                        Button {settings=true} label:{Image(systemName:"slider.horizontal.3").frame(width:44,height:44)}.accessibilityIdentifier("jewel.settings")
                    }.padding(.horizontal,24)
                    worldHeader
                    if world==1 {
                        ZStack {
                            JewelMetalView(state:state)
                            if state.inspecting {
                                VStack {Spacer();HStack {Button {state.back()} label:{Label("リングに戻る",systemImage:"chevron.left").font(.caption).padding(12).background(jewelBackground.opacity(0.9),in:Capsule())}.accessibilityIdentifier("inspector.back");Spacer()}}.padding(12)
                            }
                            if state.count==0 {VStack(spacing:8){Image(systemName:"sparkles").font(.title);Text("最初の宝石を見つけよう").font(.footnote);Text("名前のある台座からプレイ").font(.caption)}.padding().background(jewelBackground.opacity(0.8),in:RoundedRectangle(cornerRadius:14)).allowsHitTesting(false).accessibilityIdentifier("ring.empty")}
                            if let error=state.error {Text(L(error)).font(.footnote).padding()}
                        }.frame(width:min(geo.size.width,480),height:min(geo.size.width,480))
                        collection.padding(.horizontal,24)
                    } else {comingSoon}
                    if let message=state.saveMessage {Text(L(message)).font(.footnote).foregroundStyle(.orange).padding()}
                    Text("0.10–20.00 ct · WORLD 1").font(.caption2.monospaced()).foregroundStyle(.secondary).padding(.bottom,24)
                }.frame(maxWidth:528).frame(maxWidth:.infinity)
            }.scrollBounceBehavior(.basedOnSize)
        }.background(jewelBackground.ignoresSafeArea()).foregroundStyle(jewelWhite).preferredColorScheme(.dark)
            .sheet(isPresented:$settings){settingsView}
            .sheet(isPresented:$inventory){InventoryScreen(state:state)}
            .sheet(isPresented:$state.paywallRequested){WorldPaywall(store:purchases)}
            .sheet(isPresented:$games,onDismiss:{if let jewel=pending {pending=nil;state.startGame(jewel)}}){gamePicker}
            .fullScreenCover(item:$state.game){MiniGameScreen(state:state,session:$0)}
            .fullScreenCover(item:$state.crusher){CrusherScreen(state:state,run:$0)}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json]){if case .success(let url)=$0 {Task{await state.importSave(url)}}}
            .onChange(of:purchases.unlocked){_,v in state.fullDepthAccess=v}
            .onChange(of:settings){_,_ in syncPause()}.onChange(of:inventory){_,_ in syncPause()}.onChange(of:games){_,_ in syncPause()}
            .onChange(of:state.game?.id){_,_ in syncPause()}.onChange(of:state.crusher?.id){_,_ in syncPause()}
            .onChange(of:world){_,_ in syncPause()}.onChange(of:state.paywallRequested){_,_ in syncPause()}
            .onChange(of:phase){_,p in
                if p != .active {state.game?.pause();state.crusher?.pause();state.persist()}
                else {Task{await purchases.refresh()}}
                syncPause()
            }
            .onAppear{state.reduceMotion=reduceMotion;state.persist();syncPause()}
            .onChange(of:reduceMotion){_,v in state.reduceMotion=v}
            .task{await purchases.refresh();state.fullDepthAccess=purchases.unlocked}
            .task{await purchases.observeUpdates()}
    }
    func syncPause(){state.paused=settings || inventory || games || state.paywallRequested || state.game != nil || state.crusher != nil || phase != .active || world==2}
    private var worldHeader:some View {
        HStack {
            Button {world=1} label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.disabled(world==1)
            Spacer();VStack(spacing:5){Text("WORLD \(world)").font(.caption.monospaced()).foregroundStyle(jewelGold);Text(L(world==1 ? "ジュエルリング":"海と虹の世界")).font(.title.weight(.light))};Spacer()
            Button {world=2} label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.disabled(world==2).accessibilityIdentifier("world.next")
        }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:30).onEnded{v in if abs(v.translation.width)>abs(v.translation.height) {world=v.translation.width<0 ? 2:1}})
    }
    private var comingSoon:some View {
        VStack(spacing:24) {
            Image(systemName:"water.waves").font(.system(size:68,weight:.ultraLight)).foregroundStyle(jewelGold)
            Text("Coming soon").font(.largeTitle.weight(.light)).accessibilityIdentifier("world.comingSoon")
            Text("真珠とオパールを集める、新しいリング。\nWorld 2は今後のアップデートで登場予定です。").multilineTextAlignment(.center)
            Text("World 1の解放商品には含まれません。").font(.caption).foregroundStyle(.secondary)
            Button("World 1へ戻る"){world=1}.padding()
        }.frame(height:400).padding(24)
    }
    private var collection:some View {
        VStack(spacing:16) {
            HStack {Text("収集 \(state.ownedCount) / 4 種類").accessibilityIdentifier("ring.count");Spacer();Text("全 \(state.collectionCount) 個")}.font(.caption).foregroundStyle(jewelGold)
            if !state.visible.isEmpty {
                HStack {
                    Button{state.selectNext(-1)}label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.accessibilityIdentifier("ring.previous")
                    Spacer()
                    VStack(spacing:6){Text(state.kind.english).font(.caption2.monospaced()).foregroundStyle(jewelGold);Text(L(state.kind.name)).font(.title2.weight(.light)).accessibilityIdentifier("ring.selection");Text(state.save.representative(state.kind.key).map{GemScale.label($0.centicarats)} ?? L("開発プレビュー")).monospacedDigit().accessibilityIdentifier("ring.weight")}
                    Spacer();Button{state.selectNext(1)}label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.accessibilityIdentifier("ring.next")
                }
                if state.inspecting {
                    Text(L(state.kind.composition)).font(.caption)
                    Text("リングと同じ大きさで表示しています。スワイプで回転、宝石をタップでリングに戻ります。").font(.caption).foregroundStyle(.secondary)
                }
                Button {state.startGame(state.kind)} label:{goldButton(String(format:L("%@をプレイ"),L(state.kind.game.title)),icon:"play.fill")}.accessibilityIdentifier("ring.play")
                Text(L(state.inspecting ? "スワイプで回転 · 宝石をタップでリングに戻る":"スワイプでリングを回転 · タップで宝石を中央に表示")).font(.caption2).foregroundStyle(.secondary)
            }
            Button{games=true}label:{goldButton(L("宝石と深度を選ぶ"),icon:"square.grid.2x2")}.accessibilityIdentifier("ring.games")
            Button{inventory=true}label:{goldButton(String(format:L("宝石箱 · %lld 個"),state.collectionCount),icon:"shippingbox")}.accessibilityIdentifier("ring.inventory")
            Button{state.paywallRequested=true}label:{Label(L(purchases.unlocked ? "World 1 解放済み":"World 1の深度4〜6を解放"),systemImage:purchases.unlocked ? "checkmark.seal":"lock.open")}.font(.footnote).foregroundStyle(jewelGold).accessibilityIdentifier("ring.unlock")
            Text("無料では3.00ctまで。解放後は最大20.00ctに挑戦できます。").font(.caption).foregroundStyle(.secondary)
            #if DEBUG
            Button(L(state.visible.count==4 ? "開発プレビューを終了":"開発用：4つの宝石を比較")){
                if state.visible.count==4 {state.normalVisibility()} else {for jewel in JewelKind.worldOne {state.setVisible(jewel,true)}}
            }.font(.caption).accessibilityIdentifier("ring.preview")
            #endif
        }
    }
    private var gamePicker:some View {
        NavigationStack {
            List {ForEach(JewelKind.worldOne){jewel in
                Section(L(jewel.name)+" · "+L(jewel.game.title)) {
                    ForEach(1...6,id:\.self){depth in
                        let unlocked=depth<=state.save.unlockedDepth(jewel.key),paid=depth>3 && !purchases.unlocked
                        Button {
                            if paid {games=false;DispatchQueue.main.asyncAfter(deadline:.now()+0.35){state.paywallRequested=true}}
                            else {state.selectedDepth=depth;pending=jewel;games=false}
                        } label:{HStack{Text("深度 \(depth)");Spacer();Text(depth==6 ? L("最大20.00ct"):GemScale.label(DepthRules(depth).reward(.s,streak:0)));Image(systemName:paid ? "lock":unlocked ? "play.circle":"lock.fill")}}
                            .disabled(!unlocked && !paid).accessibilityIdentifier("game.pick.\(jewel.key).\(depth)")
                    }
                    Text("前の深度をクリアすると次へ。深度4以降はWorld 1の解放も必要です。").font(.caption)
                }
            }}.navigationTitle("宝石と深度").toolbar{Button("閉じる"){games=false}}
        }.tint(jewelGold)
    }
    private func supportURL(_ page:String)->URL {
        let prefix=Bundle.main.preferredLocalizations.first=="ja" ? "":"en/"
        return URL(string:"https://marcottlab.com/"+prefix+"apps/tamor/"+page)!
    }
    private var settingsView:some View {
        NavigationStack {Form {
            Section("描画") {
                Toggle("窓の光を動かす",isOn:$state.windowLightMotion).accessibilityIdentifier("settings.windowMotion")
                Toggle("端末の傾きにリングを合わせる",isOn:$state.ringTiltEnabled).accessibilityIdentifier("settings.ringTilt")
                Text("傾きは画面表示にだけ使い、保存・送信しません。「視差効果を減らす」がオンの場合は動きません。").font(.caption)
                Toggle("レイトレーシング",isOn:$state.rayTracing).disabled(!state.rayAvailable).accessibilityIdentifier("settings.rayTracing")
                Text(L(state.rayStatus)).font(.caption)
                Text("対応GPUではリングで選択中の1個に適用します。低電力・高温時は通常描画になります。").font(.caption)
                Picker("品質",selection:$state.quality){ForEach(QualityPreference.allCases){Text(L($0.title)).tag($0)}}
            }
            Section("宝石の保存と復元") {
                Text("宝石はこの端末内に保存されます。iCloud同期には対応していません。アプリの削除や機種変更に備え、保存データを書き出して保管してください。").font(.caption).accessibilityIdentifier("save.localNotice")
                ShareLink("保存データを書き出す",item:state.files.primary)
                Button("保存データを取り込む"){importing=true}.disabled(!state.save.gems.isEmpty)
            }
            Section("購入") {
                Button("購入を復元"){Task{await purchases.restore()}}.disabled(purchases.busy || !purchases.configured)
                if let message=purchases.message {Text(L(message)).font(.caption)}
                Text("購入の復元でWorld 1の解放を戻せます。宝石やプレイ記録は復元されません。").font(.caption)
            }
            Section("サポートと規約") {
                Link("プライバシーポリシー",destination:supportURL("privacy.html")).accessibilityIdentifier("settings.privacy")
                Link("利用規約",destination:supportURL("terms.html")).accessibilityIdentifier("settings.terms")
                Link("サポート・お問い合わせ",destination:supportURL("")).accessibilityIdentifier("settings.support")
            }
            #if DEBUG
            Section("開発用表示") {
                ForEach(JewelKind.worldOne){j in Toggle(L(j.name),isOn:Binding(get:{state.visible.contains(j)},set:{state.setVisible(j,$0)}))}
                Button("通常表示に戻す"){state.normalVisibility()}
            }
            #endif
        }.navigationTitle("設定").toolbar{Button("閉じる"){settings=false}.accessibilityIdentifier("settings.done")}}
    }
}

struct GemGlyph:View {
    let kind:JewelKind
    let centicarats:Int
    var body:some View {
        let width=GemScale.width(centicarats:centicarats)
        Canvas {context,size in
            let points=[CGPoint(x:0.26,y:0),CGPoint(x:0.74,y:0),CGPoint(x:1,y:0.36),CGPoint(x:0.5,y:1),CGPoint(x:0,y:0.36)]
            let color=Color(red:Double(kind.tint.x),green:Double(kind.tint.y),blue:Double(kind.tint.z))
            for i in points.indices {
                var path=Path();path.move(to:CGPoint(x:size.width*0.5,y:size.height*0.36))
                for j in [i,(i+1)%points.count]{path.addLine(to:CGPoint(x:points[j].x*size.width,y:points[j].y*size.height))};path.closeSubpath()
                context.fill(path,with:.color(i%2==0 ? color:color.opacity(0.5)))
            }
        }.frame(width:width,height:width).accessibilityHidden(true)
    }
}
struct InventoryScreen:View {
    @ObservedObject var state:JewelSceneState
    @State private var filter="all"
    @State private var order=0
    @Environment(\.dismiss) var dismiss
    var items:[GemInstance] {
        state.save.gems.filter{filter=="all" || (filter=="legacy" ? $0.worldID=="legacy":$0.gemID==filter)}.sorted {
            if order==0 && $0.centicarats != $1.centicarats {return $0.centicarats>$1.centicarats}
            if $0.acquiredAt != $1.acquiredAt {return $0.acquiredAt>$1.acquiredAt};return $0.id<$1.id
        }
    }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Picker("種類",selection:$filter){Text("すべて").tag("all");ForEach(JewelKind.worldOne){Text(L($0.name)).tag($0.key)};Text("旧コレクション").tag("legacy")}
                    Picker("並び順",selection:$order){Text("カラット順").tag(0);Text("入手順").tag(1)}.pickerStyle(.segmented)
                    let list=items
                    let representatives=Set(JewelKind.allCases.compactMap{state.save.representative($0.key)?.id})
                    HStack{Text("\(list.count) 個");Spacer();Text(L("合計 ")+GemScale.label(list.reduce(0){$0+$1.centicarats}))}.font(.caption.monospaced())
                    Text(L("最大 ")+GemScale.label(list.map(\.centicarats).max() ?? 0)).foregroundStyle(jewelGold)
                    if list.isEmpty {ContentUnavailableView("まだ宝石がありません",systemImage:"shippingbox",description:Text("ミニゲームで集めた宝石は、小さなものもここに残ります。"))}
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:96),spacing:12)],spacing:16){ForEach(list){gem in
                        if let kind=JewelKind.allCases.first(where:{$0.key==gem.gemID}) {
                            VStack(spacing:8) {
                                GemGlyph(kind:kind,centicarats:gem.centicarats).frame(height:54)
                                Text(GemScale.label(gem.centicarats)).font(.caption.monospaced());Text(L(kind.name)).font(.caption2)
                                if representatives.contains(gem.id) {Label("代表",systemImage:"crown.fill").font(.caption2).foregroundStyle(jewelGold)}
                                Text(gem.acquiredAt,style:.date).font(.system(size:9)).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity).padding(.vertical,14).background(Color.white.opacity(0.045),in:RoundedRectangle(cornerRadius:8))
                        }
                    }}
                    Text("宝石は同じ表示倍率で並べています。代表を更新しても、以前の宝石は失いません。").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationTitle("宝石箱").toolbar{Button("閉じる"){dismiss()}}.background(jewelBackground)
        }.tint(jewelGold).accessibilityIdentifier("inventory.screen")
    }
}
func goldButton(_ text:String,icon:String)->some View {
    HStack{Text(text);Spacer();Image(systemName:icon)}.font(.system(size:14,weight:.medium)).padding(17).foregroundStyle(jewelBackground).background(jewelGold,in:RoundedRectangle(cornerRadius:5))
}
