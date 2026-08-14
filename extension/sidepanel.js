// うながすくん サイドパネル
// chrome.storage が無い環境（ブラウザプレビュー）では localStorage にフォールバックする。
// 文言は _locales の messages.json から T() で引く（プレビューでは fetch フォールバック）。

const hasChromeStorage = typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local;
const hasChromeI18n = typeof chrome !== 'undefined' && chrome.i18n && chrome.i18n.getMessage;

const store = {
  async get(keys) {
    if (hasChromeStorage) return chrome.storage.local.get(keys);
    const out = {};
    for (const k of Array.isArray(keys) ? keys : [keys]) {
      const raw = localStorage.getItem('unagasukun:' + k);
      if (raw !== null) out[k] = JSON.parse(raw);
    }
    return out;
  },
  async set(obj) {
    if (hasChromeStorage) return chrome.storage.local.set(obj);
    for (const [k, v] of Object.entries(obj)) {
      localStorage.setItem('unagasukun:' + k, JSON.stringify(v));
    }
  }
};

// ---- i18n ----

let previewMessages = null; // プレビュー用（?lang=ja / ?lang=en で切替）

function T(key, subs) {
  const arr = subs == null ? [] : Array.isArray(subs) ? subs : [subs];
  if (hasChromeI18n) {
    return chrome.i18n.getMessage(key, arr.map(String)) || key;
  }
  const m = previewMessages && previewMessages[key];
  if (!m) return key;
  let out = m.message;
  if (m.placeholders) {
    for (const [name, def] of Object.entries(m.placeholders)) {
      const idx = parseInt(String(def.content).replace('$', ''), 10) - 1;
      out = out.replaceAll('$' + name.toUpperCase() + '$', String(arr[idx] ?? ''));
    }
  }
  return out;
}

async function loadPreviewMessages() {
  if (hasChromeI18n) return;
  const lang = new URLSearchParams(location.search).get('lang') || 'ja';
  try {
    previewMessages = await (await fetch(`_locales/${lang}/messages.json`)).json();
  } catch (e) {
    previewMessages = null;
  }
}

function applyI18n() {
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    el.textContent = T(el.dataset.i18n);
  });
  document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
    el.placeholder = T(el.dataset.i18nPlaceholder);
  });
  document.querySelectorAll('[data-i18n-title]').forEach((el) => {
    el.title = T(el.dataset.i18nTitle);
  });
}

let toastTimer = null;
function showToast(text) {
  const el = document.getElementById('toast');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3000);
}

// ---- 別ウィンドウ表示（おさむくん v1.2〜1.3 と同じ仕組み）----

const WINDOW_WIDTH = 400;
const WINDOW_HEIGHT = 680;
const POPUP_ID_KEY = 'popupWindowId';
// サイドパネルに戻すとき、開いたときと同じウィンドウに戻すために覚えておく
const ORIGIN_ID_KEY = 'popupOriginWindowId';
const isPopupWindow = new URLSearchParams(location.search).get('view') === 'window';
// まとめるくん（自作のハブ拡張）の iframe 内で動いているとき。
// ハブ側の窓がすでに「切り離された1枚」なので、こちらの切り離し・移譲は全部黙らせる
const isEmbedded = window.self !== window.top;
const canOpenWindow = typeof chrome !== 'undefined' && !!chrome.windows && !!chrome.runtime;

// 自分が属しているウィンドウを取る。getCurrent が使えない場合に備えて getLastFocused に落とす
async function getOwnWindow() {
  try {
    return await chrome.windows.getCurrent();
  } catch {
    try {
      return await chrome.windows.getLastFocused();
    } catch {
      return null;
    }
  }
}

