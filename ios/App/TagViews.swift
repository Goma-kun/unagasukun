import SwiftUI

/// ラベルの色つきチップ（名前の右に置く小さな印）。
/// 色は仕分けの目印なので、地を薄く・点を濃くして、状態の印（進行中・未対応）より控えめにする
struct TagChip: View {
    let tag: Tag
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.tagColor(tag.color)).frame(width: 7, height: 7)
            Text(tag.name).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Theme.tagColor(tag.color).opacity(0.14), in: Capsule())
    }
}

/// 一覧の行に置く、名前の前の小さな点
struct TagDot: View {
    let tag: Tag?
    var body: some View {
        if let tag {
            Circle().fill(Theme.tagColor(tag.color)).frame(width: 8, height: 8)
        }
    }
}

/// カードの左端の細い帯
struct TagStripe: View {
    let tag: Tag?
    var body: some View {
        if let tag {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.tagColor(tag.color))
                .frame(width: 4)
                .padding(.vertical, 12)
                .padding(.leading, 6)
        }
    }
}

/// 今日の画面の上の絞り込み。「すべて」＋使っているラベルだけ
struct TagFilterBar: View {
    let tags: [Tag]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(nil)
                ForEach(tags) { filterChip($0) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Theme.bg)
    }

    private func filterChip(_ tag: Tag?) -> some View {
        let id = tag?.id ?? ""
        let on = selected == id
        let color = tag.map { Theme.tagColor($0.color) } ?? Theme.tint
        return Button { withAnimation(.easeInOut(duration: 0.15)) { selected = on && tag != nil ? "" : id } } label: {
            HStack(spacing: 5) {
                if let tag { Circle().fill(on ? Color.white : Theme.tagColor(tag.color)).frame(width: 7, height: 7) }
                Text(tag?.name ?? "すべて").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(on ? .white : Theme.text)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(on ? color : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(on ? color : Theme.skip.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 登録フォームでラベルを選ぶ列。「なし」＋ラベル。押すと選ぶ／もう一度押すと外す
struct TagPickerRow: View {
    let tags: [Tag]
    @Binding var selected: String?

    var body: some View {
        FlowLayout(spacing: 8) {
            pickChip(nil)
            ForEach(tags) { pickChip($0) }
        }
    }

    private func pickChip(_ tag: Tag?) -> some View {
        let on = selected == tag?.id
        let color = tag.map { Theme.tagColor($0.color) } ?? Theme.muted
        return Button { selected = tag?.id } label: {
            HStack(spacing: 5) {
                if let tag { Circle().fill(on ? Color.white : Theme.tagColor(tag.color)).frame(width: 7, height: 7) }
                Text(tag?.name ?? "なし").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(on ? .white : Theme.text)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(on ? color : Theme.bg, in: Capsule())
            .overlay(Capsule().stroke(on ? color : Theme.skip, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// ラベルを整える画面。名前・色・「🔥 とタイルに数える」・削除・追加。
/// 「保存」を押すまで本体には触らない（途中でやめても元のまま）
struct TagEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [Tag] = []
    @State private var confirmingDelete: Tag? = nil

    var body: some View {
        NavigationStack {
            Form {
                ForEach($tags) { $tag in
                    Section {
                        TextField("ラベルの名前", text: $tag.name)
                            .onChange(of: tag.name) { _, v in
                                if v.count > Tag.nameMaxLength { tag.name = String(v.prefix(Tag.nameMaxLength)) }
                            }
                        HStack(spacing: 10) {
                            ForEach(Tag.colorKeys, id: \.self) { key in
                                Button { tag.color = key } label: {
                                    Circle()
                                        .fill(Theme.tagColor(key))
                                        .frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Theme.text, lineWidth: tag.color == key ? 2.5 : 0).padding(-3))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(key)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        Toggle("🔥 とタイルに数える", isOn: $tag.countsStreak)
                        Button("このラベルを消す", role: .destructive) { confirmingDelete = tag }
                    } footer: {
                        if !tag.countsStreak {
                            Text("買い物のように「習慣」でないものは、数えないほうが気が楽です。忘れても続けた日数は切れません。")
                        }
                    }
                }
                Section {
                    Button {
                        let used = Set(tags.map(\.color))
                        let color = Tag.colorKeys.first { !used.contains($0) } ?? Tag.colorKeys[tags.count % Tag.colorKeys.count]
                        tags.append(Tag(name: "", color: color))
                    } label: {
                        Label("ラベルを足す", systemImage: "plus")
                    }
                } footer: {
                    Text("ラベルを消しても、予定と記録は残ります。その予定は「ラベルなし」に戻ります。")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 480, idealWidth: 480, minHeight: 560)
            #endif
            .navigationTitle("ラベル")
            .compactNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let cleaned = tags.map { t -> Tag in
                            var t = t; t.name = t.name.trimmingCharacters(in: .whitespaces); return t
                        }.filter { !$0.name.isEmpty }
                        model.setTags(cleaned)
                        dismiss()
                    }
                }
            }
            .onAppear { tags = model.tags }
            .confirmationDialog("このラベルを消しますか？", isPresented: Binding(get: { confirmingDelete != nil },
                                                                     set: { if !$0 { confirmingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("消す", role: .destructive) {
                    if let t = confirmingDelete { tags.removeAll { $0.id == t.id } }
                    confirmingDelete = nil
                }
                Button("やめる", role: .cancel) { confirmingDelete = nil }
            } message: {
                Text("付いていた予定は「ラベルなし」に戻ります。記録はそのまま残ります。")
            }
        }
    }
}
