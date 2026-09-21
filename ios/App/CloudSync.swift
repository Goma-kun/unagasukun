import CloudKit
import Foundation

/// iCloud（CloudKit）での端末間の同期。
///
/// リマインダーやメモと同じ仕組み。**サーバーは用意しない。アカウントも作らせない。**
/// データはその人の iCloud の「私用データベース」に入るので、こちらからは見えない。
///
/// 置き方は **`Snapshot` の JSON をまるごと1レコード**にする。
/// 予定ごとにレコードを分けないのは、拡張機能と同じ形のまま持つと決めてあるから。
/// ぶつかったときは `Merge.snapshots` がそのまま使える。
@MainActor
final class CloudSync {

    /// 画面に出す状態。**うまくいっていないことを黙っていない**ための型
    enum State: Equatable {
        /// 同期をオフにしている
        case off
        /// iCloud にサインインしていないなど、こちらではどうにもならない理由
        case unavailable(String)
        case syncing
        case ok(Date)
        case failed(String)
    }

    /// **起動時には作らない。** `CKContainer(identifier:)` は
    /// iCloud の権利が無いビルドだと、例外ではなく**その場で落ちる**（catch できない）。
    /// 同期を実際に使うときまで遅らせておけば、少なくとも画面は開く
    private lazy var container = CKContainer(identifier: "iCloud.jp.nishira.unagasukun")
    private var db: CKDatabase { container.privateCloudDatabase }
    private let recordID = CKRecord.ID(recordName: "snapshot")
    private let recordType = "Snapshot"

    /// 直前に取ってきたレコード。保存のときに使い回す（毎回取り直さないため）
    private var cached: CKRecord?

    // MARK: - サインインしているか

    func availability() async -> State? {
        do {
            switch try await container.accountStatus() {
            case .available:
                return nil   // 使える
            case .noAccount:
                return .unavailable("iCloud にサインインすると、ほかの端末と揃います")
            case .restricted:
                return .unavailable("この端末では iCloud の利用が制限されています")
            case .couldNotDetermine, .temporarilyUnavailable:
                return .unavailable("iCloud に接続できませんでした")
            @unknown default:
                return .unavailable("iCloud の状態が分かりませんでした")
            }
        } catch {
            return .unavailable("iCloud に接続できませんでした")
        }
    }

    // MARK: - 取ってくる

    /// iCloud にある分を取ってくる。まだ何も無ければ nil
    func pull() async throws -> Snapshot? {
        do {
            let record = try await db.record(for: recordID)
            cached = record
            return Self.decode(record)
        } catch let error as CKError where error.code == .unknownItem {
            cached = nil
            return nil   // まだ1度も上げていない
        }
    }

    // MARK: - 上げる

    /// こちらの分を上げる。**向こうが進んでいたら、その場で混ぜて上げ直す。**
    /// 戻り値は実際に iCloud に載った内容（混ざった結果のことがある）
    @discardableResult
    func push(_ snapshot: Snapshot) async throws -> Snapshot {
        do {
            return try await save(snapshot, base: cached)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // 2台で同時に触ると必ずここを通る。**片方を捨ててはいけない**
            guard let server = error.serverRecord else { throw error }
            let merged = Merge.snapshots(snapshot, Self.decode(server) ?? Snapshot())
            cached = server
            return try await save(merged, base: server)
        }
    }

    private func save(_ snapshot: Snapshot, base: CKRecord?) async throws -> Snapshot {
        let record = base ?? CKRecord(recordType: recordType, recordID: recordID)
        record["data"] = try JSONEncoder().encode(snapshot) as CKRecordValue
        record["updatedAt"] = snapshot.updatedAt as CKRecordValue
        cached = try await db.save(record)
        return snapshot
    }

    private static func decode(_ record: CKRecord) -> Snapshot? {
        guard let data = record["data"] as? Data else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
