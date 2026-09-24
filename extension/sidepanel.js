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

// 英語の複数形（1 day / 2 days）を正しく出すための引き分け。
// n=1 のときだけ「◯◯1」という単数形キーを使う（ja は両方同じ文言）
function Tn(key, n, extra = []) {
  // 単数形のキーでは $1 から extra が入る。複数形では n が $1、extra は $2 以降
  return n === 1 ? T(key + '1', extra) : T(key, [n, ...extra]);
}

// 月名などを出すときの言語。拡張なら Chrome の表示言語、プレビューなら ?lang= に合わせる
// （ブラウザの既定言語だと、英語表示のなかに「9月」が混ざる）
function uiLocale() {
  if (hasChromeI18n) return chrome.i18n.getUILanguage();
  return new URLSearchParams(location.search).get('lang') || 'ja';
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
function showToast(text, opts) {
  const el = document.getElementById('toast');
  el.textContent = text;
  if (opts && opts.emoji) {
    const s = document.createElement('span');
    s.className = 'toast-animal';
    s.textContent = opts.emoji;
    el.prepend(s);
  }
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, opts && opts.emoji ? 3600 : 3000);
  if (opts && opts.party) throwPetParty();
}

// 今日のぜんぶ済みのお祝い：動物たちがふわっと浮かんで消える。
// 数秒で跡形もなく消え、記録には何も残さない（見た人だけのごほうび）
function throwPetParty() {
  if (document.getElementById('pet-party')) return;
  const wrap = document.createElement('div');
  wrap.id = 'pet-party';
  for (let i = 0; i < 6; i++) {
    const s = document.createElement('span');
    s.textContent = CHEER_ANIMALS[Math.floor(Math.random() * CHEER_ANIMALS.length)];
    s.style.left = `${8 + Math.random() * 84}%`;
    s.style.animationDelay = `${i * 0.18}s`;
    wrap.append(s);
  }
  document.body.append(wrap);
  setTimeout(() => wrap.remove(), 3400);
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

// サイドパネルとして開かれたとき、別のウィンドウで既にサイドパネルが開いていればそちらへ寄せる。
// アイコンをクリックするたびにウィンドウごとへ増えていくのを防ぐ（既存を前面に出す）。
// 同じウィンドウで開き直したときは寄せない（それは普通の開閉なので）
async function handOverToExistingSidePanel() {
  if (isPopupWindow || isEmbedded || !canOpenWindow) return false;
  if (typeof chrome.runtime.getContexts !== 'function') return false; // Chrome 116未満
  try {
    const self = await getOwnWindow();
    if (!self) return false;
    const contexts = await chrome.runtime.getContexts({ contextTypes: ['SIDE_PANEL'] });
    // frameId 0 以外は、まとめるくん（ハブ）に埋め込まれた自分の iframe なので対象にしない
    const other = contexts.find((c) => (c.frameId ?? 0) === 0 && c.windowId != null && c.windowId !== self.id);
    if (!other) return false;
    await chrome.windows.update(other.windowId, { focused: true, drawAttention: true });
    window.close();
    return true;
  } catch {
    // 判定に失敗したら普通に表示する（二重表示になっても実害は表示だけ）
    return false;
  }
}

// 曜日名・チップは init 時（プレビュー文言の読み込み後）に確定させる
let DAY_NAMES = [];
let NOTE_CHOICES = []; // 「実際は」のワンタップ選択肢。責める言葉は使わない

// pad2 / dateKey / streakFor などは logic.js（共有ロジック）から来る
function todayKey() {
  return dateKey(new Date());
}

function timeText(item) {
  if (isAnytime(item)) return T('anytimeBadge');
  return item.endTime ? `${item.time}〜${item.endTime}` : item.time;
}

// 時刻列（「09:00」または「いつでも」バッジ）と目安時間の表示を組み立てる
function buildTimeSpan(item) {
  const time = document.createElement('span');
  time.className = 'time' + (isAnytime(item) ? ' anytime' : '');
  time.textContent = timeText(item);
  return time;
}

// 「前にできていた」の候補日チップ。昨日から新しい順に、最後にやった日の翌日まで（最大7日）
function buildPastDoneRow(item, now) {
  const wrap = document.createElement('div');
  wrap.className = 'past-done-row';
  const hint = document.createElement('div');
  hint.className = 'note-label';
  hint.textContent = T('pastDoneHint');
  const chips = document.createElement('div');
  chips.className = 'past-done-chips';
  const yesterday = dateKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1));
  for (const key of pastDoneCandidates(item, records, now, 7)) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'chip';
    b.textContent = key === yesterday ? T('pastDoneYesterday', [reviewDateText(key)]) : reviewDateText(key);
    b.addEventListener('click', () => recordPastDone(item, key));
    chips.append(b);
  }
  wrap.append(hint, chips);
  return wrap;
}

// 過去の日に「できた」を付ける。◯日ごとは基準日が動くので、次の目安日を言い切って知らせる
// （カードが今日の予定から消えることがあり、黙って消えると「無くなった」に見える）
async function recordPastDone(item, key) {
  const targetId = item.origId || item.id;
  if (!records[key]) records[key] = {};
  records[key][targetId] = 'done';
  await saveRecords();
  pastDoneOpenFor.delete(item.id);
  const now = new Date();
  const info = intervalDueInfo(item, records, now);
  const due = new Date(now.getFullYear(), now.getMonth(), now.getDate() + info.daysUntil);
  const dueText = reviewDateText(dateKey(due));
  if (info.daysUntil > intervalNoticeDays(item)) {
    showToast(T('pastDoneToastNext', [reviewDateText(key), dueText]));
  } else if (info.daysUntil > 0) {
    showToast(T('pastDoneToastSoon', [reviewDateText(key), dueText]));
  } else {
    showToast(T('pastDoneToastDue', [reviewDateText(key), dueText]));
  }
  renderAll();
}

