// DeskPilot GUI. Mirrors DalSegno's architecture: AHK pushes one state object
// into window.receiveState, the page posts {action:…} messages back.
let st = null;
let lang = 'en';
let rulesDirty = false;

const STR = {
  en: {
    hkH: 'Hotkeys',
    hkHelp: 'AutoHotkey syntax: + Shift, ^ Ctrl, # Win, ! Alt. Empty disables the hotkey.',
    prefixH: 'Digit prefixes',
    prefixHelp: 'Held with a digit 1-9 to address that desktop directly. Note that ^# and !# override Windows’ own taskbar shortcuts for pinned apps; empty them to keep those.',
    hkMoveNext: 'Move window to the next desktop',
    hkMovePrevious: 'Move window to the previous desktop',
    hkMoveFollowNext: 'Move and follow to the next desktop',
    hkMoveFollowPrevious: 'Move and follow to the previous desktop',
    hkMoveMenu: 'Open the window menu for the active window',
    hkShowName: 'Show the desktop name overlay',
    hkSwitchToPrefix: 'Switch to desktop N',
    hkMoveToPrefix: 'Move window to desktop N',
    hkMoveFollowToPrefix: 'Move and follow to desktop N',

    rulesH: 'Window rules',
    rulesHelp: 'A window is moved when it is new, or when its title changes into matching. Rules are tried in order and the first match wins - so put the specific ones first. Matching a window you drag away later leaves it where you put it.',
    thDesktop: 'Desktop', thExe: 'Program', thTitle: 'Title matches', thFollow: 'Follow',
    thDesktopTip: 'The desktop number the window is moved to.',
    thExeTip: 'Executable name, e.g. msedge.exe. Leave empty to match any program.',
    thTitleTip: 'Regular expression matched against the window title. Leave empty to match every window of the program. Tip: (?i) at the start makes it case-insensitive.',
    thFollowTip: 'Also switch to that desktop when the rule fires, instead of moving the window away in the background.',
    addRule: 'Add rule', saveRules: 'Save rules', delRuleTip: 'Delete the rule',
    unsaved: 'unsaved changes', anyProgram: '(any)',
    rulesEmpty: 'No rules yet.',

    winsH: 'Open windows',
    winsHelp: 'Windows DeskPilot can act on right now. "Rule…" fills in a new rule from the window.',
    thWinProgram: 'Program', thWinTitle: 'Title', thWinDesktop: 'Desktop',
    ruleBtn: 'Rule…', ruleBtnTip: 'Create a rule prefilled from this window',
    winsEmpty: 'No windows found.',

    menuH: 'Window menu',
    menuHelp: 'Hold the modifier and press the button to open DeskPilot’s menu on a window. The plain right-click is left to the app.',
    tglTitleMenu: 'Enable the window menu',
    lblMenuModifier: 'Modifier', lblMenuButton: 'Button',
    tglWholeWindow: 'Opens anywhere in the window',
    wholeWindowHelp: 'Off restricts it to the title bar and the top band of apps with custom title bars.',
    lblExclude: 'Leave these programs alone',
    excludeHelp: 'Process names as a regular expression, e.g. (?i)^(msedge|explorer)\\.exe$ - for apps that use the same combination themselves. Empty means no exclusions.',

    taskbarH: 'Taskbar and tray',
    tglNameInTray: 'Show the desktop name on the taskbar',
    tglWheel: 'Mouse wheel over the taskbar switches desktop',
    wheelHelp: 'Scroll anywhere on the taskbar that is not a button.',
    tglArrows: 'Two arrow tray icons that switch desktop',
    arrowsHelp: 'Drag them out of the overflow area once to keep them visible.',

    langH: 'Language',
    langHelp: 'Applies to this window, the tray menu, the menu and the overlay.',
    filesH: 'Files',
    openConfig: 'Open the configuration file…',
    reload: 'Reload configuration',

    tabHotkeys: 'Hotkeys', tabRules: 'Rules', tabSettings: 'Settings',
    statusDesktops: '{n} desktops, currently on {i}'
  },
  sv: {
    hkH: 'Kortkommandon',
    hkHelp: 'AutoHotkey-syntax: + Skift, ^ Ctrl, # Win, ! Alt. Tomt stänger av kortkommandot.',
    prefixH: 'Sifferprefix',
    prefixHelp: 'Hålls tillsammans med en siffra 1-9 för att adressera det skrivbordet direkt. Observera att ^# och !# tar över Windows egna aktivitetsfältsgenvägar för fästa appar; lämna dem tomma om du vill behålla dessa.',
    hkMoveNext: 'Flytta fönstret till nästa skrivbord',
    hkMovePrevious: 'Flytta fönstret till föregående skrivbord',
    hkMoveFollowNext: 'Flytta och följ efter till nästa skrivbord',
    hkMoveFollowPrevious: 'Flytta och följ efter till föregående skrivbord',
    hkMoveMenu: 'Öppna fönstermenyn för aktivt fönster',
    hkShowName: 'Visa skrivbordsnamnet som överlägg',
    hkSwitchToPrefix: 'Växla till skrivbord N',
    hkMoveToPrefix: 'Flytta fönstret till skrivbord N',
    hkMoveFollowToPrefix: 'Flytta och följ efter till skrivbord N',

    rulesH: 'Fönsterregler',
    rulesHelp: 'Ett fönster flyttas när det är nytt, eller när dess titel ändras till att matcha. Reglerna prövas i ordning och första träffen gäller - sätt de specifika först. Drar du sedan bort ett matchande fönster för hand får det ligga kvar där.',
    thDesktop: 'Skrivbord', thExe: 'Program', thTitle: 'Titeln matchar', thFollow: 'Följ',
    thDesktopTip: 'Numret på skrivbordet fönstret flyttas till.',
    thExeTip: 'Programfilens namn, t.ex. msedge.exe. Tomt matchar alla program.',
    thTitleTip: 'Reguljärt uttryck som matchas mot fönstrets titel. Tomt matchar alla fönster i programmet. Tips: (?i) först gör det skiftlägesokänsligt.',
    thFollowTip: 'Växla också till skrivbordet när regeln slår till, i stället för att flytta bort fönstret i bakgrunden.',
    addRule: 'Lägg till regel', saveRules: 'Spara regler', delRuleTip: 'Ta bort regeln',
    unsaved: 'osparade ändringar', anyProgram: '(alla)',
    rulesEmpty: 'Inga regler än.',

    winsH: 'Öppna fönster',
    winsHelp: 'Fönster som DeskPilot kan agera på just nu. "Regel…" fyller i en ny regel från fönstret.',
    thWinProgram: 'Program', thWinTitle: 'Titel', thWinDesktop: 'Skrivbord',
    ruleBtn: 'Regel…', ruleBtnTip: 'Skapa en regel förifylld från det här fönstret',
    winsEmpty: 'Inga fönster hittades.',

    menuH: 'Fönstermeny',
    menuHelp: 'Håll modifieraren och tryck knappen för att öppna DeskPilots meny på ett fönster. Vanligt högerklick lämnas till appen.',
    tglTitleMenu: 'Aktivera fönstermenyn',
    lblMenuModifier: 'Modifierare', lblMenuButton: 'Knapp',
    tglWholeWindow: 'Öppnas var som helst i fönstret',
    wholeWindowHelp: 'Av begränsar den till titelraden och överkanten på appar med egenritade titelrader.',
    lblExclude: 'Lämna dessa program i fred',
    excludeHelp: 'Processnamn som reguljärt uttryck, t.ex. (?i)^(msedge|explorer)\\.exe$ - för appar som använder samma kombination själva. Tomt betyder inga undantag.',

    taskbarH: 'Aktivitetsfält och systemfält',
    tglNameInTray: 'Visa skrivbordsnamnet i aktivitetsfältet',
    tglWheel: 'Mushjulet över aktivitetsfältet växlar skrivbord',
    wheelHelp: 'Rulla var som helst på fältet där det inte sitter en knapp.',
    tglArrows: 'Två pilikoner i systemfältet som växlar skrivbord',
    arrowsHelp: 'Dra ut dem ur överflödet en gång för att hålla dem synliga.',

    langH: 'Språk',
    langHelp: 'Gäller det här fönstret, tray-menyn, fönstermenyn och överlägget.',
    filesH: 'Filer',
    openConfig: 'Öppna konfigurationsfilen…',
    reload: 'Läs om konfigurationen',

    tabHotkeys: 'Kortkommandon', tabRules: 'Regler', tabSettings: 'Inställningar',
    statusDesktops: '{n} skrivbord, du är på {i}'
  }
};

