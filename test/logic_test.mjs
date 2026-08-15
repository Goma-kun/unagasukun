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
const { dateKey, nextOccurrence, isTooLate, isValidEndTime, blockEndMs, streakFor, isOneOff, isAnytime, listSortMs } = new Function(
  `${block}; return { dateKey, nextOccurrence, isTooLate, isValidEndTime, blockEndMs, streakFor, isOneOff, isAnytime, listSortMs };`
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

console.log(`テスト完了: ${pass} 件成功 / ${fail} 件失敗`);
process.exit(fail === 0 ? 0 : 1);
