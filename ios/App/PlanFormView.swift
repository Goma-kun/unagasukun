import SwiftUI

/// 予定の登録と編集。拡張機能 v1.6.0 と同じく、繰り返しは**先頭の3択タブ**にしてある。
/// 選んだ結果は**必ずプレビュー帯に日本語で言い切る**（「3日ごとって何日空くの？」を日付で潰す）。
struct PlanFormView: View {
    /// 編集するとき。新規なら nil
    var editing: Item? = nil

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    enum Repeat: String, CaseIterable { case once = "1回だけ", weekly = "毎週", interval = "◯日ごと" }

    @State private var label = ""
    @State private var mode: Repeat = .once
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    @State private var noTime = false
    @State private var date = Date()
    @State private var days: Set<Int> = []
    @State private var intervalDays = 3
    @State private var enabled = true

    private let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]
    private let intervalChoices = [1, 2, 3, 4, 6, 7, 14, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("やること", text: $label)
                        .font(.system(size: 16))
                }

                Section("繰り返し") {
                    Picker("", selection: $mode) {
                        ForEach(Repeat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch mode {
                    case .once:
                        DatePicker("日付", selection: $date, displayedComponents: .date)
                    case .weekly:
                        weekdayChips
                    case .interval:
                        intervalChips
                    }
                }

                Section("時刻") {
                    Toggle("時刻を決めない", isOn: $noTime)
                    if !noTime {
                        DatePicker("時刻", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Text(preview)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.navy)
                }

                if editing != nil {
                    Section {
                        Toggle("しばらく休む", isOn: Binding(get: { !enabled },
                                                       set: { enabled = !$0 }))
                    } footer: {
                        Text("一覧と通知から外れます。記録はそのまま残ります。")
                    }

                    Section {
                        Button("この予定を削除する", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(editing == nil ? "予定を追加" : "予定を編集")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "追加" : "保存") { save() }.disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("この予定を削除しますか？", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("削除する", role: .destructive) {
                    if let editing { model.remove(editing) }
                    dismiss()
                }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("これまでの記録は残ります。")
            }
        }
    }

    /// 編集のとき、いまの内容をフォームに写す
    private func load() {
        guard let item = editing else { return }
        label = item.label
        enabled = item.enabled
        noTime = Logic.isAnytime(item)
        if let t = item.time, let d = Logic.parseTime(t) {
            time = Logic.at(Date(), hour: d.0, minute: d.1)
        }
        if Logic.isInterval(item) {
            mode = .interval
            intervalDays = item.intervalDays ?? 3
        } else if let days = item.days, !days.isEmpty {
            mode = .weekly
            self.days = Set(days)
        } else if Logic.isOneOff(item) {
            mode = .once
            if let d = Logic.parseDateKey(item.date) { date = d }
        } else {
            // 旧来の「毎日」は曜日を全部選んだ状態として見せる
            mode = .weekly
            self.days = Set(0...6)
        }
    }

    // MARK: - 部品

    private var weekdayChips: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { d in
                Button {
                    if days.contains(d) { days.remove(d) } else { days.insert(d) }
                } label: {
                    Text(weekdayNames[d])
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(days.contains(d) ? Theme.navy : Theme.bg, in: Circle())
                        .foregroundStyle(days.contains(d) ? .white : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var intervalChips: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(intervalChoices, id: \.self) { n in
                Button { intervalDays = n } label: {
                    Text("\(n)日")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(intervalDays == n ? Theme.navy : Theme.bg,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(intervalDays == n ? .white : Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// **選んだ結果を日本語で言い切る。** 読み違えはここで潰す
    private var preview: String {
        switch mode {
        case .once:
            return "→ \(dateText(date)) に1回だけ。" + timeSentence
        case .weekly:
            guard !days.isEmpty else { return "→ 曜日を選んでください。毎日なら全部押します。" }
            let how = days.count == 7 ? "毎日" : "毎週 " + days.sorted().map { weekdayNames[$0] }
                                                            .joined(separator: "・")
            return "→ \(how) に繰り返します。" + timeSentence
        case .interval:
            let base = editing?.anchorDate.flatMap(Logic.parseDateKey) ?? Date()
            let due = Logic.day(base, plus: intervalDays)
            return "→ \(intervalDays)日ごと。次の目安日は \(dateText(due)) です。"
                + "「できた」を押した日から数え直します。" + timeSentence
        }
    }

    private var timeSentence: String {
        noTime
            ? "時刻は決めません。済ませるまで今日の予定に残ります。"
            : "\(hhmm) にお知らせします。"
    }

    private var hhmm: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private func dateText(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day, .weekday], from: d)
        return "\(c.month ?? 0)/\(c.day ?? 0)(\(weekdayNames[(c.weekday ?? 1) - 1]))"
    }

    private var canSave: Bool {
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if mode == .weekly && days.isEmpty { return false }
        return true
    }

    private func save() {
        var item = Item(id: editing?.id ?? UUID().uuidString,
                        label: label.trimmingCharacters(in: .whitespaces))
        item.enabled = enabled
        item.origId = editing?.origId
        item.archived = editing?.archived ?? false
        item.endTime = editing?.endTime
        item.targetMin = editing?.targetMin
        if noTime {
            item.anytime = true
        } else {
            item.time = hhmm
        }
        switch mode {
        case .once:
            item.date = Logic.dateKey(date)
        case .weekly:
            item.days = days.sorted()
        case .interval:
            item.intervalDays = intervalDays
            // **編集のときは基準日を作り直さない。** やり直すと数え直しが起きて、
            // 「名前を直しただけなのに目安日が飛んだ」ことになる
            item.anchorDate = editing?.anchorDate ?? Logic.dateKey(Date())
            // 短い間隔で「そろそろ」が一覧に居座らないよう、お知らせ開始を詰める
            item.noticeDays = max(0, min(3, intervalDays - 2))
        }
        if editing == nil { model.add(item) } else { model.update(item) }
        dismiss()
    }
}
