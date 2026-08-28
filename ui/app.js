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
    tglSave: 'Save on manual move',
    tglNotify: 'Toasts',
    applyAll: 'Move all now',
    applyAllTip: 'Move every open window to its saved position (§ + Home)',
    tabPositions: 'Saved positions',
    tabWindows: 'Open windows',
    tabRules: 'Rules',
    setupLabel: 'Monitor setup:',
    thisSetup: ' (this)',
    openIni: 'Open the ini file…',
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
    winsEmpty: 'No manageable windows found.',
    rulesH: 'Title rules',
    rulesHelp: 'Windows whose title contains the text (or matches the regular expression) share one saved position, regardless of program and the rest of the title. Needed for windows with varying titles, e.g. LIMS popups.',
    thAlias: 'Name (alias)', thPattern: 'Text / pattern',
    aliasPh: 'alias', patternPh: 'text found in the title',
    addRule: '+ Add rule',
    rulesEmpty: 'No title rules.',
    onlyRules: 'Manage <b>only</b> windows that match a title rule (like the old LIMS move)',
    ignoreH: 'Ignore',
    ignExeHelp: 'Programs (one exe name per line):',
    ignTitleHelp: 'Titles containing (one text per line):',
    saveRules: 'Save rules',
    unsaved: 'unsaved changes',
    openConfig: 'Open the config file…',
    status: (n, total, s) => `${n} saved positions for this monitor setup · ${total} total · setup: ${s}`,
    paused: '⏸ automatic moving is off',
    delRuleTip: 'Remove the rule'
  },
  sv: {
    appSub: 'Fönsterlägen',
    tglMove: 'Flytta nya fönster automatiskt',
    tglSave: 'Spara vid manuell flytt',
    tglNotify: 'Notiser',
    applyAll: 'Flytta alla nu',
    applyAllTip: 'Flytta alla öppna fönster till sina sparade lägen (§ + Home)',
    tabPositions: 'Sparade lägen',
    tabWindows: 'Öppna fönster',
    tabRules: 'Regler',
    setupLabel: 'Skärmuppsättning:',
    thisSetup: ' (denna)',
    openIni: 'Öppna ini-filen…',
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
    winsEmpty: 'Inga hanterbara fönster hittades.',
    rulesH: 'Titelregler',
    rulesHelp: 'Fönster vars titel innehåller texten (eller matchar det reguljära uttrycket) delar ett gemensamt sparat läge, oavsett program och resten av titeln. Behövs för fönster med varierande titlar, t.ex. LIMS-popupfönster.',
    thAlias: 'Namn (alias)', thPattern: 'Textbit / mönster',
    aliasPh: 'alias', patternPh: 'textbit i titeln',
    addRule: '+ Lägg till regel',
    rulesEmpty: 'Inga titelregler.',
    onlyRules: 'Hantera <b>endast</b> fönster som matchar en titelregel (som gamla LIMS move)',
    ignoreH: 'Ignorera',
    ignExeHelp: 'Program (ett exenamn per rad):',
    ignTitleHelp: 'Titlar som innehåller (en text per rad):',
    saveRules: 'Spara regler',
    unsaved: 'osparade ändringar',
    openConfig: 'Öppna konfigfilen…',
    status: (n, total, s) => `${n} sparade lägen för denna skärmuppsättning · ${total} totalt · uppsättning: ${s}`,
    paused: '⏸ automatisk flyttning är avstängd',
    delRuleTip: 'Ta bort regeln'
  }
};
function t(id) { return (STR[lang] || STR.en)[id] ?? STR.en[id] ?? id; }

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
  $('lblNotify').textContent = t('tglNotify');
  $('btnApplyAll').textContent = t('applyAll');
  $('btnApplyAll').title = t('applyAllTip');
  $('tabBtnPositions').textContent = t('tabPositions');
  $('tabBtnWindows').textContent = t('tabWindows');
  $('tabBtnRules').textContent = t('tabRules');
  $('lblSetup').textContent = t('setupLabel');
  $('btnOpenPositions').textContent = t('openIni');
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
  $('appname').innerHTML = `DalSegno <span class="sub">${esc(t('appSub'))}</span>`;
  $('langSel').value = lang;
}

// ── topbar ─────────────────────────────────────────────────────────────
function renderTopbar() {
  $('tglMove').checked = !!st.settings.move;
  $('tglSave').checked = !!st.settings.autosave;
  $('tglNotify').checked = !!st.settings.notify;
}
$('tglMove').addEventListener('change', e => post({ action: 'toggle', name: 'move', value: e.target.checked ? 1 : 0 }));
$('tglSave').addEventListener('change', e => post({ action: 'toggle', name: 'autosave', value: e.target.checked ? 1 : 0 }));
$('tglNotify').addEventListener('change', e => post({ action: 'toggle', name: 'notify', value: e.target.checked ? 1 : 0 }));
$('btnApplyAll').addEventListener('click', () => post({ action: 'applyAll' }));
$('langSel').addEventListener('change', e => post({ action: 'setLang', lang: e.target.value }));

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
function renderPositions() {
  const sel = $('setupSel');
  sel.innerHTML = setupList().map(s =>
    `<option value="${esc(s)}"${s === curSetup ? ' selected' : ''}>` +
    `${esc(s)}${s === st.currentSetup ? esc(t('thisSetup')) : ''}</option>`).join('');

  const rows = st.positions.filter(p => p.setup === curSetup);
  const body = $('posBody');
  if (!rows.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="7">${esc(t('posEmpty'))}</td></tr>`;
    return;
  }
  const isCur = curSetup === st.currentSetup;
  body.innerHTML = rows.map(p => {
    const rule = p.key.startsWith('rule:') ? p.key.slice(5) : '';
    return `<tr data-section="${esc(p.section)}" data-key="${esc(p.key)}">
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
}
$('setupSel').addEventListener('change', e => { curSetup = e.target.value; renderPositions(); });
$('btnOpenPositions').addEventListener('click', () => post({ action: 'openPositions' }));

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
      </td></tr>`).join('');
}
$('btnRefresh').addEventListener('click', () => post({ action: 'refresh' }));
$('winBody').addEventListener('click', e => {
  const tr = e.target.closest('tr');
  if (!tr || !tr.dataset.hwnd) return;
  const hwnd = Number(tr.dataset.hwnd);
  if (e.target.classList.contains('act-save')) post({ action: 'saveWin', hwnd });
  else if (e.target.classList.contains('act-movewin')) post({ action: 'moveWin', hwnd });
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

// ── start ──────────────────────────────────────────────────────────────
post({ action: 'ready' });