function t(id) { return (STR[lang] || STR.en)[id] ?? STR.en[id] ?? id; }
function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function $(id) { return document.getElementById(id); }
function post(msg) { window.chrome.webview.postMessage(msg); }

const HOTKEYS = ['MoveNext', 'MovePrevious', 'MoveFollowNext', 'MoveFollowPrevious',
                 'MoveMenu', 'ShowName'];
const PREFIXES = ['SwitchToPrefix', 'MoveToPrefix', 'MoveFollowToPrefix'];

// ── state from AHK ─────────────────────────────────────────────────────
window.receiveState = function (s) {
  st = s;
  lang = st.settings.lang === 'sv' ? 'sv' : 'en';
  localizeStatic();
  renderHotkeys();
  renderSettings();
  if (!rulesDirty) renderRules();
  renderWindows();
  renderStatus();
};

function localizeStatic() {
  document.documentElement.lang = lang;
  const set = (id, key) => { const e = $(id); if (e) e.textContent = t(key); };
  set('tabBtnHotkeys', 'tabHotkeys'); set('tabBtnRules', 'tabRules');
  set('tabBtnSettings', 'tabSettings');
  set('hkH', 'hkH'); set('hkHelp', 'hkHelp');
  set('prefixH', 'prefixH'); set('prefixHelp', 'prefixHelp');
  set('rulesH', 'rulesH'); set('rulesHelp', 'rulesHelp');
  set('thDesktop', 'thDesktop'); set('thExe', 'thExe');
  set('thTitle', 'thTitle'); set('thFollow', 'thFollow');
  set('btnAddRule', 'addRule'); set('btnSaveRules', 'saveRules');
  set('winsH', 'winsH'); set('winsHelp', 'winsHelp');
  set('thWinProgram', 'thWinProgram'); set('thWinTitle', 'thWinTitle');
  set('thWinDesktop', 'thWinDesktop'); set('btnRefreshWins', 'ruleBtn');
  $('btnRefreshWins').textContent = lang === 'sv' ? 'Uppdatera' : 'Refresh';
  set('menuH', 'menuH'); set('menuHelp', 'menuHelp');
  set('lblTitleMenu', 'tglTitleMenu');
  set('lblMenuModifier', 'lblMenuModifier'); set('lblMenuButton', 'lblMenuButton');
  set('lblWholeWindow', 'tglWholeWindow'); set('wholeWindowHelp', 'wholeWindowHelp');
  set('lblExclude', 'lblExclude'); set('excludeHelp', 'excludeHelp');
  set('taskbarH', 'taskbarH'); set('lblNameInTray', 'tglNameInTray');
  set('lblWheel', 'tglWheel'); set('wheelHelp', 'wheelHelp');
  set('lblArrows', 'tglArrows'); set('arrowsHelp', 'arrowsHelp');
  set('langH', 'langH'); set('langHelp', 'langHelp');
  set('filesH', 'filesH');
  set('btnOpenConfig', 'openConfig'); set('btnReload', 'reload');
  // column tips
  [['thDesktop', 'thDesktopTip'], ['thExe', 'thExeTip'],
   ['thTitle', 'thTitleTip'], ['thFollow', 'thFollowTip']
  ].forEach(([id, tip]) => { const e = $(id); if (e) e.title = t(tip); });
  document.querySelectorAll('input[name=lang]').forEach(r => { r.checked = r.value === lang; });
}