async function ensureWindow() {
  // すでに開いているウィンドウがあれば、新しく作らずに前面へ出す
  try {
    const saved = await chrome.storage.local.get(POPUP_ID_KEY);
    const id = saved[POPUP_ID_KEY];
    if (id != null) {
      await chrome.windows.update(id, { focused: true, drawAttention: true });
      return true;
    }
  } catch {
    // 閉じられているとIDが無効になる。そのまま新規作成に進む
  }

  const options = {
    url: chrome.runtime.getURL('sidepanel.html') + '?view=window',
    type: 'popup',
    width: WINDOW_WIDTH,
    height: WINDOW_HEIGHT
  };
  // いま自分が入っているウィンドウ。位置の基準にもなるし、戻り先としても覚えておく
  const base = await getOwnWindow();
  if (base && typeof base.left === 'number' && typeof base.width === 'number') {
    options.left = Math.max(0, base.left + base.width - WINDOW_WIDTH - 20);
    options.top = Math.max(0, (base.top || 0) + 20);
  }

  try {
    const created = await chrome.windows.create(options);
    // 閉じる前にIDを確実に保存する（保存前にパネルを閉じると次回の再利用ができなくなる）
    const toSave = { [POPUP_ID_KEY]: created.id };
    if (base && base.type === 'normal') toSave[ORIGIN_ID_KEY] = base.id;
    await chrome.storage.local.set(toSave);
    return true;
  } catch {
    showToast(T('toastWindowFailed'));
    return false;
  }
}

async function openInWindow() {
  // 同じものがサイドパネルと別ウィンドウに2つ並ぶと分かりにくいので、
  // 別ウィンドウを開けたらサイドパネルのほうは閉じる
  if (await ensureWindow()) window.close();
}

// サイドパネルを開き直す先を決める。開いたときと同じウィンドウを最優先にする
async function findSidePanelTarget() {
  try {
    const saved = await chrome.storage.local.get(ORIGIN_ID_KEY);
    const originId = saved[ORIGIN_ID_KEY];
    if (originId != null) {
      const origin = await chrome.windows.get(originId);
      if (origin && origin.type === 'normal') return origin;
    }
  } catch {
    // 元のウィンドウが閉じられている。下のフォールバックへ
  }

  try {
    // populate を付けずにウィンドウを見るだけなので tabs 権限は要らない
    const normals = (await chrome.windows.getAll()).filter((w) => w.type === 'normal');
    return normals.find((w) => w.focused) || normals[0] || null;
  } catch {
    return null;
  }
}

// 別ウィンドウからサイドパネルへ戻す。
// 順序が重要で、記憶しているウィンドウIDを消してから chrome.sidePanel.open() を呼ぶ。
// IDが残ったままだと、開いたサイドパネルが handOverToExistingWindow() で
// 「別ウィンドウが生きている」と判断して即座に自分を閉じてしまう
async function returnToSidePanel() {
  const target = await findSidePanelTarget();
  const self = await getOwnWindow();

  if (!target) {
    showToast(T('toastNoBrowserWindow'));
    return;
  }

  try {
    await chrome.storage.local.remove([POPUP_ID_KEY, ORIGIN_ID_KEY]);
  } catch {
    // 消せなくても続行する（最悪サイドパネルが閉じるだけで、このウィンドウは残る）
  }

  try {
    await chrome.sidePanel.open({ windowId: target.id });
  } catch {
    // 開けなかったらIDを戻して、この別ウィンドウをそのまま使い続けられるようにする
    if (self) {
      try {
        await chrome.storage.local.set({ [POPUP_ID_KEY]: self.id, [ORIGIN_ID_KEY]: target.id });
      } catch {
        // 戻せない場合は二重表示になりうるが、実害は表示だけ
      }
    }
    showToast(T('toastSidePanelFailed'));
    return;
  }

  // サイドパネルはブラウザ側のウィンドウに出るので、そちらを前面に持ってくる
  try {
    await chrome.windows.update(target.id, { focused: true });
  } catch {
    // 前面化に失敗しても閉じてよい
  }
  window.close();
}

// サイドパネルとして開かれたとき、すでに別ウィンドウが生きていればそちらへ寄せる。
// ツールバーのアイコンから開いた場合も2つ並ばないようにするため
async function handOverToExistingWindow() {
  if (isPopupWindow || isEmbedded || !canOpenWindow) return false;
  let id;
  try {
    const saved = await chrome.storage.local.get(POPUP_ID_KEY);
    id = saved[POPUP_ID_KEY];
  } catch {
    return false;
  }
  if (id == null) return false;

  try {
    await chrome.windows.update(id, { focused: true, drawAttention: true });
  } catch {
    // すでに閉じられている。古いIDを捨てて、サイドパネルをそのまま使う
    try {
      await chrome.storage.local.remove([POPUP_ID_KEY, ORIGIN_ID_KEY]);
    } catch {
      // 消せなくても表示は続けられる
    }
    return false;
  }
  window.close();
  return true;
}