function buildTargetSpan(item) {
  if (!isAnytime(item) || !item.targetMin) return null;
  const t = document.createElement('span');
  t.className = 'target';
  t.textContent = T('targetText', [item.targetMin]);
  return t;
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
let settings = {}; // 設定（今は予告のオン/オフと何分前か）
let settingsOpen = false; // 「設定」の開閉状態（既定は畳む）

async function load() {
  const data = await store.get(['schedule', 'records', 'notes', 'activeBlock', 'settings']);
  schedule = Array.isArray(data.schedule) ? data.schedule : [];
  records = data.records || {};
  notes = data.notes || {};
  activeBlock = data.activeBlock || null;
  settings = data.settings || {};
}

async function saveSettings() {
  await store.set({ settings });
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
  // やりなおしコピー（origId付き）への記録・メモは元の予定に付ける
  const targetId = item.origId || item.id;
  if (!notes[key]) notes[key] = {};
  notes[key][targetId] = text;
  await saveNotes();
  if (!(records[key] && records[key][targetId])) {
    if (!records[key]) records[key] = {};
    records[key][targetId] = 'skip';
    await saveRecords();
  }
  if (item.origId) {
    schedule = schedule.filter((it) => it.id !== item.id);
    await saveSchedule();
  }
  expandedNoteFor = null;
  noteFreeTextFor = null;
  renderToday();
}

// 記録を付ける。やりなおしコピー（origId付き）は元の予定に記録を付けて
// ストリークを守り、役目を終えたコピーは一覧から消す。
// 「済み」のときだけ応援のことばを出す（責めない設計：スキップには何も言わない）
const PRAISE_KEYS = ['praise1', 'praise2', 'praise3', 'praise4', 'praise5'];

// こっそりお祝い（隠し機能）。今日の予定がぜんぶ済んだ日とストリークの節目だけ
// 動物が出てきて祝う。ふだんの「できた」にも、ときどき1匹だけ顔を出す。
// どこにも説明を書かない・記録に残さない・出なくても何も失わない（責めない設計の裏返し）
const CHEER_ANIMALS = ['🐶', '🐱', '🐹', '🐰', '🐻', '🐧', '🦔', '🐿️', '🐥', '🦊'];

function pickAnimal() {
  return CHEER_ANIMALS[Math.floor(Math.random() * CHEER_ANIMALS.length)];
}

function cheerAfterDone(item, targetId) {
  const now = new Date();
  if (allDoneToday(schedule, records, now)) {
    showToast(T('cheerAllDone'), { emoji: pickAnimal(), party: true });
    return;
  }
  if (!isOneOff(item) && !isInterval(item)) {
    const streak = streakFor(records, targetId, now, item.days);
    if (isStreakMilestone(streak)) {
      showToast(T('cheerStreak', [streak]), { emoji: pickAnimal() });
      return;
    }
  }
  const emoji = Math.random() < 0.25 ? pickAnimal() : '';
  showToast(T(PRAISE_KEYS[Math.floor(Math.random() * PRAISE_KEYS.length)]), { emoji });
}

async function recordFromPanel(item, result) {
  const key = todayKey();
  const targetId = item.origId || item.id;
  if (!records[key]) records[key] = {};
  records[key][targetId] = result;
  await saveRecords();
  if (item.origId) {
    schedule = schedule.filter((it) => it.id !== item.id);
    await saveSchedule();
  }
  if (result === 'done') {
    cheerAfterDone(item, targetId);
  }
  renderToday();
}

// 「実際は」の行を組み立てる（スキップ済み、または時間が過ぎて未記録のカードに付く）
function buildNoteRow(item) {
  const row = document.createElement('div');
  row.className = 'note-row';
  const note = (notes[todayKey()] || {})[item.origId || item.id];

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
  if (isInterval(item)) return T('intervalText', [item.intervalDays]);
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
  if (!item.enabled || isArchived(item)) return false;
  // 済んでから◯日後：目安日の noticeDays 日前から「今日の予定」に出す。
  // 今日「できた」を押すと次の目安日は先になるが、カードが消えると押した結果が
  // 見えなくなるので、今日の記録がある間は「今日対応済み」に残す
  if (isInterval(item)) {
    if ((records[todayKey()] || {})[item.id] !== undefined) return true;
    const info = intervalDueInfo(item, records, new Date());
    return info.daysUntil <= intervalNoticeDays(item);
  }
  if (isOneOff(item)) return item.date === todayKey();
  if (!Array.isArray(item.days) || item.days.length === 0) return true; // 旧形式＝毎日
  return item.days.includes(new Date().getDay());
}

// 済んでから◯日後の状態バッジ（そろそろ／今日が目安／最後にやってから◯日）。
// 今日の予定と登録済み一覧の両方で同じ表示を使う（状態表示は全箇所で連動させる）
function buildIntervalBadge(item, now) {
  const info = intervalDueInfo(item, records, now);
  const s = document.createElement('span');
  // 「あと2日」だけでは次がいつか分からないので、日付を先に出す（本人指摘・2026-09-23）
  const dueText = shortDateText(dateKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() + info.daysUntil)));
  if (info.daysUntil > intervalNoticeDays(item)) {
    // まだ先（お知らせ期間の外）は「そろそろ」と言わず、日付と日数だけ淡く出す
    s.className = 'status since';
    s.textContent = Tn('inDays', info.daysUntil, [dueText]);
  } else if (info.daysUntil > 0) {
    s.className = 'status soon';
    s.textContent = Tn('dueSoon', info.daysUntil, [dueText]);
  } else if (info.daysUntil === 0) {
    s.className = 'status soon';
    s.textContent = T('dueToday');
  } else {
    // 過ぎても責めない：事実（最後にやってからの日数）だけを淡々と出す
    s.className = 'status since';
    s.textContent = Tn('sinceDone', info.sinceDone);
  }
  return s;
}

let doneOpen = true; // 「今日対応済み」の開閉状態

// 件名の全文を開いている予定のID。画面を閉じるまで覚えていれば足りるので保存はしない
const expandedToday = new Set();

// 「再設定」の入力行を開いているカードのID（同じく画面ごとの一時状態）
const redoOpenFor = new Set();
// ◯日ごとのカードで「前にできていた」の候補日を開いている予定の id
const pastDoneOpenFor = new Set();

// 「再設定」の行。今日の別の時刻でもう一度通知させる。
// 繰り返し予定は本体の時刻を動かさず、今日だけの「やりなおし」コピー（origId付き）を作る。
// コピーへの記録は recordFromPanel / saveNote が元の予定に付け替える
function buildRedoRow(item) {
  const row = document.createElement('div');
  row.className = 'redo-row';
  const input = document.createElement('input');
  input.type = 'time';
  const def = new Date(Date.now() + 15 * 60000);
  input.value = `${pad2(def.getHours())}:${pad2(def.getMinutes())}`;
  const go = document.createElement('button');
  go.className = 'redo-go';
  go.textContent = T('redoGo');
  go.addEventListener('click', async () => {
    const t = input.value;
    const now = new Date();
    const nowHM = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
    if (!t || t <= nowHM) {
      showToast(T('redoPastTime'));
      return;
    }
    // 終了時刻つきの予定は、開始との間隔を保ったままずらす（日をまたぐなら外す）
    let endTime;
    if (item.endTime) {
      const toMin = (hm) => Number(hm.slice(0, 2)) * 60 + Number(hm.slice(3));
      const end = toMin(t) + Math.max(0, toMin(item.endTime) - toMin(item.time));
      if (end < 24 * 60) endTime = `${pad2(Math.floor(end / 60))}:${pad2(end % 60)}`;
    }
    if (isOneOff(item)) {
      // 今日1回だけの予定（やりなおしコピー自身も含む）は、その場で時刻を差し替える
      item.time = t;
      if (item.endTime) {
        if (endTime) item.endTime = endTime;
        else delete item.endTime;
      }
    } else {
      schedule.push({
        id: 'it' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
        label: item.label,
        ...(item.detail ? { detail: item.detail } : {}),
        time: t,
        ...(endTime ? { endTime } : {}),
        date: todayKey(),
        days: [],
        enabled: true,
        origId: item.id,
      });
    }
    redoOpenFor.delete(item.id);
    await saveSchedule();
    renderToday();
  });
  const cancel = document.createElement('button');
  cancel.className = 'redo-cancel';
  cancel.textContent = T('redoCancel');
  cancel.addEventListener('click', () => {
    redoOpenFor.delete(item.id);
    renderToday();
  });
  row.append(input, go, cancel);
  return row;
}

