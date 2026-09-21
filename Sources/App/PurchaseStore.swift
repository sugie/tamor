import SwiftUI
import RevenueCat

@MainActor final class PurchaseStore:ObservableObject {
    static let productID="com.marcottlab.tamor.world1.depth"
    static let entitlementID="world1_full_depth"
    @Published private(set) var unlocked=false
    @Published private(set) var busy=false
    @Published private(set) var price:String?
    @Published var message:String?
    private var package:Package?
    private(set) var configured=false
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            message=L("購入サービスの接続準備中です。無料の深度1〜3をお楽しみください。")
            return
        }
        #endif
        let key=(Bundle.main.object(forInfoDictionaryKey:"RevenueCatAPIKey") as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard key.hasPrefix("appl_") else {
            message=L("購入サービスの接続準備中です。無料の深度1〜3をお楽しみください。")
            return
        }
        if !Purchases.isConfigured {Purchases.configure(withAPIKey:key)}
        configured=true
    }
    // SwiftUI owns cancellation of this stream when the home view disappears.
    func observeUpdates() async {
        guard configured else {return}
        for await info in Purchases.shared.customerInfoStream {
            guard !Task.isCancelled else {return}
            apply(info)
        }
    }
    private func apply(_ info:CustomerInfo) {
        unlocked=info.entitlements[Self.entitlementID]?.isActive == true
    }
    func refresh() async {
        guard configured,!busy else {return}
        busy=true;defer{busy=false}
        do {
            let info=try await Purchases.shared.customerInfo()
            apply(info)
            let offerings=try await Purchases.shared.offerings()
            package=offerings.current?.availablePackages.first{$0.storeProduct.productIdentifier==Self.productID}
            price=package?.localizedPriceString
            message=package == nil && !unlocked ? L("商品を取得できません。接続を確認して再試行してください。"):nil
        } catch {package=nil;price=nil;message=L("購入情報を更新できません：")+error.localizedDescription}
    }
    func buy() async {
        guard configured,!busy,let package else {return}
        busy=true;defer{busy=false}
        do {
            let result=try await Purchases.shared.purchase(package:package)
            if result.userCancelled {message=L("購入はキャンセルされました。");return}
            apply(result.customerInfo)
            message=L(unlocked ? "World 1の深度4〜6を解放しました。":"購入の確認を待っています。")
        } catch {message=L("購入を完了できません：")+error.localizedDescription}
    }
    func restore() async {
        guard configured,!busy else {return}
        busy=true;defer{busy=false}
        do {
            let info=try await Purchases.shared.restorePurchases()
            apply(info)
            message=L(unlocked ? "購入を復元しました。":"復元できるWorld 1の購入はありません。")
        } catch {message=L("購入を復元できません：")+error.localizedDescription}
    }
}

struct WorldPaywall:View {
    @ObservedObject var store:PurchaseStore
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Image(systemName:"sparkles").font(.largeTitle).foregroundStyle(jewelGold)
                Text("World 1の最深部へ").font(.largeTitle.weight(.light)).fixedSize(horizontal:false,vertical:true)
                Text("深度4〜6を解放し、最大20.00ctの宝石に挑戦できます。各深度のクリア条件は購入後も同じです。")
                Text("無料：深度1〜3・最大3.00ct\n買い切り：追加の体力消費や定期課金なし\nWorld 2は含まれません。購入しても20ctが自動でもらえるわけではありません。")
                    .font(.footnote).foregroundStyle(.secondary)
                if store.unlocked {Label("購入済み",systemImage:"checkmark.seal.fill").foregroundStyle(.green)}
                else {Button {Task{await store.buy()}} label:{goldButton(store.price.map{String(format:L("%@で解放"),$0)} ?? L("商品を確認中"),icon:"lock.open")}.disabled(store.price==nil || store.busy).accessibilityIdentifier("purchase.buy")}
                if store.busy {ProgressView()}
                if let message=store.message {Text(L(message)).font(.footnote).accessibilityIdentifier("purchase.status")}
                Button("購入を復元する") {Task{await store.restore()}}.disabled(!store.configured || store.busy).accessibilityIdentifier("purchase.restore")
                Button("接続を再確認") {Task{await store.refresh()}}.disabled(store.busy)
                Text("購入の復元はWorld 1の解放が対象です。宝石は端末内に保存され、購入の復元では戻りません。").font(.caption).foregroundStyle(.secondary)
            }.fixedSize(horizontal:false,vertical:true).padding(24).frame(maxWidth:560,alignment:.leading).frame(maxWidth:.infinity)
            }.navigationTitle("World 1 解放").navigationBarTitleDisplayMode(.inline)
                .toolbar {Button("閉じる"){dismiss()}}
        }.tint(jewelGold).task{await store.refresh()}
    }
}
