// うながすくん service worker
// 予定の時刻に chrome.alarms で起きて通知を出し、
// 終了時刻つきの予定は「進行中ブロック」としてバッジに残り時間を出す係。

importScripts('logic.js');

const ALARM_PREFIX = 'item:';
const TICK_ALARM = 'block-tick';

async function getSchedule() {
  const { schedule } = await chrome.storage.local.get('schedule');
  return Array.isArray(schedule) ? schedule : [];
}

async function getTodayRecord(itemId) {
  const { records = {} } = await chrome.storage.local.get('records');
  const day = records[dateKey(new Date())];
  return day ? day[itemId] : undefined;
}

// 通知を出した事実を記録しておく（「通知が出ていたか」を後から確認できるように）
async function logNotif(kind, itemId, label) {
  const { notifLog = [] } = await chrome.storage.local.get('notifLog');
  notifLog.push({ ts: Date.now(), kind, itemId, label });
  while (notifLog.length > 30) notifLog.shift();
  await chrome.storage.local.set({ notifLog });
}

async function recordResult(itemId, result) {
  const key = dateKey(new Date());
  const { records = {} } = await chrome.storage.local.get('records');
  if (!records[key]) records[key] = {};
  records[key][itemId] = result; // 'done' | 'skip'
  await chrome.storage.local.set({ records });
}

// ---- 進行中ブロック（終了時刻つき予定の「いまは○○の時間」状態）----

async function updateBadge() {
  const { activeBlock } = await chrome.storage.local.get('activeBlock');
  if (!activeBlock || Date.now() >= activeBlock.endMs) return;
  const rem = Math.max(1, Math.ceil((activeBlock.endMs - Date.now()) / 60000));
  chrome.action.setBadgeText({ text: String(Math.min(rem, 99)) });
  chrome.action.setBadgeBackgroundColor({ color: '#e8a13a' });
  chrome.action.setBadgeTextColor({ color: '#1b2a4a' });
  chrome.action.setTitle({ title: chrome.i18n.getMessage('badgeTitle', [activeBlock.label, String(rem)]) });
}

async function startBlock(item, endMs) {
  await chrome.storage.local.set({
    activeBlock: { itemId: item.id, label: item.label, endMs }
  });
  chrome.alarms.create(TICK_ALARM, { periodInMinutes: 1 });
  updateBadge();
}

async function endBlock() {
  await chrome.storage.local.remove('activeBlock');
  chrome.alarms.clear(TICK_ALARM);
  chrome.action.setBadgeText({ text: '' });
  chrome.action.setTitle({ title: chrome.i18n.getMessage('extName') });
}

// ブロックの終了時刻が来たときの処理（未記録なら「できましたか？」を聞く）
async function finishBlockIfDue() {
  const { activeBlock } = await chrome.storage.local.get('activeBlock');
  if (!activeBlock) {
    chrome.alarms.clear(TICK_ALARM);
    return;
  }
  if (Date.now() < activeBlock.endMs) {
    updateBadge();
    return;
  }
  const rec = await getTodayRecord(activeBlock.itemId);
  if (rec === undefined) {
    chrome.notifications.create(`notifend|${activeBlock.itemId}|${Date.now()}`, {
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: chrome.i18n.getMessage('extName'),
      message: chrome.i18n.getMessage('notifEndMsg', [activeBlock.label]),
      buttons: [
        { title: chrome.i18n.getMessage('notifBtnDone') },
        { title: chrome.i18n.getMessage('notifBtnNotDone') }
      ],
      priority: 2
    });
    logNotif('end', activeBlock.itemId, activeBlock.label);
  }
  await endBlock();
}

// ---- アラームの登録 ----

