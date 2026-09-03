'use strict';

// ── bridge ─────────────────────────────────────────────────────────────
function post(msg) {
  if (window.chrome && window.chrome.webview)
    window.chrome.webview.postMessage(msg);
}

let st = null;          // last state pushed from AHK
let lang = 'en';        // interface language, mirrors st.settings.lang
let curSetup = null;    // monitor setup selected in the dropdown
let armedForget = null; // section whose Forget button awaits confirmation
let awaitingState = false; // a rule edit was posted; the next state carries it

// ── interface strings ──────────────────────────────────────────────────
const STR = {
  en: {
    appSub: 'Window Keeper',
    tglMove: 'Move new windows automatically',
    tglSave: 'Save position on manual move',
    tglModOnly: 'Only when {mod} is held while dropping',
    modOnlyHelp: 'Saving becomes a deliberate gesture: a sloppy drag cannot overwrite a carefully placed position. Deliberate saves ({mod} + S, the window menu, Save all) always work.',
    thWindowTip: 'Which windows this position applies to. A rule\'s text is edited right here and saved when you leave the field. Hover a row for the window the position was saved from.',
    thIdentityTip: 'What the position is stored under - that is, which windows share it. "standard" means all windows of the same program and window class; "rule" means all windows whose title matches that title rule.',
    thActive: 'Active',
    thActiveTip: 'Untick to switch a rule off without deleting it: its windows are then treated like any other window of their program, and its saved position waits until it is ticked again.',
    thXTip: 'Distance from the left edge of the desktop, in pixels.',
    thYTip: 'Distance from the top edge of the desktop, in pixels.',
    thWidthTip: 'Window width in pixels.',
    thHeightTip: 'Window height in pixels.',
    selColTip: 'Tick rows to forget their positions in one go.',
    thProgramTip: 'Executable name of the process owning the window.',
    thTitleTip: 'The window title right now. Title rules match against this.',
    thSavedTip: 'Whether a position is stored for this window’s identity in the current monitor setup.',
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
    tabPositions: 'Positions',
    tabWindows: 'Open windows',
    tabSettings: 'Settings',
    setupLabel: 'Monitor setup:',
    thisSetup: ' (this)',
    openIni: 'Open the saved positions file…',
    openConfig: 'Open the config file…',
    filesH: 'Files',
    forgetSel: 'Forget selected',
    thWindow: 'Applies to', thIdentity: 'Identity', thWidth: 'Width', thHeight: 'Height',
    posEmpty: 'No rules and no saved positions for this monitor setup yet. Drag a window where you want it, save with {mod} + S, or hold {mod} and right-click a title bar.',
    badgeRule: 'rule', badgeStd: 'standard', badgeMax: 'maximized', badgeNew: 'new',
    moveNow: 'Move now', forget: 'Forget', sure: 'Sure?',
    appliesPre: 'windows with', appliesPost: 'in the title',
    appliesRuleGone: 'rule "{0}" (no longer exists)',
    appliesStd: 'all {0} windows',
    savedFromTip: 'Saved from: {0}',
    noPosYet: 'no position yet',
    patternPh: 'text found in the title',
    regexLbl: 'regex',
    addRule: '+ Add rule',
    addRuleTip: 'A new rule row - type the text and press Enter',
    deleteRule: 'Delete rule',
    deleteRuleTip: 'Remove the rule and its saved positions in every monitor setup',
    confirmDeleteRule: 'Delete the rule "{0}" and its saved positions in every monitor setup?',
    winsHint: 'Open windows DalSegno can manage right now.',
    refresh: 'Refresh',
    thProgram: 'Program', thTitle: 'Title', thSaved: 'Saved position',
    savedYes: '✓ saved',
    saveBtn: 'Save position', saveTip: "Save the window's current position",
    moveHere: 'Move there', moveTip: 'Move the window to its saved position',
    newRuleBtn: 'Rule…', editRuleBtn: 'Edit rule…',
    ruleRowTip: "The window menu's save dialog for this window: what the position applies to, or the rule it matches",
    unmanagedTip: 'Only managed through a title rule - none matches yet',
    winsEmpty: 'No manageable windows found.',
    managedH: 'Which windows are managed',
    onlyRules: 'Manage <b>only</b> windows that match a title rule',
    onlyRulesHelp: 'Off (default): every window is managed. A window that matches no rule is identified by its program and window class, so all windows of the same program share one position - the rules are refinements that break specific windows out into their own. On: only windows matching a rule are touched at all; everything else is left alone, with no saving and no moving. Use it to manage a handful of specific windows and nothing else.',
    onlyRulesExeH: 'Rules only for these programs',
    onlyRulesExeHelp: 'Programs handled only through title rules (one exe name per line). Their other windows are left alone. The natural setting for a browser: every popup is a separate window that would otherwise share one position with every other window of the browser, so the first popup you saved would drag all the others along.',
    ignoreH: 'Ignore',
    ignExeHelp: 'Programs (one exe name per line):',
    ignTitleHelp: 'Titles containing (one text per line):',
    managedSavedHint: 'Changes here are saved as soon as you leave the field.',
    status: (n, total, s) => `${n} saved positions for this monitor setup · ${total} total · setup: ${s}`,
    paused: '⏸ automatic moving is off',
    langH: 'Language',
    langHelp: 'Applies to this window, the tray menu and notifications.'
  },
  sv: {
    appSub: 'Fönsterlägen',
    tglMove: 'Flytta nya fönster automatiskt',
    tglSave: 'Spara läge vid manuell flytt',
    tglModOnly: 'Bara när {mod} hålls nere vid släppet',
    modOnlyHelp: 'Sparandet blir en avsiktlig gest: en slarvig flytt kan inte skriva över ett omsorgsfullt placerat läge. Avsiktliga sparningar ({mod} + S, fönstermenyn, Spara alla) fungerar alltid.',
    thWindowTip: 'Vilka fönster läget gäller. En regels text redigeras direkt här och sparas när du lämnar fältet. Håll muspekaren över raden för att se fönstret läget sparades från.',
    thIdentityTip: 'Vad läget sparas under - alltså vilka fönster som delar det. "standard" betyder alla fönster i samma program och fönsterklass; "regel" betyder alla fönster vars titel matchar den titelregeln.',
    thActive: 'Aktiv',
    thActiveTip: 'Kryssa ur för att stänga av en regel utan att ta bort den: dess fönster behandlas då som vilka fönster som helst i sitt program, och det sparade läget väntar tills regeln kryssas i igen.',
    thXTip: 'Avstånd från skrivbordets vänsterkant, i bildpunkter.',
    thYTip: 'Avstånd från skrivbordets överkant, i bildpunkter.',
    thWidthTip: 'Fönstrets bredd i bildpunkter.',
    thHeightTip: 'Fönstrets höjd i bildpunkter.',
    selColTip: 'Kryssa i rader för att glömma deras lägen i ett svep.',
    thProgramTip: 'Namnet på programfilen som äger fönstret.',
    thTitleTip: 'Fönstrets titel just nu. Titelregler matchas mot den.',
    thSavedTip: 'Om det finns ett sparat läge för fönstrets identitet i den aktuella skärmuppsättningen.',
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
    tabPositions: 'Lägen',
    tabWindows: 'Öppna fönster',
    tabSettings: 'Inställningar',
    setupLabel: 'Skärmuppsättning:',
    thisSetup: ' (denna)',
    openIni: 'Öppna filen med sparade lägen…',
    openConfig: 'Öppna konfigfilen…',
    filesH: 'Filer',
    forgetSel: 'Glöm markerade',
    thWindow: 'Gäller', thIdentity: 'Identitet', thWidth: 'Bredd', thHeight: 'Höjd',
    posEmpty: 'Inga regler och inga sparade lägen för den här skärmuppsättningen ännu. Dra ett fönster dit du vill ha det, spara med {mod} + S, eller håll {mod} och högerklicka på en titelrad.',
    badgeRule: 'regel', badgeStd: 'standard', badgeMax: 'maximerat', badgeNew: 'ny',
    moveNow: 'Flytta nu', forget: 'Glöm', sure: 'Säkert?',
    appliesPre: 'fönster med', appliesPost: 'i titeln',
    appliesRuleGone: 'regeln "{0}" (finns inte längre)',
    appliesStd: 'alla {0}-fönster',
    savedFromTip: 'Sparat från: {0}',
    noPosYet: 'inget läge ännu',
    patternPh: 'textbit i titeln',
    regexLbl: 'regex',
    addRule: '+ Lägg till regel',
    addRuleTip: 'En ny regelrad - skriv texten och tryck Enter',
    deleteRule: 'Ta bort regel',
    deleteRuleTip: 'Ta bort regeln och dess sparade lägen i alla skärmuppsättningar',
    confirmDeleteRule: 'Ta bort regeln "{0}" och dess sparade lägen i alla skärmuppsättningar?',
    winsHint: 'Öppna fönster som DalSegno kan hantera just nu.',
    refresh: 'Uppdatera',
    thProgram: 'Program', thTitle: 'Titel', thSaved: 'Sparat läge',
    savedYes: '✓ finns',
    saveBtn: 'Spara läge', saveTip: 'Spara fönstrets nuvarande läge',
    moveHere: 'Flytta hit', moveTip: 'Flytta fönstret till det sparade läget',
    newRuleBtn: 'Regel…', editRuleBtn: 'Ändra regel…',
    ruleRowTip: 'Fönstermenyns spardialog för det här fönstret: vad läget ska gälla, eller regeln som matchar',
    unmanagedTip: 'Hanteras bara via titelregel - ingen matchar ännu',
    winsEmpty: 'Inga hanterbara fönster hittades.',
    managedH: 'Vilka fönster hanteras',
    onlyRules: 'Hantera <b>endast</b> fönster som matchar en titelregel',
    onlyRulesHelp: 'Av (standard): alla fönster hanteras. Ett fönster som inte matchar någon regel identifieras av sitt program och sin fönsterklass, så alla fönster i samma program delar ett läge - reglerna är förfiningar som bryter ut enskilda fönster till egna lägen. På: bara fönster som matchar en regel rörs över huvud taget; allt annat lämnas i fred, utan sparande och utan flyttning. Använd det när du bara vill styra en handfull specifika fönster.',
    onlyRulesExeH: 'Endast regler för dessa program',
    onlyRulesExeHelp: 'Program som bara hanteras via titelregler (ett exenamn per rad). Deras övriga fönster lämnas i fred. Det naturliga valet för en webbläsare: varje popup är ett eget fönster som annars skulle dela läge med webbläsarens alla andra fönster, så den första popup du sparade skulle dra med sig alla de andra.',
    ignoreH: 'Ignorera',
    ignExeHelp: 'Program (ett exenamn per rad):',
    ignTitleHelp: 'Titlar som innehåller (en text per rad):',
    managedSavedHint: 'Ändringar här sparas så fort du lämnar fältet.',
    status: (n, total, s) => `${n} sparade lägen för denna skärmuppsättning · ${total} totalt · uppsättning: ${s}`,
    paused: '⏸ automatisk flyttning är avstängd',
    langH: 'Språk',
    langHelp: 'Gäller det här fönstret, tray-menyn och notiserna.'
  }
};
function t(id) {
  const s = (STR[lang] || STR.en)[id] ?? STR.en[id] ?? id;
  if (typeof s === 'function') return s;   // status is a formatter, not text
  const mod = (st && st.settings && st.settings.modifier) || 'CapsLock';
  return s.replace(/\{mod\}/g, mod);
}

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                  .replace(/"/g, '&quot;');
}
function $(id) { return document.getElementById(id); }

