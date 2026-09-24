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

/// 日付の入力。iOS は標準の DatePicker。Mac は年・月・日のプルダウン（時刻と同じ理由）
struct DateField: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        #if os(iOS)
        DatePicker(title, selection: $date, displayedComponents: .date)
        #else
        LabeledContent(title) {
            HStack(spacing: 4) {
                Picker("年", selection: year) {
                    ForEach(yearChoices, id: \.self) { Text(String($0)).tag($0) }
                }
                .labelsHidden().frame(width: 84)
                Picker("月", selection: month) {
                    ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                }
                .labelsHidden().frame(width: 72)
                Picker("日", selection: day) {
                    ForEach(1...daysInMonth, id: \.self) { Text("\($0)日").tag($0) }
                }
                .labelsHidden().frame(width: 72)
                Text(weekdayText)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        #endif
    }

    private var cal: Calendar { Calendar.current }
    private var c: DateComponents { cal.dateComponents([.year, .month, .day], from: date) }

    /// 去年〜来年。選んでいる年が外れていればそれも並べる
    private var yearChoices: [Int] {
        let thisYear = cal.component(.year, from: Date())
        var v = Array((thisYear - 1)...(thisYear + 1))
        if let y = c.year, !v.contains(y) { v.append(y); v.sort() }
        return v
    }

    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: date)?.count ?? 31
    }

    private var weekdayText: String {
        ["日", "月", "火", "水", "木", "金", "土"][Logic.jsWeekday(date)] + "曜"
    }

    private func set(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        var n = DateComponents()
        n.year = year ?? c.year; n.month = month ?? c.month
        // 月を変えて日が無くなったら（1/31 → 2月）、その月の末日に寄せる
        let probe = cal.date(from: DateComponents(year: n.year, month: n.month, day: 1)) ?? date
        let last = cal.range(of: .day, in: .month, for: probe)?.count ?? 28
        n.day = min(day ?? c.day ?? 1, last)
        if let d = cal.date(from: n) { date = d }
    }

    private var year: Binding<Int> { Binding(get: { c.year ?? 2026 }, set: { set(year: $0) }) }
    private var month: Binding<Int> { Binding(get: { c.month ?? 1 }, set: { set(month: $0) }) }
    private var day: Binding<Int> { Binding(get: { c.day ?? 1 }, set: { set(day: $0) }) }
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
