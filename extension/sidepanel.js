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

let schedule = [];
let records = {};
let notes = {}; // { 日付: { itemId: '実際にやっていたこと' } }
let editingId = null; // null なら新規追加モード
let expandedNoteFor = null; // 「実際は」を編集中の itemId
let noteFreeTextFor = null; // 「その他…」の自由入力を開いている itemId

async function load() {
  const data = await store.get(['schedule', 'records', 'notes']);
  schedule = Array.isArray(data.schedule) ? data.schedule : [];
  records = data.records || {};
  notes = data.notes || {};
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
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); ok.click(); }
    });
    row.append(input, ok);
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

function daysText(days) {
  if (!Array.isArray(days) || days.length === 0) return T('everyday');
  return days.slice().sort().map((d) => DAY_NAMES[d]).join('・');
}

function isTodayItem(item) {
  if (!item.enabled) return false;
  if (!Array.isArray(item.days) || item.days.length === 0) return true;
  return item.days.includes(new Date().getDay());
}

function renderToday() {
  const listEl = document.getElementById('today-list');
  const emptyEl = document.getElementById('today-empty');
  listEl.textContent = '';
  const items = schedule.filter(isTodayItem).sort((a, b) => a.time.localeCompare(b.time));
  emptyEl.hidden = items.length > 0;

  const now = new Date();
  const nowHM = `${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  const todayRec = records[todayKey()] || {};

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

    // 連続記録（2日以上続いていたら見せる。スキップでは切れない）
    const streak = streakFor(records, item.id, now, item.days);
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

    if (result === 'done') {
      const s = document.createElement('span');
      s.className = 'status done';
      s.textContent = T('statusDone');
      card.append(s);
    } else if (result === 'skip') {
      const s = document.createElement('span');
      s.className = 'status skip';
      s.textContent = T('statusSkip');
      card.append(s);
    } else {
      if (item.time <= nowHM) card.classList.add('now');
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

    // 「実際は」行：スキップ済み、または時間が過ぎて未記録のとき。
    // 何をしていたかを後から見返すための自己申告（自動追跡はしない）
    if (result === 'skip' || (result === undefined && pastDue)) {
      card.append(buildNoteRow(item));
    }
    listEl.append(card);
  }
}

function renderItems() {
  const listEl = document.getElementById('item-list');
  listEl.textContent = '';
  const items = schedule.slice().sort((a, b) => a.time.localeCompare(b.time));
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
    days.textContent = daysText(item.days);

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

    card.append(time, label, days, toggleBtn, editBtn, delBtn);
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

function startEdit(id) {
  const item = schedule.find((it) => it.id === id);
  if (!item) return;
  editingId = id;
  document.getElementById('form-title').textContent = T('editHeading');
  document.getElementById('save-btn').textContent = T('saveBtn');
  document.getElementById('cancel-btn').hidden = false;
  document.getElementById('input-time').value = item.time;
  document.getElementById('input-end-time').value = item.endTime || '';
  document.getElementById('input-label').value = item.label;
  setSelectedDays(item.days);
  document.getElementById('edit-section').scrollIntoView({ behavior: 'smooth' });
}

function resetForm() {
  editingId = null;
  document.getElementById('form-title').textContent = T('addHeading');
  document.getElementById('save-btn').textContent = T('addBtn');
  document.getElementById('cancel-btn').hidden = true;
  document.getElementById('item-form').reset();
  setSelectedDays([]);
}

document.getElementById('item-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const time = document.getElementById('input-time').value;
  const endTime = document.getElementById('input-end-time').value;
  const label = document.getElementById('input-label').value.trim();
  if (!time || !label) return;
  if (endTime && !isValidEndTime(time, endTime)) {
    alert(T('endTimeInvalid'));
    return;
  }
  const days = selectedDays();

  if (editingId) {
    const item = schedule.find((it) => it.id === editingId);
    if (item) {
      item.time = time;
      item.endTime = endTime || undefined;
      item.label = label;
      item.days = days;
      item.updatedAt = Date.now();
    }
  } else {
    schedule.push({
      id: 'it' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      time,
      endTime: endTime || undefined,
      label,
      days,
      enabled: true,
      createdAt: Date.now(),
      updatedAt: Date.now()
    });
  }
  await saveSchedule();
  resetForm();
  renderAll();
});

document.getElementById('cancel-btn').addEventListener('click', resetForm);

(async function init() {
  // 文言の確定 → 画面組み立ての順を守る（逆にすると文言が出ない）
  await loadPreviewMessages();
  applyI18n();
  DAY_NAMES = ['day0', 'day1', 'day2', 'day3', 'day4', 'day5', 'day6'].map((k) => T(k));
  NOTE_CHOICES = ['chipOtherWork', 'chipBreak', 'chipBrowsing', 'chipNoMood'].map((k) => T(k));
  buildDayBoxes();
  await load();
  renderAll();
  // 通知ボタンからの実績記録を画面に反映する
  if (hasChromeStorage) {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== 'local') return;
      if (changes.records) records = changes.records.newValue || {};
      if (changes.notes) notes = changes.notes.newValue || {};
      if (changes.schedule) schedule = changes.schedule.newValue || [];
      renderAll();
    });
  }
  // 「いまの時間」の強調を1分ごとに更新
  setInterval(renderToday, 60 * 1000);
})();
