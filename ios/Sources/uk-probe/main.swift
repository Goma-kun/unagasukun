import Foundation
import UnagasukunCore

// JS版と答えを突き合わせるためだけの入口。
// 標準入力に {"cases":[...]} を受け取り、1件ずつ Logic を呼んで結果をJSONで返す。
// アプリからは使わない。../test/parity_test.mjs が使う。

func item(_ d: [String: Any]?) -> Item {
    let d = d ?? [:]
    var days: [Int]? = nil
    if let a = d["days"] as? [Any] { days = a.compactMap { ($0 as? NSNumber)?.intValue } }
    return Item(
        id: d["id"] as? String ?? "",
        label: d["label"] as? String ?? "",
        time: d["time"] as? String,
        date: d["date"] as? String,
        days: days,
        enabled: (d["enabled"] as? NSNumber)?.boolValue ?? (d["enabled"] == nil),
        anytime: (d["anytime"] as? NSNumber)?.boolValue ?? false,
        targetMin: (d["targetMin"] as? NSNumber)?.intValue,
        intervalDays: (d["intervalDays"] as? NSNumber)?.intValue,
        noticeDays: (d["noticeDays"] as? NSNumber)?.intValue,
        anchorDate: d["anchorDate"] as? String,
        archived: (d["archived"] as? NSNumber)?.boolValue ?? false,
        origId: d["origId"] as? String,
        endTime: d["endTime"] as? String
    )
}

func records(_ d: [String: Any]?) -> Records {
    var out: Records = [:]
    for (k, v) in d ?? [:] {
        guard let inner = v as? [String: Any] else { continue }
        var marks: [String: Mark] = [:]
        for (id, m) in inner { if let s = m as? String, let mark = Mark(rawValue: s) { marks[id] = mark } }
        out[k] = marks
    }
    return out
}

func date(_ v: Any?) -> Date {
    Date(timeIntervalSince1970: ((v as? NSNumber)?.doubleValue ?? 0) / 1000)
}

/// 無限大と NaN は JSON に載らないので、両側とも文字列で表す
func msOut(_ v: Double) -> Any {
    if v.isNaN { return "NaN" }
    return v.isFinite ? v : "Infinity"
}

func run(_ c: [String: Any]) -> Any {
    let fn = c["fn"] as? String ?? ""
    let it = item(c["item"] as? [String: Any])
    let rec = records(c["records"] as? [String: Any])
    let now = date(c["now"])
    let sched = (c["schedule"] as? [[String: Any]] ?? []).map { item($0) }

    switch fn {
    case "dateKey": return Logic.dateKey(now)
    case "isScheduledOn":
        let days = (c["days"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
        return Logic.isScheduledOn(days, now)
    case "isOneOff": return Logic.isOneOff(it)
    case "isAnytime": return Logic.isAnytime(it)
    case "isInterval": return Logic.isInterval(it)
    case "isArchived": return Logic.isArchived(it)
    case "intervalNoticeDays": return Logic.intervalNoticeDays(it)
    case "intervalAnchorKey": return Logic.intervalAnchorKey(it, rec, now) ?? NSNull()
    case "intervalDueInfo":
        guard let info = Logic.intervalDueInfo(it, rec, now) else { return NSNull() }
        return ["daysUntil": info.daysUntil, "sinceDone": info.sinceDone ?? NSNull()] as [String: Any]
    case "nextOccurrence":
        guard let d = Logic.nextOccurrence(it, now, rec) else { return NSNull() }
        return Logic.ms(d)
    case "isTooLate":
        return Logic.isTooLate((c["scheduledMs"] as? NSNumber)?.doubleValue ?? 0,
                               (c["now"] as? NSNumber)?.doubleValue ?? 0)
    case "isValidEndTime": return Logic.isValidEndTime(c["time"] as? String, c["endTime"] as? String)
    case "blockEndMs": return msOut(Logic.blockEndMs(c["endTime"] as? String ?? "", now))
    case "listSortMs": return msOut(Logic.listSortMs(it, now, rec))
    case "streakFor":
        let days = (c["days"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
        return Logic.streakFor(rec, c["itemId"] as? String ?? "", now, days)
    case "doneCountRecent":
        return Logic.doneCountRecent(rec, c["itemId"] as? String ?? "", now,
                                     (c["windowDays"] as? NSNumber)?.intValue ?? 0)
    case "avgDoneIntervalDays":
        return Logic.avgDoneIntervalDays(rec, c["itemId"] as? String ?? "", now,
                                         (c["windowDays"] as? NSNumber)?.intValue ?? 0) ?? NSNull()
    case "itemsOnDay":
        return Logic.itemsOnDay(sched, rec, c["key"] as? String ?? "").map(\.id)
    case "pastDoneCandidates":
        return Logic.pastDoneCandidates(it, rec, now, maxDays: (c["maxDays"] as? NSNumber)?.intValue ?? 7)
    case "dayMark":
        let ids = (c["ids"] as? [Any])?.compactMap { $0 as? String } ?? []
        return Logic.dayMark(rec, c["key"] as? String ?? "", ids)?.rawValue ?? NSNull()
    case "isStreakMilestone":
        return Logic.isStreakMilestone((c["streak"] as? NSNumber)?.intValue ?? 0)
    case "allDoneToday": return Logic.allDoneToday(sched, rec, now)
    case "preNoticeSettings":
        let s = Logic.preNoticeSettings(on: (c["on"] as? NSNumber)?.boolValue,
                                        minutes: (c["minutes"] as? NSNumber)?.intValue)
        return ["on": s.on, "minutes": s.minutes] as [String: Any]
    case "preNoticeAt":
        let next = (c["nextMs"] as? NSNumber)?.doubleValue
        let v = Logic.preNoticeAt(next, on: (c["on"] as? NSNumber)?.boolValue,
                                  minutes: (c["minutes"] as? NSNumber)?.intValue,
                                  nowMs: (c["now"] as? NSNumber)?.doubleValue ?? 0)
        return v ?? NSNull()
    default: return ["error": "unknown fn: \(fn)"] as [String: Any]
    }
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
      let cases = root["cases"] as? [[String: Any]] else {
    FileHandle.standardError.write(Data("NG: 入力を読めません\n".utf8))
    exit(1)
}
let results = cases.map { run($0) }
let out = try! JSONSerialization.data(withJSONObject: ["results": results])
FileHandle.standardOutput.write(out)