// 曜日名・チップは init 時（プレビュー文言の読み込み後）に確定させる
let DAY_NAMES = [];
let NOTE_CHOICES = []; // 「実際は」のワンタップ選択肢。責める言葉は使わない

// pad2 / dateKey / streakFor などは logic.js（共有ロジック）から来る
function todayKey() {
  return dateKey(new Date());
}

function timeText(item) {
  return item.endTime ? `${item.time}〜${item.endTime}` : item.time;
}

// 「あと45分」「あと1時間5分」のような残り時間の文言
function durText(minutes) {
  if (minutes < 60) return T('durMin', [minutes]);
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m === 0 ? T('durH', [h]) : T('durHM', [h, m]);
}

// 「予定を追加」フォームの開閉（既定は閉じて、予定の一覧を見やすくする）
function setFormOpen(open) {
  document.getElementById('item-form').hidden = !open;
  document.getElementById('form-title').classList.toggle('open', open);
}

let schedule = [];
let records = {};
let notes = {}; // { 日付: { itemId: '実際にやっていたこと' } }
let activeBlock = null; // 進行中の時間帯ブロック（service worker が管理）
let editingId = null; // null なら新規追加モード
let expandedNoteFor = null; // 「実際は」を編集中の itemId
let noteFreeTextFor = null; // 「その他…」の自由入力を開いている itemId
let expandedActionsFor = null; // 登録済み一覧で操作ボタンを開いている itemId

async function load() {
  const data = await store.get(['schedule', 'records', 'notes', 'activeBlock']);
  schedule = Array.isArray(data.schedule) ? data.schedule : [];
  records = data.records || {};
  notes = data.notes || {};
  activeBlock = data.activeBlock || null;
}

async function saveSchedule() {
  await store.set({ schedule });
}

async function saveRecords() {
  await store.set({ records });
}

async function saveNotes() {
  await store.set({ notes });
}

// 実際にやっていたことを記録する。未記録の予定ならスキップ扱いも同時に付ける
// （予定していたことは流れた、という事実だけを残す）
async function saveNote(item, text) {
  const key = todayKey();
  if (!notes[key]) notes[key] = {};
  notes[key][item.id] = text;
  await saveNotes();
  if (!(records[key] && records[key][item.id])) {
    if (!records[key]) records[key] = {};
    records[key][item.id] = 'skip';
    await saveRecords();
  }
  expandedNoteFor = null;
  noteFreeTextFor = null;
  renderToday();
}

// 「実際は」の行を組み立てる（スキップ済み、または時間が過ぎて未記録のカードに付く）
function buildNoteRow(item) {
  const row = document.createElement('div');
  row.className = 'note-row';
  const note = (notes[todayKey()] || {})[item.id];

  if (note && expandedNoteFor !== item.id) {
    const view = document.createElement('button');
    view.className = 'note-view';
    view.textContent = T('noteView', [note]);
    view.title = T('noteViewTitle');
    view.addEventListener('click', () => {
      expandedNoteFor = item.id;
      renderToday();
    });
    row.append(view);
    return row;
  }

  const lbl = document.createElement('span');
  lbl.className = 'note-label';
  lbl.textContent = T('noteLabel');
  row.append(lbl);

  if (noteFreeTextFor === item.id) {
    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'note-input';
    input.maxLength = 30;
    input.placeholder = T('noteInputPlaceholder');
    input.value = note && !NOTE_CHOICES.includes(note) ? note : '';
    const ok = document.createElement('button');
    ok.textContent = T('noteSaveBtn');
    ok.addEventListener('click', () => {
      const v = input.value.trim();
      if (v) saveNote(item, v);
    });
    // 「やっぱり選択肢から選ぶ」に戻れる道を残す（Escキーでも戻れる）
    const backToChips = () => {
      noteFreeTextFor = null;
      expandedNoteFor = item.id;
      renderToday();
    };
    const back = document.createElement('button');
    back.textContent = T('noteBackBtn');
    back.title = T('noteBackTip');
    back.addEventListener('click', backToChips);
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); ok.click(); }
      if (e.key === 'Escape') { e.preventDefault(); backToChips(); }
    });
    row.append(input, ok, back);
    setTimeout(() => input.focus(), 0);
    return row;
  }

  for (const choice of NOTE_CHOICES) {
    const chip = document.createElement('button');
    chip.className = 'chip' + (note === choice ? ' selected' : '');
    chip.textContent = choice;
    chip.addEventListener('click', () => saveNote(item, choice));
    row.append(chip);
  }
  const other = document.createElement('button');
  other.className = 'chip';
  other.textContent = T('chipOther');
  other.addEventListener('click', () => {
    noteFreeTextFor = item.id;
    expandedNoteFor = item.id;
    renderToday();
  });
  row.append(other);
  return row;
}