function renderStatus() {
  $('status').textContent = t('statusDesktops')
    .replace('{n}', st.desktops.count).replace('{i}', st.desktops.index);
}

// ── hotkeys ────────────────────────────────────────────────────────────
function hkRows(names, hostId) {
  if (document.activeElement && document.activeElement.classList &&
      document.activeElement.classList.contains('hkkey')) return;
  $(hostId).innerHTML = names.map(n => `
    <div class="hkrow">
      <input class="hkkey" data-name="${n}" value="${esc(st.hotkeys[n] ?? '')}">
      <span class="hklbl">${esc(t('hk' + n))}</span>
    </div>`).join('');
}
function renderHotkeys() { hkRows(HOTKEYS, 'hkList'); hkRows(PREFIXES, 'prefixList'); }
document.addEventListener('change', e => {
  if (!e.target.classList.contains('hkkey')) return;
  post({ action: 'setHotkey', name: e.target.dataset.name, key: e.target.value.trim() });
});

// ── settings ───────────────────────────────────────────────────────────
function renderSettings() {
  const s = st.settings;
  $('tglTitleMenu').checked = !!s.titleMenu;
  $('inMenuModifier').value = s.menuModifier ?? '';
  $('inMenuButton').value = s.menuButton ?? '';
  $('tglWholeWindow').checked = !!s.wholeWindow;
  if (document.activeElement !== $('inExclude')) $('inExclude').value = s.exclude ?? '';
  $('tglNameInTray').checked = !!s.nameInTray;
  $('tglWheel').checked = !!s.wheel;
  $('tglArrows').checked = !!s.arrowIcons;
  // the modifier fields are meaningless while the menu is off
  ['inMenuModifier', 'inMenuButton', 'tglWholeWindow', 'inExclude']
    .forEach(id => { $(id).disabled = !s.titleMenu; });
}
const setOpt = (name, value) => post({ action: 'setOption', name, value });
$('tglTitleMenu').addEventListener('change', e => setOpt('TitleMenu', e.target.checked ? 1 : 0));
$('tglWholeWindow').addEventListener('change', e => setOpt('MenuWholeWindow', e.target.checked ? 1 : 0));
$('tglNameInTray').addEventListener('change', e => setOpt('NameInTray', e.target.checked ? 1 : 0));
$('tglWheel').addEventListener('change', e => setOpt('Wheel', e.target.checked ? 1 : 0));
$('tglArrows').addEventListener('change', e => setOpt('ArrowIcons', e.target.checked ? 1 : 0));
$('inMenuModifier').addEventListener('change', e => setOpt('MenuModifier', e.target.value.trim()));
$('inMenuButton').addEventListener('change', e => setOpt('MenuButton', e.target.value.trim()));
$('inExclude').addEventListener('change', e => setOpt('TitleMenuExclude', e.target.value.trim()));
document.querySelectorAll('input[name=lang]').forEach(r =>
  r.addEventListener('change', e => { if (e.target.checked) post({ action: 'setLang', lang: e.target.value }); }));
