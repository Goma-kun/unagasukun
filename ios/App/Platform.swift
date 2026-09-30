import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// OS ごとに違うところを、ここ1か所にまとめる。
/// **画面の側に `#if` を散らさない。**散らすと、どちらかの OS だけ直し忘れる
enum Platform {

    /// 浮かぶ「＋」（iPhone だけ）に一番下のカードが隠れないための余白。Mac は 0
    static var fabClearance: CGFloat {
        #if os(iOS)
        return 72
        #else
        return 0
        #endif
    }

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

/// 日付の入力。iOS は標準の DatePicker（押すとカレンダーが出る）。
/// Mac は**曜日つきの月カレンダー**を自前で出す。年・月・日のプルダウンだと「10月3日は何曜日か」を
/// 自分で数えることになる（2026-09-30 本人指摘）。macOS 標準の graphical は字が小さいので、
/// カレンダー画面と同じ見た目のマスで作る。選んだ日は上に「2026/10/30(金)」と言い切る
struct DateField: View {
    let title: String
    @Binding var date: Date

    var body: some View {
        #if os(iOS)
        DatePicker(title, selection: $date, displayedComponents: .date)
        #else
        LabeledContent(title) {
            MonthPickerGrid(date: $date)
        }
        #endif
    }
}

#if os(macOS)
/// 月のマスから日を選ぶ。アプリのカレンダー画面と同じ並び（日曜はじまり・月送りは左右の矢印）
struct MonthPickerGrid: View {
    @Binding var date: Date
    /// 表示している月（選んだ日とは別に動かせる）
    @State private var month = Date()

    private let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]
    private let cell: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(selectedText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Button("今日") { date = Date(); month = Date() }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tint)
                    .disabled(Calendar.current.isDateInToday(date))
                Spacer(minLength: 0)
            }

            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 24) }
                Spacer()
                Text(monthTitle).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 24) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.tint)

            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdayNames[i])
                        .font(.system(size: 11))
                        .foregroundStyle(i == 0 ? Theme.danger : (i == 6 ? Theme.tint : Theme.muted))
                        .frame(width: cell)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(LookBack.monthGrid(month).enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(width: cell, height: cell) }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { month = date }
        .onChange(of: date) { _, d in
            // 外から日付が変わったら（編集で読み込んだとき）、その月を見せる
            let c = Calendar.current
            if !c.isDate(d, equalTo: month, toGranularity: .month) { month = d }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let selected = cal.isDate(day, inSameDayAs: date)
        let today = cal.isDateInToday(day)
        let wd = Logic.jsWeekday(day)
        return Button { date = day } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? .white : (wd == 0 ? Theme.danger : (wd == 6 ? Theme.tint : Theme.text)))
                .frame(width: cell, height: cell)
                .background(selected ? Theme.tint : Theme.bg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(today ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Describe.short(day))
    }

    private var selectedText: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)(\(weekdayNames[Logic.jsWeekday(date)]))"
    }

    private var monthTitle: String {
        let c = Calendar.current.dateComponents([.year, .month], from: month)
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }

    private func shift(_ n: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: n, to: month) { month = d }
    }
}
#endif

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
