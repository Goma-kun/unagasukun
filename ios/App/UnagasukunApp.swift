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
/// 位置は画面の幅・高さに対する割合で持つので、縦横が変わっても画面の外に出ない
struct FloatingAddButton: View {
    var action: () -> Void
    /// 割合（0〜1）。既定は左下（Apple のリマインダーと同じ・左手の親指が届く）
    @AppStorage("fabX") private var fabX = 0.0
    @AppStorage("fabY") private var fabY = 1.0
    @State private var drag: CGSize = .zero

    private let size: CGFloat = 52
    private let margin: CGFloat = 16
    private let bottomInset: CGFloat = 62   // タブバーぶん

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(x: margin, y: margin + 8,
                              width: max(1, geo.size.width - margin * 2 - size),
                              height: max(1, geo.size.height - margin - bottomInset - size))
            let base = CGPoint(x: area.minX + area.width * fabX, y: area.minY + area.height * fabY)
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Theme.navyLight, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("予定を追加。長押しして動かせます")
            .position(x: base.x + size / 2 + drag.width, y: base.y + size / 2 + drag.height)
            .gesture(
                // 少し動かしてからドラッグ扱いにする（軽く押しただけなら追加のまま）
                DragGesture(minimumDistance: 10)
                    .onChanged { drag = $0.translation }
                    .onEnded { v in
                        let nx = (base.x + v.translation.width - area.minX) / area.width
                        let ny = (base.y + v.translation.height - area.minY) / area.height
                        fabX = min(1, max(0, nx))
                        fabY = min(1, max(0, ny))
                        drag = .zero
                    }
            )
            .animation(.easeOut(duration: 0.15), value: drag == .zero)
        }
        .allowsHitTesting(true)
    }
}
#endif
