import Foundation

/// 予定と記録の入れ物。**拡張機能の `chrome.storage.local` と同じ形のまま持つ。**
///
/// SwiftData を使わずに素の JSON で持っているのは、あとで同期を足すときに
/// **この JSON をそのまま暗号化して送れる**ようにするため。
/// アプリ側だけ独自の形にすると、同期のたびに変換が要り、変換のたびに食い違いが生まれる。
public struct Snapshot: Codable, Equatable, Sendable {
    public var schedule: [Item]
    public var records: Records
    /// 同期で「新しいほう」を選ぶのに使う（拡張側にも同じものを足す）
    public var updatedAt: Double
    /// 記録の操作履歴。"YYYY-MM-DD|予定ID" → 最後の操作。
    ///
    /// `records` は同期で足し合わせるので、**手元で消した記録は向こうの写しで戻ってしまう**
    /// （「できた」を押し直したらすぐ戻る・2026-09-24 本人報告）。「消した」も伝わるよう、
    /// 操作の時刻つきで残し、混ぜるときは新しい操作を採る。拡張機能から取り込んだ古い記録には
    /// 履歴が無いので、そこは従来どおり足し合わせ
    public var recordLog: [String: RecordEntry]
    /// 「実際は…」の一言。日付 → 予定ID → 文（拡張機能の `notes` と同じ形）
    public var notes: Notes
    /// notes の操作履歴（records と同じ理由。消したことも同期で伝える）
    public var noteLog: [String: NoteEntry]

    /// 中身が同じか。`updatedAt` は見ない。
    /// 同期で「上げ直す必要があるか」を決めるのに使う（時刻だけ違うものを上げ続けないため）
    public func sameContent(as other: Snapshot) -> Bool {
        schedule == other.schedule && records == other.records && recordLog == other.recordLog
            && notes == other.notes && noteLog == other.noteLog
    }

    public init(schedule: [Item] = [], records: Records = [:], updatedAt: Double = 0,
                recordLog: [String: RecordEntry] = [:], notes: Notes = [:],
                noteLog: [String: NoteEntry] = [:]) {
        self.schedule = schedule
        self.records = records
        self.updatedAt = updatedAt
        self.recordLog = recordLog
        self.notes = notes
        self.noteLog = noteLog
    }

    /// 履歴を足す前に保存したファイルにはキーが無いので、無ければ空で読む
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedule = try c.decode([Item].self, forKey: .schedule)
        records = try c.decode(Records.self, forKey: .records)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0
        recordLog = try c.decodeIfPresent([String: RecordEntry].self, forKey: .recordLog) ?? [:]
        notes = try c.decodeIfPresent(Notes.self, forKey: .notes) ?? [:]
        noteLog = try c.decodeIfPresent([String: NoteEntry].self, forKey: .noteLog) ?? [:]
    }

    /// 「実際は…」を付ける・直す・消す入口。空文字や空白だけなら消す。30字まで
    public mutating func setNote(_ text: String?, item id: String, on day: String,
                                 at: Double = Date().timeIntervalSince1970 * 1000) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value: String? = trimmed.isEmpty ? nil : String(trimmed.prefix(ActualNote.maxLength))
        var d = notes[day] ?? [:]
        if let value { d[id] = value } else { d.removeValue(forKey: id) }
        if d.isEmpty { notes.removeValue(forKey: day) } else { notes[day] = d }
        noteLog[Self.logKey(day, id)] = NoteEntry(text: value, at: at)
    }

    /// 記録を付ける・付け直す・消す入口。**アプリからの記録の変更は必ずここを通す**
    /// （`records` を直接いじると履歴が残らず、同期で戻される）。`mark` が nil なら消す
    public mutating func setMark(_ mark: Mark?, item id: String, on day: String,
                                 at: Double = Date().timeIntervalSince1970 * 1000) {
        var d = records[day] ?? [:]
        if let mark { d[id] = mark } else { d.removeValue(forKey: id) }
        if d.isEmpty { records.removeValue(forKey: day) } else { records[day] = d }
        recordLog[Self.logKey(day, id)] = RecordEntry(mark: mark, at: at)
    }

    static func logKey(_ day: String, _ id: String) -> String { "\(day)|\(id)" }
}

