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

    /// 中身が同じか。`updatedAt` は見ない。
    /// 同期で「上げ直す必要があるか」を決めるのに使う（時刻だけ違うものを上げ続けないため）
    public func sameContent(as other: Snapshot) -> Bool {
        schedule == other.schedule && records == other.records
    }

    public init(schedule: [Item] = [], records: Records = [:], updatedAt: Double = 0) {
        self.schedule = schedule
        self.records = records
        self.updatedAt = updatedAt
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

        return Snapshot(
            schedule: newer.schedule,
            records: records,
            updatedAt: max(a.updatedAt, b.updatedAt)
        )
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