// ── state from AHK ─────────────────────────────────────────────────────
window.receiveState = function (s) {
  st = s;
  awaitingState = false;
  lang = st.settings.lang === 'sv' ? 'sv' : 'en';
  const setups = setupList();
  if (curSetup === null || !setups.includes(curSetup)) curSetup = st.currentSetup;
  localizeStatic();
  renderTopbar();
  renderHotkeys();
  renderPositions();
  renderWindows();
  renderManaged();
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
  $('btnAddRule').textContent = t('addRule');
  $('btnAddRule').title = t('addRuleTip');
  $('tabBtnPositions').textContent = t('tabPositions');
  $('tabBtnWindows').textContent = t('tabWindows');
  $('tabBtnSettings').textContent = t('tabSettings');
  $('lblSetup').textContent = t('setupLabel');
  $('btnOpenPositions').textContent = t('openIni');
  $('btnOpenConfig').textContent = t('openConfig');
  $('filesH').textContent = t('filesH');
  $('hkH').textContent = t('hkH');
  $('hkHelp').textContent = t('hkHelp');
  updateForgetSel();
  $('thWindow').textContent = t('thWindow');
  $('thIdentity').textContent = t('thIdentity');
  $('thActive').textContent = t('thActive');
  $('thWidth').textContent = t('thWidth');
  $('thHeight').textContent = t('thHeight');
  // column tips: the headers are terse by necessity, their meaning is not
  [['thWindow', 'thWindowTip'], ['thIdentity', 'thIdentityTip'], ['thActive', 'thActiveTip'],
   ['thX', 'thXTip'], ['thY', 'thYTip'],
   ['thWidth', 'thWidthTip'], ['thHeight', 'thHeightTip'],
   ['thProgram', 'thProgramTip'], ['thTitle', 'thTitleTip'],
   ['thIdentity2', 'thIdentityTip'], ['thSaved', 'thSavedTip']
  ].forEach(([id, tip]) => { const el = $(id); if (el) el.title = t(tip); });
  document.querySelectorAll('th.selcol').forEach(el => { el.title = t('selColTip'); });
  $('winsHint').textContent = t('winsHint');
  $('btnRefresh').textContent = t('refresh');
  $('thProgram').textContent = t('thProgram');
  $('thTitle').textContent = t('thTitle');
  $('thIdentity2').textContent = t('thIdentity');
  $('thSaved').textContent = t('thSaved');
  $('managedH').textContent = t('managedH');
  $('lblOnlyRules').innerHTML = t('onlyRules');
  $('onlyRulesHelp').textContent = t('onlyRulesHelp');
  $('onlyRulesExeH').textContent = t('onlyRulesExeH');
  $('onlyRulesExeHelp').textContent = t('onlyRulesExeHelp');
  $('ignoreH').textContent = t('ignoreH');
  $('ignExeHelp').textContent = t('ignExeHelp');
  $('ignTitleHelp').textContent = t('ignTitleHelp');
  $('managedSavedHint').textContent = t('managedSavedHint');
  $('langH').textContent = t('langH');
  $('langHelp').textContent = t('langHelp');
  document.querySelectorAll('input[name=lang]').forEach(r => { r.checked = r.value === lang; });
}

