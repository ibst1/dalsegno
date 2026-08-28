'use strict';

// ── bridge ─────────────────────────────────────────────────────────────
function post(msg) {
  if (window.chrome && window.chrome.webview)
    window.chrome.webview.postMessage(msg);
}

let st = null;          // last state pushed from AHK
let lang = 'en';        // interface language, mirrors st.settings.lang
let curSetup = null;    // monitor setup selected in the dropdown
let rulesDirty = false; // unsaved edits on the rules tab
let armedForget = null; // section whose Forget button awaits confirmation

// ── interface strings ──────────────────────────────────────────────────
const STR = {
  en: {
    appSub: 'Window Keeper',
    tglMove: 'Move new windows automatically',
    tglSave: 'Save position on manual move',
    tglModOnly: 'Only when {mod} is held while dropping',
    modOnlyHelp: 'Saving becomes a deliberate gesture: a sloppy drag cannot overwrite a carefully placed position. Deliberate saves ({mod} + S, the window menu, Save all) always work.',
    behaveH: 'Behavior',
    hkH: 'Hotkeys',
    hkHelp: 'Pressed together with {mod}. AutoHotkey key names (d, F10, Home, Backspace…). Leave empty to disable one.',
    hkOpenUi: 'Open the DalSegno window',
    hkSaveActive: "Save the active window's position",
    hkSaveAll: "Save all open windows' positions",
    hkApplyAll: 'Move all windows to their saved positions',
    hkForgetActive: "Forget the active window's position",
    hkToggleMove: 'Toggle automatic moving',
    hkReload: 'Restart the script',
    tglNotify: 'Toasts',
    saveAll: 'Save all now',
    saveAllTip: "Save every open window's current position",
    applyAll: 'Move all now',
    applyAllTip: 'Move every open window to its saved position ({mod} + Home)',
    tabPositions: 'Saved positions',
    tabWindows: 'Open windows',
    tabRules: 'Rules',
    setupLabel: 'Monitor setup:',
    thisSetup: ' (this)',
    openIni: 'Open the saved positions file…',
    filesH: 'Files',
    forgetSel: 'Forget selected',
    thWindow: 'Window', thIdentity: 'Identity', thWidth: 'Width', thHeight: 'Height',
    posEmpty: 'No saved positions for this monitor setup yet. Drag a window where you want it, or save with § + S.',
    badgeRule: 'rule', badgeStd: 'standard',
    moveNow: 'Move now', forget: 'Forget', sure: 'Sure?',
    winsHint: 'Open windows DalSegno can manage right now.',
    refresh: 'Refresh',
    thProgram: 'Program', thTitle: 'Title', thSaved: 'Saved position',
    savedYes: '✓ saved',
    saveBtn: 'Save position', saveTip: "Save the window's current position",
    moveHere: 'Move there', moveTip: 'Move the window to its saved position',
    ruleBtn: 'Rule…', ruleRowTip: 'Create a title rule prefilled from this window',
    winsEmpty: 'No manageable windows found.',
    rulesH: 'Title rules',
    rulesHelp: 'Windows whose title contains the text (or matches the regular expression) share one saved position, regardless of program and the rest of the title. Needed for windows with varying titles, e.g. popups with a record id in the title.',
    thAlias: 'Name (alias)', thPattern: 'Text / pattern',
    aliasPh: 'alias', patternPh: 'text found in the title',
    addRule: '+ Add rule',
    rulesEmpty: 'No title rules.',
    onlyRules: 'Manage <b>only</b> windows that match a title rule',
    ignoreH: 'Ignore',
    ignExeHelp: 'Programs (one exe name per line):',
    ignTitleHelp: 'Titles containing (one text per line):',
    saveRules: 'Save rules',
    unsaved: 'unsaved changes',
    openConfig: 'Open the config file…',
    status: (n, total, s) => `${n} saved positions for this monitor setup · ${total} total · setup: ${s}`,
    paused: '⏸ automatic moving is off',
    delRuleTip: 'Remove the rule',
    tabSettings: 'Settings',
    langH: 'Language',
    langHelp: 'Applies to this window, the tray menu and notifications.'
  },
  sv: {
    appSub: 'Fönsterlägen',
    tglMove: 'Flytta nya fönster automatiskt',
    tglSave: 'Spara läge vid manuell flytt',
    tglModOnly: 'Bara när {mod} hålls nere vid släppet',
    modOnlyHelp: 'Sparandet blir en avsiktlig gest: en slarvig flytt kan inte skriva över ett omsorgsfullt placerat läge. Avsiktliga sparningar ({mod} + S, fönstermenyn, Spara alla) fungerar alltid.',
    behaveH: 'Beteende',
    hkH: 'Kortkommandon',
    hkHelp: 'Trycks tillsammans med {mod}. AutoHotkey-tangentnamn (d, F10, Home, Backspace…). Lämna tomt för att stänga av ett.',
    hkOpenUi: 'Öppna DalSegno-fönstret',
    hkSaveActive: 'Spara det aktiva fönstrets läge',
    hkSaveAll: 'Spara alla öppna fönsters lägen',
    hkApplyAll: 'Flytta alla fönster till sina sparade lägen',
    hkForgetActive: 'Glöm det aktiva fönstrets läge',
    hkToggleMove: 'Växla automatisk flyttning',
    hkReload: 'Starta om skriptet',
    tglNotify: 'Notiser',
    saveAll: 'Spara alla nu',
    saveAllTip: 'Spara alla öppna fönsters nuvarande lägen',
    applyAll: 'Flytta alla nu',
    applyAllTip: 'Flytta alla öppna fönster till sina sparade lägen ({mod} + Home)',
    tabPositions: 'Sparade lägen',
    tabWindows: 'Öppna fönster',
    tabRules: 'Regler',
    setupLabel: 'Skärmuppsättning:',
    thisSetup: ' (denna)',
    openIni: 'Öppna filen med sparade lägen…',
    filesH: 'Filer',
    forgetSel: 'Glöm markerade',
    thWindow: 'Fönster', thIdentity: 'Identitet', thWidth: 'Bredd', thHeight: 'Höjd',
    posEmpty: 'Inga sparade lägen för den här skärmuppsättningen ännu. Dra ett fönster dit du vill ha det, eller spara med § + S.',
    badgeRule: 'regel', badgeStd: 'standard',
    moveNow: 'Flytta nu', forget: 'Glöm', sure: 'Säkert?',
    winsHint: 'Öppna fönster som DalSegno kan hantera just nu.',
    refresh: 'Uppdatera',
    thProgram: 'Program', thTitle: 'Titel', thSaved: 'Sparat läge',
    savedYes: '✓ finns',
    saveBtn: 'Spara läge', saveTip: 'Spara fönstrets nuvarande läge',
    moveHere: 'Flytta hit', moveTip: 'Flytta fönstret till det sparade läget',
    ruleBtn: 'Regel…', ruleRowTip: 'Skapa en titelregel förifylld från det här fönstret',
    winsEmpty: 'Inga hanterbara fönster hittades.',
    rulesH: 'Titelregler',
    rulesHelp: 'Fönster vars titel innehåller texten (eller matchar det reguljära uttrycket) delar ett gemensamt sparat läge, oavsett program och resten av titeln. Behövs för fönster med varierande titlar, t.ex. popupfönster med ett ärende-id i titeln.',
    thAlias: 'Namn (alias)', thPattern: 'Textbit / mönster',
    aliasPh: 'alias', patternPh: 'textbit i titeln',
    addRule: '+ Lägg till regel',
    rulesEmpty: 'Inga titelregler.',
    onlyRules: 'Hantera <b>endast</b> fönster som matchar en titelregel',
    ignoreH: 'Ignorera',
    ignExeHelp: 'Program (ett exenamn per rad):',
    ignTitleHelp: 'Titlar som innehåller (en text per rad):',
    saveRules: 'Spara regler',
    unsaved: 'osparade ändringar',
    openConfig: 'Öppna konfigfilen…',
    status: (n, total, s) => `${n} sparade lägen för denna skärmuppsättning · ${total} totalt · uppsättning: ${s}`,
    paused: '⏸ automatisk flyttning är avstängd',
    delRuleTip: 'Ta bort regeln',
    tabSettings: 'Inställningar',
    langH: 'Språk',
    langHelp: 'Gäller det här fönstret, tray-menyn och notiserna.'
  }
};
function t(id) {
  const s = (STR[lang] || STR.en)[id] ?? STR.en[id] ?? id;
  const mod = (st && st.settings && st.settings.modifier) || 'CapsLock';
  return s.replace('{mod}', mod);
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                  .replace(/"/g, '&quot;');
}
function $(id) { return document.getElementById(id); }

// ── state from AHK ─────────────────────────────────────────────────────
window.receiveState = function (s) {
  st = s;
  lang = st.settings.lang === 'sv' ? 'sv' : 'en';
  const setups = setupList();
  if (curSetup === null || !setups.includes(curSetup)) curSetup = st.currentSetup;
  localizeStatic();
  renderTopbar();
  renderHotkeys();
  renderPositions();
  renderWindows();
  if (!rulesDirty) renderRules();
  renderStatus();
};

function setupList() {
  const set = new Set(st.positions.map(p => p.setup));
  set.add(st.currentSetup);
  return [...set].sort();
}

// ── static labels (all translatable chrome) ────────────────────────────
function localizeStatic() {
  document.documentElement.lang = lang;
  $('lblMove').textContent = t('tglMove');
  $('lblSave').textContent = t('tglSave');
  $('lblModOnly').textContent = t('tglModOnly');
  $('modOnlyHelp').textContent = t('modOnlyHelp');
  $('behaveH').textContent = t('behaveH');
  $('lblNotify').textContent = t('tglNotify');
  $('btnSaveAll').textContent = t('saveAll');
  $('btnSaveAll').title = t('saveAllTip');
  $('btnApplyAll').textContent = t('applyAll');
  $('btnApplyAll').title = t('applyAllTip');
  $('tabBtnPositions').textContent = t('tabPositions');
  $('tabBtnWindows').textContent = t('tabWindows');
  $('tabBtnRules').textContent = t('tabRules');
  $('lblSetup').textContent = t('setupLabel');
  $('btnOpenPositions').textContent = t('openIni');
  $('filesH').textContent = t('filesH');
  $('hkH').textContent = t('hkH');
  $('hkHelp').textContent = t('hkHelp');
  updateForgetSel();
  $('thWindow').textContent = t('thWindow');
  $('thIdentity').textContent = t('thIdentity');
  $('thWidth').textContent = t('thWidth');
  $('thHeight').textContent = t('thHeight');
  $('winsHint').textContent = t('winsHint');
  $('btnRefresh').textContent = t('refresh');
  $('thProgram').textContent = t('thProgram');
  $('thTitle').textContent = t('thTitle');
  $('thIdentity2').textContent = t('thIdentity');
  $('thSaved').textContent = t('thSaved');
  $('rulesH').textContent = t('rulesH');
  $('rulesHelp').textContent = t('rulesHelp');
  $('thAlias').textContent = t('thAlias');
  $('thPattern').textContent = t('thPattern');
  $('btnAddRule').textContent = t('addRule');
  $('lblOnlyRules').innerHTML = t('onlyRules');
  $('ignoreH').textContent = t('ignoreH');
  $('ignExeHelp').textContent = t('ignExeHelp');
  $('ignTitleHelp').textContent = t('ignTitleHelp');
  $('btnSaveRules').textContent = t('saveRules');
  $('rulesDirty').textContent = t('unsaved');
  $('btnOpenConfig').textContent = t('openConfig');
  $('tabBtnSettings').textContent = t('tabSettings');
  $('langH').textContent = t('langH');
  $('langHelp').textContent = t('langHelp');
  document.querySelectorAll('input[name=lang]').forEach(r => { r.checked = r.value === lang; });
}

// ── toggles (Settings tab) ─────────────────────────────────────────────────────────────
function renderTopbar() {
  $('tglMove').checked = !!st.settings.move;
  $('tglSave').checked = !!st.settings.autosave;
  $('tglModOnly').checked = !!st.settings.modOnly;
  $('tglModOnly').disabled = !st.settings.autosave;
  $('tglNotify').checked = !!st.settings.notify;
}
$('tglMove').addEventListener('change', e => post({ action: 'toggle', name: 'move', value: e.target.checked ? 1 : 0 }));
$('tglSave').addEventListener('change', e => post({ action: 'toggle', name: 'autosave', value: e.target.checked ? 1 : 0 }));
$('tglModOnly').addEventListener('change', e => post({ action: 'toggle', name: 'modOnly', value: e.target.checked ? 1 : 0 }));
$('tglNotify').addEventListener('change', e => post({ action: 'toggle', name: 'notify', value: e.target.checked ? 1 : 0 }));
$('btnSaveAll').addEventListener('click', () => post({ action: 'saveAll' }));
$('btnApplyAll').addEventListener('click', () => post({ action: 'applyAll' }));
document.querySelectorAll('input[name=lang]').forEach(r =>
  r.addEventListener('change', e => { if (e.target.checked) post({ action: 'setLang', lang: e.target.value }); }));

// ── tabs ───────────────────────────────────────────────────────────────
document.querySelectorAll('#tabs .tab').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#tabs .tab').forEach(b => b.classList.toggle('active', b === btn));
    document.querySelectorAll('.tabpane').forEach(p =>
      p.classList.toggle('active', p.id === 'tab-' + btn.dataset.tab));
    if (btn.dataset.tab === 'windows') post({ action: 'refresh' });
  });
});

