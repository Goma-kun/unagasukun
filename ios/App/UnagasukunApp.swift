import SwiftUI

@main
struct UnagasukunApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environmentObject(model)
                .task {
                    // 通知の許可はここでは聞かない。
                    // **何のアプリか分からないうちに聞かれると、人は断る。**
                    // 最初の予定を登録したとき（＝通知が意味を持った瞬間）に聞く
                    model.reschedule()
                }
        }
    }
}