// ── toggles (Settings tab) ─────────────────────────────────────────────
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

// ── positions: rules and saved positions in one list ───────────────────
// One row per identity for the selected monitor setup: every title rule
// (with its position, or "no position yet") and every program identity that
// has a position. Rules and positions used to live on two tabs, which showed
// the same things twice - a rule is only ever interesting together with the
// place its windows go to.
const selPos = new Set();   // sections ticked for bulk forget

function updateForgetSel() {
  const b = $('btnForgetSel');
  b.disabled = !selPos.size;
  b.textContent = t('forgetSel') + (selPos.size ? ` (${selPos.size})` : '');
}

function rowsForSetup() {
  const pos = st.positions.filter(p => p.setup === curSetup);
  const byKey = new Map(pos.map(p => [p.key, p]));
  const rows = st.rules.map(r => ({ kind: 'rule', rule: r, pos: byKey.get('rule:' + r.alias) || null }));
  const known = new Set(st.rules.map(r => 'rule:' + r.alias));
  for (const p of pos)
    if (!known.has(p.key))
      rows.push({ kind: p.key.startsWith('rule:') ? 'gone' : 'std', rule: null, pos: p });
  return rows;
}

function patternCell(alias, pattern, regex, isNew) {
  const a = esc(alias);
  return `<span class="pre">${esc(t('appliesPre'))}</span>` +
    `<input type="text" class="r-pattern" data-alias="${a}" value="${esc(pattern)}" placeholder="${esc(t('patternPh'))}"${isNew ? ' data-new="1"' : ''}>` +
    `<span class="post">${esc(t('appliesPost'))}</span>` +
    `<label class="rx"><input type="checkbox" class="r-regex" data-alias="${a}"${regex ? ' checked' : ''}> ${esc(t('regexLbl'))}</label>`;
}