// ── saved positions ────────────────────────────────────────────────────
const selPos = new Set();   // sections ticked for bulk forget

function updateForgetSel() {
  const b = $('btnForgetSel');
  b.disabled = !selPos.size;
  b.textContent = t('forgetSel') + (selPos.size ? ` (${selPos.size})` : '');
}

function renderPositions() {
  const sel = $('setupSel');
  sel.innerHTML = setupList().map(s =>
    `<option value="${esc(s)}"${s === curSetup ? ' selected' : ''}>` +
    `${esc(s)}${s === st.currentSetup ? esc(t('thisSetup')) : ''}</option>`).join('');

  const rows = st.positions.filter(p => p.setup === curSetup);
  const body = $('posBody');
  if (!rows.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="8">${esc(t('posEmpty'))}</td></tr>`;
    selPos.clear();
    updateForgetSel();
    return;
  }
  const isCur = curSetup === st.currentSetup;
  body.innerHTML = rows.map(p => {
    const rule = p.key.startsWith('rule:') ? p.key.slice(5) : '';
    return `<tr data-section="${esc(p.section)}" data-key="${esc(p.key)}">
      <td class="selcol"><input type="checkbox" class="rowsel"${selPos.has(p.section) ? ' checked' : ''}></td>
      <td class="ellip" title="${esc(p.key)}">${esc(p.info || p.key)}</td>
      <td>${rule ? `<span class="badge rule">${esc(t('badgeRule'))}: ${esc(rule)}</span>`
                 : `<span class="badge">${esc(t('badgeStd'))}</span>`}</td>
      <td class="num">${esc(p.x)}</td><td class="num">${esc(p.y)}</td>
      <td class="num">${esc(p.w)}</td><td class="num">${esc(p.h)}</td>
      <td class="actions">
        ${isCur ? `<button class="small act-move">${esc(t('moveNow'))}</button>` : ''}
        <button class="small act-forget">${esc(t('forget'))}</button>
      </td></tr>`;
  }).join('');
  // the state can be re-pushed at any moment (autosave elsewhere), so the
  // selection lives outside the DOM and is pruned to the rows still shown
  const shown = new Set(rows.map(p => p.section));
  for (const s of [...selPos]) if (!shown.has(s)) selPos.delete(s);
  $('selAllPos').checked = rows.length > 0 && rows.every(p => selPos.has(p.section));
  updateForgetSel();
}
$('setupSel').addEventListener('change', e => { curSetup = e.target.value; renderPositions(); });
$('btnOpenPositions').addEventListener('click', () => post({ action: 'openPositions' }));
$('posBody').addEventListener('change', e => {
  if (!e.target.classList.contains('rowsel')) return;
  const sec = e.target.closest('tr').dataset.section;
  if (e.target.checked) selPos.add(sec); else selPos.delete(sec);
  $('selAllPos').checked = [...$('posBody').querySelectorAll('.rowsel')].every(c => c.checked);
  updateForgetSel();
});
$('selAllPos').addEventListener('change', e => {
  $('posBody').querySelectorAll('tr[data-section]').forEach(tr => {
    if (e.target.checked) selPos.add(tr.dataset.section); else selPos.delete(tr.dataset.section);
  });
  renderPositions();
});
$('btnForgetSel').addEventListener('click', () => {
  if (!selPos.size) return;
  post({ action: 'forgetMany', sections: [...selPos] });
  selPos.clear();
});

$('posBody').addEventListener('click', e => {
  const tr = e.target.closest('tr');
  if (!tr || !tr.dataset.section) return;
  if (e.target.classList.contains('act-move')) {
    post({ action: 'moveKey', key: tr.dataset.key });
  } else if (e.target.classList.contains('act-forget')) {
    // two clicks: arm first, delete second - no dialog needed
    if (armedForget === tr.dataset.section) {
      armedForget = null;
      post({ action: 'forget', section: tr.dataset.section });
    } else {
      armedForget = tr.dataset.section;
      e.target.textContent = t('sure');
      e.target.classList.add('danger-armed');
      setTimeout(() => {
        if (armedForget === tr.dataset.section) armedForget = null;
        e.target.textContent = t('forget');
        e.target.classList.remove('danger-armed');
      }, 2500);
    }
  }
});

// ── open windows ───────────────────────────────────────────────────────
function renderWindows() {
  const body = $('winBody');
  if (!st.windows.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="5">${esc(t('winsEmpty'))}</td></tr>`;
    return;
  }
  body.innerHTML = st.windows.map(w => `
    <tr data-hwnd="${w.hwnd}">
      <td>${esc(w.exe)}</td>
      <td class="ellip" title="${esc(w.title)}">${esc(w.title)}</td>
      <td>${w.rule ? `<span class="badge rule">${esc(t('badgeRule'))}: ${esc(w.rule)}</span>`
                   : `<span class="badge">${esc(t('badgeStd'))}</span>`}</td>
      <td>${w.saved ? `<span class="ok">${esc(t('savedYes'))}</span>` : '<span class="dim">–</span>'}</td>
      <td class="actions">
        <button class="small act-save" title="${esc(t('saveTip'))}">${esc(t('saveBtn'))}</button>
        <button class="small act-movewin" ${w.saved ? '' : 'disabled'}
          title="${esc(t('moveTip'))}">${esc(t('moveHere'))}</button>
        <button class="small act-rule" title="${esc(t('ruleRowTip'))}">${esc(t('ruleBtn'))}</button>
      </td></tr>`).join('');
}
$('btnRefresh').addEventListener('click', () => post({ action: 'refresh' }));
$('winBody').addEventListener('click', e => {
  const tr = e.target.closest('tr');
  if (!tr || !tr.dataset.hwnd) return;
  const hwnd = Number(tr.dataset.hwnd);
  if (e.target.classList.contains('act-save')) post({ action: 'saveWin', hwnd });
  else if (e.target.classList.contains('act-movewin')) post({ action: 'moveWin', hwnd });
  else if (e.target.classList.contains('act-rule')) {
    // same prefill as the window menu's "Create title rule" - the alias is
    // derived exactly like TmCreateRule does on the AHK side, and the row
    // already carries exe and title, so no round-trip is needed
    const w = st.windows.find(x => Number(x.hwnd) === hwnd);
    if (w) prefillRule({
      alias: String(w.exe).replace(/\.exe$/i, '').toLowerCase().replace(/[^a-z0-9]/g, ''),
      pattern: w.title
    });
  }
});

