import SwiftUI

/// カレンダー。過去は**できた日だけに色がつく**ふりかえり、未来はその日の予定の確認。
/// できなかった日は何も出さず、達成率も出さない（沈黙が中立＝責めない設計）。
/// 未来にも進めるようにしたのは 2026-09-26（本人「未来の予定をカレンダーで確認できない」）
struct LookBackView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = Date()
    @State private var selected: String? = nil

    private let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("カレンダー").font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.navy)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        calendarCard.id("calendar")
                        if let key = selected { dayDetail(key) }
                        tiles
                    }
                    .padding(16)
                }
                // タイルで日を選んだら、付け直す場所（カレンダーの下）まで戻す
                .onChange(of: selected) { _, _ in
                    withAnimation { proxy.scrollTo("calendar", anchor: .top) }
                }
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
                Button { month = Date(); selected = Logic.dateKey(Date()) } label: {
                    Text(monthTitle).font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("今月に戻る")
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 30)
                }
                // 今月より先にも進める（先の予定を見るため）。今月へ戻る近道を真ん中の月名に
            }
            .foregroundStyle(Theme.tint)

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
        // 先の日は、予定がある日だけ数字の下に小さな点（何があるかは押して見る）
        let hasPlan = isFuture && !model.plannedOn(key).isEmpty

        return Button { selected = key } label: {
            Text("\(Logic.calendar.component(.day, from: day))")
                .font(.system(size: 14, weight: mark == .done ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(cellText(mark: mark, isFuture: isFuture))
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(cellBackground(mark: mark), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) {
                    if hasPlan {
                        Circle().fill(Theme.tint).frame(width: 4, height: 4).padding(.bottom, 5)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.tint, lineWidth: isSelected ? 2 : 0)
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

    @ViewBuilder
    private func dayDetail(_ key: String) -> some View {
        if key > Logic.dateKey(Date()) {
            futureDetail(key)
        } else {
            recordDetail(key)
        }
    }

    /// 先の日: その日の予定を時刻つきで並べるだけ。まだ来ていない日に記録のボタンは出さない
    private func futureDetail(_ key: String) -> some View {
        let items = model.plannedOn(key)
        return VStack(alignment: .leading, spacing: 10) {
            Text((Logic.parseDateKey(key).map(Describe.short) ?? key) + " の予定")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)

            if items.isEmpty {
                Text("この日の予定はありません")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.skip)
                    .padding(.vertical, 6)
            } else {
                ForEach(items, id: \.id) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(planTimeText(item))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.tint)
                            .monospacedDigit()
                        Text(item.label)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                }
                Text("◯日ごとの予定は、いまの目安日から数えた見込みです。済ませた日で変わります。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.skip)
            }
        }
    }

    private func planTimeText(_ item: Item) -> String {
        if Logic.isAnytime(item) { return "いつでも" }
        guard let t = item.time else { return "—" }
        if let e = item.endTime, Logic.isValidEndTime(t, e) { return "\(t)〜\(e)" }
        return t
    }

    private func recordDetail(_ key: String) -> some View {
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
        // 先週までの12週に今週の列を足す（右端が今週）。今週のまだ来ていない日は点線の枠だけ
        let weeks = LookBack.tileWeeks(now: Date(), count: 12)

        return VStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                Text("ここには、できた日が色で並びます。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.skip)
                    .padding(.top, 4)
            } else {
                Text("これまで（今週までの13週）")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                // 見方の説明。「マスが並んでいるだけで何か分からない」と言われたので、先頭に1回だけ
                Text("マス1つが1日。縦が日〜土、横が週で、右端の列が今週です。色が付いた日が「できた」日。マスを押すと、その日の記録を上のカレンダーで付け直せます。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.skip)

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
                        // 繰り返しと時刻。同じ名前の予定が2つあっても（曜日違いの登録など）どちらか分かるように
                        Text(model.describe(item))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                        tileGrid(item, weeks)
                        legend
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private let tileSize: CGFloat = 12
    private let tileGap: CGFloat = 3

    private func tileGrid(_ item: Item, _ weeks: [[Date]]) -> some View {
        let labels = LookBack.monthLabelColumns(weeks)
        let today = Logic.startOfDay(Date())
        let todayKey = Logic.dateKey(today)
        return VStack(alignment: .leading, spacing: tileGap) {
            // 月名の行。月が変わった最初の週の上に出す（左右どちらが新しいかも、これで分かる）
            HStack(spacing: tileGap) {
                Color.clear.frame(width: 16, height: 12)
                ForEach(Array(weeks.indices), id: \.self) { w in
                    ZStack(alignment: .leading) {
                        Color.clear.frame(width: tileSize, height: 12)
                        if let l = labels.first(where: { $0.column == w }) {
                            Text("\(Logic.calendar.component(.month, from: l.sunday))月")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.muted)
                                .fixedSize()
                        }
                    }
                }
            }
            ForEach(0..<7, id: \.self) { r in
                HStack(spacing: tileGap) {
                    // 左端に曜日。どの行が何曜日か、見なくても分かるように
                    Text(weekdayNames[r])
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 16, alignment: .trailing)
                    ForEach(Array(weeks.indices), id: \.self) { w in
                        let day = weeks[w][r]
                        let key = Logic.dateKey(day)
                        if day > today {
                            // まだ来ていない日。押せないし色も付かない
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Theme.skip.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(width: tileSize, height: tileSize)
                        } else {
                            Button {
                                // その日を上のカレンダーで選ぶ（付け直しはカレンダーの下でする）
                                selected = key
                                month = day
                            } label: {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(LookBack.tileMark(item, model.snapshot.records, day, now: Date()) == .done
                                          ? Theme.done : Theme.skip.opacity(0.22))
                                    .frame(width: tileSize, height: tileSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(key == todayKey ? Theme.accent : (key == selected ? Theme.tint : .clear),
                                                    lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Describe.short(day))
                        }
                    }
                }
            }
        }
    }

    /// 凡例（色の意味。小さく1行だけ）
    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(Theme.done, "できた")
            legendItem(Theme.skip.opacity(0.22), "記録なし")
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.skip.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 10, height: 10)
                Text("これから")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.muted)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
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
