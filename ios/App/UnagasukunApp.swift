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
