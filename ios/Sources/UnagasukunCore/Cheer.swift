import Foundation

/// 「できた」のあとに出す一言。拡張機能 v1.5.0 の「こっそりお祝い」をそのまま移した。
///
/// どこにも説明を書かない・記録に残さない・出なくても何も失わない（責めない設計の裏返し）。
/// 定石は Finch（小さな達成をすべて祝う・休んでも罰しない）。Duolingo の損失回避型は採らない。
public struct Cheer: Equatable, Sendable {
    public var text: String
    /// 動物が1匹だけ顔を出す（ふだんは 25%・お祝いのときは必ず）
    public var emoji: String?
    /// 今日の予定がぜんぶ「できた」。動物6匹がふわっと浮かぶ
    public var party: Bool

    public init(text: String, emoji: String? = nil, party: Bool = false) {
        self.text = text; self.emoji = emoji; self.party = party
    }
}

public enum CheerLogic {
    public static let animals = ["🐶", "🐱", "🐹", "🐰", "🐻", "🐧", "🦔", "🐿️", "🐥", "🦊"]

    /// ふだんの応援ことば（拡張機能の praise1〜5 と同じ）
    public static let praises = [
        "済みにしました。おつかれさま！",
        "いいペースです。この調子！",
        "またひとつ前に進みました",
        "ちゃんと続いています。すばらしい！",
        "今日の分、きちんと積み上がりました",
    ]

    /// 優先順位は ぜんぶ済み > 節目 > ふだん。**記録を付けたあと**に呼ぶ（今日の分を数えるため）。
    /// 1回だけ・◯日ごとは節目を数えない（拡張機能と同じ）
    public static func afterDone<G: RandomNumberGenerator>(
        _ item: Item, schedule: [Item], records: Records, now: Date, using g: inout G
    ) -> Cheer {
        if Logic.allDoneToday(schedule, records, now) {
            return Cheer(text: "今日のよてい、ぜんぶできました！おめでとう🎉",
                         emoji: animals.randomElement(using: &g), party: true)
        }
        if !Logic.isOneOff(item) && !Logic.isInterval(item) {
            let streak = Logic.streakFor(records, item.origId ?? item.id, now, item.days)
            if Logic.isStreakMilestone(streak) {
                return Cheer(text: "\(streak)日つづいています。おめでとう！",
                             emoji: animals.randomElement(using: &g))
            }
        }
        let emoji = Double.random(in: 0..<1, using: &g) < 0.25 ? animals.randomElement(using: &g) : nil
        return Cheer(text: praises.randomElement(using: &g) ?? praises[0], emoji: emoji)
    }

    public static func afterDone(_ item: Item, schedule: [Item], records: Records, now: Date) -> Cheer {
        var g = SystemRandomNumberGenerator()
        return afterDone(item, schedule: schedule, records: records, now: now, using: &g)
    }
}
