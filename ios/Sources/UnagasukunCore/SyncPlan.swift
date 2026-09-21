import Foundation

/// 同期のときに「何をするか」だけを決める。通信はしない。
///
/// ここを間違えると**記録が消える**。iCloud に繋がずに確かめられるよう、
/// 判断だけを純粋な関数に切り出してある。
public enum SyncPlan {

    public struct Decision: Equatable, Sendable {
        /// 混ぜた結果
        public var merged: Snapshot
        /// 手元を書き換える必要があるか
        public var updateLocal: Bool
        /// iCloud に上げる必要があるか
        public var push: Bool
    }

    /// - Parameter remote: iCloud にある分。まだ1度も上げていなければ nil
    public static func decide(local: Snapshot, remote: Snapshot?) -> Decision {
        guard let remote else {
            // まだ向こうに何も無い。**手元が空でも上げる**
            // （空のまま上げないと、2台目が「向こうには何も無い」と判断できない）
            return Decision(merged: local, updateLocal: false, push: true)
        }

        let merged = Merge.snapshots(local, remote)
        return Decision(
            merged: merged,
            updateLocal: !merged.sameContent(as: local),
            push: !merged.sameContent(as: remote)
        )
    }
}