// ── rules ──────────────────────────────────────────────────────────────
function ruleRow(r) {
  return `<tr>
    <td class="alias"><input type="text" class="r-alias" value="${esc(r.alias)}" placeholder="${esc(t('aliasPh'))}"></td>
    <td><input type="text" class="r-pattern" value="${esc(r.pattern)}" placeholder="${esc(t('patternPh'))}"></td>
    <td class="rx"><input type="checkbox" class="r-regex" ${r.regex ? 'checked' : ''}></td>
    <td class="del"><button class="small act-delrule" title="${esc(t('delRuleTip'))}">✕</button></td>
  </tr>`;
}

function renderRules() {
  $('rulesBody').innerHTML = st.rules.map(ruleRow).join('') ||
    `<tr class="empty-row"><td colspan="4">${esc(t('rulesEmpty'))}</td></tr>`;
  $('tglOnlyRules').checked = !!st.settings.rulesOnly;
  $('txtIgnoreExe').value = st.ignoreExe.join('\n');
  $('txtIgnoreTitle').value = st.ignoreTitles.join('\n');
  setRulesDirty(false);
}

function setRulesDirty(v) {
  rulesDirty = v;
  $('rulesDirty').hidden = !v;
}

$('tab-rules').addEventListener('input', () => setRulesDirty(true));
$('btnAddRule').addEventListener('click', () => {
  const empty = $('rulesBody').querySelector('.empty-row');
  if (empty) empty.remove();
  $('rulesBody').insertAdjacentHTML('beforeend', ruleRow({ alias: '', pattern: '', regex: 0 }));
  setRulesDirty(true);
});
$('rulesBody').addEventListener('click', e => {
  if (e.target.classList.contains('act-delrule')) {
    e.target.closest('tr').remove();
    setRulesDirty(true);
  }
});
$('btnSaveRules').addEventListener('click', () => {
  const rules = [...$('rulesBody').querySelectorAll('tr')]
    .filter(tr => tr.querySelector('.r-alias'))
    .map(tr => ({
      alias: tr.querySelector('.r-alias').value.trim(),
      pattern: tr.querySelector('.r-pattern').value.trim(),
      regex: tr.querySelector('.r-regex').checked ? 1 : 0
    }))
    .filter(r => r.alias && r.pattern);
  post({
    action: 'saveRules',
    rules,
    rulesOnly: $('tglOnlyRules').checked ? 1 : 0,
    ignoreExe: $('txtIgnoreExe').value.split('\n').map(s => s.trim()).filter(Boolean),
    ignoreTitles: $('txtIgnoreTitle').value.split('\n').map(s => s.trim()).filter(Boolean)
  });
  setRulesDirty(false);
});
$('btnOpenConfig').addEventListener('click', () => post({ action: 'openConfig' }));