// 予定の繰り返し表示。1回だけなら「8/15（金）のみ」、毎週なら曜日、全曜日なら「毎日」
function repeatText(item) {
  if (isOneOff(item)) {
    const [y, m, d] = item.date.split('-').map(Number);
    const dayName = DAY_NAMES[new Date(y, m - 1, d).getDay()];
    return T('onceOn', [`${m}/${d}(${dayName})`]);
  }
  if (!Array.isArray(item.days) || item.days.length === 0) return T('everydayBtn'); // 旧形式＝毎日
  if (item.days.length === 7) return T('everydayBtn');
  return item.days.slice().sort().map((d) => DAY_NAMES[d]).join('・');
}

function isTodayItem(item) {
  if (!item.enabled) return false;
  if (isOneOff(item)) return item.date === todayKey();
  if (!Array.isArray(item.days) || item.days.length === 0) return true; // 旧形式＝毎日
  return item.days.includes(new Date().getDay());
}

let doneOpen = true; // 「今日対応済み」の開閉状態

function renderToday() {
  const listEl = document.getElementById('today-list');
  const emptyEl = document.getElementById('today-empty');
  const doneListEl = document.getElementById('done-list');
  const doneTitleEl = document.getElementById('done-title');
  listEl.textContent = '';
  doneListEl.textContent = '';
  const items = schedule.filter(isTodayItem).sort((a, b) => a.time.localeCompare(b.time));

  const now = new Date();
  const nowHM = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  const todayRec = records[todayKey()] || {};

  // 上の欄は「今日のこれから」だけ：進行中 → これから → 未対応（各グループ内は時刻順）。
  // 対応済み（できた・スキップ）は下の「今日対応済み」に移す
  const groupOf = (it) => {
    if (activeBlock && activeBlock.itemId === it.id && Date.now() < activeBlock.endMs) return 0;
    const result = todayRec[it.id];
    if (result === undefined && it.time > nowHM) return 1;
    if (result === undefined) return 2; // 時間が過ぎて未対応
    return 3; // できた・スキップ
  };
  items.sort((a, b) => groupOf(a) - groupOf(b) || a.time.localeCompare(b.time));

  const resolvedCount = items.filter((it) => groupOf(it) === 3).length;
  emptyEl.hidden = items.length - resolvedCount > 0;
  doneTitleEl.hidden = resolvedCount === 0;
  doneTitleEl.textContent = T('doneHeading', [resolvedCount]);
  doneTitleEl.classList.toggle('open', doneOpen);
  doneListEl.hidden = !doneOpen || resolvedCount === 0;

  // 「次の予定」＝まだ時間が来ていない未記録の予定のうち、いちばん早いもの
  const nextItem = items.find((it) => todayRec[it.id] === undefined && it.time > nowHM);

  for (const item of items) {
    const card = document.createElement('div');
    card.className = 'card';
    // いまの時刻を過ぎた直近1件を強調（「今はこれの時間」の目印）
    const time = document.createElement('span');
    time.className = 'time';
    time.textContent = timeText(item);
    const label = document.createElement('span');
    label.className = 'label';
    label.textContent = item.label;
    card.append(time, label);

    // 連続記録（繰り返し予定のみ。2日以上続いていたら見せる。スキップでは切れない）
    const streak = isOneOff(item) ? 0 : streakFor(records, item.id, now, item.days);
    if (streak >= 2) {
      const st = document.createElement('span');
      st.className = 'streak';
      st.textContent = T('streakText', [streak]);
      st.title = T('streakTitle', [streak]);
      card.append(st);
    }

    const result = todayRec[item.id];
    // 「時間が過ぎた」の判定。時間帯ブロックなら終了時刻を基準にする
    const dueHM = item.endTime || item.time;
    const pastDue = dueHM <= nowHM;

    // 長いバッジ（次の予定・いまの時間）はタイトルを潰さないよう2行目に出す
    const subBadges = [];

    // 次に来る予定は「次の予定・あと◯分」で目立たせる
    if (item === nextItem) {
      const [hh, mm] = item.time.split(':').map(Number);
      const startMs = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hh, mm).getTime();
      const rem = Math.max(1, Math.ceil((startMs - now.getTime()) / 60000));
      const nx = document.createElement('span');
      nx.className = 'status next';
      nx.textContent = T('nextUp', [durText(rem)]);
      subBadges.push(nx);
    }

    // いままさに進行中のブロックは、ひと目で分かるように強調して残り時間を出す
    const isActive = activeBlock && activeBlock.itemId === item.id && Date.now() < activeBlock.endMs;
    if (isActive) {
      card.classList.add('active');
      const rem = Math.max(1, Math.ceil((activeBlock.endMs - Date.now()) / 60000));
      const badge = document.createElement('span');
      badge.className = 'status active';
      badge.textContent = T('activeNow', [rem]);
      subBadges.push(badge);
    }

    if (result === 'done' || result === 'skip') {
      const s = document.createElement('span');
      s.className = result === 'done' ? 'status done' : 'status skip';
      s.textContent = result === 'done' ? T('statusDone') : T('statusSkip');
      card.append(s);
      // 誤タップの救済：記録を取り消して今日の予定に戻せる
      const undo = document.createElement('button');
      undo.className = 'undo-btn';
      undo.textContent = T('undoBtn');
      undo.title = T('undoTip');
      undo.addEventListener('click', async () => {
        const key = todayKey();
        if (records[key]) {
          delete records[key][item.id];
          if (Object.keys(records[key]).length === 0) delete records[key];
        }
        await saveRecords();
        renderToday();
      });
      card.append(undo);
    } else {
      if (!isActive && item.time <= nowHM) card.classList.add('now');
      // 時間が過ぎて未対応なら、枠色だけでなく文字でも分かるようにする
      if (!isActive && pastDue) {
        const p = document.createElement('span');
        p.className = 'status pending';
        p.textContent = T('statusPending');
        card.append(p);
      }
      const doneBtn = document.createElement('button');
      doneBtn.className = 'mark-done';
      doneBtn.textContent = T('doneBtn');
      doneBtn.addEventListener('click', async () => {
        if (!records[todayKey()]) records[todayKey()] = {};
        records[todayKey()][item.id] = 'done';
        await saveRecords();
        renderToday();
      });
      card.append(doneBtn);
    }

    if (subBadges.length > 0) {
      const row = document.createElement('div');
      row.className = 'badge-row';
      row.append(...subBadges);
      card.append(row);
    }

    // 詳細（任意メモ）があれば小さく添える
    if (item.detail) {
      const dt = document.createElement('div');
      dt.className = 'detail-row';
      dt.textContent = item.detail;
      card.append(dt);
    }

    // 「実際は」行：スキップ済み、または時間が過ぎて未記録のとき。
    // 何をしていたかを後から見返すための自己申告（自動追跡はしない）
    if (result === 'skip' || (result === undefined && pastDue)) {
      card.append(buildNoteRow(item));
    }
    // 対応済みは「今日対応済み」欄へ、それ以外は「今日の予定」欄へ
    (groupOf(item) === 3 ? doneListEl : listEl).append(card);
  }
}