function posRow(row) {
  const p = row.pos, r = row.rule;
  const key = p ? p.key : 'rule:' + r.alias;
  const section = p ? p.section : '';
  const isCur = curSetup === st.currentSetup;
  let applies, ident, active;
  if (row.kind === 'rule') {
    applies = patternCell(r.alias, r.pattern, r.regex, false);
    ident = `<span class="badge rule">${esc(t('badgeRule'))}: ${esc(r.alias)}</span>`;
    active = `<input type="checkbox" class="r-enabled" data-alias="${esc(r.alias)}"${r.enabled ? ' checked' : ''} title="${esc(t('thActiveTip'))}">`;
  } else if (row.kind === 'gone') {
    applies = esc(t('appliesRuleGone').replace('{0}', key.slice(5)));
    ident = `<span class="badge rule">${esc(t('badgeRule'))}: ${esc(key.slice(5))}</span>`;
    active = '<span class="dim">–</span>';
  } else {
    applies = esc(t('appliesStd').replace('{0}', key.split('|')[0]));
    ident = `<span class="badge">${esc(t('badgeStd'))}</span>`;
    active = '<span class="dim">–</span>';
  }
  const maxBadge = p && String(p.max) === '1' ? ` <span class="badge">${esc(t('badgeMax'))}</span>` : '';
  const tip = p ? t('savedFromTip').replace('{0}', p.info || key) + '\n' + key : key;
  const nums = p
    ? `<td class="num">${esc(p.x)}</td><td class="num">${esc(p.y)}</td><td class="num">${esc(p.w)}</td><td class="num">${esc(p.h)}</td>`
    : `<td class="num dim nopos" colspan="4">${esc(t('noPosYet'))}</td>`;
  const canMove = p && isCur && (row.kind !== 'rule' || r.enabled);
  const off = r && !r.enabled ? ' off' : '';
  return `<tr class="${row.kind}${off}" data-section="${esc(section)}" data-key="${esc(key)}"${r ? ` data-alias="${esc(r.alias)}"` : ''}>
    <td class="selcol">${p ? `<input type="checkbox" class="rowsel"${selPos.has(section) ? ' checked' : ''}>` : ''}</td>
    <td class="applies" title="${esc(tip)}">${applies}${maxBadge}</td>
    <td>${ident}</td>
    <td class="active">${active}</td>
    ${nums}
    <td class="actions">
      ${canMove ? `<button class="small act-move">${esc(t('moveNow'))}</button>` : ''}
      ${p ? `<button class="small act-forget">${esc(t('forget'))}</button>` : ''}
      ${row.kind === 'rule' ? `<button class="small act-delrule" title="${esc(t('deleteRuleTip'))}">${esc(t('deleteRule'))}</button>` : ''}
    </td></tr>`;
}