/// 日付 → 予定ID → 「実際は…」の文
public typealias Notes = [String: [String: String]]

/// 「実際は…」の1操作。`text` が nil なら「消した」
public struct NoteEntry: Codable, Equatable, Sendable {
    public var text: String?
    public var at: Double
    public init(text: String?, at: Double) { self.text = text; self.at = at }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(at, forKey: .at)
    }
}

/// 「実際は…」の選択肢。拡張機能と同じ4つ。**責める言葉は使わない**（成績表でなく、予定の側を直す材料）
public enum ActualNote {
    public static let choices = ["別の作業", "休憩", "ブラウジング", "気分が乗らず"]
    public static let maxLength = 30
}

/// 記録の1操作。`mark` が nil なら「消した」
public struct RecordEntry: Codable, Equatable, Sendable {
    public var mark: Mark?
    /// 操作した時刻（ms）
    public var at: Double

    public init(mark: Mark?, at: Double) { self.mark = mark; self.at = at }

    /// `mark` が nil のときもキーを書く（無いキーと区別しなくてよいが、読みやすさのため）
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mark, forKey: .mark)
        try c.encode(at, forKey: .at)
    }
}

public enum MergeError: Error, Equatable {
    case notImplemented
}

public enum Merge {
    /// 2台ぶんを1つにまとめる。**records は足し合わせ、schedule は新しいほうを採る。**
    ///
    /// records を「新しいほうで丸ごと上書き」にすると、iPhone で付けた記録が
    /// Mac を開いた瞬間に消える。習慣アプリでこれをやると、その時点で信用を失う。
    ///
    /// 同じ日の同じ予定に別々の記録が付いた場合だけ、決め方が要る。
    /// **「できた」を優先する**（「休む」で上書きされて記録が消えるより、
    /// 残るほうが本人の不利益が小さい）。
    public static func snapshots(_ a: Snapshot, _ b: Snapshot) -> Snapshot {
        let newer = a.updatedAt >= b.updatedAt ? a : b

        var records = a.records
        for (day, marks) in b.records {
            var merged = records[day] ?? [:]
            for (id, mark) in marks {
                if merged[id] == .done { continue }   // 「できた」は譲らない
                merged[id] = mark
            }
            records[day] = merged
        }

        // 操作履歴があるものは、足し合わせより履歴を信じる（新しい操作が勝つ。「消した」も伝わる）
        var log = a.recordLog
        for (k, e) in b.recordLog where log[k].map({ RecordEntry.isNewer(e, than: $0) }) ?? true {
            log[k] = e
        }
        for (k, e) in log {
            guard let sep = k.firstIndex(of: "|") else { continue }
            let day = String(k[..<sep]), id = String(k[k.index(after: sep)...])
            var d = records[day] ?? [:]
            if let m = e.mark { d[id] = m } else { d.removeValue(forKey: id) }
            if d.isEmpty { records.removeValue(forKey: day) } else { records[day] = d }
        }
        // 1年より古い履歴は捨てる（その頃には全端末に行き渡っている）
        let cutoff = max(a.updatedAt, b.updatedAt) - 365 * 86_400_000
        log = log.filter { $0.value.at >= cutoff }

        // 「実際は…」も同じ考え方: 足し合わせ（手元優先）→ 履歴のあるものは新しい操作で上書き
        var notes = a.notes
        for (day, texts) in b.notes {
            var merged = notes[day] ?? [:]
            for (id, t) in texts where merged[id] == nil { merged[id] = t }
            notes[day] = merged
        }
        var nlog = a.noteLog
        for (k, e) in b.noteLog where nlog[k].map({ e.at > $0.at }) ?? true { nlog[k] = e }
        for (k, e) in nlog {
            guard let sep = k.firstIndex(of: "|") else { continue }
            let day = String(k[..<sep]), id = String(k[k.index(after: sep)...])
            var d = notes[day] ?? [:]
            if let t = e.text { d[id] = t } else { d.removeValue(forKey: id) }
            if d.isEmpty { notes.removeValue(forKey: day) } else { notes[day] = d }
        }
        nlog = nlog.filter { $0.value.at >= cutoff }

        return Snapshot(
            schedule: newer.schedule,
            records: records,
            updatedAt: max(a.updatedAt, b.updatedAt),
            recordLog: log,
            notes: notes,
            noteLog: nlog
        )
    }
}

