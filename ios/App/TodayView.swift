import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAdd = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let (todo, done) = model.today(now: now)

        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if todo.isEmpty && done.isEmpty {
                        emptyState
                    } else {
                        if !todo.isEmpty {
                            sectionTitle("今日の予定", count: todo.count)
                            ForEach(todo, id: \.item.id) { entry in
                                TodoCard(entry: entry, now: now)
                            }
                        }
                        if !done.isEmpty {
                            sectionTitle("今日対応済み", count: done.count)
                            ForEach(done, id: \.item.id) { entry in
                                DoneCard(entry: entry)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.bg)
        .onReceive(tick) { now = $0 }
        .sheet(isPresented: $showingAdd) { AddPlanView() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("うながすくん")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Button { showingAdd = true } label: {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timeText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.navy)
                    .monospacedDigit()
                Text(entry.item.label)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }

            if !subtitles.isEmpty {
                HStack(spacing: 8) {
                    ForEach(subtitles, id: \.self) { chip($0) }
                }
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