function renderToday() {
  const listEl = document.getElementById('today-list');
  const emptyEl = document.getElementById('today-empty');
  const doneListEl = document.getElementById('done-list');
  const doneTitleEl = document.getElementById('done-title');
  listEl.textContent = '';
  doneListEl.textContent = '';
  const items = schedule.filter(isTodayItem).sort((a, b) => (a.time || '').localeCompare(b.time || ''));

  const now = new Date();
  const nowHM = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  const todayRec = records[todayKey()] || {};

  // 上の欄は「今日のこれから」だけ：進行中 → いつでも → これから → 未対応（各グループ内は時刻順）。
  // 時刻を固定しない予定は「今すぐ着手できる」ので進行中の直下に置く。
  // 対応済み（できた・スキップ）は下の「今日対応済み」に移す
  const groupOf = (it) => {
    if (activeBlock && activeBlock.itemId === it.id && Date.now() < activeBlock.endMs) return 0;
    const result = todayRec[it.id];
    if (result !== undefined) return 5; // できた・スキップ
    // 済んでから◯日後：目安日以降は「いつでも」と同じ扱い。
    // まだ先（そろそろ予告中）は今日の本来の予定を邪魔しないよう一番下に置く
    if (isInterval(it)) return intervalDueInfo(it, records, now).daysUntil > 0 ? 4 : 1;
    if (isAnytime(it)) return 1; // いつでも（時間切れの概念がなく、未対応にもならない）
    if (it.time > nowHM) return 2; // これから
    return 3; // 時間が過ぎて未対応
  };
  items.sort((a, b) => groupOf(a) - groupOf(b) || (a.time || '').localeCompare(b.time || ''));

  const resolvedCount = items.filter((it) => groupOf(it) === 5).length;
  emptyEl.hidden = items.length - resolvedCount > 0;
  doneTitleEl.hidden = resolvedCount === 0;
  doneTitleEl.textContent = T('doneHeading', [resolvedCount]);
  doneTitleEl.classList.toggle('open', doneOpen);
  doneListEl.hidden = !doneOpen || resolvedCount === 0;

  // 「次の予定」＝まだ時間が来ていない未記録の予定のうち、いちばん早いもの
  // （時刻を固定しない予定と済んでから◯日後は「次」の対象にしない）
  const nextItem = items.find((it) => !isAnytime(it) && !isInterval(it) && todayRec[it.id] === undefined && it.time > nowHM);

  // 有効な「やりなおし」コピー（元の予定ID→コピー）。元のカードとは二重に出さない
  const redoOf = new Map();
  for (const it of items) {
    if (it.origId) redoOf.set(it.origId, it);
  }

  for (const item of items) {
    // やりなおし待ちの元予定は隠す（コピーのカードが「これから」に出ている）
    if (redoOf.has(item.id) && todayRec[item.id] === undefined) continue;
    const card = document.createElement('div');
    card.className = 'card';
    const time = buildTimeSpan(item);
    const label = document.createElement('span');
    label.className = 'label';
    label.textContent = item.label;
    // 長い件名は1行に切り詰めるので、カードのクリックで全文を開けるようにする。
    // 毎分の再描画で閉じてしまわないよう、開いた予定は expandedToday に覚えておく
    label.title = item.detail ? `${item.label}\n${item.detail}` : item.label;
    if (expandedToday.has(item.id)) card.classList.add('expanded');
    card.addEventListener('click', (e) => {
      if (e.target.closest('button, input, textarea, select, a')) return;
      if (expandedToday.has(item.id)) expandedToday.delete(item.id);
      else expandedToday.add(item.id);
      // 開閉で管理操作（休む・編集・削除）の行も出し入れするので描画し直す
      renderToday();
    });
    const result = todayRec[item.id];
    card.append(time, label);
    // 時刻を固定しない予定の目安時間。未記録のカードでは操作ボタンと一緒に
    // 2行目へ出す（1行目に全部並べるとタイトルが潰れて読めなくなる）
    const target = buildTargetSpan(item);
    if (target && result !== undefined) card.append(target);

    // 連続記録（繰り返し予定のみ。2日以上続いていたら見せる。スキップでは切れない）
    // 済んでから◯日後は毎日やるものではないので連続の概念を持たない
    const streak = isOneOff(item) || isInterval(item) ? 0 : streakFor(records, item.id, now, item.days);
    if (streak >= 2) {
      const st = document.createElement('span');
      st.className = 'streak';
      st.textContent = T('streakText', [streak]);
      st.title = T('streakTitle', [streak]);
      card.append(st);
    }

    // やりなおしコピーには目印を付ける（元の時間ではなく再設定した時間だと分かるように）
    if (item.origId) {
      const tag = document.createElement('span');
      tag.className = 'redo-tag';
      tag.textContent = T('redoTag');
      card.append(tag);
    }

    // 「時間が過ぎた」の判定。時間帯ブロックなら終了時刻を基準にする。
    // 時刻を固定しない予定と済んでから◯日後は「時間が過ぎた」にならない
    // （未対応バッジも出さない。済んでから◯日後は日数の事実だけを別バッジで見せる）
    const dueHM = item.endTime || item.time;
    const pastDue = !isAnytime(item) && !isInterval(item) && dueHM <= nowHM;

    // 長いバッジ（次の予定・いまの時間）はタイトルを潰さないよう2行目に出す
    const subBadges = [];

    // 済んでから◯日後の状態（そろそろ／今日が目安／最後にやってから◯日）
    if (isInterval(item) && result === undefined) {
      subBadges.push(buildIntervalBadge(item, now));
      // 済ませたのに付け忘れた日を、あとから「できた」にする入口。
      // ふりかえりまで行かなくても今日のカードから直せる（2026-09-22 本人指摘：
      // 昨日やった点滴が今日の予定に残り、「今日済み」では次の目安日がずれる）
      if (pastDoneCandidates(item, records, now, 7).length > 0) {
        const spacer = document.createElement('span');
        spacer.className = 'row-spacer';
        const pastBtn = document.createElement('button');
        pastBtn.type = 'button';
        pastBtn.className = 'redo-btn' + (pastDoneOpenFor.has(item.id) ? ' open' : '');
        pastBtn.textContent = T('pastDoneBtn');
        pastBtn.title = T('pastDoneTip');
        pastBtn.addEventListener('click', () => {
          if (pastDoneOpenFor.has(item.id)) pastDoneOpenFor.delete(item.id);
          else pastDoneOpenFor.add(item.id);
          renderToday();
        });
        subBadges.push(spacer, pastBtn);
      }
    }

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
      if (!isActive && !isAnytime(item) && !isInterval(item) && item.time <= nowHM) card.classList.add('now');
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
      doneBtn.addEventListener('click', () => recordFromPanel(item, 'done'));
      if (isAnytime(item) || isInterval(item)) {
        // 時刻を固定しない予定は通知が無く、通知ボタンからスキップできないので、
        // パネル側に「今日はスキップ」を置く（スキップはストリークを切らない）。
        // 済んでから◯日後も「その日のどこかでやる」ものなので同じ形にする。
        // 目安時間とボタン2つは1行目に収まらないため、まとめて2行目に出す
        const skipBtn = document.createElement('button');
        skipBtn.className = 'mark-skip';
        skipBtn.textContent = T('notifBtnSkipToday');
        skipBtn.addEventListener('click', () => recordFromPanel(item, 'skip'));
        const row = document.createElement('div');
        row.className = 'badge-row';
        if (target) row.append(target);
        const spacer = document.createElement('span');
        spacer.className = 'row-spacer';
        row.append(spacer, doneBtn, skipBtn);
        card.append(row);
      } else {
        card.append(doneBtn);
      }
      // 時間が過ぎた予定は、今日の別の時刻でやりなおせるようにする
      if (!isActive && pastDue) {
        const redoBtn = document.createElement('button');
        redoBtn.className = 'redo-btn';
        redoBtn.textContent = T('redoBtn');
        redoBtn.title = T('redoTip');
        redoBtn.addEventListener('click', () => {
          if (redoOpenFor.has(item.id)) redoOpenFor.delete(item.id);
          else redoOpenFor.add(item.id);
          renderToday();
        });
        card.append(redoBtn);
      }
    }

    if (subBadges.length > 0) {
      const row = document.createElement('div');
      row.className = 'badge-row';
      row.append(...subBadges);
      card.append(row);
    }
    // 「前にできていた」の候補日（◯日ごとの未記録カードで、ボタンを押したときだけ）
    if (isInterval(item) && result === undefined && pastDoneOpenFor.has(item.id)) {
      card.append(buildPastDoneRow(item, now));
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
    // 「再設定」の入力行（未対応カードで再設定ボタンを押したときだけ）
    if (redoOpenFor.has(item.id) && result === undefined && pastDue && !isActive) {
      card.append(buildRedoRow(item));
    }
    // 今日に出ている予定は「登録済みの予定」に重ねて出さないので、管理操作
    // （休む・編集・削除）はカードを開いたときにここへ出す（登録済み一覧と同じ並び）。
    // やりなおしコピーは元の予定側で管理するため出さない
    if (expandedToday.has(item.id) && !item.origId) {
      const pauseBtn = document.createElement('button');
      pauseBtn.textContent = T('pauseBtn');
      pauseBtn.title = T('pauseTitle');
      pauseBtn.addEventListener('click', async () => {
        item.enabled = false;
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
      const manage = document.createElement('div');
      manage.className = 'badge-row';
      manage.append(pauseBtn, editBtn, delBtn);
      card.append(manage);
    }
    // 対応済みは「今日対応済み」欄へ、それ以外は「今日の予定」欄へ
    (groupOf(item) === 5 ? doneListEl : listEl).append(card);
  }
}

let registeredOpen = false; // 「登録済みの予定」の開閉状態（既定は畳む。開くと明日以降も見える）

function renderItems() {
  const listEl = document.getElementById('item-list');
  const emptyEl = document.getElementById('items-empty');
  listEl.textContent = '';
  const sortNow = new Date();
  // 今日の予定・今日対応済みに出ているものは、ここには重ねて出さない（同じ予定が
  // 2か所にあると「登録済みの方にもあるけど、なんだっけ」となる。本人指摘）。
  // その分の休む・編集・削除は、今日の予定のカードを開いたところに出す。
  // 保管済みの1回だけ予定（カレンダー用に残しているもの）もここには出さない
  const items = schedule
    .filter((it) => !isArchived(it) && !isTodayItem(it) && !it.origId)
    // 次に実行される順に並べる（これからの予定が上から順に見える）。
    // 時刻を固定しない予定は「その日の終わり」扱いで同じ日の時刻つき予定の後ろ。
    // 実行予定のないもの（休止中・終わった1回だけ）は一番下
    .sort((a, b) => {
      const na = listSortMs(a, sortNow, records);
      const nb = listSortMs(b, sortNow, records);
      return na - nb || (a.time || '').localeCompare(b.time || '');
    });
  // 今日側に出ていて隠した件数。1件でもあれば「重ねて出さない」ことを一言添える
  // （黙って隠すと「登録したのに無い」に見える）
  const hiddenToday = schedule.filter((it) => !isArchived(it) && !it.origId && isTodayItem(it)).length;
  const noteEl = document.getElementById('items-today-note');
  noteEl.hidden = !registeredOpen || hiddenToday === 0;
  listEl.hidden = !registeredOpen;
  emptyEl.hidden = !registeredOpen || items.length > 0 || hiddenToday > 0;
  const now = new Date();
  for (const item of items) {
    const card = document.createElement('div');
    card.className = 'card' + (item.enabled ? '' : ' disabled');

    const time = buildTimeSpan(item);
    const label = document.createElement('span');
    label.className = 'label';
    label.textContent = item.label;
    const days = document.createElement('span');
    days.className = 'days';
    days.textContent = repeatText(item);
    const target = buildTargetSpan(item);

    // 今日側に出ている予定はこの一覧に来ないので、今日の状態バッジはここでは不要。
    // 済んでから◯日後（まだ先のもの）だけ「あと何日か」を見せる（今日の予定側と同じバッジ）
    let statusBadge = null;
    if (isInterval(item) && item.enabled) statusBadge = buildIntervalBadge(item, now);

    // 1行に収める：普段は 時刻・名前・繰り返し・状態 だけ。
    // カードをクリックすると操作ボタン（休む・編集・削除）が2行目に開く
    const more = document.createElement('span');
    more.className = 'item-more';
    more.textContent = expandedActionsFor === item.id ? '▾' : '▸';

    card.append(time, label, days);
    if (target) card.append(target);
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

// ---- ふりかえり（過去の実績のタイルグリッド。HabitKit等のGitHub風グリッドが定石だが、
// 「できた」だけに色を付けて欠けを強調しない＝責めない設計に合わせた形にする）----

let reviewOpen = false; // 「ふりかえり」の開閉状態（既定は畳む）
let reviewSelected = null; // 選択中の日 { itemId, key }

const REVIEW_WEEKS = 12; // 先週までの12週間。これに今週の列を足して並べる（幅340pxに収まる）

// 過去の日の記録を付け直す（付け忘れの救済。グリッドの日をタップして使う）
async function setPastRecord(itemId, key, result) {
  if (result === undefined) {
    if (records[key]) {
      delete records[key][itemId];
      if (Object.keys(records[key]).length === 0) delete records[key];
    }
  } else {
    if (!records[key]) records[key] = {};
    records[key][itemId] = result;
  }
  await saveRecords();
  renderAll();
}

function reviewDateText(key) {
  const [y, m, d] = key.split('-').map(Number);
  return `${m}/${d}(${DAY_NAMES[new Date(y, m - 1, d).getDay()]})`;
}

// 選択した日の詳細行（状態＋「実際は」＋記録の修正ボタン）。
// カレンダーの日別リストからは日付も状態も行の側に出ているので showHead=false で使う
function buildReviewDetail(item, key, showHead = true) {
  const wrap = document.createElement('div');
  wrap.className = 'review-detail';

  const rec = records[key] && records[key][item.id];
  if (showHead) {
    const head = document.createElement('div');
    head.className = 'review-detail-head';
    const dateEl = document.createElement('span');
    dateEl.className = 'review-date';
    dateEl.textContent = reviewDateText(key);
    const st = document.createElement('span');
    st.className = 'status ' + (rec === 'done' ? 'done' : rec === 'skip' ? 'skip' : 'since');
    st.textContent = rec === 'done' ? T('statusDone') : rec === 'skip' ? T('statusSkip') : T('recNone');
    head.append(dateEl, st);
    wrap.append(head);
  }

  const note = notes[key] && notes[key][item.id];
  if (note) {
    const n = document.createElement('div');
    n.className = 'review-note';
    n.textContent = T('noteView', [note]);
    wrap.append(n);
  }

  wrap.append(buildRecordActions(item, key));
  return wrap;
}

// 記録の付け直しボタン。今の記録と同じボタンは出さない（意味のある操作だけ見せる）
function buildRecordActions(item, key) {
  const rec = records[key] && records[key][item.id];
  const actions = document.createElement('div');
  actions.className = 'badge-row';
  if (rec !== 'done') {
    const b = document.createElement('button');
    b.className = 'mark-done';
    b.textContent = T('reviewMarkDone');
    b.addEventListener('click', () => setPastRecord(item.id, key, 'done'));
    actions.append(b);
  }
  if (rec !== 'skip') {
    const b = document.createElement('button');
    b.textContent = T('reviewMarkSkip');
    b.addEventListener('click', () => setPastRecord(item.id, key, 'skip'));
    actions.append(b);
  }
  if (rec !== undefined) {
    const b = document.createElement('button');
    b.textContent = T('reviewClear');
    b.addEventListener('click', () => setPastRecord(item.id, key, undefined));
    actions.append(b);
  }
  return actions;
}

// ---- カレンダー（日付起点のふりかえり。Streaks / Loop Habit Tracker 等の
// 「日をタップしてその日の記録を見る・直す」が定石）----
// 印は「できた」の日だけ濃く、スキップだけの日は薄く、何もない日は白いまま（責めない設計）

let calYm = null; // 表示中の月 { y, m }（m は 1〜12）。null なら今月から始める
let calSelected = null; // 選択中の日（dateKey 形式）

function renderCalendar() {
  const box = document.getElementById('cal-box');
  box.hidden = !reviewOpen;
  if (!reviewOpen) return;
  const now = new Date();
  if (!calYm) calYm = { y: now.getFullYear(), m: now.getMonth() + 1 };
  const { y, m } = calYm;
  document.getElementById('cal-title').textContent = T('calMonthTitle', [String(y), T('monthName' + m)]);
  // 未来の月へは進めない（これからの予定は「今日の予定」と「登録済み」の担当）
  document.getElementById('cal-next').disabled = y === now.getFullYear() && m === now.getMonth() + 1;

  const grid = document.getElementById('cal-grid');
  grid.textContent = '';
  for (const name of DAY_NAMES) {
    const h = document.createElement('span');
    h.className = 'cal-dow';
    h.textContent = name;
    grid.append(h);
  }
  const first = new Date(y, m - 1, 1);
  const daysInMonth = new Date(y, m, 0).getDate();
  const today = todayKey();
  // 色の判定に使うのは、いまある予定（やりなおしコピー以外）の記録だけ。
  // 削除した予定の記録で色が付くと、日別リストと食い違って「何の色か分からない」
  const knownIds = schedule.filter((it) => !it.origId).map((it) => it.id);
  for (let i = 0; i < first.getDay(); i++) {
    const b = document.createElement('span');
    b.className = 'cal-cell blank';
    grid.append(b);
  }
  for (let d = 1; d <= daysInMonth; d++) {
    const key = `${y}-${pad2(m)}-${pad2(d)}`;
    const cell = document.createElement('button');
    cell.type = 'button';
    cell.className = 'cal-cell';
    cell.textContent = String(d);
    if (key > today) {
      // これからの日は数字だけ薄く見せて押せなくする
      cell.classList.add('future');
      cell.disabled = true;
    } else {
      const mark = dayMark(records, key, knownIds);
      if (mark) cell.classList.add(mark);
      if (key === today) cell.classList.add('today');
      if (calSelected === key) cell.classList.add('selected');
      cell.addEventListener('click', () => {
        calSelected = calSelected === key ? null : key;
        // 下のタイル側で開いていた日の詳細は閉じる。カレンダーの日を替えたのに
        // 前に選んだ日の「できた」が下に残っていると、その日の内容に見えてしまう
        reviewSelected = null;
        renderReview();
      });
    }
    grid.append(cell);
  }
  renderCalDayDetail();
}

// 選んだ日にあった予定の一覧（1回だけ・保管済みも含む）。
// 付け直しのボタンは行に最初から出す。以前は行をタップして開く形だったが、
// 開けることに気づけず「付け直せない」と受け取られた（2026-09-22 本人指摘）
function renderCalDayDetail() {
  const box = document.getElementById('cal-detail');
  box.textContent = '';
  if (!calSelected) return;
  const head = document.createElement('div');
  head.className = 'cal-detail-date';
  head.textContent = reviewDateText(calSelected);
  box.append(head);
  const items = itemsOnDay(schedule, records, calSelected);
  if (items.length === 0) {
    const p = document.createElement('p');
    p.className = 'empty-note';
    p.textContent = T('calDayEmpty');
    box.append(p);
    return;
  }
  const rec = records[calSelected] || {};
  for (const item of items) {
    const row = document.createElement('div');
    row.className = 'card cal-day-row';
    const label = document.createElement('span');
    label.className = 'label';
    label.textContent = item.label;
    label.title = item.label;
    const r = rec[item.id];
    const st = document.createElement('span');
    st.className = 'status ' + (r === 'done' ? 'done' : r === 'skip' ? 'skip' : 'since');
    st.textContent = r === 'done' ? T('statusDone') : r === 'skip' ? T('statusSkip') : T('recNone');
    row.append(buildTimeSpan(item), label, st);
    // 「実際は」のメモがあれば見せる（ここでは読むだけ。書くのは今日のカードから）
    const note = notes[calSelected] && notes[calSelected][item.id];
    if (note) {
      const n = document.createElement('div');
      n.className = 'review-note';
      n.textContent = T('noteView', [note]);
      row.append(n);
    }
    row.append(buildRecordActions(item, calSelected));
    box.append(row);
  }
}

function renderReview() {
  renderCalendar();
  const listEl = document.getElementById('review-list');
  const emptyEl = document.getElementById('review-empty');
  listEl.textContent = '';
  listEl.hidden = !reviewOpen;
  // やりなおしコピーは元の予定に集約されるので出さない。
  // 1回だけの予定は習慣ではないので、タイルや30日集計の対象にしない
  const items = schedule.filter((it) => !it.origId && !isOneOff(it));
  emptyEl.hidden = !reviewOpen || items.length > 0;
  if (!reviewOpen) return;

  const now = new Date();
  const today = todayKey();
  // 列＝週（左が古い）、行＝日〜土。先週までの12週に今週の列を足し、右端が今週になる。
  // 今週のまだ来ていない日は点線の枠だけにして、四角の形を崩さない。
  // （以前は「今週の列だけ欠けて飛び出して見える」の指摘で完全な週だけにしていたが、
  //  それだと昨日の記録を付け直す入口がここに無い。2026-09-22 本人指摘で今週まで出す）
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  start.setDate(start.getDate() - start.getDay() - 7 * REVIEW_WEEKS);
  const columns = REVIEW_WEEKS + 1;

  // 見方の説明。「ブロックが並んでいるだけで何か分からない」と言われたので、先頭に1回だけ書く
  const guide = document.createElement('p');
  guide.className = 'review-guide';
  guide.textContent = T('reviewGuide');
  listEl.append(guide);

  for (const item of items) {
    const card = document.createElement('div');
    card.className = 'card review-card';

    const label = document.createElement('span');
    label.className = 'label';
    label.textContent = item.label;
    label.title = item.label;
    card.append(label);

    // 繰り返しと時刻。同じ名前の予定が2つあっても（曜日違いの登録など）どちらか分かるように
    const when = document.createElement('span');
    when.className = 'review-when';
    when.textContent = `${repeatText(item)}・${timeText(item)}`;
    card.append(when);

    // 集計は事実だけ。0回のときは何も言わない（沈黙が中立）。
    // 済んでから◯日後は間隔が本体なので、30日窓に関係なく実際のペースを出す
    const parts = [];
    const doneN = doneCountRecent(records, item.id, now, 30);
    if (doneN > 0) parts.push(Tn('doneCount30', doneN));
    if (isInterval(item)) {
      const avg = avgDoneIntervalDays(records, item.id, now, 365);
      if (avg !== null) parts.push(Tn('avgInterval', avg));
    }
    if (parts.length > 0) {
      const sum = document.createElement('span');
      sum.className = 'review-summary';
      sum.textContent = parts.join('・');
      card.append(sum);
    }

    const grid = document.createElement('div');
    grid.className = 'review-grid';
    grid.style.gridTemplateColumns = `16px repeat(${columns}, 14px)`;
    // 左端に曜日。どの行が何曜日か、見なくても分かるように
    DAY_NAMES.forEach((name, r) => {
      const dow = document.createElement('span');
      dow.className = 'review-dow';
      dow.textContent = name;
      dow.style.gridRow = String(r + 2);
      dow.style.gridColumn = '1';
      grid.append(dow);
    });
    const sundayOf = (w) => new Date(start.getFullYear(), start.getMonth(), start.getDate() + w * 7);
    for (let w = 0; w < columns; w++) {
      const sunday = sundayOf(w);
      // 月が変わった最初の週の上に月名。左右どちらが新しいかも、これで分かる。
      // 左端の列は、隣の列で月が変わるなら書かない（「6月 7月」と詰まって読めないため）
      const startsMonth = w === 0 || sunday.getMonth() !== sundayOf(w - 1).getMonth();
      const nextStartsMonth = w + 1 < columns && sundayOf(w + 1).getMonth() !== sunday.getMonth();
      if (startsMonth && !(w === 0 && nextStartsMonth)) {
        const mon = document.createElement('span');
        mon.className = 'review-month';
        mon.textContent = sunday.toLocaleDateString(uiLocale(), { month: 'short' });
        mon.style.gridRow = '1';
        mon.style.gridColumn = String(w + 2);
        grid.append(mon);
      }
      for (let r = 0; r < 7; r++) {
        const d = new Date(sunday.getFullYear(), sunday.getMonth(), sunday.getDate() + r);
        const key = dateKey(d);
        const tile = document.createElement('button');
        tile.type = 'button';
        tile.className = 'tile';
        tile.style.gridRow = String(r + 2);
        tile.style.gridColumn = String(w + 2);
        if (key > today) {
          // まだ来ていない日。押せないし色も付かない
          tile.classList.add('future');
          tile.disabled = true;
          tile.title = reviewDateText(key);
          grid.append(tile);
          continue;
        }
        if (key === today) tile.classList.add('today');
        const rec = records[key] && records[key][item.id];
        if (rec === 'done') tile.classList.add('done');
        else if (rec === 'skip') tile.classList.add('skip');
        if (reviewSelected && reviewSelected.itemId === item.id && reviewSelected.key === key) {
          tile.classList.add('selected');
        }
        tile.title = `${reviewDateText(key)} ${rec === 'done' ? T('statusDone') : rec === 'skip' ? T('statusSkip') : T('recNone')}`;
        tile.addEventListener('click', () => {
          const same = reviewSelected && reviewSelected.itemId === item.id && reviewSelected.key === key;
          reviewSelected = same ? null : { itemId: item.id, key };
          // 逆方向も同じ：タイルの日を選んだら、上のカレンダーで開いていた日は閉じる
          // （日の詳細を見る場所は一度に1つ）
          calSelected = null;
          renderReview();
        });
        grid.append(tile);
      }
    }
    card.append(grid);

    // 凡例（タイルの色の意味。小さく1行だけ）
    const legend = document.createElement('div');
    legend.className = 'review-legend';
    const legDone = document.createElement('span');
    legDone.className = 'legend-swatch done';
    const legSkip = document.createElement('span');
    legSkip.className = 'legend-swatch skip';
    const legFuture = document.createElement('span');
    legFuture.className = 'legend-swatch future';
    legend.append(
      legDone, document.createTextNode(T('reviewMarkDone') + '　'),
      legSkip, document.createTextNode(T('reviewMarkSkip') + '　'),
      legFuture, document.createTextNode(T('legendFuture'))
    );
    card.append(legend);

    if (reviewSelected && reviewSelected.itemId === item.id) {
      card.append(buildReviewDetail(item, reviewSelected.key));
    }
    listEl.append(card);
  }
}

function renderAll() {
  renderToday();
  renderItems();
  renderSettings();
  renderReview();
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

// YYYY-MM-DD を「9/8(火)」の形にする（プレビュー用）
function shortDateText(key) {
  const [y, m, d] = key.split('-').map(Number);
  return `${m}/${d}(${DAY_NAMES[new Date(y, m - 1, d).getDay()]})`;
}

// いま登録しようとしている繰り返しの内容を、フォームの中でその場で具体的に言い切る。
// 説明文だけだと「今週の土曜のつもりで土に付けたら毎週だった」「3日ごとは何日空くのか」の
// 読み違えを防げないため。◯日ごとは次の目安日を実際の日付で見せる
function syncRepeatPreview() {
  const el = document.getElementById('repeat-preview');
  const hint = document.getElementById('interval-hint');
  const mode = getRepeatMode();
  hint.hidden = mode !== 'interval';
  el.hidden = false;
  if (mode === 'weekly') {
    const days = selectedDays();
    if (days.length === 7) el.textContent = T('previewEveryday');
    else if (days.length > 0) el.textContent = T('previewWeekly', [days.sort((a, b) => a - b).map((d) => DAY_NAMES[d]).join('・')]);
    else el.textContent = T('previewWeeklyNone');
    return;
  }
  if (mode === 'interval') {
    const n = Number(document.getElementById('input-interval-days').value);
    const anchor = document.getElementById('input-anchor-date').value;
    hint.textContent = T('intervalHint', [n]);
    // 「3日ごと」は、間の日数で数える人（「3日空けて」）には1日ずれて伝わる。
    // 「3日に1回」＋「間は2日空きます」＋実際の日付3つ、で読み違えの余地を消す
    const gap = n > 1 ? T('intervalGap', [n - 1]) : T('intervalGapNone');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(anchor)) { el.textContent = T('previewInterval', [n, gap]); return; }
    // 登録直後の状態をそのまま計算する（records は使わない＝フォームの値だけで決まる）
    const info = intervalDueInfo({ intervalDays: n, anchorDate: anchor }, {}, new Date());
    const today = new Date();
    const dayAt = (add) => dateKey(new Date(today.getFullYear(), today.getMonth(), today.getDate() + add));
    const due = dayAt(info.daysUntil);
    el.textContent = info.daysUntil > 0
      ? T('previewIntervalNext', [n, gap, shortDateText(due), shortDateText(dayAt(info.daysUntil + n)), shortDateText(dayAt(info.daysUntil + 2 * n))])
      : T('previewIntervalDue', [n, gap, shortDateText(due)]);
    return;
  }
  const v = document.getElementById('input-date').value;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) { el.hidden = true; return; }
  el.textContent = T('previewOneOff', [shortDateText(v)]);
}

// 「時刻を決めない」の切り替え：時刻欄と目安欄を入れ替える。
// 隠れた required 入力が保存を止めないよう、required も一緒に切り替える
function syncAnytime() {
  const on = document.getElementById('input-anytime').checked;
  document.getElementById('time-range-field').hidden = on;
  document.getElementById('end-hint').hidden = on;
  document.getElementById('target-field').hidden = !on;
  document.getElementById('anytime-hint').hidden = !on;
  document.getElementById('input-time').required = !on;
}

// 目安時間の選択肢。よく使う短時間は5分刻み、長くなるほど間隔を広げる。
// 全部を一度に見せるチップ方式なので、数は1画面に収まる範囲に絞る
const TARGET_MIN_CHOICES = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 180, 240, 360, 480];

function renderTargetMinChips() {
  renderValueChips('target-min-chips', 'input-target-min', TARGET_MIN_CHOICES, (v) => T('minuteOption', v));
}

function setTargetMinValue(v) {
  document.getElementById('input-target-min').value = String(v);
  renderTargetMinChips();
}

// ---- ◯日ごと（間隔と、何日前から知らせるかのチップ）----

// 間隔の選択肢。薬や点滴の「3日ごと・4日ごと」から、靴の手入れの月次・四半期までを1画面に収める
const INTERVAL_DAY_CHOICES = [2, 3, 4, 5, 6, 7, 10, 14, 21, 30, 45, 60, 90];
// お知らせ開始の選択肢（0=目安日の当日から）
const NOTICE_DAY_CHOICES = [0, 1, 2, 3, 5, 7];

// hidden input が値を持ち、チップで選ぶ（目安時間と同じ方式）。
// 選択肢に無い保存済みの値も編集時に壊さないよう、並び順の位置に足す。
// onChange はチップで値を変えたときだけ呼ぶ（プレビューの追従用）
function renderValueChips(boxId, inputId, choices, labelOf, onChange) {
  const box = document.getElementById(boxId);
  const cur = Number(document.getElementById(inputId).value);
  box.textContent = '';
  const values = [...choices];
  if (!values.includes(cur)) values.push(cur);
  values.sort((a, b) => a - b);
  for (const v of values) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chip' + (v === cur ? ' selected' : '');
    btn.textContent = labelOf(v);
    btn.addEventListener('click', () => {
      document.getElementById(inputId).value = String(v);
      renderValueChips(boxId, inputId, choices, labelOf, onChange);
      if (onChange) onChange();
    });
    box.append(btn);
  }
}

function renderIntervalChips() {
  renderValueChips('interval-chips', 'input-interval-days', INTERVAL_DAY_CHOICES, (v) => T('dayOption', v), () => {
    // 「3日ごと」に「3日前から出す」が付くと済ませた翌日からずっと一覧に居座る。
    // 短い間隔を選んだら、お知らせ開始を間隔より2日以上短くして「済んだら一度消える」を保つ
    const n = Number(document.getElementById('input-interval-days').value);
    const notice = Number(document.getElementById('input-notice-days').value);
    if (notice > Math.max(0, n - 2)) setNoticeDaysValue(Math.max(0, n - 2));
    syncRepeatPreview();
  });
}

function renderNoticeChips() {
  renderValueChips('notice-chips', 'input-notice-days', NOTICE_DAY_CHOICES,
    (v) => (v === 0 ? T('noticeToday') : Tn('noticeBefore', v)));
}

function setIntervalDaysValue(v) {
  document.getElementById('input-interval-days').value = String(v);
  renderIntervalChips();
}

function setNoticeDaysValue(v) {
  document.getElementById('input-notice-days').value = String(v);
  renderNoticeChips();
}

// ---- 設定（予告）----

// 何分前に出すかの選択肢。3分＝直前の一声、60分＝出かける支度が要る予定まで
const PRE_MIN_CHOICES = [3, 5, 10, 15, 30, 60];

function renderSettings() {
  const box = document.getElementById('settings-box');
  box.hidden = !settingsOpen;
  document.getElementById('settings-title').classList.toggle('open', settingsOpen);
  if (!settingsOpen) return;
  const { on, minutes } = preNoticeSettings(settings);
  document.getElementById('input-pre-notice').checked = on;
  document.getElementById('input-pre-min').value = String(minutes);
  // オフのときに「何分前」を出しておくと、効いていないのに効いて見える（状態表示は全箇所で連動）
  document.getElementById('pre-min-field').hidden = !on;
  renderValueChips('pre-min-chips', 'input-pre-min', PRE_MIN_CHOICES,
    (v) => T('minuteBeforeOption', String(v)), async () => {
      settings = { ...settings, preNoticeMin: Number(document.getElementById('input-pre-min').value) };
      await saveSettings();
    });
}

// 繰り返しの種類（'once' | 'weekly' | 'interval'）。排他のタブで1つだけ選ぶ
const REPEAT_MODES = ['once', 'weekly', 'interval'];
let repeatMode = 'once';

function getRepeatMode() {
  return repeatMode;
}

// タブの切り替え。選ばれていない種類の入力欄は隠すだけでなく disabled にして、
// 隠れた required の日付が保存を止めないようにする（制約検証は disabled を飛ばす）
function setRepeatMode(mode) {
  repeatMode = REPEAT_MODES.includes(mode) ? mode : 'once';
  document.querySelectorAll('#repeat-seg .seg-btn').forEach((btn) => {
    const on = btn.dataset.mode === repeatMode;
    btn.classList.toggle('selected', on);
    btn.setAttribute('aria-pressed', on ? 'true' : 'false');
  });
  document.getElementById('once-fields').hidden = repeatMode !== 'once';
  document.getElementById('weekly-fields').hidden = repeatMode !== 'weekly';
  document.getElementById('interval-fields').hidden = repeatMode !== 'interval';
  document.getElementById('input-date').disabled = repeatMode !== 'once';
  document.getElementById('input-anchor-date').disabled = repeatMode !== 'interval';
  syncRepeatPreview();
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
  // 「最後にやった日」は登録時の値でなく、いま効いている基準日（記録の最新「できた」が
  // 新しければそちら）を出す。プレビューの「次の目安日」を実際の表示と一致させるため
  document.getElementById('input-anchor-date').value =
    (isInterval(item) && intervalAnchorKey(item, records, new Date())) || todayKey();
  document.getElementById('input-anytime').checked = isAnytime(item);
  setTargetMinValue(item.targetMin || 10);
  setIntervalDaysValue(isInterval(item) ? item.intervalDays : 7);
  setNoticeDaysValue(isInterval(item) ? intervalNoticeDays(item) : 0);
  document.getElementById('input-time').value = item.time || '';
  document.getElementById('input-end-time').value = item.endTime || '';
  document.getElementById('input-label').value = item.label;
  document.getElementById('input-detail').value = item.detail || '';
  // 旧形式（曜日なし・日付なし＝毎日）は全曜日を付けた「毎週」として開く。
  // そのまま保存すると1回だけに化けていた取りこぼしの修正
  const weekly = !isInterval(item) && !isOneOff(item);
  setSelectedDays(weekly && (!Array.isArray(item.days) || item.days.length === 0) ? [0, 1, 2, 3, 4, 5, 6] : item.days);
  setRepeatMode(isInterval(item) ? 'interval' : weekly ? 'weekly' : 'once');
  syncAnytime();
  document.getElementById('edit-section').scrollIntoView({ behavior: 'smooth' });
}

// パネルを開いたまま日付が変わったとき（まとめるくんの窓で開きっぱなし等）の追従。
// 追加フォームの日付は resetForm() で入れた「その日の今日」のままになるので、
// まだ触っていなければ新しい今日に進める（2026-09-23 本人指摘：昨日の日付になっていた）。
// 日付が変わったらカレンダーやふりかえりも含めて描き直す
let lastSeenDay = todayKey();
function rollOverDay() {
  const today = todayKey();
  if (today === lastSeenDay) return;
  const prev = lastSeenDay;
  lastSeenDay = today;
  if (editingId === null) {
    for (const id of ['input-date', 'input-anchor-date']) {
      const el = document.getElementById(id);
      if (el.value === prev || el.value === '') el.value = today;
    }
    syncRepeatPreview();
  }
  renderAll();
}

function resetForm() {
  editingId = null;
  document.getElementById('form-title').textContent = T('addHeading');
  document.getElementById('save-btn').textContent = T('addBtn');
  document.getElementById('cancel-btn').hidden = true;
  document.getElementById('item-form').reset();
  document.getElementById('input-date').value = todayKey();
  document.getElementById('input-anchor-date').value = todayKey();
  setTargetMinValue(10);
  setIntervalDaysValue(7);
  setNoticeDaysValue(0);
  setSelectedDays([]);
  setRepeatMode('once');
  syncAnytime();
}

document.getElementById('item-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const anytime = document.getElementById('input-anytime').checked;
  const time = document.getElementById('input-time').value;
  const endTime = document.getElementById('input-end-time').value;
  const label = document.getElementById('input-label').value.trim();
  const detail = document.getElementById('input-detail').value.trim();
  if (!label) return;
  let targetMin;
  if (anytime) {
    // 時刻の代わりに1日の目安時間だけを持つ
    targetMin = Number(document.getElementById('input-target-min').value);
    if (!Number.isInteger(targetMin) || targetMin < 1 || targetMin > 480) {
      alert(T('targetMinInvalid'));
      return;
    }
  } else {
    if (!time) return;
    if (endTime && !isValidEndTime(time, endTime)) {
      alert(T('endTimeInvalid'));
      return;
    }
  }
  const mode = getRepeatMode();
  const intervalOn = mode === 'interval';
  const days = mode === 'weekly' ? selectedDays() : [];
  let date;
  let intervalDays;
  let noticeDays;
  let anchorDate;
  if (mode === 'weekly' && days.length === 0) {
    alert(T('weeklyNoDays'));
    return;
  }
  if (intervalOn) {
    // ◯日ごと：「最後にやった日」が次の目安日の基準。
    // 過去の日付でよいが、未来はまだ「済んで」いないので受け付けない
    intervalDays = Number(document.getElementById('input-interval-days').value);
    noticeDays = Number(document.getElementById('input-notice-days').value);
    if (!Number.isInteger(intervalDays) || intervalDays < 1 || intervalDays > 365) return;
    if (!Number.isInteger(noticeDays) || noticeDays < 0 || noticeDays > 30) noticeDays = 0;
    anchorDate = document.getElementById('input-anchor-date').value;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(anchorDate)) return;
    if (anchorDate > todayKey()) {
      alert(T('anchorFuture'));
      return;
    }
  } else {
    // 1回だけ＝日付指定。過去の日時は受け付けない
    // （時刻を固定しない予定は日付だけで判定し、今日はその日のうちなので受け付ける）
    date = mode === 'once' ? document.getElementById('input-date').value : undefined;
    if (date) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return;
      if (anytime) {
        if (date < todayKey()) {
          alert(T('pastDate'));
          return;
        }
      } else {
        const [y, m, d] = date.split('-').map(Number);
        const [hh, mm] = time.split(':').map(Number);
        if (new Date(y, m - 1, d, hh, mm).getTime() <= Date.now()) {
          alert(T('pastDateTime'));
          return;
        }
      }
    }
  }

  if (editingId) {
    const item = schedule.find((it) => it.id === editingId);
    if (item) {
      // 時刻あり⇔なしを切り替えたときに古い側の値が残らないよう、両方の欄を毎回上書きする
      // （undefined を入れたキーは保存時に落ちる）
      item.anytime = anytime || undefined;
      item.targetMin = anytime ? targetMin : undefined;
      item.time = anytime ? undefined : time;
      item.endTime = anytime ? undefined : (endTime || undefined);
      item.label = label;
      item.detail = detail || undefined;
      item.days = days;
      item.date = date;
      item.intervalDays = intervalOn ? intervalDays : undefined;
      item.noticeDays = intervalOn ? noticeDays : undefined;
      item.anchorDate = intervalOn ? anchorDate : undefined;
      item.updatedAt = Date.now();
    }
  } else {
    schedule.push({
      id: 'it' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      anytime: anytime || undefined,
      targetMin: anytime ? targetMin : undefined,
      time: anytime ? undefined : time,
      endTime: anytime ? undefined : (endTime || undefined),
      label,
      detail: detail || undefined,
      days,
      date,
      intervalDays: intervalOn ? intervalDays : undefined,
      noticeDays: intervalOn ? noticeDays : undefined,
      anchorDate: intervalOn ? anchorDate : undefined,
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

// 「設定」も見出しクリックで開閉する
document.getElementById('settings-title').addEventListener('click', () => {
  settingsOpen = !settingsOpen;
  renderSettings();
});

// 「ふりかえり」も見出しクリックで開閉する
document.getElementById('review-title').addEventListener('click', () => {
  reviewOpen = !reviewOpen;
  document.getElementById('review-title').classList.toggle('open', reviewOpen);
  renderReview();
});

(async function init() {
  // 別ウィンドウが生きているならそちらに任せて閉じる。描画前に判定して画面のちらつきを避ける
  if (await handOverToExistingWindow()) return;
  // 別のウィンドウでサイドパネルが開いているなら、そちらを前面に出して閉じる
  if (await handOverToExistingSidePanel()) return;
  // 文言の確定 → 画面組み立ての順を守る（逆にすると文言が出ない）
  await loadPreviewMessages();
  applyI18n();
  // バージョンバッジはmanifestから入れる（手書きだと更新漏れでズレる）
  try {
    document.getElementById('versionBadge').textContent =
      'v' + chrome.runtime.getManifest().version;
  } catch {
    // プレビュー（chrome.* なし）ではバッジを空のままにする
  }
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
  renderTargetMinChips();
  renderIntervalChips();
  renderNoticeChips();
  buildDayBoxes();
  // 繰り返しの種類はタブで排他に選ぶ
  document.querySelectorAll('#repeat-seg .seg-btn').forEach((btn) => {
    btn.addEventListener('click', () => setRepeatMode(btn.dataset.mode));
  });
  // 曜日・日付・最後にやった日を変えたら、プレビューの文言も追従させる
  document.getElementById('day-boxes').addEventListener('change', syncRepeatPreview);
  document.getElementById('input-date').addEventListener('input', syncRepeatPreview);
  document.getElementById('input-anchor-date').addEventListener('input', syncRepeatPreview);
  // カレンダーの月送り。移動したら日の選択は外す（別の月の日付が残ると紛らわしい）
  const calMove = (delta) => {
    const d = new Date(calYm.y, calYm.m - 1 + delta, 1);
    calYm = { y: d.getFullYear(), m: d.getMonth() + 1 };
    calSelected = null;
    renderCalendar();
  };
  document.getElementById('cal-prev').addEventListener('click', () => calMove(-1));
  document.getElementById('cal-next').addEventListener('click', () => calMove(1));
  // 「時刻を決めない」の切り替えで時刻欄⇔目安欄を入れ替える
  document.getElementById('input-anytime').addEventListener('change', syncAnytime);
  // 予告のオン/オフ
  // 拡張 → iPhone/Mac アプリへの引っ越し用。予定と記録をそのままの形で1ファイルに落とす
  // （アプリ側は同じ JSON の形を読むので、変換はしない）
  document.getElementById('export-data').addEventListener('click', async () => {
    const data = await store.get(['schedule', 'records', 'notes']);
    const body = { app: 'unagasukun', version: chrome.runtime.getManifest().version, exportedAt: Date.now(),
                   schedule: data.schedule || [], records: data.records || {}, notes: data.notes || {} };
    const blob = new Blob([JSON.stringify(body, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `unagasukun-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  });
  document.getElementById('input-pre-notice').addEventListener('change', async (e) => {
    settings = { ...settings, preNoticeOn: e.target.checked };
    await saveSettings();
    renderSettings();
  });
  // 「毎日」ボタン：全曜日を一括で付け外しする
  document.getElementById('btn-everyday').addEventListener('click', () => {
    const boxes = [...document.querySelectorAll('#day-boxes input')];
    const allChecked = boxes.every((b) => b.checked);
    boxes.forEach((b) => { b.checked = !allChecked; });
    syncRepeatPreview();
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
  bindInputHint(['input-anchor-date'], 'anchor-hint');
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
      if (changes.settings) settings = changes.settings.newValue || {};
      renderAll();
    });
  }
  // 「いまの時間」の強調を1分ごとに更新
  setInterval(() => { rollOverDay(); renderToday(); }, 60 * 1000);
  // 隠れている間はタイマーが間引かれることがあるので、見えた瞬間にも日付の変わり目を見る
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) { rollOverDay(); renderToday(); }
  });
})();
