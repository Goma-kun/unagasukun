import SwiftUI
import UserNotifications

@main
struct UnagasukunApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    /// `UNUserNotificationCenter` は delegate を弱参照で持つ。
    /// App の値に持たせると解放されて通知が前面に出なくなるので、寿命の長いところに置く
    private static let presenter = ForegroundNotificationPresenter()

    init() {
        UNUserNotificationCenter.current().delegate = Self.presenter
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                TodayView()
                    .tabItem { Label("今日", systemImage: "list.bullet") }
                LookBackView()
                    .tabItem { Label("ふりかえり", systemImage: "calendar") }
                SettingsView()
                    .tabItem { Label("設定", systemImage: "gearshape") }
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