$('btnOpenConfig').addEventListener('click', () => post({ action: 'openConfig' }));
$('btnReload').addEventListener('click', () => post({ action: 'reloadConfig' }));

// ── tabs ───────────────────────────────────────────────────────────────
document.querySelectorAll('#tabs .tab').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#tabs .tab').forEach(b => b.classList.toggle('active', b === btn));
    document.querySelectorAll('.tabpane').forEach(p =>
      p.classList.toggle('active', p.id === 'tab-' + btn.dataset.tab));
    if (btn.dataset.tab === 'rules') post({ action: 'refresh' });
  });
});

// ── rules ──────────────────────────────────────────────────────────────
function desktopOptions(sel) {
  let o = '';
  for (let i = 1; i <= Math.max(st.desktops.count, sel || 1); i++)
    o += `<option value="${i}"${i === sel ? ' selected' : ''}>${i}</option>`;
  return o;
}
function ruleRow(r) {
  return `<tr>
    <td><select class="r-desktop">${desktopOptions(Number(r.desktop) || 1)}</select></td>
    <td><input class="r-exe" value="${esc(r.exe)}" placeholder="${esc(t('anyProgram'))}"></td>
    <td><input class="r-title wide" value="${esc(r.title)}"></td>
    <td style="text-align:center"><input type="checkbox" class="r-follow"${r.follow ? ' checked' : ''}></td>
    <td class="actions"><button class="small act-del" title="${esc(t('delRuleTip'))}">✕</button></td>
  </tr>`;
}
function renderRules() {
  const body = $('rulesBody');
  if (!st.rules.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="5">${esc(t('rulesEmpty'))}</td></tr>`;
    return;
  }
  body.innerHTML = st.rules.map(ruleRow).join('');
}
function setRulesDirty(v) {
  rulesDirty = v;
  $('rulesDirty').textContent = v ? t('unsaved') : '';
}
$('rulesBody').addEventListener('input', () => setRulesDirty(true));
$('rulesBody').addEventListener('change', () => setRulesDirty(true));
$('rulesBody').addEventListener('click', e => {
  if (!e.target.classList.contains('act-del')) return;
  e.target.closest('tr').remove();
  setRulesDirty(true);
});
$('btnAddRule').addEventListener('click', () => {
  const empty = $('rulesBody').querySelector('.empty-row');
  if (empty) empty.remove();
  $('rulesBody').insertAdjacentHTML('beforeend',
    ruleRow({ desktop: st.desktops.index, exe: '', title: '', follow: 0 }));
  setRulesDirty(true);
});
$('btnSaveRules').addEventListener('click', () => {
  const rules = [...$('rulesBody').querySelectorAll('tr')].filter(tr => tr.querySelector('.r-desktop'))
    .map(tr => ({
      desktop: Number(tr.querySelector('.r-desktop').value),
      exe: tr.querySelector('.r-exe').value.trim(),
      title: tr.querySelector('.r-title').value.trim(),
      follow: tr.querySelector('.r-follow').checked ? 1 : 0
    }))
    .filter(r => r.exe !== '' || r.title !== '');   // a rule needs at least one
  post({ action: 'saveRules', rules });
  setRulesDirty(false);
});

window.prefillRule = function (r) {
  $('tabBtnRules').click();
  const empty = $('rulesBody').querySelector('.empty-row');
  if (empty) empty.remove();
  $('rulesBody').insertAdjacentHTML('beforeend',
    ruleRow({ desktop: st.desktops.index, exe: r.exe || '', title: r.title || '', follow: 0 }));
  setRulesDirty(true);
  const rows = $('rulesBody').querySelectorAll('tr');
  const input = rows[rows.length - 1].querySelector('.r-title');
  input.focus();
  input.select();   // prefilled with the whole title - trim to the stable part
};

// ── open windows ───────────────────────────────────────────────────────
function renderWindows() {
  const body = $('winBody');
  if (!st.windows || !st.windows.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="4">${esc(t('winsEmpty'))}</td></tr>`;
    return;
  }
  body.innerHTML = st.windows.map(w => `
    <tr data-hwnd="${w.hwnd}">
      <td>${esc(w.exe)}</td>
      <td class="ellip" title="${esc(w.title)}">${esc(w.title)}</td>
      <td>${esc(w.desktop || '–')}</td>
      <td class="actions">
        <button class="small act-rule" title="${esc(t('ruleBtnTip'))}">${esc(t('ruleBtn'))}</button>
      </td></tr>`).join('');
}
$('btnRefreshWins').addEventListener('click', () => post({ action: 'refresh' }));
$('winBody').addEventListener('click', e => {
  if (!e.target.classList.contains('act-rule')) return;
  const hwnd = Number(e.target.closest('tr').dataset.hwnd);
  const w = st.windows.find(x => Number(x.hwnd) === hwnd);
  if (w) prefillRule({ exe: w.exe, title: w.title });
});

// ── start ──────────────────────────────────────────────────────────────
post({ action: 'ready' });