let registeredOpen = false; // 「登録済みの予定」の開閉状態（既定は畳む。開くと明日以降も見える）

function renderItems() {
  const listEl = document.getElementById('item-list');
  const emptyEl = document.getElementById('items-empty');
  listEl.textContent = '';
  const sortNow = new Date();
  const recToday = records[todayKey()] || {};
  // 今日だけの予定で今日すでに対応済みのものは「今日対応済み」欄に出ているので、
  // ここには重複して出さない（繰り返し予定は明日以降があるので残す）
  const items = schedule
    .filter((it) => !(isOneOff(it) && it.date === todayKey() && recToday[it.id] !== undefined))
    // 次に実行される順に並べる（これからの予定が上から順に見える）。
    // 実行予定のないもの（休止中・終わった1回だけ）は一番下
    .sort((a, b) => {
      const na = nextOccurrence(a, sortNow)?.getTime() ?? Infinity;
      const nb = nextOccurrence(b, sortNow)?.getTime() ?? Infinity;
      return na - nb || a.time.localeCompare(b.time);
    });
  listEl.hidden = !registeredOpen;
  emptyEl.hidden = !registeredOpen || items.length > 0;
  const now = new Date();
  const nowHM = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  const todayRec = records[todayKey()] || {};
  for (const item of items) {
    const card = document.createElement('div');
    card.className = 'card' + (item.enabled ? '' : ' disabled');

    const time = document.createElement('span');
    time.className = 'time';
    time.textContent = timeText(item);
    const label = document.createElement('span');
    label.className = 'label';
    label.textContent = item.label;
    const days = document.createElement('span');
    days.className = 'days';
    days.textContent = repeatText(item);

    // 今日の分の状態（✓できた／スキップ／未対応）は、今日の予定側と同じ表示で連動させる
    let statusBadge = null;
    if (isTodayItem(item)) {
      const rec = todayRec[item.id];
      if (rec === 'done') {
        statusBadge = document.createElement('span');
        statusBadge.className = 'status done';
        statusBadge.textContent = T('statusDone');
      } else if (rec === 'skip') {
        statusBadge = document.createElement('span');
        statusBadge.className = 'status skip';
        statusBadge.textContent = T('statusSkip');
      } else if ((item.endTime || item.time) <= nowHM) {
        statusBadge = document.createElement('span');
        statusBadge.className = 'status pending';
        statusBadge.textContent = T('statusPending');
      }
    }

    // 1行に収める：普段は 時刻・名前・繰り返し・状態 だけ。
    // カードをクリックすると操作ボタン（休む・編集・削除）が2行目に開く
    const more = document.createElement('span');
    more.className = 'item-more';
    more.textContent = expandedActionsFor === item.id ? '▾' : '▸';

    card.append(time, label, days);
    if (statusBadge) card.append(statusBadge);
    card.append(more);

    if (expandedActionsFor === item.id) {
      const toggleBtn = document.createElement('button');
      toggleBtn.textContent = item.enabled ? T('pauseBtn') : T('resumeBtn');
      toggleBtn.title = item.enabled ? T('pauseTitle') : T('resumeTitle');
      toggleBtn.addEventListener('click', async () => {
        item.enabled = !item.enabled;
        await saveSchedule();
        renderAll();
      });

      const editBtn = document.createElement('button');
      editBtn.textContent = T('editBtn');
      editBtn.addEventListener('click', () => startEdit(item.id));

      const delBtn = document.createElement('button');
      delBtn.className = 'delete';
      delBtn.textContent = T('deleteBtn');
      delBtn.addEventListener('click', async () => {
        if (!confirm(T('deleteConfirm', [item.label, timeText(item)]))) return;
        schedule = schedule.filter((it) => it.id !== item.id);
        await saveSchedule();
        if (editingId === item.id) resetForm();
        renderAll();
      });

      const actions = document.createElement('div');
      actions.className = 'badge-row';
      actions.append(toggleBtn, editBtn, delBtn);
      card.append(actions);
    }

    card.addEventListener('click', (e) => {
      if (e.target.closest('button')) return; // ボタン操作はそのまま通す
      expandedActionsFor = expandedActionsFor === item.id ? null : item.id;
      renderItems();
    });
    listEl.append(card);
  }
}

