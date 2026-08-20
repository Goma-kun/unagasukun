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

// 1回だけの予定か（日付があり、曜日の繰り返しがない）
function isOneOff(item) {
  return !!(item && item.date) && (!Array.isArray(item.days) || item.days.length === 0);
}

// 時刻を固定しない予定か（1日の目安時間だけ決めて、空いた時間にやる）
function isAnytime(item) {
  return !!(item && item.anytime);
}

// 「済んでから◯日後」の予定か（靴の手入れ等。日付でなく、済ませた日を基準に数え直す）
function isInterval(item) {
  return !!item && Number.isInteger(item.intervalDays) && item.intervalDays > 0;
}

// 何日前から「今日の予定」に出すか（未設定は3日前から）
function intervalNoticeDays(item) {
  return Number.isInteger(item.noticeDays) && item.noticeDays >= 0 ? item.noticeDays : 3;
}

// 「済んでから◯日後」の基準日（YYYY-MM-DD）。records の最新の「できた」と
// 登録時の「最後にやった日」（anchorDate）の新しいほうを使う。どちらも無ければ null
function intervalAnchorKey(item, records, now) {
  const anchor = /^\d{4}-\d{2}-\d{2}$/.test(item.anchorDate || '') ? item.anchorDate : null;
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  for (let i = 0; i < 366; i++) {
    const k = dateKey(d);
    // anchorDate のほうが新しいと分かった時点で records を遡っても勝てない
    if (anchor && anchor >= k) return anchor;
    if (records[k] && records[k][item.id] === 'done') return k;
    d.setDate(d.getDate() - 1);
  }
  return anchor;
}

// 「済んでから◯日後」の状態。daysUntil: 目安日まであと何日（0=今日、負=過ぎている）。
// sinceDone: 最後にやってから何日（基準が無ければ null → 「そろそろ」扱いで daysUntil 0）
function intervalDueInfo(item, records, now) {
  if (!isInterval(item)) return null;
  const anchor = intervalAnchorKey(item, records || {}, now);
  if (!anchor) return { daysUntil: 0, sinceDone: null };
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const [y, m, d] = anchor.split('-').map(Number);
  const anchorDay = new Date(y, m - 1, d);
  const due = new Date(y, m - 1, d + item.intervalDays);
  const DAY_MS = 24 * 60 * 60 * 1000;
  return {
    daysUntil: Math.round((due.getTime() - today.getTime()) / DAY_MS),
    sinceDone: Math.round((today.getTime() - anchorDay.getTime()) / DAY_MS)
  };
}

// 予定 item が次に来る日時を返す。無効な予定や空振りなら null。
// item: { time: "HH:MM", date?: "YYYY-MM-DD"（1回だけ）, days: [0-6]（毎週繰り返し）, enabled }
// days が空で date も無い旧形式は「毎日」として扱う（後方互換）
// records は「済んでから◯日後」の予定だけが使う（基準日の計算に要る）
function nextOccurrence(item, now, records) {
  // 時刻を固定しない予定は発火時刻を持たない（アラームを張らない）
  if (isAnytime(item)) return null;
  if (!item || !item.enabled || !/^\d{2}:\d{2}$/.test(item.time || '')) return null;
  const [hh, mm] = item.time.split(':').map(Number);
  if (hh > 23 || mm > 59) return null;

  // 済んでから◯日後：目安日の指定時刻に1回だけ知らせる。
  // 目安日を過ぎても翌日以降は鳴らさない（催促を重ねない＝責めない設計）
  if (isInterval(item)) {
    const info = intervalDueInfo(item, records || {}, now);
    if (info.daysUntil < 0) return null;
    const cand = new Date(now.getFullYear(), now.getMonth(), now.getDate() + info.daysUntil, hh, mm, 0, 0);
    return cand.getTime() > now.getTime() ? cand : null;
  }

  if (isOneOff(item)) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(item.date)) return null;
    const [y, mo, d] = item.date.split('-').map(Number);
    const cand = new Date(y, mo - 1, d, hh, mm, 0, 0);
    return cand.getTime() > now.getTime() ? cand : null;
  }

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

// 登録済み一覧の並び順キー（ミリ秒）。時刻つきの予定は次回の発火時刻。
// 時刻を固定しない予定は「次に該当する日ならいつでも」なので、その日の終わりを使う
// （同じ日の時刻つき予定より後ろ、翌日以降の予定より前に並ぶ）。
// 実行予定のないもの（休止中・日付が過ぎた1回だけ）は Infinity で一番下。
function listSortMs(item, now, records) {
  // 済んでから◯日後は「目安日ならいつでも」なので目安日の終わりを使う。
  // 目安日を過ぎていたら「今日やれる」ので今日の終わり
  if (isInterval(item)) {
    if (!item.enabled) return Infinity;
    const info = intervalDueInfo(item, records || {}, now);
    const add = Math.max(0, info.daysUntil);
    return new Date(now.getFullYear(), now.getMonth(), now.getDate() + add, 23, 59, 59, 999).getTime();
  }
  if (!isAnytime(item)) {
    const next = nextOccurrence(item, now, records);
    return next ? next.getTime() : Infinity;
  }
  if (!item.enabled) return Infinity;
  if (isOneOff(item)) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(item.date)) return Infinity;
    const [y, mo, d] = item.date.split('-').map(Number);
    const endOfDay = new Date(y, mo - 1, d, 23, 59, 59, 999).getTime();
    return endOfDay > now.getTime() ? endOfDay : Infinity;
  }
  for (let add = 0; add < 8; add++) {
    const cand = new Date(now.getFullYear(), now.getMonth(), now.getDate() + add, 23, 59, 59, 999);
    if (isScheduledOn(item.days, cand)) return cand.getTime();
  }
  return Infinity;
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
