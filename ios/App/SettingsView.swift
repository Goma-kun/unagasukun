import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private let minuteChoices = [3, 5, 10, 15, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("設定").font(.system(size: 17, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.navy)

            Form {
                Section {
                    Toggle("iCloud で揃える", isOn: $model.syncEnabled)
                    HStack(spacing: 8) {
                        Image(systemName: syncIcon).foregroundStyle(syncColor)
                        Text(syncText).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("ほかの端末と")
                } footer: {
                    Text("同じ Apple アカウントの iPhone や Mac と、予定と記録が揃います。"
                         + "データはあなたの iCloud に入ります。こちらからは見えません。")
                }

                Section {
                    Toggle("早めにお知らせする", isOn: $model.preNoticeOn)
                    if model.preNoticeOn {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3),
                                  spacing: 8) {
                            ForEach(minuteChoices, id: \.self) { m in
                                Button { model.preNoticeMin = m } label: {
                                    Text("\(m)分前")
                                        .font(.system(size: 14, weight: .medium))
                                        .frame(maxWidth: .infinity).frame(height: 34)
                                        .background(model.preNoticeMin == m ? Theme.navy : Theme.bg,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(model.preNoticeMin == m ? .white : Theme.muted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("お知らせ")
                } footer: {
                    Text(model.preNoticeOn
                         ? "予定の時刻より前に、一度お知らせします。済ませたものには出しません。"
                         : "予定の時刻にだけお知らせします。")
                }

                if !model.notificationsWorking {
                    Section {
                        Button("通知の設定を開く") { Platform.openNotificationSettings() }
                    } footer: {
                        Text("通知がオフのため、時間が来てもお知らせできません。")
                    }
                }
            }
        }
        .background(Theme.bg)
        .task { await model.syncNow() }
    }

    private var syncIcon: String {
        switch model.syncState {
        case .ok: return "checkmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .off: return "icloud.slash"
        case .unavailable, .failed: return "exclamationmark.icloud"
        }
    }

    private var syncColor: Color {
        switch model.syncState {
        case .ok: return Theme.done
        case .syncing: return Theme.muted
        case .off: return Theme.skip
        case .unavailable, .failed: return Theme.accent
        }
    }

    private var syncText: String {
        switch model.syncState {
        case .off: return "この端末の中だけで使っています"
        case .syncing: return "揃えています…"
        case .ok(let at): return "最後に揃えたのは \(timeText(at))"
        case .unavailable(let why): return why
        case .failed(let why): return why
        }
    }

    private func timeText(_ d: Date) -> String {
        let c = Logic.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
