// extension/logic.js のマーカーブロックを切り出して Node で実行するテスト。
// 実行: node test/logic_test.mjs（プロジェクトルートから）

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const src = readFileSync(join(root, 'extension', 'logic.js'), 'utf8');

const START = '// ===== スケジュール計算ロジック（ここから）=====';
const END = '// ===== スケジュール計算ロジック（ここまで）=====';
const s = src.indexOf(START);
const e = src.indexOf(END);
if (s === -1 || e === -1) {
  console.error('マーカーブロックが見つかりません');
  process.exit(1);
}
const block = src.slice(s + START.length, e);
const { dateKey, nextOccurrence, isTooLate, isValidEndTime, blockEndMs, streakFor, isOneOff, isAnytime, listSortMs, isInterval, intervalNoticeDays, intervalAnchorKey, intervalDueInfo, doneCountRecent, avgDoneIntervalDays, isArchived, itemsOnDay, dayMark } = new Function(
  `${block}; return { dateKey, nextOccurrence, isTooLate, isValidEndTime, blockEndMs, streakFor, isOneOff, isAnytime, listSortMs, isInterval, intervalNoticeDays, intervalAnchorKey, intervalDueInfo, doneCountRecent, avgDoneIntervalDays, isArchived, itemsOnDay, dayMark };`
)();

let pass = 0;
let fail = 0;
function eq(name, actual, expected) {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a === b) {
    pass++;
  } else {
    fail++;
    console.error(`NG: ${name}\n  expected ${b}\n  actual   ${a}`);
  }
}

// 2026-08-13 は木曜日（getDay()=4）
const thu10 = new Date(2026, 7, 13, 10, 0, 0);

// dateKey
eq('dateKey ゼロ埋め', dateKey(new Date(2026, 0, 5)), '2026-01-05');
eq('dateKey 8月', dateKey(thu10), '2026-08-13');

