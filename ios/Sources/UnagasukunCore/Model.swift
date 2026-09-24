import Foundation

/// 予定1件。拡張機能の `schedule` 配列の要素をそのまま写したもの。
/// 判定の意味は extension/logic.js のコメントが正本。ここでは形だけ持つ。
public struct Item: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    /// "HH:MM"。時刻を固定しない予定は nil
    public var time: String?
    /// "YYYY-MM-DD"。1回だけの予定だけが持つ
    public var date: String?
    /// 0=日 〜 6=土。空または nil で（date も無ければ）毎日
    public var days: [Int]?
    public var enabled: Bool
    /// 時刻を決めず、1日の目安分数だけ決める予定
    public var anytime: Bool
    public var targetMin: Int?
    /// 「◯日ごと」。済ませた日から数え直す
    public var intervalDays: Int?
    /// 目安日の何日前から今日の予定に出すか（未設定は3）。拡張機能用の設定で、アプリは当日から出す
    public var noticeDays: Int?
    /// 登録時に入れる「最後にやった日」
    public var anchorDate: String?
    /// 日付が過ぎた1回だけの予定。一覧にも通知にも出さないが、名前を引くために残す
    public var archived: Bool
    /// やりなおしコピー。記録は元の予定に付くので集計から外す
    public var origId: String?
    public var endTime: String?
    /// 詳細メモ（任意）。拡張機能と同じ項目。今日のカードと通知の本文に出す（2026-09-24 本人指摘で追加）
    public var detail: String?

    /// 拡張機能の JSON は false のときにキーごと省くことがある（`anytime` `archived` `enabled`）。
    /// 素の Codable だと欠けたキーで丸ごと失敗するので、無ければ既定値で読む
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        time = try c.decodeIfPresent(String.self, forKey: .time)
        date = try c.decodeIfPresent(String.self, forKey: .date)
        days = try c.decodeIfPresent([Int].self, forKey: .days)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        anytime = try c.decodeIfPresent(Bool.self, forKey: .anytime) ?? false
        targetMin = try c.decodeIfPresent(Int.self, forKey: .targetMin)
        intervalDays = try c.decodeIfPresent(Int.self, forKey: .intervalDays)
        noticeDays = try c.decodeIfPresent(Int.self, forKey: .noticeDays)
        anchorDate = try c.decodeIfPresent(String.self, forKey: .anchorDate)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        origId = try c.decodeIfPresent(String.self, forKey: .origId)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
    }

    public init(
        id: String, label: String = "", time: String? = nil, date: String? = nil,
        days: [Int]? = nil, enabled: Bool = true, anytime: Bool = false, targetMin: Int? = nil,
        intervalDays: Int? = nil, noticeDays: Int? = nil, anchorDate: String? = nil,
        archived: Bool = false, origId: String? = nil, endTime: String? = nil, detail: String? = nil
    ) {
        self.id = id; self.label = label; self.time = time; self.date = date
        self.days = days; self.enabled = enabled; self.anytime = anytime; self.targetMin = targetMin
        self.intervalDays = intervalDays; self.noticeDays = noticeDays; self.anchorDate = anchorDate
        self.archived = archived; self.origId = origId; self.endTime = endTime; self.detail = detail
    }
}

/// その日の記録。"できた" は .done、"今日は休む" は .skip
public enum Mark: String, Codable, Equatable, Sendable {
    case done
    case skip
}

/// 日付キー("YYYY-MM-DD") → 予定ID → 記録
public typealias Records = [String: [String: Mark]]

/// 予告ポップアップの設定（v1.7.0）
public struct PreNotice: Equatable, Sendable {
    public var on: Bool
    public var minutes: Int
    public init(on: Bool, minutes: Int) { self.on = on; self.minutes = minutes }
}

/// 「◯日ごと」の予定がいま何日目か
public struct IntervalDue: Equatable, Sendable {
    /// 目安日まであと何日。0=今日、負=過ぎている
    public var daysUntil: Int
    /// 最後にやってから何日。基準が無ければ nil
    public var sinceDone: Int?
    public init(daysUntil: Int, sinceDone: Int?) {
        self.daysUntil = daysUntil; self.sinceDone = sinceDone
    }
}