function renderAll() {
  renderToday();
  renderItems();
}

function buildDayBoxes() {
  const wrap = document.getElementById('day-boxes');
  wrap.textContent = '';
  DAY_NAMES.forEach((name, idx) => {
    const label = document.createElement('label');
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.value = String(idx);
    label.append(input, document.createTextNode(name));
    wrap.append(label);
  });
}

function selectedDays() {
  return [...document.querySelectorAll('#day-boxes input:checked')].map((el) => Number(el.value));
}

function setSelectedDays(days) {
  document.querySelectorAll('#day-boxes input').forEach((el) => {
    el.checked = Array.isArray(days) && days.includes(Number(el.value));
  });
}

// 曜日を選んでいる間は日付が使われないので、入力欄を無効化して意味を見せる
function syncDateDisabled() {
  document.getElementById('input-date').disabled = selectedDays().length > 0;
}

function startEdit(id) {
  const item = schedule.find((it) => it.id === id);
  if (!item) return;
  editingId = id;
  setFormOpen(true);
  document.getElementById('form-title').textContent = T('editHeading');
  document.getElementById('save-btn').textContent = T('saveBtn');
  document.getElementById('cancel-btn').hidden = false;
  document.getElementById('input-date').value = item.date || todayKey();
  document.getElementById('input-time').value = item.time;
  document.getElementById('input-end-time').value = item.endTime || '';
  document.getElementById('input-label').value = item.label;
  document.getElementById('input-detail').value = item.detail || '';
  setSelectedDays(item.days);
  syncDateDisabled();
  document.getElementById('edit-section').scrollIntoView({ behavior: 'smooth' });
}