// ── status bar ─────────────────────────────────────────────────────────
function renderStatus() {
  const nCur = st.positions.filter(p => p.setup === st.currentSetup).length;
  $('status').textContent = t('status')(nCur, st.positions.length, st.currentSetup);
  $('statusPause').innerHTML = st.settings.move ? ''
    : `<span class="warn">${esc(t('paused'))}</span>`;
}

// ── prefill from the title bar menu ("Create title rule…") ─────────────
window.prefillRule = function (r) {
  $('tabBtnRules').click();
  const empty = $('rulesBody').querySelector('.empty-row');
  if (empty) empty.remove();
  $('rulesBody').insertAdjacentHTML('beforeend',
    ruleRow({ alias: r.alias || '', pattern: r.pattern || '', regex: 0 }));
  setRulesDirty(true);
  const rows = $('rulesBody').querySelectorAll('tr');
  const input = rows[rows.length - 1].querySelector('.r-pattern');
  input.focus();
  input.select();   // the title is prefilled whole - trim it to the stable part
};

// ── hotkeys (Settings tab) ─────────────────────────────────────────────
const HK_ACTIONS = ['OpenUi', 'SaveActive', 'SaveAll', 'ApplyAll',
                    'ForgetActive', 'ToggleMove', 'Reload'];

function renderHotkeys() {
  // never rebuild under the user's fingers - a state push can arrive while
  // an input has focus (autosave elsewhere), and blur will re-sync anyway
  if (document.activeElement && document.activeElement.classList &&
      document.activeElement.classList.contains('hkkey')) return;
  const hk = (st.settings && st.settings.hotkeys) || {};
  const mod = (st.settings && st.settings.modifier) || 'CapsLock';
  $('hkList').innerHTML = HK_ACTIONS.map(name => `
    <div class="hkrow">
      <span class="hkcombo">${esc(mod)} +
        <input class="hkkey" data-name="${name}" value="${esc(hk[name] ?? '')}"></span>
      <span class="hklbl">${esc(t('hk' + name))}</span>
    </div>`).join('');
}
$('hkList').addEventListener('change', e => {
  if (!e.target.classList.contains('hkkey')) return;
  post({ action: 'setHotkey', name: e.target.dataset.name, key: e.target.value.trim() });
});

// ── start ──────────────────────────────────────────────────────────────
post({ action: 'ready' });