extension RecordEntry {
    /// 新しい操作が勝つ。同時刻なら「できた」＞「休んだ」＞「消した」（どちらから混ぜても同じ答えにするため）
    static func isNewer(_ e: RecordEntry, than cur: RecordEntry) -> Bool {
        if e.at != cur.at { return e.at > cur.at }
        return rank(e.mark) > rank(cur.mark)
    }
    private static func rank(_ m: Mark?) -> Int {
        switch m { case .done: return 2; case .skip: return 1; case nil: return 0 }
    }
}

/// 拡張機能から書き出したファイルの形。`schedule`・`records`・`notes`（実際は…）を読む
public struct ExportFile: Codable {
    public var schedule: [Item]
    public var records: Records
    public var notes: Notes?

    public init(schedule: [Item], records: Records, notes: Notes? = nil) {
        self.schedule = schedule; self.records = records; self.notes = notes
    }
}

extension Merge {
    /// 拡張機能から取り込む。**同期の Merge とは違い、予定は「足す」。**
    /// 同期は「新しいほうの予定一覧を丸ごと採る」（消した予定を復活させないため）が、
    /// 取り込みでそれをやると、手元が空でないときに片方が丸ごと消える。
    /// - 手元に同じ ID があれば手元を残す（手元で直した内容を上書きしない）
    /// - 記録は同期と同じく足し合わせ、同じ日は「できた」を残す
    public static func importing(local: Snapshot, imported: ExportFile) -> Snapshot {
        let have = Set(local.schedule.map(\.id))
        var schedule = local.schedule
        schedule += imported.schedule.filter { !have.contains($0.id) }

        var records = local.records
        for (day, marks) in imported.records {
            var merged = records[day] ?? [:]
            for (id, mark) in marks where merged[id] != .done { merged[id] = mark }
            records[day] = merged
        }
        // 「実際は…」は手元に無い日だけ足す
        var notes = local.notes
        for (day, texts) in imported.notes ?? [:] {
            var merged = notes[day] ?? [:]
            for (id, t) in texts where merged[id] == nil { merged[id] = t }
            notes[day] = merged
        }
        return Snapshot(schedule: schedule, records: records,
                        updatedAt: Date().timeIntervalSince1970 * 1000,
                        recordLog: local.recordLog, notes: notes, noteLog: local.noteLog)
    }
}

/// 端末のディスクに置く。Application Support の中の1ファイル。
public final class SnapshotStore {
    private let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let dir = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Unagasukun", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snapshot.json")
    }

    public func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }

    // MARK: - 控え

    /// 同期で手元を書き換える**直前**の中身を残しておく。
    ///
    /// `Merge` も `SyncPlan` もテストしてあるが、**記録が消えたときに戻せる場所が無い**のは別の話。
    /// 習慣アプリで記録が消えると、そこで使うのをやめる。保険は安い
    private var backupDir: URL {
        url.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
    }

    /// 残す数。これを超えた古いものから消す
    public static let backupLimit = 5

    public func saveBackup(_ snapshot: Snapshot, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = Int(date.timeIntervalSince1970 * 1000)
        let file = backupDir.appendingPathComponent("snapshot-\(stamp).json")
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
        pruneBackups()
    }

    /// 新しい順
    public func backups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("snapshot-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public func loadBackup(_ file: URL) throws -> Snapshot {
        try JSONDecoder().decode(Snapshot.self, from: try Data(contentsOf: file))
    }

    private func pruneBackups() {
        for old in backups().dropFirst(Self.backupLimit) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// 書き込みは一時ファイル経由。途中で落ちても、読めないファイルを残さない
    public func save(_ snapshot: Snapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
