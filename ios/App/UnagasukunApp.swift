import SwiftUI
import UserNotifications

@main
struct UnagasukunApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    /// `UNUserNotificationCenter` は delegate を弱参照で持つ。
    /// App の値に持たせると解放されて通知が前面に出なくなるので、寿命の長いところに置く
    private static let presenter = ForegroundNotificationPresenter()
    /// 開いているタブ。撮影用の引数 `-UKShotTab 1` があればそこから開く（DEBUG のみ）
    @State private var tab = Shot.initialTab
    /// 浮かぶ「＋」から開く登録フォーム（iPhone だけ）
    @State private var addingFromFab = false

    init() {
        UNUserNotificationCenter.current().delegate = Self.presenter
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                TodayView()
                    .tabItem { Label("今日", systemImage: "list.bullet") }.tag(0)
                LookBackView()
                    .tabItem { Label("カレンダー", systemImage: "calendar") }.tag(1)
                SettingsView()
                    .tabItem { Label("設定", systemImage: "gearshape") }.tag(2)
            }
                .environmentObject(model)
                .tint(Theme.tint)
                #if os(macOS)
                .frame(minWidth: 380, minHeight: 560)
                #else
                // 右上の「追加」は左手だと遠い（2026-09-26 本人指摘）。浮かぶ「＋」を出す。
                // 今日とカレンダーの両方に出し、設定では出さない。指で好きな場所へ動かせる（Things 3 と同じ）
                .overlay {
                    if tab != 2 {
                        FloatingAddButton { addingFromFab = true }
                    }
                }
                .sheet(isPresented: $addingFromFab) { PlanFormView().environmentObject(model) }
                #endif
                .task {
                    // 通知の許可はここでは聞かない。
                    // **何のアプリか分からないうちに聞かれると、人は断る。**
                    // 最初の予定を登録したとき（＝通知が意味を持った瞬間）に聞く
                    model.reschedule()
                }
                .onChange(of: scenePhase) { _, phase in
                    // 設定アプリで通知を切られていることがあるので、戻るたびに見に行く
                    guard phase == .active else { return }
                    Task {
                        await model.refreshNotificationState()
                        model.reschedule()
                        // 前面に戻るたびに揃える。ほかの端末で付けた記録を取りに行く
                        await model.syncNow()
                    }
                }
        }
        #if os(macOS)
        // 予定を縦に並べる画面なので、横に広げても読みやすくならない。
        // リマインダーやメモと同じくらいの幅を既定にする
        .defaultSize(width: 420, height: 760)
        .windowResizability(.contentMinSize)
        #endif
    }
}

/// App Store 用スクリーンショットの撮影フック。**Release では何もしない。**
///
/// シミュレータは `simctl` でタップできないので、開くタブ・フォームの中身・同期の見た目を
/// 起動引数で指定して、`simctl io screenshot` で撮る（まもるくんの `MAMORU_DEMO` と同じ型）。
///   -UKShotTab 1        カレンダーのタブで開く（0=今日 1=カレンダー 2=設定）
///   -UKShotForm interval 「◯日ごと」を選んだ登録フォームを開いた状態にする
///   -UKShotSync 1       設定の iCloud 表示を「揃っている」にする（シミュレータは iCloud 未サインインのため）
enum Shot {
    static var initialTab: Int {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "UKShotTab")
        #else
        return 0
        #endif
    }
    static var formPreset: Item? {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "UKShotForm") == "interval" else { return nil }
        return Item(id: "shot", label: "猫の点滴", time: "09:00", intervalDays: 4,
                    detail: "首の後ろに 100ml。終わったらおやつ")
        #else
        return nil
        #endif
    }
    /// `-UKShotScroll tiles` カレンダーのタブをタイルまで下げた状態で開く
    static var scrollTarget: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "UKShotScroll")
        #else
        return nil
        #endif
    }
    /// `-UKShotDay 2026-09-24` カレンダーで最初に選んでおく日
    static var day: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "UKShotDay")
        #else
        return nil
        #endif
    }
    /// `-UKShotNotif 1` 通知が効いている扱いにする（シミュレータは未許可のため帯が出る）
    static var fakeNotifications: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "UKShotNotif")
        #else
        return false
        #endif
    }
    static var fakeSync: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "UKShotSync")
        #else
        return false
        #endif
    }
}

#if os(iOS)
/// 浮かぶ「＋」。指で動かせて、置いた場所を端末ごとに覚える（見出しの文字に被る、という指摘への答え）。
/// 位置は画面の幅・高さに対する割合で持つので、縦横が変わっても画面の外に出ない。
///
/// **Button に DragGesture を重ねない。** Button が指の動きを取ってしまい、指に追従せず離した瞬間に
/// まとめて飛ぶ（2026-09-26 本人「ピュンって飛ぶ」）。丸は素の View にして、
/// 押す／動かすは1つの DragGesture(minimumDistance: 0) の中で距離で見分ける
struct FloatingAddButton: View {
    var action: () -> Void
    /// 割合（0〜1）。既定は左下（Apple のリマインダーと同じ・左手の親指が届く）
    @AppStorage("fabX") private var fabX = 0.0
    @AppStorage("fabY") private var fabY = 1.0
    @State private var drag: CGSize = .zero
    @State private var pressed = false

    private let size: CGFloat = 52
    private let margin: CGFloat = 16
    private let bottomInset: CGFloat = 62   // タブバーぶん

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(x: margin, y: margin + 8,
                              width: max(1, geo.size.width - margin * 2 - size),
                              height: max(1, geo.size.height - margin - bottomInset - size))
            let base = CGPoint(x: area.minX + area.width * fabX + size / 2,
                               y: area.minY + area.height * fabY + size / 2)
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.navyLight, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .scaleEffect(pressed ? 1.08 : 1)
                .contentShape(Circle())
                .position(x: base.x + drag.width, y: base.y + drag.height)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            // 指にそのまま追従（アニメーションは掛けない）
                            var t = Transaction(); t.disablesAnimations = true
                            withTransaction(t) {
                                drag = v.translation
                                pressed = true
                            }
                        }
                        .onEnded { v in
                            let moved = hypot(v.translation.width, v.translation.height)
                            if moved < 8 {
                                // ほとんど動いていない＝押した
                                drag = .zero; pressed = false
                                action()
                                return
                            }
                            // 置いた場所を割合で覚える。画面の外に出ていたら縁まで戻す（ここだけ軽く動く）
                            let nx = min(1, max(0, (base.x + v.translation.width - size / 2 - area.minX) / area.width))
                            let ny = min(1, max(0, (base.y + v.translation.height - size / 2 - area.minY) / area.height))
                            withAnimation(.spring(duration: 0.25)) {
                                fabX = nx; fabY = ny
                                drag = .zero
                                pressed = false
                            }
                        }
                )
                .accessibilityLabel("予定を追加")
                .accessibilityHint("押したまま動かすと位置を変えられます")
                .accessibilityAddTraits(.isButton)
        }
    }
}
#endif
