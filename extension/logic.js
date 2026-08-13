// うながすくん 共有ロジック
// service worker（importScripts）とサイドパネル（<script>）の両方から読み込む。
// chrome.* に触れるコードを入れないこと。

// ===== スケジュール計算ロジック（ここから）=====
// このブロックは test/logic_test.mjs が Node で切り出して実行する。

function pad2(n) {
  return String(n).padStart(2, '0');
}

// その日付のキー（実績記録に使う）。例: "2026-08-13"
function dateKey(d) {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

// その日にこの予定があるか（days空=毎日）
function isScheduledOn(days, date) {
  return !Array.isArray(days) || days.length === 0 || days.includes(date.getDay());
}

// 予定 item が次に来る日時を返す。無効な予定や曜日が空振りなら null。
// item: { time: "HH:MM", days: [0-6の配列。空なら毎日], enabled: true }
function nextOccurrence(item, now) {
  if (!item || !item.enabled || !/^\d{2}:\d{2}$/.test(item.time || '')) return null;
  const [hh, mm] = item.time.split(':').map(Number);
  if (hh > 23 || mm > 59) return null;
  for (let add = 0; add < 8; add++) {
    const cand = new Date(now.getFullYear(), now.getMonth(), now.getDate() + add, hh, mm, 0, 0);
    if (cand.getTime() <= now.getTime()) continue;
    if (isScheduledOn(item.days, cand)) return cand;
  }
  return null;
}

// 発火が遅すぎたか（Chrome再起動などで過去のアラームがまとめて届いた場合）。
// 30分以上遅れは「いま知らせても意味がない」ので通知しない判断に使う。
function isTooLate(scheduledMs, nowMs) {
  return nowMs - scheduledMs > 30 * 60 * 1000;
}

// 終了時刻が開始時刻より後か（"HH:MM" 同士は文字列比較で正しく比べられる）
function isValidEndTime(time, endTime) {
  return /^\d{2}:\d{2}$/.test(endTime || '') && endTime > time;
}

// 開始日時 startDate の予定の終了時刻ミリ秒（同じ日の endTime）
function blockEndMs(endTime, startDate) {
  const [hh, mm] = endTime.split(':').map(Number);
  return new Date(startDate.getFullYear(), startDate.getMonth(), startDate.getDate(), hh, mm, 0, 0).getTime();
}

// 連続記録（ストリーク）。今日から遡って「できた」が続いた日数を数える。
// - 今日まだ「できた」でなければ昨日から数え始める（今日の分はまだ失敗ではない）
// - スキップした日は連続を切らないが、日数にも数えない（責めない設計）
// - 予定のない曜日は飛ばす
// - 予定があったのに記録がない日で途切れる
function streakFor(records, itemId, now, days) {
  let streak = 0;
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const todayRec = records[dateKey(d)] && records[dateKey(d)][itemId];
  if (todayRec !== 'done') d.setDate(d.getDate() - 1);
  for (let i = 0; i < 366; i++) {
    if (isScheduledOn(days, d)) {
      const rec = records[dateKey(d)] && records[dateKey(d)][itemId];
      if (rec === 'done') streak++;
      else if (rec !== 'skip') break;
    }
    d.setDate(d.getDate() - 1);
  }
  return streak;
}
// ===== スケジュール計算ロジック（ここまで）=====
