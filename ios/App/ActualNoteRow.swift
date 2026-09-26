import SwiftUI

/// 「実際は…」の行。休んだ予定と、時間が過ぎて記録が無い予定に付ける（拡張機能と同じ）。
///
/// 「できた」「休んだ」とは別枠の一言で、記録の種類は増やさない。狙いは成績表ではなく
/// **予定の側を直す材料**（「気分が乗らず」が続くなら時間を変える）。責める言葉は使わない。
/// 付けなくても何も起きない。付けたあとは「実際は：休憩」と出て、押せば直せる
struct ActualNoteRow: View {
    @EnvironmentObject private var model: AppModel
    let item: Item
    let key: String
    /// 何も付いていないときに、選択肢を最初から開いておくか（今日の画面は開く・カレンダーは閉じる）
    var openByDefault = true

    @State private var editing = false
    @State private var freeText = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let note = model.note(for: item, on: key)
        VStack(alignment: .leading, spacing: 6) {
            if let note, !editing {
                Button {
                    text = ActualNote.choices.contains(note) ? "" : note
                    freeText = !ActualNote.choices.contains(note)
                    withAnimation(.easeInOut(duration: 0.15)) { editing = true }
                } label: {
                    HStack(spacing: 6) {
                        Text("実際は：\(note)")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text)
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("実際は \(note)。押すと直せます")
            } else if note == nil && !openByDefault && !editing {
                Button { withAnimation(.easeInOut(duration: 0.15)) { editing = true } } label: {
                    Text("実際は…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    Text("実際は…")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    if note != nil {
                        Button("消す") { save(nil) }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .buttonStyle(.plain)
                    }
                    if editing || !openByDefault {
                        Button("閉じる") { withAnimation { editing = false; freeText = false } }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .buttonStyle(.plain)
                    }
                }
                if freeText {
                    HStack(spacing: 8) {
                        TextField("なにをしていたか（短くでOK）", text: $text)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .focused($focused)
                            .onSubmit { save(text) }
                            .onChange(of: text) { _, v in
                                if v.count > ActualNote.maxLength { text = String(v.prefix(ActualNote.maxLength)) }
                            }
                        Button("記録") { save(text) }
                            .font(.system(size: 13, weight: .medium))
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("戻る") { freeText = false }
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .buttonStyle(.plain)
                    }
                } else {
                    // 4つの選択肢＋「その他…」。狭い画面では2段に折り返す
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)],
                              alignment: .leading, spacing: 6) {
                        ForEach(ActualNote.choices, id: \.self) { c in
                            chip(c, selected: c == note) { save(c) }
                        }
                        chip("その他…", selected: false) {
                            freeText = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : Theme.muted)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(selected ? Theme.tint : Theme.bg, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save(_ value: String?) {
        model.setNote(value, item: item, on: key)
        withAnimation(.easeInOut(duration: 0.15)) { editing = false; freeText = false }
        text = ""
    }
}
