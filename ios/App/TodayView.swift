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
    /// いまのウィンドウの大きさ（編集シートをこれに収める）
    @State private var winSize = CGSize(width: 540, height: 780)
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    /// 操作の結果を短く知らせる帯（「前にできていた」で次の目安日を言い切るのに使う）
    @State private var notice: String? = nil
    /// 帯の左に顔を出す動物（こっそりお祝い）
    @State private var noticeEmoji: String? = nil
    @State private var noticeTask: Task<Void, Never>? = nil
    /// 動物6匹がふわっと浮かぶ演出。値が変わるたびに出し直す
    @State private var party: UUID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「登録済み」「過ぎた予定」を畳んでいるか。端末ごとに覚える（2026-09-24 本人要望）。
    /// 過ぎた予定は見返すことが少ないので、はじめは畳んでおく
    @AppStorage("collapseRegistered") private var collapseRegistered = false
    @AppStorage("collapsePast") private var collapsePast = true
    /// 「終わった予定」も見返すことが少ないので、はじめは畳んでおく
    @AppStorage("collapseEnded") private var collapseEnded = true
    /// ラベルの絞り込み（空＝すべて）。端末ごとに覚える
    @AppStorage("todayTagFilter") private var tagFilter = ""
    /// 「今日対応済み」も畳める。済んだ数が多い日に長くなる（2026-09-26 本人要望）。はじめは開いておく
    @AppStorage("collapseDone") private var collapseDone = false

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let (todoAll, doneAll) = model.today(now: now)
        let tagsInUse = model.tagsInUse()
        // 消したラベルで絞ったままにならないよう、無いラベルなら「すべて」に戻す
        let filter = tagsInUse.contains { $0.id == tagFilter } ? tagFilter : ""
        let todo = filter.isEmpty ? todoAll : todoAll.filter { $0.item.tagId == filter }
        let done = filter.isEmpty ? doneAll : doneAll.filter { $0.item.tagId == filter }

        VStack(spacing: 0) {
            header

            if !model.notificationsWorking {
                notificationOffBanner
            }

            // ラベルを使っている予定があるときだけ、絞り込みの列を出す
            if !tagsInUse.isEmpty {
                TagFilterBar(tags: tagsInUse, selected: $tagFilter)
            }

            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if todo.isEmpty && done.isEmpty {
                        emptyState
                    } else {
                        if !todo.isEmpty {
                            // いまやる 1 件だけ大きく出し、ほかは 1 行に畳む（2026-11-25）。
                            // 全部のカードに大きい「できた」が並ぶと、いまの 1 件が埋もれる。
                            // 進行中があればそれ（重なっていれば全部）、無ければ並びの先頭の 1 件
                            let active = todo.filter { $0.group == .active }
                            let focus = active.isEmpty ? Array(todo.prefix(1)) : active
                            let focusIds = Set(focus.map(\.item.id))
                            let rest = todo.filter { !focusIds.contains($0.item.id) }
                            // まだ時間が来ていないものを「いま」とは呼ばない
                            sectionTitle(focus.first?.group == .upcoming ? String(localized: "つぎ") : String(localized: "いま"),
                                         count: focus.count)
                            ForEach(focus, id: \.item.id) { entry in
                                TodoCard(entry: entry, now: now, focus: true, onEdit: { form = .edit($0) },
                                         onNotice: { show($0) }, onDone: { cheer($0) })
                                    .id(entry.item.id)   // 通知から飛んでくる先
                            }
                            if !rest.isEmpty {
                                sectionTitle(String(localized: "ほかの予定"), count: rest.count)
                                VStack(spacing: 8) {
                                    ForEach(rest, id: \.item.id) { entry in
                                        TodoCard(entry: entry, now: now, onEdit: { form = .edit($0) },
                                                 onNotice: { show($0) }, onDone: { cheer($0) })
                                            .id(entry.item.id)
                                    }
                                }
                            }
                        }
                        if !done.isEmpty {
                            collapsibleTitle(String(localized: "今日対応済み"), count: done.count, collapsed: $collapseDone)
                            if !collapseDone {
                                ForEach(done, id: \.item.id) { entry in
                                    DoneCard(entry: entry)
                                        .id(entry.item.id)   // 「終わりました」の通知を押したとき、済んでいればここへ
                                }
                            }
                        }
                    }

                    let registered = model.registered(now: now).filter { filter.isEmpty || $0.tagId == filter }
                    if !registered.isEmpty {
                        collapsibleTitle(String(localized: "登録済み"), count: registered.count, collapsed: $collapseRegistered)
                        if !collapseRegistered {
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

                    // 日付が過ぎた1回だけの予定。登録済みに混ざると「まだやっていない」に見えるので
                    // 分けて出し、できたかどうかをここで付けられるようにする
                    let past = model.pastOneOffs(now: now).filter { filter.isEmpty || $0.tagId == filter }
                    if !past.isEmpty {
                        collapsibleTitle(String(localized: "過ぎた予定"), count: past.count, collapsed: $collapsePast)
                        if !collapsePast {
                            Text("日付が過ぎた1回だけの予定（2週間ぶん）。できたかどうかをここで付けられます。それより前はカレンダーのタブで見られます。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.skip)
                            ForEach(past, id: \.id) { item in
                                PastOneOffRow(item: item) { form = .edit(item) }
                            }
                        }
                    }

                    // 「終わりにする」で片づけた予定。押すと編集が開き、そこで戻すか削除できる
                    let ended = model.ended(now: now).filter { filter.isEmpty || $0.tagId == filter }
                    if !ended.isEmpty {
                        collapsibleTitle(String(localized: "終わった予定"), count: ended.count, collapsed: $collapseEnded)
                        if !collapseEnded {
                            Text("終わりにした予定です。押すと、予定に戻すか削除できます。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.skip)
                            ForEach(ended, id: \.id) { item in
                                RegisteredRow(item: item, detail: model.describe(item, now: now), ended: true) {
                                    form = .edit(item)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, Platform.fabClearance)
            }
            // 通知を押して開いたら、その予定まで送って光らせる。4 秒で印は消える。
            // 合図で受けるのは開いていたとき、onAppear で受けるのは閉じていたところから開いたとき
            .onReceive(NotificationCenter.default.publisher(for: ForegroundNotificationPresenter.tapped)) { _ in
                openTapped(proxy)
            }
            .onAppear { openTapped(proxy) }
            }
        }
        .background(Theme.bg)
        // ウィンドウの大きさを覚えておき、編集シートをその中に収める（Mac）
        .background(GeometryReader { g in
            Color.clear
                .onAppear { winSize = g.size }
                .onChange(of: g.size) { _, s in winSize = s }
        })
        .overlay {
            if let party, !reduceMotion {
                PetPartyView().id(party).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice {
                HStack(spacing: 8) {
                    if let noticeEmoji {
                        Text(noticeEmoji).font(.system(size: 22))
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(notice)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.navy, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24).padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(tick) { now = $0 }
        // 裏にいる間は 30 秒おきの時計が止まる。戻った瞬間に合わせないと、通知を押して開いても
        // 「時間が過ぎた」の橙の枠が数秒遅れて出る（2026-11-17 本人指摘）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .task {
            await model.refreshNotificationState()
            if Shot.formPreset != nil, form == nil { form = .add }
            if let l = Shot.editLabel, form == nil,
               let it = model.snapshot.schedule.first(where: { $0.label == l }) { form = .edit(it) }
        }
        .sheet(item: $form) { PlanFormView(editing: $0.item, preset: Shot.formPreset, maxSize: winSize) }
    }

    /// 押された通知を受け取って、何の通知だったかを下の帯で言い、その予定まで送って光らせる。
    /// **カードが今日の一覧に無くても（絞り込み中・登録済みの側など）、帯で題は必ず見せる**
    private func openTapped(_ proxy: ScrollViewProxy) {
        guard let t = ForegroundNotificationPresenter.pending else { return }
        ForegroundNotificationPresenter.pending = nil
        show("🔔 " + t.title)
        now = Date()   // 並びと枠の色を、押した時点の時刻で出す
        // 済んだ側にあって畳んでいたら開く。絞り込みで隠れていたら「すべて」に戻す
        let (todoAll, doneAll) = model.today(now: Date())
        if doneAll.contains(where: { $0.item.id == t.itemId }) { collapseDone = false }
        if let item = (todoAll + doneAll).first(where: { $0.item.id == t.itemId })?.item,
           !tagFilter.isEmpty, item.tagId != tagFilter {
            tagFilter = ""
        }
        // 印はすぐ付ける（アニメーションで待たせない）
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) { model.highlightedId = t.itemId }
        Task {
            // すぐ送る。開いた直後は一覧の配置が済んでいないことがあるので、少し後にもう一度送る
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(t.itemId, anchor: .center) }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(t.itemId, anchor: .center) }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if model.highlightedId == t.itemId { withAnimation { model.highlightedId = nil } }
        }
    }

    private func show(_ text: String, emoji: String? = nil) {
        noticeTask?.cancel()
        withAnimation { notice = text; noticeEmoji = emoji }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { notice = nil; noticeEmoji = nil }
        }
    }

    /// 「できた」のあとの一言。ぜんぶ済みなら動物が浮かぶ（3.4秒で跡形なし・記録に残さない）
    private func cheer(_ item: Item) {
        let c = model.cheerAfterDone(item, now: now)
        show(c.text, emoji: c.emoji)
        if c.party { party = UUID() }
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

    /// 押すと畳める見出し。右端の山形で開閉が分かる
    private func collapsibleTitle(_ title: String, count: Int, collapsed: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { collapsed.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                sectionTitle(title, count: count)
                Spacer(minLength: 0)
                Image(systemName: collapsed.wrappedValue ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed.wrappedValue ? String(localized: "\(title)を開く") : String(localized: "\(title)を畳む"))
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.uk(15, weight: .semibold))
            Text("\(count)")
                .font(.uk(14, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Theme.skip.opacity(0.35), in: Capsule())
        }
        .foregroundStyle(Theme.sub)
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
    /// 大きく出すか（いまやる 1 件）。false は 1 行に畳んだ形
    var focus = false
    /// 毎日の予定は登録済み一覧に出ないので、**今日のカードが編集の唯一の入口**になる
    var onEdit: (Item) -> Void
    var onNotice: (String) -> Void = { _ in }
    /// 「できた」を押したあと（お祝いの一言を出す）
    var onDone: (Item) -> Void = { _ in }
    /// 「前にできていた」の候補日を開いているか
    @State private var pastOpen = false
    @AppStorage(AskAI.storageKey) private var askRaw = AskAI.off.rawValue
    /// 文字サイズの設定が変わったら描き直す（Font.uk はその時点の設定で大きさを決める）
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 畳んだ行の時刻の列。文字と一緒に広がる
    @ScaledMetric private var timeColumn: CGFloat = 64

    var body: some View {
        let pastCandidates = Logic.isInterval(entry.item) ? model.pastDoneCandidates(for: entry.item, now: now) : []
        let tag = model.tag(for: entry.item)
        let radius: CGFloat = focus ? 16 : 12

        Group {
            if focus { focusBody(pastCandidates, tag) } else { compactBody(pastCandidates, tag) }
        }
        .background(Theme.cardBg(tag?.color), in: RoundedRectangle(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(highlighted ? Theme.accent : borderColor,
                        lineWidth: highlighted ? 4 : borderWidth)
        )
        .shadow(color: highlighted ? Theme.accent.opacity(0.55) : .clear, radius: highlighted ? 8 : 0)
        .animation(.easeInOut(duration: 0.3), value: highlighted)
    }

    // MARK: 大きいカード（いまやる 1 件）

    private func focusBody(_ pastCandidates: [String], _ tag: Tag?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let tag { TagChip(tag: tag) }
                ForEach(states, id: \.self) { stateChip($0) }
                Spacer(minLength: 0)
                menu(pastCandidates)
            }

            // 時刻と名前。押しても編集に入れる。⋯ だけだと当たりが小さく、
            // 押したつもりで押せていないことがあった（本人報告・2026-09-23）
            Button { onEdit(entry.item) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(timeText)
                        .font(.uk(26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.timeColor(tag?.color))
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(entry.item.label)
                        .font(.uk(22, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("この予定を編集")

            if streak > 0 { streakMark }

            // 詳細メモの右に「AI に聞く」。設定で聞き先を選んだときだけ出る（行を増やさない）
            if askRaw == AskAI.off.rawValue {
                detailText(lines: nil)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    detailText(lines: nil)
                    Spacer(minLength: 0)
                    AskAIButton(item: entry.item, onNotice: onNotice)
                }
            }

            // 済ませたのに付け忘れた日を、あとから「できた」にする入口。
            // ふりかえりまで行かなくても今日のカードから直せる（2026-09-22 本人指摘）
            if !pastCandidates.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    Button { withAnimation { pastOpen.toggle() } } label: {
                        Text("前にできていた")
                            .font(.uk(14, weight: .medium))
                            .foregroundStyle(pastOpen ? Theme.tint : Theme.sub)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .overlay(Capsule().stroke(pastOpen ? Theme.tint : Theme.skip, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if pastOpen { pastDoneRow(pastCandidates) }
            }

            // 時間が過ぎて記録が無い予定には「実際は…」（拡張機能と同じ）。畳んだ状態で置く
            if entry.group == .overdue {
                ActualNoteRow(item: entry.item, key: Logic.dateKey(now), openByDefault: false)
            }

            HStack(spacing: 10) {
                Button { markDone() } label: {
                    Text("できた").frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButton(color: Theme.done, large: true))

                Button { markSkip() } label: {
                    Text("今日は休む").frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButton(large: true))
            }
            .padding(.top, 2)
        }
        .padding(16)
    }

    // MARK: 畳んだ行（ほかの予定）

    /// 時刻／名前と印とメモ／⋯／丸いチェック。丸いチェックが「できた」、
    /// 「今日は休む」「前にできていた」「編集」は ⋯ の中。名前を押しても編集に入れる
    private func compactBody(_ pastCandidates: [String], _ tag: Tag?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 4) {
                Button { onEdit(entry.item) } label: {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(startText)
                                .font(Logic.isAnytime(entry.item) ? .uk(15, weight: .bold)
                                                                  : .uk(19, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.timeColor(tag?.color))
                                .monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.7)
                            if let end = endText {
                                Text("〜\(end)")
                                    .font(.uk(14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.sub)
                                    .monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                        .frame(width: timeColumn, alignment: .leading)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.item.label)
                                .font(.uk(18, weight: .semibold))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if tag != nil || !states.isEmpty || streak > 0 {
                                FlowLayout(spacing: 6) {
                                    if let tag { TagChip(tag: tag) }
                                    ForEach(states, id: \.self) { stateChip($0) }
                                    if streak > 0 { streakMark }
                                }
                            }
                            detailText(lines: 2)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("この予定を編集")

                menu(pastCandidates)

                Button { markDone() } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.done)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Theme.done, lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("できた")
            }

            if askRaw != AskAI.off.rawValue {
                HStack {
                    Spacer(minLength: 0)
                    AskAIButton(item: entry.item, onNotice: onNotice)
                }
            }

            if entry.group == .overdue {
                ActualNoteRow(item: entry.item, key: Logic.dateKey(now), openByDefault: false)
            }
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
    }

    // MARK: 部品

    private func markDone() {
        Haptic.success()
        model.record(entry.item, .done, now: now)
        onDone(entry.item)
    }

    private func markSkip() {
        Haptic.light()
        model.record(entry.item, .skip, now: now)
    }

    /// ⋯ のメニュー。畳んだ行では、大きいカードにあるボタンの代わりをここに入れる
    private func menu(_ pastCandidates: [String]) -> some View {
        let yesterday = Logic.dateKey(Logic.day(now, plus: -1))
        return Menu {
            if !focus {
                Button { markSkip() } label: { Label("今日は休む", systemImage: "moon.zzz") }
                if !pastCandidates.isEmpty {
                    Menu("前にできていた") {
                        ForEach(pastCandidates, id: \.self) { key in
                            Button(dateChipText(key, yesterday: yesterday)) {
                                onNotice(model.recordPastDone(entry.item, on: key, now: now))
                            }
                        }
                    }
                }
            }
            Button { onEdit(entry.item) } label: { Label("編集", systemImage: "pencil") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.sub)
                .frame(width: 40, height: 44)   // Apple の推奨の当たり（高さ）
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("その他の操作")
    }

    /// 通知を押して飛んできた相手かどうか。橙の太い枠＋にじみで「これですよ」と示す。
    /// **紺の 3pt は白いカードの上でほとんど見えなかった**（2026-11-17）。本人は橙の枠を目印にしている
    private var highlighted: Bool { model.highlightedId == entry.item.id }

    /// 時間が過ぎたものは枠の色でも分かるようにする。
    /// **赤は使わない。**責めるためではなく、気づくための表示なので。
    /// ふだんの枠はラベルの色（暗い画面で地の色だけだと見分けにくいため・2026-10-03）
    /// 状態の枠（進行中・未対応）は 1.5（大きいカードは 2）、ラベル付きは 2、何も無い「これから」は 1
    private var borderWidth: CGFloat {
        switch entry.group {
        case .active, .overdue: return focus ? 2 : 1.5
        default:
            let key = model.tag(for: entry.item)?.color
            return key == nil ? (entry.group == .upcoming ? 1 : 1.5) : Theme.cardStrokeWidth(key)
        }
    }

    private var borderColor: Color {
        switch entry.group {
        case .active: return Theme.done
        case .overdue: return Theme.accent
        default: return Theme.cardStroke(model.tag(for: entry.item)?.color)
        }
    }

    /// 詳細メモ（メモや手順）。名前の下に控えめに。畳んだ行は 2 行まで
    @ViewBuilder
    private func detailText(lines: Int?) -> some View {
        if let d = entry.item.detail, !d.isEmpty {
            Text(d)
                .font(.uk(15))
                .foregroundStyle(Theme.sub)
                .multilineTextAlignment(.leading)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeText: String {
        if Logic.isAnytime(entry.item) { return String(localized: "いつでも") }
        guard let t = entry.item.time else { return "—" }
        // 時間帯は「14:00〜16:00」（拡張機能の timeText() と同じ書き方）
        if let e = entry.item.endTime, Logic.isValidEndTime(t, e) { return String(localized: "\(t)〜\(e)") }
        return t
    }

    /// 畳んだ行の時刻の列：始まりの時刻だけ。終わりは下に小さく出す（列を狭く保つ）
    private var startText: String {
        if Logic.isAnytime(entry.item) { return String(localized: "いつでも") }
        return entry.item.time ?? "—"
    }

    private var endText: String? {
        guard !Logic.isAnytime(entry.item), let t = entry.item.time,
              let e = entry.item.endTime, Logic.isValidEndTime(t, e) else { return nil }
        return e
    }

    /// 状態の印に出す言葉（進行中・未対応・今日が目安 など）
    private var states: [String] {
        var out: [String] = []
        switch entry.group {
        case .active: out.append(String(localized: "進行中"))
        case .overdue: out.append(String(localized: "未対応"))
        default: break
        }
        if let due = model.nextDueText(for: entry.item, now: now) { out.append(due) }
        return out
    }

    private var streak: Int { model.streak(for: entry.item, now: now) }

    /// 「進行中」は緑、それ以外（未対応・目安日）は橙の地。字はどちらも本文の色で、色だけに頼らない
    private func stateChip(_ text: String) -> some View {
        let isActive = entry.group == .active && text == String(localized: "進行中")
        return Text(text)
            .font(.uk(14, weight: .semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background((isActive ? Theme.done : Theme.accent).opacity(0.2), in: Capsule())
    }

    /// 続けた日数。絵文字の 🔥 をやめ、橙の六角形と数字にした（2026-11-25）
    private var streakMark: some View {
        HStack(spacing: 5) {
            HexMark().fill(Theme.accent).frame(width: 12, height: 13)
            Text("\(streak)日")
                .font(.uk(15, weight: .semibold))
                .foregroundStyle(Theme.sub)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// 「前にできていた」の候補日。昨日から新しい順に、最後にやった日の翌日まで（最大7日）
    private func pastDoneRow(_ keys: [String]) -> some View {
        let yesterday = Logic.dateKey(Logic.day(now, plus: -1))
        return VStack(alignment: .leading, spacing: 8) {
            Text("済ませていた日を押すと、その日に「できた」が付き、次の目安日が数え直されます。")
                .font(.uk(14))
                .foregroundStyle(Theme.sub)
            FlowLayout(spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        let message = model.recordPastDone(entry.item, on: key, now: now)
                        pastOpen = false
                        onNotice(message)
                    } label: {
                        Text(dateChipText(key, yesterday: yesterday))
                            .font(.uk(15, weight: .medium))
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
        return key == yesterday ? String(localized: "きのう \(text)") : text
    }
}

/// 幅に収まるぶんだけ横に並べ、あふれたら次の行へ（候補日のチップ用）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // 「理想の幅」を聞かれたら（proposal.width が nil）1行ぶんの巨大な幅を返さない。
        // macOS の Form はラベル列の幅を各行の理想幅から決めるので、ここで無限に近い幅を返すと
        // 同じ Form の TextField が押しつぶされて文字が見えなくなる（2026-09-30 Mac のラベル欄で発覚）
        let width = proposal.width ?? 320
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: entry.mark == .done ? "checkmark.circle.fill" : "moon.zzz.fill")
                    .foregroundStyle(entry.mark == .done ? Theme.done : Theme.skip)
                TagDot(tag: model.tag(for: entry.item))
                Text(entry.item.label)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Button("取り消す") { model.undo(entry.item) }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.navyLight)
            }
            // 休んだ予定には「実際は…」。付けなくてもよい
            if entry.mark == .skip {
                ActualNoteRow(item: entry.item, key: Logic.dateKey(Date()))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(highlighted ? Theme.accent : Theme.plainStroke, lineWidth: highlighted ? 4 : 1.5))
        .shadow(color: highlighted ? Theme.accent.opacity(0.55) : .clear, radius: highlighted ? 8 : 0)
        .animation(.easeInOut(duration: 0.3), value: highlighted)
    }

    /// 通知を押して飛んできた相手（済んだ側にあるとき）
    private var highlighted: Bool { model.highlightedId == entry.item.id }
}

// MARK: - ボタンの見た目

struct FilledButton: ButtonStyle {
    var color: Color
    /// 今日の画面の大きいカード用（字と高さを大きく）
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .uk(19, weight: .bold) : .system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.vertical, large ? 14 : 10)
            .frame(minHeight: large ? 54 : nil)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: large ? 12 : 9))
    }
}

struct OutlineButton: ButtonStyle {
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .uk(17, weight: .semibold) : .system(size: 15, weight: .medium))
            .foregroundStyle(large ? Theme.sub : Theme.muted)
            .padding(.vertical, large ? 14 : 10)
            .frame(minHeight: large ? 54 : nil)
            .background(configuration.isPressed ? Theme.bg : Theme.card,
                        in: RoundedRectangle(cornerRadius: large ? 12 : 9))
            .overlay(RoundedRectangle(cornerRadius: large ? 12 : 9).stroke(Theme.skip, lineWidth: large ? 1.5 : 1))
    }
}


/// 日付が過ぎた1回だけの予定の1行。名前を押すと編集、右の2つで記録を付け直す
/// （ふりかえりの日別リストと同じ押し心地）
private struct PastOneOffRow: View {
    @EnvironmentObject private var model: AppModel
    let item: Item
    var onEdit: () -> Void

    private var key: String { item.date ?? "" }
    private var dateText: String { Logic.parseDateKey(item.date).map(Describe.short) ?? key }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.label)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            markButton(.done, String(localized: "できた"), Theme.done)
            markButton(.skip, String(localized: "休んだ"), Theme.skip)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.cardBg(model.tag(for: item)?.color), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Theme.cardStroke(model.tag(for: item)?.color), lineWidth: Theme.cardStrokeWidth(model.tag(for: item)?.color)))
    }

    private var statusText: String {
        switch model.mark(item, on: key) {
        case .done: return String(localized: "\(dateText)・できた")
        case .skip: return String(localized: "\(dateText)・休んだ")
        case nil: return String(localized: "\(dateText)・記録なし")
        }
    }

    private func markButton(_ mark: Mark, _ title: String, _ color: Color) -> some View {
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
}

/// 登録済み一覧の1行。今日の画面に出ていないものだけが並ぶ
private struct RegisteredRow: View {
    @EnvironmentObject private var model: AppModel
    let item: Item
    let detail: String
    /// 「終わった予定」の欄で使うとき。字を薄くして、動いている予定と見分ける
    var ended = false
    var onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) { row }.buttonStyle(.plain)
    }

    private var row: some View {
        HStack(spacing: 10) {
            TagDot(tag: model.tag(for: item))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(size: 15))
                    .foregroundStyle(item.enabled && !ended ? Theme.text : Theme.muted)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            if !item.enabled && !ended {
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
        .background(Theme.cardBg(model.tag(for: item)?.color), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Theme.cardStroke(model.tag(for: item)?.color), lineWidth: Theme.cardStrokeWidth(model.tag(for: item)?.color)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.skip.opacity(0.35), lineWidth: 1))
    }
}


/// 今日の予定がぜんぶ済んだときだけ、動物6匹が下からふわっと浮かんで消える（拡張機能の pet-party）。
/// 3.4秒で跡形なく消え、記録には残さない
private struct PetPartyView: View {
    private let pets: [(emoji: String, x: CGFloat, delay: Double)] = (0..<6).map { i in
        (CheerLogic.animals.randomElement() ?? "🐶", CGFloat.random(in: 0.08...0.92), Double(i) * 0.18)
    }
    @State private var flying = false

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(pets.enumerated()), id: \.offset) { _, p in
                Text(p.emoji)
                    .font(.system(size: 26))
                    .position(x: geo.size.width * p.x,
                              y: flying ? geo.size.height * 0.22 : geo.size.height + 20)
                    .rotationEffect(.degrees(flying ? 12 : 0))
                    .opacity(flying ? 0 : 1)
                    .animation(.easeOut(duration: 2.6).delay(p.delay), value: flying)
            }
        }
        .onAppear { flying = true }
    }
}