function resetForm() {
  editingId = null;
  document.getElementById('form-title').textContent = T('addHeading');
  document.getElementById('save-btn').textContent = T('addBtn');
  document.getElementById('cancel-btn').hidden = true;
  document.getElementById('item-form').reset();
  document.getElementById('input-date').value = todayKey();
  setSelectedDays([]);
  syncDateDisabled();
}

document.getElementById('item-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const time = document.getElementById('input-time').value;
  const endTime = document.getElementById('input-end-time').value;
  const label = document.getElementById('input-label').value.trim();
  const detail = document.getElementById('input-detail').value.trim();
  if (!time || !label) return;
  if (endTime && !isValidEndTime(time, endTime)) {
    alert(T('endTimeInvalid'));
    return;
  }
  const days = selectedDays();
  // 曜日なし＝日付指定の1回だけ。過去の日時は受け付けない
  const date = days.length === 0 ? document.getElementById('input-date').value : undefined;
  if (date) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return;
    const [y, m, d] = date.split('-').map(Number);
    const [hh, mm] = time.split(':').map(Number);
    if (new Date(y, m - 1, d, hh, mm).getTime() <= Date.now()) {
      alert(T('pastDateTime'));
      return;
    }
  }

  if (editingId) {
    const item = schedule.find((it) => it.id === editingId);
    if (item) {
      item.time = time;
      item.endTime = endTime || undefined;
      item.label = label;
      item.detail = detail || undefined;
      item.days = days;
      item.date = date;
      item.updatedAt = Date.now();
    }
  } else {
    schedule.push({
      id: 'it' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      time,
      endTime: endTime || undefined,
      label,
      detail: detail || undefined,
      days,
      date,
      enabled: true,
      createdAt: Date.now(),
      updatedAt: Date.now()
    });
  }
  await saveSchedule();
  resetForm();
  setFormOpen(false);
  renderAll();
});

document.getElementById('cancel-btn').addEventListener('click', () => {
  resetForm();
  setFormOpen(false);
});

// 見出しクリックでフォームを開閉する
document.getElementById('form-title').addEventListener('click', () => {
  const isOpen = !document.getElementById('item-form').hidden;
  if (isOpen && editingId) resetForm(); // 編集を畳むときは編集状態も解除する
  setFormOpen(!isOpen);
});