// nextOccurrence: 毎日・今日まだ来ていない時刻 → 今日
eq(
  '毎日・未来時刻は今日',
  nextOccurrence({ time: '14:30', days: [], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 13, 14, 30).toISOString()
);

// nextOccurrence: 毎日・今日すでに過ぎた時刻 → 明日
eq(
  '毎日・過去時刻は明日',
  nextOccurrence({ time: '09:00', days: [], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 14, 9, 0).toISOString()
);

// nextOccurrence: ちょうど今の時刻は「次」に送る（<= now は含めない）
eq(
  '同時刻は翌日に送る',
  nextOccurrence({ time: '10:00', days: [], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 14, 10, 0).toISOString()
);

// nextOccurrence: 曜日指定（月=1）。木曜10時からなら次の月曜
eq(
  '曜日指定は次の該当曜日',
  nextOccurrence({ time: '08:00', days: [1], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 17, 8, 0).toISOString()
);

// nextOccurrence: 今日の曜日（木=4）で未来時刻 → 今日
eq(
  '今日の曜日・未来時刻は今日',
  nextOccurrence({ time: '23:59', days: [4], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 13, 23, 59).toISOString()
);

// nextOccurrence: 今日の曜日で過去時刻 → 来週の同じ曜日
eq(
  '今日の曜日・過去時刻は来週',
  nextOccurrence({ time: '09:00', days: [4], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 20, 9, 0).toISOString()
);

// nextOccurrence: 無効な予定は null
eq('enabled=false は null', nextOccurrence({ time: '14:00', days: [], enabled: false }, thu10), null);
eq('時刻形式が壊れていたら null', nextOccurrence({ time: '25:99', days: [], enabled: true }, thu10), null);
eq('time なしは null', nextOccurrence({ days: [], enabled: true }, thu10), null);

// 月末またぎ: 8/31 23:00 から毎日 09:00 → 9/1
eq(
  '月末またぎ',
  nextOccurrence({ time: '09:00', days: [], enabled: true }, new Date(2026, 7, 31, 23, 0))?.toISOString(),
  new Date(2026, 8, 1, 9, 0).toISOString()
);

// 1回だけの予定（日付指定）
eq('isOneOff: 日付あり曜日なし', isOneOff({ date: '2026-08-15', days: [] }), true);
eq('isOneOff: 曜日があれば繰り返し', isOneOff({ date: '2026-08-15', days: [1] }), false);
eq('isOneOff: 日付なしは旧形式', isOneOff({ days: [] }), false);

eq(
  '1回だけ・今日の未来時刻',
  nextOccurrence({ time: '14:00', date: '2026-08-13', days: [], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 13, 14, 0).toISOString()
);
eq(
  '1回だけ・別の日',
  nextOccurrence({ time: '09:00', date: '2026-08-20', days: [], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 20, 9, 0).toISOString()
);
eq('1回だけ・過ぎた日時は null（再発火しない）',
  nextOccurrence({ time: '09:00', date: '2026-08-13', days: [], enabled: true }, thu10), null);
eq('1回だけ・日付形式が壊れていたら null',
  nextOccurrence({ time: '09:00', date: '2026/08/20', days: [], enabled: true }, thu10), null);
eq(
  '日付があっても曜日があれば毎週扱い',
  nextOccurrence({ time: '08:00', date: '2026-08-13', days: [1], enabled: true }, thu10)?.toISOString(),
  new Date(2026, 7, 17, 8, 0).toISOString()
);

// isTooLate
eq('5分遅れは通知する', isTooLate(thu10.getTime(), thu10.getTime() + 5 * 60 * 1000), false);
eq('31分遅れは通知しない', isTooLate(thu10.getTime(), thu10.getTime() + 31 * 60 * 1000), true);

// isValidEndTime
eq('終了が後なら有効', isValidEndTime('09:00', '10:30'), true);
eq('終了が同時刻は無効', isValidEndTime('09:00', '09:00'), false);
eq('終了が前は無効', isValidEndTime('09:00', '08:00'), false);
eq('終了が空は無効', isValidEndTime('09:00', ''), false);

// blockEndMs: 開始日の同日 endTime
eq(
  'blockEndMs は同じ日の終了時刻',
  blockEndMs('10:30', new Date(2026, 7, 13, 9, 0)),
  new Date(2026, 7, 13, 10, 30).getTime()
);

// streakFor（毎日予定・8/13木曜のいま時点）
const rec = (obj) => obj;

// 今日まだ未記録：昨日から数える。昨日・一昨日 done → 2
eq(
  '今日未記録なら昨日から2日',
  streakFor(rec({ '2026-08-12': { a: 'done' }, '2026-08-11': { a: 'done' } }), 'a', thu10, []),
  2
);

// 今日 done：今日を含めて3
eq(
  '今日doneで3日',
  streakFor(
    rec({ '2026-08-13': { a: 'done' }, '2026-08-12': { a: 'done' }, '2026-08-11': { a: 'done' } }),
    'a', thu10, []
  ),
  3
);

// スキップは切らないが数えない：done, skip, done → 2
eq(
  'スキップは連続を切らない',
  streakFor(
    rec({ '2026-08-12': { a: 'done' }, '2026-08-11': { a: 'skip' }, '2026-08-10': { a: 'done' } }),
    'a', thu10, []
  ),
  2
);

// 記録なしの日で途切れる：8/11 が無記録 → 1
eq(
  '無記録で途切れる',
  streakFor(rec({ '2026-08-12': { a: 'done' }, '2026-08-10': { a: 'done' } }), 'a', thu10, []),
  1
);

// 曜日指定（月水金=1,3,5）：予定のない日は飛ばす。
// 8/12(水) done・8/10(月) done、8/13(木)は予定なし → 2
eq(
  '予定のない曜日は飛ばす',
  streakFor(
    rec({ '2026-08-12': { a: 'done' }, '2026-08-10': { a: 'done' } }),
    'a', thu10, [1, 3, 5]
  ),
  2
);

// 記録ゼロなら0
eq('記録ゼロは0', streakFor(rec({}), 'a', thu10, []), 0);

// ---- 時刻を固定しない予定（anytime） ----

// isAnytime
eq('isAnytime: anytime予定', isAnytime({ anytime: true, targetMin: 10 }), true);
eq('isAnytime: 時刻つき予定', isAnytime({ time: '09:00' }), false);
eq('isAnytime: null', isAnytime(null), false);

// nextOccurrence: anytime はアラームを張らない（time があっても null）
eq('anytime は nextOccurrence null',
  nextOccurrence({ anytime: true, days: [], enabled: true }, thu10), null);
eq('anytime は time が残っていても null',
  nextOccurrence({ anytime: true, time: '09:00', days: [], enabled: true }, thu10), null);

// listSortMs: 時刻つきは次回発火時刻と同じ
eq(
  'listSortMs: 時刻つきは nextOccurrence と一致',
  listSortMs({ time: '14:30', days: [], enabled: true }, thu10),
  new Date(2026, 7, 13, 14, 30).getTime()
);
eq('listSortMs: 休止中は Infinity',
  listSortMs({ time: '14:30', days: [], enabled: false }, thu10), Infinity);

// listSortMs: anytime 毎日は「今日の終わり」→ 今日の時刻つき予定の後ろ・明日の予定の前
const anytimeDaily = listSortMs(
  { anytime: true, days: [0, 1, 2, 3, 4, 5, 6], enabled: true }, thu10
);
eq('listSortMs: anytime毎日は今日の終わり',
  anytimeDaily, new Date(2026, 7, 13, 23, 59, 59, 999).getTime());
eq('listSortMs: 今日の時刻つき予定より後ろ',
  anytimeDaily > listSortMs({ time: '23:00', days: [], enabled: true }, thu10), true);
eq('listSortMs: 明日朝の予定より前',
  anytimeDaily < listSortMs({ time: '06:00', days: [5], enabled: true }, thu10), true);

// listSortMs: anytime 曜日指定（月=1）は次の月曜の終わり
eq(
  'listSortMs: anytime曜日指定は次の該当日の終わり',
  listSortMs({ anytime: true, days: [1], enabled: true }, thu10),
  new Date(2026, 7, 17, 23, 59, 59, 999).getTime()
);

// listSortMs: anytime 1回だけ（今日）は今日の終わり。日付が過ぎたら Infinity
eq(
  'listSortMs: anytime今日1回だけは今日の終わり',
  listSortMs({ anytime: true, date: '2026-08-13', days: [], enabled: true }, thu10),
  new Date(2026, 7, 13, 23, 59, 59, 999).getTime()
);
eq('listSortMs: anytime過ぎた1回だけは Infinity',
  listSortMs({ anytime: true, date: '2026-08-12', days: [], enabled: true }, thu10), Infinity);
eq('listSortMs: anytime休止中は Infinity',
  listSortMs({ anytime: true, days: [], enabled: false }, thu10), Infinity);

// isOneOff は anytime でも同じ判定（日付が過ぎたSWの自動片付けが効く）
eq('isOneOff: anytime＋日付あり', isOneOff({ anytime: true, date: '2026-08-13', days: [] }), true);

// streakFor は anytime 毎日でもそのまま数えられる（days全曜日）
eq(
  'streakFor: anytime毎日でも数える',
  streakFor(rec({ '2026-08-12': { a: 'done' }, '2026-08-11': { a: 'done' } }), 'a', thu10, [0, 1, 2, 3, 4, 5, 6]),
  2
);

// ---- 済んでから◯日後（interval） ----

// isInterval
eq('isInterval: intervalDaysあり', isInterval({ intervalDays: 30 }), true);
eq('isInterval: 0以下は無効', isInterval({ intervalDays: 0 }), false);
eq('isInterval: 小数は無効', isInterval({ intervalDays: 7.5 }), false);
eq('isInterval: なし', isInterval({ time: '09:00' }), false);
eq('isInterval: null', isInterval(null), false);

// intervalNoticeDays: 未設定は3、0も有効
eq('noticeDays 未設定は3', intervalNoticeDays({ intervalDays: 30 }), 3);
eq('noticeDays 0は当日から', intervalNoticeDays({ intervalDays: 30, noticeDays: 0 }), 0);
eq('noticeDays 7', intervalNoticeDays({ intervalDays: 30, noticeDays: 7 }), 7);

// intervalAnchorKey: recordsの最新done / anchorDate / 新しいほう優先
const iv = { id: 'a', intervalDays: 30 };
eq('anchor: recordsの最新done',
  intervalAnchorKey(iv, { '2026-08-01': { a: 'done' }, '2026-07-20': { a: 'done' } }, thu10),
  '2026-08-01');
eq('anchor: skipは基準にしない',
  intervalAnchorKey(iv, { '2026-08-10': { a: 'skip' }, '2026-08-01': { a: 'done' } }, thu10),
  '2026-08-01');
eq('anchor: 記録なしはanchorDate',
  intervalAnchorKey({ ...iv, anchorDate: '2026-08-05' }, {}, thu10), '2026-08-05');
eq('anchor: anchorDateのほうが新しければそちら',
  intervalAnchorKey({ ...iv, anchorDate: '2026-08-10' }, { '2026-08-01': { a: 'done' } }, thu10),
  '2026-08-10');
eq('anchor: doneのほうが新しければそちら',
  intervalAnchorKey({ ...iv, anchorDate: '2026-07-01' }, { '2026-08-01': { a: 'done' } }, thu10),
  '2026-08-01');
eq('anchor: どちらも無ければnull', intervalAnchorKey(iv, {}, thu10), null);

// intervalDueInfo: 8/1にやった30日周期 → 目安日8/31、8/13時点であと18日・経過12日
eq('dueInfo: あと18日',
  intervalDueInfo(iv, { '2026-08-01': { a: 'done' } }, thu10),
  { daysUntil: 18, sinceDone: 12 });
// 7/1にやった30日周期 → 目安日7/31、8/13時点で13日過ぎ・経過43日
eq('dueInfo: 過ぎたら負の日数',
  intervalDueInfo(iv, { '2026-07-01': { a: 'done' } }, thu10),
  { daysUntil: -13, sinceDone: 43 });
// 今日やった → あとちょうど30日
eq('dueInfo: 今日やったらあと30日',
  intervalDueInfo(iv, { '2026-08-13': { a: 'done' } }, thu10),
  { daysUntil: 30, sinceDone: 0 });
// 基準なし → 「そろそろ」扱い（daysUntil 0）
eq('dueInfo: 基準なしは今日そろそろ',
  intervalDueInfo(iv, {}, thu10), { daysUntil: 0, sinceDone: null });
// 月またぎ: 8/20にやった30日周期 → 9/19
eq('dueInfo: 月またぎ',
  intervalDueInfo(iv, { '2026-08-20': { a: 'done' } }, new Date(2026, 8, 1, 10, 0)),
  { daysUntil: 18, sinceDone: 12 });

// nextOccurrence: 時刻つきintervalは目安日の時刻に1回だけ
const ivTimed = { id: 'a', intervalDays: 30, time: '09:00', enabled: true, days: [] };
eq('interval: 目安日の時刻に発火',
  nextOccurrence(ivTimed, thu10, { '2026-08-01': { a: 'done' } })?.toISOString(),
  new Date(2026, 7, 31, 9, 0).toISOString());
eq('interval: 目安日当日・時刻が未来なら今日',
  nextOccurrence({ ...ivTimed, time: '14:00' }, thu10, { '2026-07-14': { a: 'done' } })?.toISOString(),
  new Date(2026, 7, 13, 14, 0).toISOString());
eq('interval: 目安日当日・時刻が過ぎたらnull（翌日は鳴らさない）',
  nextOccurrence(ivTimed, thu10, { '2026-07-14': { a: 'done' } }), null);
eq('interval: 目安日を過ぎたらnull（催促しない）',
  nextOccurrence(ivTimed, thu10, { '2026-07-01': { a: 'done' } }), null);
eq('interval: anytimeなら常にnull',
  nextOccurrence({ id: 'a', intervalDays: 30, anytime: true, enabled: true, days: [] }, thu10,
    { '2026-08-01': { a: 'done' } }), null);
eq('interval: 休止中はnull',
  nextOccurrence({ ...ivTimed, enabled: false }, thu10, { '2026-08-01': { a: 'done' } }), null);

// listSortMs: intervalは目安日の終わり。過ぎていたら今日の終わり
eq('listSortMs: intervalは目安日の終わり',
  listSortMs({ id: 'a', intervalDays: 30, anytime: true, enabled: true }, thu10,
    { '2026-08-01': { a: 'done' } }),
  new Date(2026, 7, 31, 23, 59, 59, 999).getTime());
eq('listSortMs: 過ぎたintervalは今日の終わり',
  listSortMs({ id: 'a', intervalDays: 30, anytime: true, enabled: true }, thu10,
    { '2026-07-01': { a: 'done' } }),
  new Date(2026, 7, 13, 23, 59, 59, 999).getTime());
eq('listSortMs: 休止中intervalはInfinity',
  listSortMs({ id: 'a', intervalDays: 30, anytime: true, enabled: false }, thu10, {}), Infinity);

// intervalはisOneOffに該当しない（dateを持たないのでSWの自動片付け対象にならない）
eq('isOneOff: intervalはfalse', isOneOff({ id: 'a', intervalDays: 30, anchorDate: '2026-08-01' }), false);

// ---- ふりかえりの集計（doneCountRecent / avgDoneIntervalDays） ----

// 直近30日の「できた」回数。今日を含む・skipは数えない
eq('doneCount: doneだけ数える',
  doneCountRecent(rec({
    '2026-08-13': { a: 'done' }, '2026-08-12': { a: 'skip' }, '2026-08-01': { a: 'done' }
  }), 'a', thu10, 30), 2);
// 窓の外（31日前）は数えない。7/15は8/13の29日前（窓内）、7/14は30日前（窓外・今日を含む30日）
eq('doneCount: 窓の内側ぎりぎりは数える',
  doneCountRecent(rec({ '2026-07-15': { a: 'done' } }), 'a', thu10, 30), 1);
eq('doneCount: 窓の外は数えない',
  doneCountRecent(rec({ '2026-07-14': { a: 'done' } }), 'a', thu10, 30), 0);
eq('doneCount: 記録ゼロは0', doneCountRecent(rec({}), 'a', thu10, 30), 0);
// 他の予定の記録は混ざらない
eq('doneCount: 他IDは数えない',
  doneCountRecent(rec({ '2026-08-13': { b: 'done' } }), 'a', thu10, 30), 0);

// 平均間隔：8/1・8/7・8/13にできた → 12日間を2区間で割って6日
eq('avgInterval: 等間隔',
  avgDoneIntervalDays(rec({
    '2026-08-01': { a: 'done' }, '2026-08-07': { a: 'done' }, '2026-08-13': { a: 'done' }
  }), 'a', thu10, 365), 6);
// 不等間隔：7/1と8/10 → 40日1区間 → 40
eq('avgInterval: 2回なら差そのもの',
  avgDoneIntervalDays(rec({ '2026-07-01': { a: 'done' }, '2026-08-10': { a: 'done' } }), 'a', thu10, 365), 40);
eq('avgInterval: 1回だけならnull',
  avgDoneIntervalDays(rec({ '2026-08-01': { a: 'done' } }), 'a', thu10, 365), null);
eq('avgInterval: 記録ゼロはnull', avgDoneIntervalDays(rec({}), 'a', thu10, 365), null);

// ---- isArchived / dayMark / itemsOnDay（カレンダー用・v1.4.0）----

eq('isArchived: フラグあり', isArchived({ archived: true }), true);
eq('isArchived: フラグなし', isArchived({ label: 'a' }), false);
eq('isArchived: null', isArchived(null), false);

// 日の印：「できた」が1つでもあれば done、スキップだけなら skip、記録なしは null。
// いまある予定（ids）以外の記録は数えない（削除済み予定の記録で色が付くと一覧と食い違う）
eq('dayMark: done優先', dayMark(rec({ '2026-08-13': { a: 'skip', b: 'done' } }), '2026-08-13', ['a', 'b']), 'done');
eq('dayMark: skipのみ', dayMark(rec({ '2026-08-13': { a: 'skip' } }), '2026-08-13', ['a']), 'skip');
eq('dayMark: 記録なしはnull', dayMark(rec({}), '2026-08-13', ['a']), null);
eq('dayMark: 削除済み予定のdoneは数えない',
  dayMark(rec({ '2026-08-13': { gone: 'done' } }), '2026-08-13', ['a']), null);
eq('dayMark: 削除済みのdoneがあっても、今ある予定のskipで判定',
  dayMark(rec({ '2026-08-13': { gone: 'done', a: 'skip' } }), '2026-08-13', ['a']), 'skip');

// 日別の予定一覧
const daily = { id: 'd1', label: '毎日', time: '09:00', days: [], enabled: true };
const weeklyThu = { id: 'w1', label: '毎週木', time: '10:00', days: [4], enabled: true };
const onceThu = { id: 'o1', label: '1回だけ', time: '11:00', date: '2026-08-13', days: [], enabled: true };
const onceArchived = { id: 'o2', label: '保管済み', time: '11:00', date: '2026-08-13', days: [], enabled: true, archived: true };
const redoCopy = { id: 'r1', label: 'やりなおし', time: '12:00', date: '2026-08-13', days: [], enabled: true, origId: 'd1' };
const interval30 = { id: 'i1', label: '靴の手入れ', time: '09:00', intervalDays: 30, anchorDate: '2026-08-01', enabled: true };
const paused = { id: 'p1', label: '休止中', time: '09:00', days: [], enabled: false };
const all = [daily, weeklyThu, onceThu, onceArchived, redoCopy, interval30, paused];
const ids = (items) => items.map((it) => it.id);

// 2026-08-13 は木曜
eq('itemsOnDay: 木曜（記録なし）は毎日・毎週木・1回だけ・保管済みが出る',
  ids(itemsOnDay(all, rec({}), '2026-08-13')), ['d1', 'w1', 'o1', 'o2']);
eq('itemsOnDay: 金曜は毎日だけ',
  ids(itemsOnDay(all, rec({}), '2026-08-14')), ['d1']);
eq('itemsOnDay: 記録があれば種類を問わず出る（そろそろ・休止中も）',
  ids(itemsOnDay(all, rec({ '2026-08-14': { i1: 'done', p1: 'skip' } }), '2026-08-14')), ['d1', 'i1', 'p1']);
eq('itemsOnDay: やりなおしコピーは記録があっても出さない',
  ids(itemsOnDay(all, rec({ '2026-08-13': { r1: 'done' } }), '2026-08-13')), ['d1', 'w1', 'o1', 'o2']);
eq('itemsOnDay: 1回だけは日付違いの日には出ない',
  itemsOnDay([onceThu], rec({}), '2026-08-20'), []);

// 保管済みの1回だけ予定にはアラームを張らない（nextOccurrence は過去日なので null）
eq('archived: 過去の1回だけはnextOccurrenceがnull',
  nextOccurrence(onceArchived, new Date(2026, 7, 20, 9, 0), rec({})), null);

console.log(`テスト完了: ${pass} 件成功 / ${fail} 件失敗`);
process.exit(fail === 0 ? 0 : 1);