function newRuleRow() {
  return `<tr class="rule new">
    <td class="selcol"></td>
    <td class="applies">${patternCell('', '', 0, true)}</td>
    <td><span class="badge rule">${esc(t('badgeRule'))}: ${esc(t('badgeNew'))}</span></td>
    <td class="active"><input type="checkbox" class="r-enabled" checked disabled></td>
    <td class="num dim nopos" colspan="4">${esc(t('noPosYet'))}</td>
    <td class="actions"></td></tr>`;
}

function editingPattern() {
  const ae = document.activeElement;
  return !!(ae && ae.classList && ae.classList.contains('r-pattern') && $('posBody').contains(ae));
}

function renderPositions() {
  const sel = $('setupSel');
  sel.innerHTML = setupList().map(s =>
    `<option value="${esc(s)}"${s === curSetup ? ' selected' : ''}>` +
    `${esc(s)}${s === st.currentSetup ? esc(t('thisSetup')) : ''}</option>`).join('');
  // never rebuild under the user's fingers - a state push can arrive while a
  // pattern is being typed; the field re-syncs when it is left
  if (editingPattern()) return;

  const rows = rowsForSetup();
  const body = $('posBody');
  if (!rows.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="9">${esc(t('posEmpty'))}</td></tr>`;
    selPos.clear();
    updateForgetSel();
    return;
  }
  body.innerHTML = rows.map(posRow).join('');
  // the state can be re-pushed at any moment (autosave elsewhere), so the
  // selection lives outside the DOM and is pruned to the rows still shown
  const withPos = rows.filter(r => r.pos);
  const shown = new Set(withPos.map(r => r.pos.section));
  for (const s of [...selPos]) if (!shown.has(s)) selPos.delete(s);
  $('selAllPos').checked = withPos.length > 0 && withPos.every(r => selPos.has(r.pos.section));
  updateForgetSel();
}
$('setupSel').addEventListener('change', e => { curSetup = e.target.value; renderPositions(); });
$('btnOpenPositions').addEventListener('click', () => post({ action: 'openPositions' }));
$('btnOpenConfig').addEventListener('click', () => post({ action: 'openConfig' }));

$('btnAddRule').addEventListener('click', () => {
  const body = $('posBody');
  const empty = body.querySelector('.empty-row');
  if (empty) empty.remove();
  if (!body.querySelector('tr.new')) body.insertAdjacentHTML('afterbegin', newRuleRow());
  body.querySelector('tr.new .r-pattern').focus();
});

// edits in a row are saved the moment the field is left (or Enter is pressed)
$('posBody').addEventListener('change', e => {
  const el = e.target;
  if (el.classList.contains('rowsel')) {
    const sec = el.closest('tr').dataset.section;
    if (el.checked) selPos.add(sec); else selPos.delete(sec);
    $('selAllPos').checked = [...$('posBody').querySelectorAll('.rowsel')].every(c => c.checked);
    updateForgetSel();
    return;
  }
  const tr = el.closest('tr');
  if (!tr) return;
  const regex = tr.querySelector('.r-regex');
  if (tr.classList.contains('new')) {
    if (!el.classList.contains('r-pattern')) return;
    const pattern = el.value.trim();
    if (!pattern) return;
    awaitingState = true;
    post({ action: 'addRule', pattern, regex: regex && regex.checked ? 1 : 0 });
    return;
  }
  if (el.classList.contains('r-pattern') || el.classList.contains('r-regex') || el.classList.contains('r-enabled')) {
    awaitingState = true;
    post({
      action: 'setRule',
      alias: tr.dataset.alias,
      pattern: tr.querySelector('.r-pattern').value.trim(),
      regex: regex && regex.checked ? 1 : 0,
      enabled: tr.querySelector('.r-enabled').checked ? 1 : 0
    });
  }
});
$('posBody').addEventListener('keydown', e => {
  if (!e.target.classList.contains('r-pattern')) return;
  if (e.key === 'Enter') {
    e.target.blur();                       // commit: change fires on blur
  } else if (e.key === 'Escape') {
    const tr = e.target.closest('tr');
    const r = st && st.rules.find(x => x.alias === tr.dataset.alias);
    e.target.value = r ? r.pattern : '';   // back to what is saved - no change event
    e.target.blur();
  }
});
$('posBody').addEventListener('focusout', e => {
  if (!e.target.classList.contains('r-pattern')) return;
  // re-sync the list once the field is left, unless an edit is on its way
  // (the state that carries it will render); a new row left empty goes away
  setTimeout(() => { if (!awaitingState && !editingPattern()) renderPositions(); }, 0);
});
$('selAllPos').addEventListener('change', e => {
  $('posBody').querySelectorAll('tr[data-section]').forEach(tr => {
    if (!tr.dataset.section) return;
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
  if (!tr) return;
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
  } else if (e.target.classList.contains('act-delrule')) {
    // the rule's positions go with it, in every setup - hence the question
    const alias = tr.dataset.alias;
    if (window.confirm(t('confirmDeleteRule').replace('{0}', alias)))
      post({ action: 'deleteRule', alias });
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
                   : w.managed ? `<span class="badge">${esc(t('badgeStd'))}</span>`
                   : `<span class="dim" title="${esc(t('unmanagedTip'))}">–</span>`}</td>
      <td>${w.saved ? `<span class="ok">${esc(t('savedYes'))}</span>` : '<span class="dim">–</span>'}</td>
      <td class="actions">
        <button class="small act-save" ${w.managed ? '' : 'disabled'} title="${esc(t('saveTip'))}">${esc(t('saveBtn'))}</button>
        <button class="small act-movewin" ${w.saved ? '' : 'disabled'}
          title="${esc(t('moveTip'))}">${esc(t('moveHere'))}</button>
        <button class="small act-rule" title="${esc(t('ruleRowTip'))}">${esc(t(w.rule ? 'editRuleBtn' : 'newRuleBtn'))}</button>
      </td></tr>`).join('');
}
$('btnRefresh').addEventListener('click', () => post({ action: 'refresh' }));
$('winBody').addEventListener('click', e => {
  const tr = e.target.closest('tr');
  if (!tr || !tr.dataset.hwnd) return;
  const hwnd = Number(tr.dataset.hwnd);
  if (e.target.classList.contains('act-save')) post({ action: 'saveWin', hwnd });
  else if (e.target.classList.contains('act-movewin')) post({ action: 'moveWin', hwnd });
  // the window menu's save/rule dialog, for a window picked from this list
  else if (e.target.classList.contains('act-rule')) post({ action: 'ruleFromWin', hwnd });
});