// 「登録済みの予定」も見出しクリックで開閉する
document.getElementById('list-title').addEventListener('click', () => {
  registeredOpen = !registeredOpen;
  document.getElementById('list-title').classList.toggle('open', registeredOpen);
  renderItems();
});

// 「今日対応済み」も見出しクリックで開閉する
document.getElementById('done-title').addEventListener('click', () => {
  doneOpen = !doneOpen;
  renderToday();
});

(async function init() {
  // 別ウィンドウが生きているならそちらに任せて閉じる。描画前に判定して画面のちらつきを避ける
  if (await handOverToExistingWindow()) return;
  // 文言の確定 → 画面組み立ての順を守る（逆にすると文言が出ない）
  await loadPreviewMessages();
  applyI18n();
  // 切り離しボタンはサイドパネル側、戻すボタンは別ウィンドウ側でだけ出す
  if (canOpenWindow && !isPopupWindow && !isEmbedded) {
    const btn = document.getElementById('btn-popout');
    btn.hidden = false;
    btn.addEventListener('click', openInWindow);
  }
  if (canOpenWindow && isPopupWindow && chrome.sidePanel && chrome.sidePanel.open) {
    const btn = document.getElementById('btn-dock');
    btn.hidden = false;
    btn.addEventListener('click', returnToSidePanel);
  }
  DAY_NAMES = ['day0', 'day1', 'day2', 'day3', 'day4', 'day5', 'day6'].map((k) => T(k));
  NOTE_CHOICES = ['chipOtherWork', 'chipBreak', 'chipBrowsing', 'chipNoMood'].map((k) => T(k));
  buildDayBoxes();
  // 曜日の選択状態で日付欄の有効/無効を切り替える
  document.getElementById('day-boxes').addEventListener('change', syncDateDisabled);
  // 「毎日」ボタン：全曜日を一括で付け外しする
  document.getElementById('btn-everyday').addEventListener('click', () => {
    const boxes = [...document.querySelectorAll('#day-boxes input')];
    const allChecked = boxes.every((b) => b.checked);
    boxes.forEach((b) => { b.checked = !allChecked; });
    syncDateDisabled();
  });
  // クリックでの showPicker() は使わない。サイドパネルではピッカーの表示位置が
  // 画面端に飛ぶ Chromium のバグがあり、遅延を入れても再発した（2026-08-14に実機で2回）。
  // 代わりに、フォーカス中だけ「数字で直接入力／一覧はアイコンから」のガイドを出す。
  const bindInputHint = (ids, hintId) => {
    const hint = document.getElementById(hintId);
    const els = ids.map((id) => document.getElementById(id));
    const update = () => { hint.hidden = !els.includes(document.activeElement); };
    for (const el of els) {
      el.addEventListener('focus', update);
      el.addEventListener('blur', () => setTimeout(update, 0));
    }
  };
  bindInputHint(['input-time', 'input-end-time'], 'time-hint');
  bindInputHint(['input-date'], 'date-hint');
  resetForm();
  await load();
  // 予定がまだ1つも無い（初回起動など）ときは、最初の一歩が見えるようフォームを開いておく
  if (schedule.length === 0) setFormOpen(true);
  // 通知がオフだとこの拡張は仕事ができないので、その状態を隠さず見せる
  if (typeof chrome !== 'undefined' && chrome.notifications && chrome.notifications.getPermissionLevel) {
    chrome.notifications.getPermissionLevel((level) => {
      document.getElementById('notif-warning').hidden = level === 'granted';
    });
  }
  renderAll();
  // 通知ボタンからの実績記録を画面に反映する
  if (hasChromeStorage) {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local') return;
      if (changes.records) records = changes.records.newValue || {};
      if (changes.notes) notes = changes.notes.newValue || {};
      if (changes.schedule) schedule = changes.schedule.newValue || [];
      if (changes.activeBlock) activeBlock = changes.activeBlock.newValue || null;
      renderAll();
    });
  }
  // 「いまの時間」の強調を1分ごとに更新
  setInterval(renderToday, 60 * 1000);
})();
