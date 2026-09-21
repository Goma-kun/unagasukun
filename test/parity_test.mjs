// 拡張機能の extension/logic.js と、iOS/Mac 用に移した ios/Sources/UnagasukunCore/Logic.swift が
// **同じ入力に同じ答えを返すか**を実際に突き合わせる。
//
// 手で書いたテストは「思いついた場面」しか見られない。移植の取りこぼしは
// たいてい思いつかなかった場面に出るので、ここでは場面を機械的に大量生成して当てる。
//
// 実行: node test/parity_test.mjs（プロジェクトルートから）
//       事前に swift build --package-path ios が要る

import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const src = readFileSync(join(root, 'extension', 'logic.js'), 'utf8');

const START = '// ===== スケジュール計算ロジック（ここから）=====';
const END = '// ===== スケジュール計算ロジック（ここまで）=====';
const s = src.indexOf(START);
const e = src.indexOf(END);
if (s === -1 || e === -1) { console.error('マーカーブロックが見つかりません'); process.exit(1); }
const block = src.slice(s + START.length, e);
const names = ['dateKey', 'isScheduledOn', 'nextOccurrence', 'isTooLate', 'isValidEndTime',
  'blockEndMs', 'streakFor', 'isOneOff', 'isAnytime', 'listSortMs', 'isInterval',
  'intervalNoticeDays', 'intervalAnchorKey', 'intervalDueInfo', 'doneCountRecent',
  'avgDoneIntervalDays', 'isArchived', 'itemsOnDay', 'dayMark', 'isStreakMilestone',
  'allDoneToday', 'preNoticeSettings', 'preNoticeAt'];
const JS = new Function(`${block}; return { ${names.join(', ')} };`)();

// ---- 場面を機械的に作る（毎回同じ並びになるよう種つき乱数を使う）----
let seed = 20260921;
function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }
function pick(a) { return a[Math.floor(rnd() * a.length)]; }
function maybe(v, p = 0.5) { return rnd() < p ? v : undefined; }

const TIMES = ['00:00', '07:30', '09:00', '12:15', '23:59', '24:00', '9:00', ''];
const DAYSETS = [undefined, [], [0], [1, 3, 5], [4], [0, 6], [0, 1, 2, 3, 4, 5, 6]];

function makeItem(i) {
  const kind = pick(['daily', 'weekly', 'oneoff', 'anytime', 'interval']);
  const it = { id: `i${i}`, label: `予定${i}`, enabled: rnd() < 0.85 };
  if (kind === 'anytime') { it.anytime = true; it.targetMin = pick([5, 30, 120]); }
  else it.time = pick(TIMES);
  if (kind === 'weekly') it.days = pick(DAYSETS.slice(2));
  if (kind === 'daily') it.days = pick([undefined, []]);
  if (kind === 'oneoff') it.date = pick(['2026-08-13', '2026-08-20', '2026-07-01', '2026-12-31', 'x']);
  if (kind === 'interval') {
    it.intervalDays = pick([1, 2, 3, 4, 7, 30]);
    it.noticeDays = maybe(pick([0, 1, 3, 5]));
    it.anchorDate = maybe(pick(['2026-08-01', '2026-08-12', '2026-08-13', 'zzz']));
  }
  if (rnd() < 0.15) it.archived = true;
  if (rnd() < 0.1) it.origId = 'i0';
  if (rnd() < 0.3) it.endTime = pick(TIMES);
  // undefined のキーは JSON に載らないので落としておく（Swift側と条件を揃えるため）
  for (const k of Object.keys(it)) if (it[k] === undefined) delete it[k];
  return it;
}

const schedule = Array.from({ length: 12 }, (_, i) => makeItem(i));
const ids = schedule.map((x) => x.id);

// 記録は 2026-06-01 〜 2026-08-13 の範囲でまばらに作る
const records = {};
for (let back = 0; back < 75; back++) {
  const d = new Date(2026, 7, 13 - back);
  const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  const day = {};
  for (const id of ids) {
    const r = rnd();
    if (r < 0.35) day[id] = 'done';
    else if (r < 0.45) day[id] = 'skip';
  }
  if (Object.keys(day).length) records[key] = day;
}

const NOWS = [
  new Date(2026, 7, 13, 10, 0, 0),   // 木曜の昼前
  new Date(2026, 7, 13, 23, 58, 0),  // 日付が変わる直前
  new Date(2026, 7, 16, 0, 1, 0),    // 日曜の直後
  new Date(2026, 2, 8, 9, 0, 0),     // 3月（夏時間のある地域で日数計算がずれやすい）
  new Date(2026, 10, 1, 9, 0, 0),    // 11月
  new Date(2026, 11, 31, 23, 0, 0),  // 年またぎの直前
];

const cases = [];
function add(c, jsFn) { cases.push({ ...c, __js: jsFn }); }

