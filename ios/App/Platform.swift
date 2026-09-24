import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// OS ごとに違うところを、ここ1か所にまとめる。
/// **画面の側に `#if` を散らさない。**散らすと、どちらかの OS だけ直し忘れる
enum Platform {

    /// 通知の設定を開く。iOS はこのアプリの設定、Mac は「通知」の設定
    static func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let url { NSWorkspace.shared.open(url) }
        #endif
    }
}

/// 時刻（時・分）の入力。iOS は標準の DatePicker。
/// Mac の標準は小さな上下矢印のステッパーで、押す向きと数字の動きが分かりにくい
/// （2026-09-24 本人指摘）ので、時と分をプルダウンから選ぶ形にする
struct TimeField: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        #if os(iOS)
        DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
        #else
        LabeledContent(title) {
            HStack(spacing: 4) {
                Picker("時", selection: hour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 72)
                Text(":")
                Picker("分", selection: minute) {
                    ForEach(minuteChoices, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 72)
                Spacer(minLength: 0)
            }
        }
        #endif
    }

    private var components: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: date)
    }

    private var hour: Binding<Int> {
        Binding(get: { components.hour ?? 0 },
                set: { date = Logic.at(Date(), hour: $0, minute: components.minute ?? 0) })
    }

    private var minute: Binding<Int> {
        Binding(get: { components.minute ?? 0 },
                set: { date = Logic.at(Date(), hour: components.hour ?? 0, minute: $0) })
    }

    /// 5分きざみ。保存済みの半端な分（例 14:07）は壊さないよう、その値も並べる
    private var minuteChoices: [Int] {
        var v = Array(stride(from: 0, through: 55, by: 5))
        let cur = components.minute ?? 0
        if !v.contains(cur) { v.append(cur); v.sort() }
        return v
    }
}

extension View {
    /// `navigationBarTitleDisplayMode` は iOS にしか無い
    @ViewBuilder
    func compactNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