// ── which windows are managed (Settings tab) ───────────────────────────
// Saved as a whole whenever one of the fields changes - the change event
// fires when a textarea is left, so typing is never interrupted.
const MANAGED_IDS = ['tglOnlyRules', 'txtRulesOnlyExe', 'txtIgnoreExe', 'txtIgnoreTitle'];

function renderManaged() {
  const ae = document.activeElement;
  if (ae && MANAGED_IDS.includes(ae.id)) return;   // not under the user's fingers
  $('tglOnlyRules').checked = !!st.settings.rulesOnly;
  $('txtRulesOnlyExe').value = (st.rulesOnlyExe || []).join('\n');
  $('txtIgnoreExe').value = st.ignoreExe.join('\n');
  $('txtIgnoreTitle').value = st.ignoreTitles.join('\n');
}
function postManaged() {
  const lines = id => $(id).value.split('\n').map(s => s.trim()).filter(Boolean);
  post({
    action: 'setManaged',
    rulesOnly: $('tglOnlyRules').checked ? 1 : 0,
    rulesOnlyExe: lines('txtRulesOnlyExe'),
    ignoreExe: lines('txtIgnoreExe'),
    ignoreTitles: lines('txtIgnoreTitle')
  });
}
MANAGED_IDS.forEach(id => $(id).addEventListener('change', postManaged));

// ── status bar ─────────────────────────────────────────────────────────
function renderStatus() {
  const nCur = st.positions.filter(p => p.setup === st.currentSetup).length;
  $('status').textContent = t('status')(nCur, st.positions.length, st.currentSetup);
  $('statusPause').innerHTML = st.settings.move ? ''
    : `<span class="warn">${esc(t('paused'))}</span>`;
}

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
