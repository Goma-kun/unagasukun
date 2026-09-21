import SwiftUI

/// ふりかえり。**できた日だけに色がつく。**
/// できなかった日は何も出さず、達成率も出さない（沈黙が中立＝責めない設計）。
struct LookBackView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = Date()
    @State private var selected: String? = nil

    private let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ふりかえり").font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.navy)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    calendarCard
                    if let key = selected { dayDetail(key) }
                    tiles
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .onAppear { if selected == nil { selected = Logic.dateKey(Date()) } }
    }

    // MARK: - カレンダー

    private var calendarCard: some View {
        VStack(spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 30)
                }
                Spacer()
                Text(monthTitle).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 30)
                }
                .disabled(isCurrentMonth)
                .opacity(isCurrentMonth ? 0.25 : 1)
            }
            .foregroundStyle(Theme.navy)

            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(weekdayNames[i])
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                      spacing: 4) {
                ForEach(Array(LookBack.monthGrid(month).enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 38) }
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dayCell(_ day: Date) -> some View {
        let key = Logic.dateKey(day)
        let mark = model.dayMark(key)
        let isSelected = key == selected
        let isFuture = day > Logic.startOfDay(Date())

        return Button { selected = key } label: {
            Text("\(Logic.calendar.component(.day, from: day))")
                .font(.system(size: 14, weight: mark == .done ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(cellText(mark: mark, isFuture: isFuture))
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(cellBackground(mark: mark), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.navy, lineWidth: isSelected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
    }

    /// **色がつくのは「できた」日だけ。** 休んだ日は薄い灰色、何も無い日は無色
    private func cellBackground(mark: Mark?) -> Color {
        switch mark {
        case .done: return Theme.done
        case .skip: return Theme.skip.opacity(0.28)
        case nil: return Theme.bg
        }
    }

    private func cellText(mark: Mark?, isFuture: Bool) -> Color {
        if mark == .done { return .white }
        return isFuture ? Theme.skip : Theme.text
    }

    // MARK: - 選んだ日

    private func dayDetail(_ key: String) -> some View {
        let items = model.itemsOn(key)
        return VStack(alignment: .leading, spacing: 10) {
            Text(dayTitle(key))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)

            if items.isEmpty {
                Text("この日の予定はありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.skip)
                    .padding(.vertical, 6)
            } else {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: 10) {
                        Text(item.label)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        markButton(item, .done, key, "できた", Theme.done)
                        markButton(item, .skip, key, "休んだ", Theme.skip)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                }
                Text("押すと記録が付き、もう一度押すと取り消せます。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.skip)
            }
        }
    }

    private func markButton(_ item: Item, _ mark: Mark, _ key: String,
                            _ title: String, _ color: Color) -> some View {
        let on = model.mark(item, on: key) == mark
        return Button { model.toggle(item, mark, on: key) } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? .white : Theme.muted)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? color : Theme.bg, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - タイル

    private var tiles: some View {
        // **1度もできていないものは並べない。** 真っ白な枠を見せるのは
        // 「何もできていない」と突きつけるのと同じで、沈黙が中立という設計に反する
        let items = LookBack.tileItems(model.snapshot.schedule)
            .filter { model.doneCount($0, weeks: 12) > 0 }
        let weeks = LookBack.tileWeeks(now: Date(), count: 12)

        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                Text("ここには、できた日が色で並びます。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.skip)
                    .padding(.top, 4)
            } else {
                Text("これまで（先週までの12週）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                ForEach(items, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(item.label).font(.system(size: 15)).foregroundStyle(Theme.text)
                            Spacer(minLength: 0)
                            // 事実の回数だけ。達成率は出さない
                            Text("\(model.doneCount(item, weeks: 12))回")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                        tileGrid(item, weeks)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func tileGrid(_ item: Item, _ weeks: [[Date]]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LookBack.tileMark(item, model.snapshot.records, day, now: Date()) == .done
                                  ? Theme.done : Theme.skip.opacity(0.22))
                            .frame(height: 12)
                    }
                }
            }
        }
    }

    // MARK: - 小物

    private var monthTitle: String {
        let c = Logic.calendar.dateComponents([.year, .month], from: month)
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }

    private var isCurrentMonth: Bool {
        let a = Logic.calendar.dateComponents([.year, .month], from: month)
        let b = Logic.calendar.dateComponents([.year, .month], from: Date())
        return a.year == b.year && a.month == b.month
    }

    private func shiftMonth(_ n: Int) {
        if let d = Logic.calendar.date(byAdding: .month, value: n, to: month) { month = d }
    }

    private func dayTitle(_ key: String) -> String {
        guard let d = Logic.parseDateKey(key) else { return key }
        return Describe.short(d) + " の記録"
    }
}
