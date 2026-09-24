import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    /// 開くフォーム。追加と編集で .sheet を2つ付けると、片方が開いた瞬間に閉じることがあるので1つにまとめる
    enum FormTarget: Identifiable {
        case add
        case edit(Item)
        var id: String { if case .edit(let i) = self { return i.id } else { return "add" } }
        var item: Item? { if case .edit(let i) = self { return i } else { return nil } }
    }
    @State private var form: FormTarget? = nil
    @State private var now = Date()
    /// 操作の結果を短く知らせる帯（「前にできていた」で次の目安日を言い切るのに使う）
    @State private var notice: String? = nil
    @State private var noticeTask: Task<Void, Never>? = nil

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let (todo, done) = model.today(now: now)

        VStack(spacing: 0) {
            header

            if !model.notificationsWorking {
                notificationOffBanner
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if todo.isEmpty && done.isEmpty {
                        emptyState
                    } else {
                        if !todo.isEmpty {
                            sectionTitle("今日の予定", count: todo.count)
                            ForEach(todo, id: \.item.id) { entry in
                                TodoCard(entry: entry, now: now, onEdit: { form = .edit($0) },
                                         onNotice: { show($0) })
                            }
                        }
                        if !done.isEmpty {
                            sectionTitle("今日対応済み", count: done.count)
                            ForEach(done, id: \.item.id) { entry in
                                DoneCard(entry: entry)
                            }
                        }
                    }

                    let registered = model.registered(now: now)
                    if !registered.isEmpty {
                        sectionTitle("登録済み", count: registered.count)
                        Text("今日の予定に出ているものは、ここには出しません。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.skip)
                        ForEach(registered, id: \.id) { item in
                            RegisteredRow(item: item, detail: model.describe(item, now: now)) {
                                form = .edit(item)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.navy, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 24).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(tick) { now = $0 }
        .task { await model.refreshNotificationState() }
        .sheet(item: $form) { PlanFormView(editing: $0.item) }
    }

    private func show(_ text: String) {
        noticeTask?.cancel()
        withAnimation { notice = text }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { notice = nil }
        }
    }

    /// 通知が届かない状態を黙っていない。**責めずに、直し方だけ示す**
    private var notificationOffBanner: some View {
        Button {
            Task { await model.enableNotifications() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bell.slash")
                Text("通知がオフのため、時間が来てもお知らせできません")
                    .font(.system(size: 13))
                Spacer(minLength: 0)
                Text("通知をオンにする").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.accent.opacity(0.22))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("うながすくん")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { form = .add } label: {
                Label("追加", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.navyLight, in: Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.navy)
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Theme.skip.opacity(0.35), in: Capsule())
        }
        .foregroundStyle(Theme.muted)
        .padding(.top, 4)
    }

    /// 何も無い日を責めない。「予定がない」とだけ言う
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.skip)
            Text("今日の予定はありません")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
            Text("右上の「追加」から登録できます")
                .font(.system(size: 13))
                .foregroundStyle(Theme.skip)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - カード

private struct TodoCard: View {
    @EnvironmentObject private var model: AppModel
    let entry: TodayEntry
    let now: Date
    /// 毎日の予定は登録済み一覧に出ないので、**今日のカードが編集の唯一の入口**になる
    var onEdit: (Item) -> Void
    var onNotice: (String) -> Void = { _ in }
    /// 「前にできていた」の候補日を開いているか
    @State private var pastOpen = false

    var body: some View {
        let pastCandidates = Logic.isInterval(entry.item) ? model.pastDoneCandidates(for: entry.item, now: now) : []

        VStack(alignment: .leading, spacing: 10) {
            // 見出し（時刻＋名前）を押しても編集に入れる。⋯ だけだと当たりが小さく、
            // 押したつもりで押せていないことがあった（本人報告・2026-09-23）
            Button { onEdit(entry.item) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(timeText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.tint)
                        .monospacedDigit()
                    Text(entry.item.label)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)   // Apple の最小の当たり
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("この予定を編集")

            // 詳細メモ（メモや手順）。名前の下に控えめに
            if let d = entry.item.detail, !d.isEmpty {
                Text(d)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !subtitles.isEmpty || !pastCandidates.isEmpty {
                HStack(spacing: 8) {
                    ForEach(subtitles, id: \.self) { chip($0) }
                    Spacer(minLength: 0)
                    // 済ませたのに付け忘れた日を、あとから「できた」にする入口。
                    // ふりかえりまで行かなくても今日のカードから直せる（2026-09-22 本人指摘）
                    if !pastCandidates.isEmpty {
                        Button { withAnimation { pastOpen.toggle() } } label: {
                            Text("前にできていた")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(pastOpen ? Theme.navy : Theme.muted)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(Capsule().stroke(pastOpen ? Theme.navy : Theme.skip, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if pastOpen && !pastCandidates.isEmpty {
                pastDoneRow(pastCandidates)
            }

            HStack(spacing: 10) {
                Button { model.record(entry.item, .done, now: now) } label: {
                    Text("できた").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButton(color: Theme.done))

                Button { model.record(entry.item, .skip, now: now) } label: {
                    Text("今日は休む").frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButton())
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: entry.group == .upcoming ? 1 : 1.5)
        )
    }

    /// 時間が過ぎたものは枠の色でも分かるようにする。
    /// **赤は使わない。**責めるためではなく、気づくための表示なので
    private var borderColor: Color {
        switch entry.group {
        case .active: return Theme.done
        case .overdue: return Theme.accent
        default: return Theme.skip.opacity(0.4)
        }
    }

    private var timeText: String {
        if Logic.isAnytime(entry.item) { return "いつでも" }
        return entry.item.time ?? "—"
    }

    private var subtitles: [String] {
        var out: [String] = []
        switch entry.group {
        case .active: out.append("進行中")
        case .overdue: out.append("未対応")
        default: break
        }
        if let due = model.nextDueText(for: entry.item, now: now) { out.append(due) }
        let s = model.streak(for: entry.item, now: now)
        if s > 0 { out.append("🔥 \(s)日") }
        return out
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.bg, in: Capsule())
    }

    /// 「前にできていた」の候補日。昨日から新しい順に、最後にやった日の翌日まで（最大7日）
    private func pastDoneRow(_ keys: [String]) -> some View {
        let yesterday = Logic.dateKey(Logic.day(now, plus: -1))
        return VStack(alignment: .leading, spacing: 8) {
            Text("済ませていた日を押すと、その日に「できた」が付き、次の目安日が数え直されます。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            FlowLayout(spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        let message = model.recordPastDone(entry.item, on: key, now: now)
                        pastOpen = false
                        onNotice(message)
                    } label: {
                        Text(dateChipText(key, yesterday: yesterday))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.bg, in: Capsule())
                            .overlay(Capsule().stroke(Theme.skip, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { Divider() }
    }

    private func dateChipText(_ key: String, yesterday: String) -> String {
        let text = Logic.parseDateKey(key).map(Describe.short) ?? key
        return key == yesterday ? "きのう \(text)" : text
    }
}

/// 幅に収まるぶんだけ横に並べ、あふれたら次の行へ（候補日のチップ用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct DoneCard: View {
    @EnvironmentObject private var model: AppModel
    let entry: TodayEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.mark == .done ? "checkmark.circle.fill" : "moon.zzz.fill")
                .foregroundStyle(entry.mark == .done ? Theme.done : Theme.skip)
            Text(entry.item.label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button("取り消す") { model.undo(entry.item) }
                .font(.system(size: 13))
                .foregroundStyle(Theme.navyLight)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - ボタンの見た目

struct FilledButton: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 9))
    }
}

struct OutlineButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? Theme.bg : Theme.card,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.skip, lineWidth: 1))
    }
}


/// 登録済み一覧の1行。今日の画面に出ていないものだけが並ぶ
private struct RegisteredRow: View {
    @EnvironmentObject private var model: AppModel
    let item: Item
    let detail: String
    var onEdit: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onEdit) { row }.buttonStyle(.plain)
    }

    private var row: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(size: 15))
                    .foregroundStyle(item.enabled ? Theme.text : Theme.muted)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if !item.enabled {
                Text("休み中")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.bg, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Theme.skip)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.skip.opacity(0.35), lineWidth: 1))
    }
}