for (const now of NOWS) {
  const nowMs = now.getTime();
  add({ fn: 'dateKey', now: nowMs }, () => JS.dateKey(now));
  for (const days of DAYSETS) {
    add({ fn: 'isScheduledOn', now: nowMs, days }, () => JS.isScheduledOn(days, now));
  }
  add({ fn: 'allDoneToday', now: nowMs, schedule, records },
      () => JS.allDoneToday(schedule, records, now));

  for (const item of schedule) {
    add({ fn: 'isOneOff', item }, () => JS.isOneOff(item));
    add({ fn: 'isAnytime', item }, () => JS.isAnytime(item));
    add({ fn: 'isInterval', item }, () => JS.isInterval(item));
    add({ fn: 'isArchived', item }, () => JS.isArchived(item));
    add({ fn: 'intervalNoticeDays', item }, () => JS.intervalNoticeDays(item));
    add({ fn: 'intervalAnchorKey', item, records, now: nowMs },
        () => JS.intervalAnchorKey(item, records, now));
    add({ fn: 'intervalDueInfo', item, records, now: nowMs },
        () => JS.intervalDueInfo(item, records, now));
    add({ fn: 'nextOccurrence', item, records, now: nowMs },
        () => { const r = JS.nextOccurrence(item, now, records); return r ? r.getTime() : null; });
    add({ fn: 'listSortMs', item, records, now: nowMs },
        () => JS.listSortMs(item, now, records));
    add({ fn: 'streakFor', itemId: item.id, days: item.days, records, now: nowMs },
        () => JS.streakFor(records, item.id, now, item.days));
    for (const w of [7, 30, 84]) {
      add({ fn: 'doneCountRecent', itemId: item.id, records, now: nowMs, windowDays: w },
          () => JS.doneCountRecent(records, item.id, now, w));
      add({ fn: 'avgDoneIntervalDays', itemId: item.id, records, now: nowMs, windowDays: w },
          () => JS.avgDoneIntervalDays(records, item.id, now, w));
    }
  }
}

// 日付をまたぐ表示まわり
for (const key of Object.keys(records).slice(0, 40)) {
  add({ fn: 'itemsOnDay', schedule, records, key },
      () => JS.itemsOnDay(schedule, records, key).map((x) => x.id));
  add({ fn: 'dayMark', records, key, ids }, () => JS.dayMark(records, key, ids));
  add({ fn: 'dayMark', records, key, ids: ids.slice(0, 3) },
      () => JS.dayMark(records, key, ids.slice(0, 3)));
}

// 単純な関数は端の値をまとめて当てる
for (let n = 0; n <= 40; n++) add({ fn: 'isStreakMilestone', streak: n }, () => JS.isStreakMilestone(n));
for (const [a, b] of [[0, 0], [0, 1], [0, 30 * 60 * 1000], [0, 30 * 60 * 1000 + 1], [1e12, 1e12 - 5]]) {
  add({ fn: 'isTooLate', scheduledMs: a, now: b }, () => JS.isTooLate(a, b));
}
for (const t of TIMES) for (const et of TIMES) {
  add({ fn: 'isValidEndTime', time: t, endTime: et }, () => JS.isValidEndTime(t, et));
}
// '24:00' は「その日の終わり」として翌日0時に繰り上がる。JS の Date が黙ってやること
for (const et of ['00:00', '07:30', '23:59', '24:00', '25:70']) {
  const start = new Date(2026, 7, 13, 10, 0, 0);
  add({ fn: 'blockEndMs', endTime: et, now: start.getTime() }, () => JS.blockEndMs(et, start));
}
for (const on of [undefined, true, false]) for (const min of [undefined, 0, 1, 10, 120, 121, -5]) {
  const settings = {};
  if (on !== undefined) settings.preNoticeOn = on;
  if (min !== undefined) settings.preNoticeMin = min;
  add({ fn: 'preNoticeSettings', on, minutes: min }, () => JS.preNoticeSettings(settings));
  const nowMs = new Date(2026, 7, 13, 10, 0, 0).getTime();
  for (const next of [nowMs + 60000, nowMs + 60 * 60000, nowMs - 1000, nowMs]) {
    add({ fn: 'preNoticeAt', nextMs: next, on, minutes: min, now: nowMs },
        () => JS.preNoticeAt(next, settings, nowMs));
  }
}

// ---- JS側を出す ----
const jsResults = cases.map((c) => {
  let v = c.__js();
  if (v === undefined) v = null;
  if (typeof v === 'number' && !Number.isFinite(v)) v = Number.isNaN(v) ? 'NaN' : 'Infinity';
  // intervalDueInfo の sinceDone は null で揃える
  if (v && typeof v === 'object' && !Array.isArray(v) && 'sinceDone' in v && v.sinceDone === null) {
    v = { ...v, sinceDone: null };
  }
  return v;
});

// ---- Swift側を出す ----
const payload = JSON.stringify({ cases: cases.map(({ __js, ...c }) => c) });
let swiftOut;
try {
  swiftOut = execFileSync(join(root, 'ios', '.build', 'debug', 'uk-probe'), {
    input: payload, maxBuffer: 64 * 1024 * 1024,
  }).toString();
} catch (err) {
  console.error('NG: uk-probe を実行できません。先に `swift build --package-path ios` を実行してください。');
  console.error(err.message);
  process.exit(1);
}
const swiftResults = JSON.parse(swiftOut).results;

// ---- 突き合わせ ----
// オブジェクトのキーの並びは JSON.stringify では揃わないので、比べる前に並べ替える
function norm(v) {
  if (Array.isArray(v)) return v.map(norm);
  if (v && typeof v === 'object') {
    return Object.fromEntries(Object.keys(v).sort().map((k) => [k, norm(v[k])]));
  }
  return v;
}

let pass = 0;
const fails = [];
for (let i = 0; i < cases.length; i++) {
  const a = JSON.stringify(norm(jsResults[i]));
  const b = JSON.stringify(norm(swiftResults[i]));
  if (a === b) { pass++; continue; }
  const { __js, records: _r, schedule: _s, ...input } = cases[i];
  fails.push({ fn: cases[i].fn, js: a, swift: b, input: JSON.stringify(input) });
}

for (const f of fails.slice(0, 12)) {
  console.error(`NG: ${f.fn}\n  JS    ${f.js}\n  Swift ${f.swift}\n  入力  ${f.input}`);
}
if (fails.length > 12) console.error(`… ほか ${fails.length - 12} 件`);
console.log(`突き合わせ完了: ${pass} 件一致 / ${fails.length} 件food不一致`.replace('food', ''));
process.exit(fails.length ? 1 : 0);
