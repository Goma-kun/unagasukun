// extension/background.js を実物のまま読み込み、chrome.* を差し替えて
// 「予告アラームが本当に張られるか」を確かめるテスト。
// ロジック単体ではなく service worker の経路そのものを通す（開発チェック Manual 項目2）。
// 実行: node test/background_test.mjs（プロジェクトルートから）

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const read = (f) => readFileSync(join(root, 'extension', f), 'utf8');

let pass = 0;
let fail = 0;
function eq(name, actual, expected) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) { pass++; return; }
  fail++;
  console.error(`✗ ${name}\n  期待: ${JSON.stringify(expected)}\n  実際: ${JSON.stringify(actual)}`);
}

// ---- chrome.* の差し替え ----
function makeChrome(store) {
  const alarms = new Map();
  const listeners = { alarm: [], changed: [], removed: [] };
  const created = { windows: [], notifications: [] };
  const chrome = {
    alarms: {
      create: (name, opts) => alarms.set(name, opts),
      clearAll: async () => { alarms.clear(); },
      onAlarm: { addListener: (fn) => listeners.alarm.push(fn) }
    },
    storage: {
      local: {
        get: async (keys) => {
          const ks = Array.isArray(keys) ? keys : [keys];
          const out = {};
          for (const k of ks) if (store[k] !== undefined) out[k] = store[k];
          return out;
        },
        set: async (obj) => { Object.assign(store, obj); },
        remove: async (keys) => { for (const k of [].concat(keys)) delete store[k]; }
      },
      onChanged: { addListener: (fn) => listeners.changed.push(fn) }
    },
    notifications: {
      create: (id, opts) => created.notifications.push({ id, opts }),
      onButtonClicked: { addListener: () => {} },
      onClicked: { addListener: () => {} }
    },
    windows: {
      create: async (opts) => { created.windows.push(opts); return { id: 99 }; },
      update: async () => { throw new Error('no window'); },
      onRemoved: { addListener: (fn) => listeners.removed.push(fn) }
    },
    runtime: {
      onInstalled: { addListener: () => {} },
      onStartup: { addListener: () => {} },
      getURL: (p) => `chrome-extension://test/${p}`
    },
    sidePanel: { setPanelBehavior: () => {} },
    action: { setBadgeText: () => {}, setBadgeBackgroundColor: () => {}, setTitle: () => {} },
    i18n: { getMessage: (k) => k }
  };
  return { chrome, alarms, listeners, created };
}

function load(store) {
  const env = makeChrome(store);
  const src = read('logic.js') + '\n' + read('background.js').replace("importScripts('logic.js');", '');
  const fn = new Function('chrome', 'self', `${src}; return { rescheduleAll };`);
  const api = fn(env.chrome, {});
  return { ...env, ...api };
}

// 毎日 20:30〜21:45 の予定を1件
const item = { id: 'a1', label: '独り言の収録', time: '20:30', endTime: '21:45',
               days: [0,1,2,3,4,5,6], enabled: true };

{
  const store = { schedule: [item], records: {} };
  const env = load(store);
  await env.rescheduleAll();
  const names = [...env.alarms.keys()].sort();
  eq('既定（10分前）で本番と予告の2本が張られる', names, ['item:a1', 'pre:a1']);
  const gap = env.alarms.get('item:a1').when - env.alarms.get('pre:a1').when;
  eq('予告は本番の10分前', gap, 10 * 60000);
}

{
  const store = { schedule: [item], records: {}, settings: { preNoticeMin: 30 } };
  const env = load(store);
  await env.rescheduleAll();
  const gap = env.alarms.get('item:a1').when - env.alarms.get('pre:a1').when;
  eq('設定した分数（30分前）が効く', gap, 30 * 60000);
}

{
  const store = { schedule: [item], records: {}, settings: { preNoticeOn: false } };
  const env = load(store);
  await env.rescheduleAll();
  eq('オフのときは予告アラームを張らない', [...env.alarms.keys()], ['item:a1']);
}

{
  const store = { schedule: [{ ...item, enabled: false }], records: {} };
  const env = load(store);
  await env.rescheduleAll();
  eq('休止中の予定には予告も張らない', [...env.alarms.keys()], []);
}

{
  // 予告アラームが鳴ったらポップアップが1つ開く
  const store = { schedule: [item], records: {} };
  const env = load(store);
  await env.rescheduleAll();
  const onAlarm = env.listeners.alarm[0];
  await onAlarm({ name: 'pre:a1', scheduledTime: Date.now() });
  eq('予告で窓が1つ開く', env.created.windows.length, 1);
  eq('開くのはポップアップ型', env.created.windows[0].type, 'popup');
  eq('開いた窓のIDを覚える', store.popupWindowId, 99);
}

{
  // すでに済ませてある予定は蒸し返さない
  const today = new Date();
  const key = `${today.getFullYear()}-${String(today.getMonth()+1).padStart(2,'0')}-${String(today.getDate()).padStart(2,'0')}`;
  const store = { schedule: [item], records: { [key]: { a1: 'done' } } };
  const env = load(store);
  await env.rescheduleAll();
  await env.listeners.alarm[0]({ name: 'pre:a1', scheduledTime: Date.now() });
  eq('済ませた予定の予告は出さない', env.created.windows.length, 0);
}

{
  // 何時間も前の予告が、PCの復帰直後にまとめて出ない
  const store = { schedule: [item], records: {} };
  const env = load(store);
  await env.rescheduleAll();
  await env.listeners.alarm[0]({ name: 'pre:a1', scheduledTime: Date.now() - 60 * 60000 });
  eq('過ぎた予告はさかのぼって出さない', env.created.windows.length, 0);
}

console.log(`テスト完了: ${pass} 件成功 / ${fail} 件失敗`);
process.exit(fail === 0 ? 0 : 1);