async function rescheduleAll() {
  await chrome.alarms.clearAll();
  let schedule = await getSchedule();
  const now = new Date();

  // 日付が過ぎた「1回だけ」の予定は翌日以降に自動で片付ける（実績の記録は残る）
  const today = dateKey(now);
  const alive = schedule.filter((item) => !(isOneOff(item) && item.date < today));
  if (alive.length !== schedule.length) {
    schedule = alive;
    await chrome.storage.local.set({ schedule });
    // この set が storage.onChanged 経由で rescheduleAll をもう一度呼ぶが、
    // 2回目は削除対象が無いのでここには戻らない（無限ループにならない）
  }

  for (const item of schedule) {
    const next = nextOccurrence(item, now);
    if (next) {
      chrome.alarms.create(ALARM_PREFIX + item.id, { when: next.getTime() });
    }
  }
  // clearAll で tick も消えるので、進行中ブロックがあれば張り直す
  const { activeBlock } = await chrome.storage.local.get('activeBlock');
  if (activeBlock && Date.now() < activeBlock.endMs) {
    chrome.alarms.create(TICK_ALARM, { periodInMinutes: 1 });
    updateBadge();
  } else if (activeBlock) {
    await endBlock();
  }
}

chrome.runtime.onInstalled.addListener(() => {
  rescheduleAll();
  chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
});

chrome.runtime.onStartup.addListener(() => {
  rescheduleAll();
});

chrome.storage.onChanged.addListener(async (changes, area) => {
  if (area !== 'local') return;
  if (changes.schedule) rescheduleAll();
  // ブロック進行中に（通知ボタンでもパネルからでも）記録されたら、バッジを畳む
  if (changes.records) {
    const { activeBlock } = await chrome.storage.local.get('activeBlock');
    if (activeBlock && (await getTodayRecord(activeBlock.itemId)) !== undefined) {
      await endBlock();
    }
  }
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === TICK_ALARM) {
    await finishBlockIfDue();
    return;
  }
  if (!alarm.name.startsWith(ALARM_PREFIX)) return;
  const itemId = alarm.name.slice(ALARM_PREFIX.length);
  const schedule = await getSchedule();
  const item = schedule.find((it) => it.id === itemId);
  // 次回分を先に組み直す(通知の成否に関わらず予定は続く)
  if (item) {
    const next = nextOccurrence(item, new Date());
    if (next) chrome.alarms.create(alarm.name, { when: next.getTime() });
  }
  if (!item || !item.enabled) return;
  if (isTooLate(alarm.scheduledTime, Date.now())) return;

  const hasEnd = isValidEndTime(item.time, item.endTime || '');
  if (hasEnd) {
    // 時間帯ブロック：開始を知らせて、記録は終わりに聞く
    const endMs = blockEndMs(item.endTime, new Date(alarm.scheduledTime));
    if (Date.now() < endMs) await startBlock(item, endMs);
    const opts = {
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: chrome.i18n.getMessage('extName'),
      message: chrome.i18n.getMessage('notifStartMsg', [item.label, `${item.time}〜${item.endTime}`]),
      priority: 2
    };
    if (item.detail) opts.contextMessage = String(item.detail).slice(0, 120);
    chrome.notifications.create(`notifstart|${itemId}|${Date.now()}`, opts);
    logNotif('start', itemId, item.label);
  } else {
    const opts = {
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: chrome.i18n.getMessage('extName'),
      message: chrome.i18n.getMessage('notifPointMsg', [item.label, item.time]),
      buttons: [
        { title: chrome.i18n.getMessage('notifBtnDone') },
        { title: chrome.i18n.getMessage('notifBtnSkipToday') }
      ],
      priority: 2
    };
    if (item.detail) opts.contextMessage = String(item.detail).slice(0, 120);
    chrome.notifications.create(`notif|${itemId}|${Date.now()}`, opts);
    logNotif('point', itemId, item.label);
  }
});

chrome.notifications.onButtonClicked.addListener(async (notifId, buttonIndex) => {
  const parts = notifId.split('|');
  if (parts[0] !== 'notif' && parts[0] !== 'notifend') return;
  await recordResult(parts[1], buttonIndex === 0 ? 'done' : 'skip');
  chrome.notifications.clear(notifId);
});
