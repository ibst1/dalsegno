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
    tabPositions: 'Positions', tabWindows: 'Windows', tabDesktops: 'Desktops', tabSettings: 'Settings',
    // positions list
    setupLabel: 'Monitor setup:', thisSetup: ' (this)',
    thWindow: 'Applies to', thIdentity: 'Identity', thActive: 'Active', thDesktop: 'Desktop',
    thWidth: 'Width', thHeight: 'Height',
    thWindowTip: 'Which windows the row applies to. A rule\'s text and program are edited right here and saved when you leave the field. Hover a row for the window the position was saved from.',
    thIdentityTip: 'What the position is stored under - that is, which windows share it. "standard" means all windows of the same program and window class; "rule" means all windows the rule matches.',
    thActiveTip: 'Untick to switch a rule off without deleting it: its windows are then treated like any other window of their program, and its saved position waits until it is ticked again.',
    thDesktopTip: 'The virtual desktop the rule\'s windows are moved to when they appear or their title changes into matching. "follow" switches along.',
    thXTip: 'Distance from the left edge of the desktop, in pixels.',
    thYTip: 'Distance from the top edge of the desktop, in pixels.',
    thWidthTip: 'Window width in pixels.', thHeightTip: 'Window height in pixels.',
    selColTip: 'Tick rows to forget their positions in one go.',
    forgetSel: 'Forget selected', saveAll: 'Save all now', saveAllTip: "Save every open window's current position",
    applyAll: 'Move all now', applyAllTip: 'Move every open window to its saved position ({mod} + Home)',
    addRule: '+ Add rule', addRuleTip: 'A new rule row - type the text and press Enter',
    posEmpty: 'No rules and no saved positions for this monitor setup yet. Drag a window where you want it, save with {mod} + S, or hold {mod} and right-click a window.',
    badgeRule: 'rule', badgeStd: 'standard', badgeMax: 'maximized', badgeNew: 'new',
    moveNow: 'Move now', forget: 'Forget', sure: 'Sure?',
    appliesPre: 'windows with', appliesPost: 'in the title', programLbl: 'program',
    appliesRuleGone: 'rule "{0}" (no longer exists)', appliesStd: 'all {0} windows',
    savedFromTip: 'Saved from: {0}', noPosYet: 'no position yet',
    patternPh: 'text in the title', exePh: '(any)', regexLbl: 'regex',
    noDesktop: '(none)', followLbl: 'follow',
    deleteRule: 'Delete rule', deleteRuleTip: 'Remove the rule and its saved positions in every monitor setup',
    confirmDeleteRule: 'Delete the rule "{0}" and its saved positions in every monitor setup?',
    upTip: 'Move the rule up - earlier rules win', downTip: 'Move the rule down',
    // windows
    winsHint: 'Open windows DalSegno can act on right now.', refresh: 'Refresh',
    thProgram: 'Program', thTitle: 'Title', thWinDesktop: 'Desktop', thSaved: 'Saved position',
    thProgramTip: 'Executable name of the process owning the window.',
    thTitleTip: 'The window title right now. Rules match against this.',
    thWinDesktopTip: 'The virtual desktop the window is on - pick another to move it there.',
    thSavedTip: 'Whether a position is stored for this window\'s identity in the current monitor setup.',
    savedYes: '✓ saved', saveBtn: 'Save position', saveTip: "Save the window's current position",
    moveHere: 'Move there', moveTip: 'Move the window to its saved position',
    newRuleBtn: 'Rule…', editRuleBtn: 'Edit rule…',
    ruleRowTip: "The window menu's save dialog for this window: what the position applies to, the desktop, or the rule it matches",
    unmanagedTip: 'Only managed through a rule - none matches yet',
    ownWinTip: 'DalSegno\'s own window. Rules never apply to it and it needs no position; it always opens on the desktop you are on.',
    winsEmpty: 'No windows found.',
    // desktops tab
    dllNote: 'VirtualDesktopAccessor.dll is missing next to the script: windows cannot be moved between desktops, and rules with a desktop do nothing. See the README for the download.',
    dhkH: 'Desktop hotkeys',
    dhkHelp: 'AutoHotkey syntax: + Shift, ^ Ctrl, # Win, ! Alt. Empty disables the hotkey. Ctrl = switch, Alt = move the window, Ctrl+Alt = move and follow.',
    prefixH: 'Digit prefixes',
    prefixHelp: 'Held with a digit 1-9 to address that desktop directly. Note that ^# and !# override Windows\' own taskbar shortcuts for pinned apps; empty them to keep those.',
    hkMoveNext: 'Move window to the next desktop', hkMovePrevious: 'Move window to the previous desktop',
    hkMoveFollowNext: 'Move and follow to the next desktop', hkMoveFollowPrevious: 'Move and follow to the previous desktop',
    hkMoveMenu: 'Open the window menu for the active window', hkShowName: 'Show the desktop name overlay',
    hkSwitchToPrefix: 'Switch to desktop N', hkMoveToPrefix: 'Move window to desktop N', hkMoveFollowToPrefix: 'Move and follow to desktop N',
    taskbarH: 'Taskbar and tray',
    tglNameInTray: 'Show the desktop name on the taskbar',
    tglWheel: 'Mouse wheel over the taskbar switches desktop', wheelHelp: 'Scroll anywhere on the taskbar that is not a button.',
    tglArrows: 'Two arrow tray icons that switch desktop', arrowsHelp: 'Drag them out of the overflow area once to keep them visible.',
    // settings
    modulesH: 'Modules',
    modulesHelp: 'Each half can be switched off on its own: off means no hotkeys, no timer work, no menu items and no tab for it.',
    modPositions: 'Positions - remember where windows go, per monitor setup and computer',
    modDesktops: 'Desktops - virtual desktops: switching, moving, overlay, taskbar label',
    menuH: 'Window menu',
    menuHelp: 'Hold the modifier and press the button on a window to open the menu. The plain right-click is left to the app. The modifier is also the key the position hotkeys below are held with.',
    tglMenuOn: 'Enable the window menu', lblMenuModifier: 'Modifier', lblMenuButton: 'Button',
    tglMenuWhole: 'Opens anywhere in the window', menuWholeHelp: 'Off restricts it to the title bar and the top band of apps with custom title bars.',
    lblMenuExclude: 'Leave these programs alone',
    menuExcludeHelp: 'Process names as a regular expression, e.g. (?i)^(msedge|explorer)\\.exe$ - for apps that use the same combination themselves. Empty means no exclusions.',
    behaveH: 'Positions',
    tglMove: 'Move new windows automatically', tglSave: 'Save position on manual move',
    tglModOnly: 'Only when {mod} is held while dropping',
    modOnlyHelp: 'Saving becomes a deliberate gesture: a sloppy drag cannot overwrite a carefully placed position. Deliberate saves ({mod} + S, the window menu, Save all) always work.',
    tglNotify: 'Toasts',
    managedH: 'Which windows get positions',
    onlyRules: 'Manage <b>only</b> windows that match a rule',
    onlyRulesHelp: 'Off (default): every window is managed. A window that matches no rule is identified by its program and window class, so all windows of the same program share one position. On: only windows matching a rule get a position at all.',
    onlyRulesExeH: 'Rules only for these programs',
    onlyRulesExeHelp: 'Programs handled only through rules (one exe name per line). Their other windows are left alone. The natural setting for a browser: every popup is a separate window that would otherwise share one position with every other window of the browser.',
    ignoreH: 'Ignore', ignExeHelp: 'Programs (one exe name per line):', ignTitleHelp: 'Titles containing (one text per line):',
    managedSavedHint: 'Changes here are saved as soon as you leave the field.',
    hkH: 'Position hotkeys',
    hkHelp: 'Pressed together with {mod}. AutoHotkey key names (d, F10, Home, Backspace…). Leave empty to disable one.',
    hkOpenUi: 'Open the DalSegno window', hkSaveActive: "Save the active window's position",
    hkSaveAll: "Save all open windows' positions", hkApplyAll: 'Move all windows to their saved positions',
    hkForgetActive: "Forget the active window's position", hkToggleMove: 'Toggle automatic moving', hkReload: 'Restart the script',
    langH: 'Language', langHelp: 'Applies to this window, the tray menu, the window menu and the overlay.',
    filesH: 'Files', openIni: 'Open the saved positions file…', openConfig: 'Open the config file…', reload: 'Reload settings',
    status: (n, total, s) => `${n} saved positions for this monitor setup · ${total} total · setup: ${s}`,
    statusDesktops: (n, i) => ` · ${n} desktops, on ${i}`,
    paused: '⏸ automatic moving is off'
  },
  sv: {
    tabPositions: 'Lägen', tabWindows: 'Fönster', tabDesktops: 'Skrivbord', tabSettings: 'Inställningar',
    setupLabel: 'Skärmuppsättning:', thisSetup: ' (denna)',
    thWindow: 'Gäller', thIdentity: 'Identitet', thActive: 'Aktiv', thDesktop: 'Skrivbord',
    thWidth: 'Bredd', thHeight: 'Höjd',
    thWindowTip: 'Vilka fönster raden gäller. En regels text och program redigeras direkt här och sparas när du lämnar fältet. Håll muspekaren över raden för att se fönstret positionen sparades från.',
    thIdentityTip: 'Vad positionen sparas under - alltså vilka fönster som delar det. "standard" betyder alla fönster i samma program och fönsterklass; "regel" betyder alla fönster regeln matchar.',
    thActiveTip: 'Kryssa ur för att stänga av en regel utan att ta bort den: dess fönster behandlas då som vilka fönster som helst i sitt program, och den sparade positionen väntar tills regeln kryssas i igen.',
    thDesktopTip: 'Det virtuella skrivbord regelns fönster flyttas till när de dyker upp eller deras titel ändras till att matcha. "följ efter" växlar också dit.',
    thXTip: 'Avstånd från skrivbordets vänsterkant, i bildpunkter.',
    thYTip: 'Avstånd från skrivbordets överkant, i bildpunkter.',
    thWidthTip: 'Fönstrets bredd i bildpunkter.', thHeightTip: 'Fönstrets höjd i bildpunkter.',
    selColTip: 'Kryssa i rader för att glömma deras positioner i ett svep.',
    forgetSel: 'Glöm markerade', saveAll: 'Spara alla nu', saveAllTip: 'Spara alla öppna fönsters nuvarande positioner',
    applyAll: 'Flytta alla nu', applyAllTip: 'Flytta alla öppna fönster till sina sparade positioner ({mod} + Home)',
    addRule: '+ Lägg till regel', addRuleTip: 'En ny regelrad - skriv texten och tryck Enter',
    posEmpty: 'Inga regler och inga sparade positioner för den här skärmuppsättningen ännu. Dra ett fönster dit du vill ha det, spara med {mod} + S, eller håll {mod} och högerklicka på ett fönster.',
    badgeRule: 'regel', badgeStd: 'standard', badgeMax: 'maximerat', badgeNew: 'ny',
    moveNow: 'Flytta nu', forget: 'Glöm', sure: 'Säkert?',
    appliesPre: 'fönster med', appliesPost: 'i titeln', programLbl: 'program',
    appliesRuleGone: 'regeln "{0}" (finns inte längre)', appliesStd: 'alla {0}-fönster',
    savedFromTip: 'Sparat från: {0}', noPosYet: 'ingen position ännu',
    patternPh: 'text i titeln', exePh: '(alla)', regexLbl: 'regex',
    noDesktop: '(inget)', followLbl: 'följ efter',
    deleteRule: 'Ta bort regel', deleteRuleTip: 'Ta bort regeln och dess sparade positioner i alla skärmuppsättningar',
    confirmDeleteRule: 'Ta bort regeln "{0}" och dess sparade positioner i alla skärmuppsättningar?',
    upTip: 'Flytta regeln uppåt - tidigare regler vinner', downTip: 'Flytta regeln nedåt',
    winsHint: 'Öppna fönster som DalSegno kan agera på just nu.', refresh: 'Uppdatera',
    thProgram: 'Program', thTitle: 'Titel', thWinDesktop: 'Skrivbord', thSaved: 'Sparad position',
    thProgramTip: 'Namnet på programfilen som äger fönstret.',
    thTitleTip: 'Fönstrets titel just nu. Regler matchas mot den.',
    thWinDesktopTip: 'Det virtuella skrivbord fönstret ligger på - välj ett annat för att flytta det dit.',
    thSavedTip: 'Om det finns en sparad position för fönstrets identitet i den aktuella skärmuppsättningen.',
    savedYes: '✓ finns', saveBtn: 'Spara position', saveTip: 'Spara fönstrets nuvarande position',
    moveHere: 'Flytta hit', moveTip: 'Flytta fönstret till den sparade positionen',
    newRuleBtn: 'Regel…', editRuleBtn: 'Ändra regel…',
    ruleRowTip: 'Fönstermenyns spardialog för det här fönstret: vad positionen ska gälla, skrivbord, eller regeln som matchar',
    unmanagedTip: 'Hanteras bara via regel - ingen matchar ännu',
    ownWinTip: 'DalSegnos eget fönster. Regler gäller aldrig det och det behöver ingen position; det öppnas alltid på skrivbordet du är på.',
    winsEmpty: 'Inga fönster hittades.',
    dllNote: 'VirtualDesktopAccessor.dll saknas bredvid skriptet: fönster kan inte flyttas mellan skrivbord, och regler med skrivbord gör ingenting. Se README för nedladdning.',
    dhkH: 'Skrivbordens kortkommandon',
    dhkHelp: 'AutoHotkey-syntax: + Skift, ^ Ctrl, # Win, ! Alt. Tomt stänger av kortkommandot. Ctrl = växla, Alt = flytta fönstret, Ctrl+Alt = flytta och följ efter.',
    prefixH: 'Sifferprefix',
    prefixHelp: 'Hålls tillsammans med en siffra 1-9 för att adressera det skrivbordet direkt. Observera att ^# och !# tar över Windows egna aktivitetsfältsgenvägar för fästa appar; lämna dem tomma om du vill behålla dessa.',
    hkMoveNext: 'Flytta fönstret till nästa skrivbord', hkMovePrevious: 'Flytta fönstret till föregående skrivbord',
    hkMoveFollowNext: 'Flytta och följ efter till nästa skrivbord', hkMoveFollowPrevious: 'Flytta och följ efter till föregående skrivbord',
    hkMoveMenu: 'Öppna fönstermenyn för aktivt fönster', hkShowName: 'Visa skrivbordsnamnet som överlägg',
    hkSwitchToPrefix: 'Växla till skrivbord N', hkMoveToPrefix: 'Flytta fönstret till skrivbord N', hkMoveFollowToPrefix: 'Flytta och följ efter till skrivbord N',
    taskbarH: 'Aktivitetsfält och systemfält',
    tglNameInTray: 'Visa skrivbordsnamnet i aktivitetsfältet',
    tglWheel: 'Mushjulet över aktivitetsfältet växlar skrivbord', wheelHelp: 'Rulla var som helst på fältet där det inte sitter en knapp.',
    tglArrows: 'Två pilikoner i systemfältet som växlar skrivbord', arrowsHelp: 'Dra ut dem ur överflödet en gång för att hålla dem synliga.',
    modulesH: 'Moduler',
    modulesHelp: 'Varje halva kan stängas av för sig: av betyder inga kortkommandon, inget timerarbete, inga menyval och ingen flik för den.',
    modPositions: 'Lägen - kom ihåg var fönster ska ligga, per skärmuppsättning och dator',
    modDesktops: 'Skrivbord - virtuella skrivbord: växla, flytta, överlägg, etikett i aktivitetsfältet',
    menuH: 'Fönstermeny',
    menuHelp: 'Håll modifieraren och tryck knappen på ett fönster för att öppna menyn. Vanligt högerklick lämnas till appen. Modifieraren är också tangenten positionskortkommandona nedan hålls med.',
    tglMenuOn: 'Aktivera fönstermenyn', lblMenuModifier: 'Modifierare', lblMenuButton: 'Knapp',
    tglMenuWhole: 'Öppnas var som helst i fönstret', menuWholeHelp: 'Av begränsar den till titelraden och överkanten på appar med egenritade titelrader.',
    lblMenuExclude: 'Lämna dessa program i fred',
    menuExcludeHelp: 'Processnamn som reguljärt uttryck, t.ex. (?i)^(msedge|explorer)\\.exe$ - för appar som använder samma kombination själva. Tomt betyder inga undantag.',
    behaveH: 'Lägen',
    tglMove: 'Flytta nya fönster automatiskt', tglSave: 'Spara position vid manuell flytt',
    tglModOnly: 'Bara när {mod} hålls nere vid släppet',
    modOnlyHelp: 'Sparandet blir en avsiktlig gest: en slarvig flytt kan inte skriva över ett omsorgsfullt placerad position. Avsiktliga sparningar ({mod} + S, fönstermenyn, Spara alla) fungerar alltid.',
    tglNotify: 'Notiser',
    managedH: 'Vilka fönster får positioner',
    onlyRules: 'Hantera <b>endast</b> fönster som matchar en regel',
    onlyRulesHelp: 'Av (standard): alla fönster hanteras. Ett fönster som inte matchar någon regel identifieras av sitt program och sin fönsterklass, så alla fönster i samma program delar en position. På: bara fönster som matchar en regel får en position över huvud taget.',
    onlyRulesExeH: 'Endast regler för dessa program',
    onlyRulesExeHelp: 'Program som bara hanteras via regler (ett exenamn per rad). Deras övriga fönster lämnas i fred. Det naturliga valet för en webbläsare: varje popup är ett eget fönster som annars skulle dela position med webbläsarens alla andra fönster.',
    ignoreH: 'Ignorera', ignExeHelp: 'Program (ett exenamn per rad):', ignTitleHelp: 'Titlar som innehåller (en text per rad):',
    managedSavedHint: 'Ändringar här sparas så fort du lämnar fältet.',
    hkH: 'Lägeskortkommandon',
    hkHelp: 'Trycks tillsammans med {mod}. AutoHotkey-tangentnamn (d, F10, Home, Backspace…). Lämna tomt för att stänga av ett.',
    hkOpenUi: 'Öppna DalSegno-fönstret', hkSaveActive: 'Spara det aktiva fönstrets position',
    hkSaveAll: 'Spara alla öppna fönsters positioner', hkApplyAll: 'Flytta alla fönster till sina sparade positioner',
    hkForgetActive: 'Glöm det aktiva fönstrets position', hkToggleMove: 'Växla automatisk flyttning', hkReload: 'Starta om skriptet',
    langH: 'Språk', langHelp: 'Gäller det här fönstret, tray-menyn, fönstermenyn och överlägget.',
    filesH: 'Filer', openIni: 'Öppna filen med sparade positioner…', openConfig: 'Öppna konfigfilen…', reload: 'Läs om inställningar',
    status: (n, total, s) => `${n} sparade positioner för denna skärmuppsättning · ${total} totalt · uppsättning: ${s}`,
    statusDesktops: (n, i) => ` · ${n} skrivbord, du är på ${i}`,
    paused: '⏸ automatisk flyttning är avstängd'
  }
};
function t(id) {
  const s = (STR[lang] || STR.en)[id] ?? STR.en[id] ?? id;
  if (typeof s === 'function') return s;   // formatters, not text
  const mod = (st && st.settings && st.settings.modifier) || 'CapsLock';
  return s.replace(/\{mod\}/g, mod);
}
function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                        .replace(/"/g, '&quot;');
}
function $(id) { return document.getElementById(id); }
const desktopsOn = () => !!(st && st.modules && st.modules.desktops);
const positionsOn = () => !!(st && st.modules && st.modules.positions);

// ── state from AHK ─────────────────────────────────────────────────────
window.receiveState = function (s) {
  st = s;
  awaitingState = false;
  lang = st.settings.lang === 'sv' ? 'sv' : 'en';
  const setups = setupList();
  if (curSetup === null || !setups.includes(curSetup)) curSetup = st.currentSetup;
  document.body.classList.toggle('no-desktops', !desktopsOn());
  $('tabBtnDesktops').hidden = !desktopsOn();
  localizeStatic();
  renderSettings();
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
  const set = (id, key) => { const e = $(id); if (e) e.textContent = t(key); };
  const tip = (id, key) => { const e = $(id); if (e) e.title = t(key); };
  ['tabBtnPositions|tabPositions', 'tabBtnWindows|tabWindows', 'tabBtnDesktops|tabDesktops', 'tabBtnSettings|tabSettings',
   'lblSetup|setupLabel', 'btnAddRule|addRule', 'btnSaveAll|saveAll', 'btnApplyAll|applyAll',
   'thWindow|thWindow', 'thIdentity|thIdentity', 'thActive|thActive', 'thDesktop|thDesktop',
   'thWidth|thWidth', 'thHeight|thHeight',
   'winsHint|winsHint', 'btnRefresh|refresh', 'thProgram|thProgram', 'thTitle|thTitle',
   'thWinDesktop|thWinDesktop', 'thIdentity2|thIdentity', 'thSaved|thSaved',
   'dllNote|dllNote', 'dhkH|dhkH', 'dhkHelp|dhkHelp', 'prefixH|prefixH', 'prefixHelp|prefixHelp',
   'taskbarH|taskbarH', 'lblNameInTray|tglNameInTray', 'lblWheel|tglWheel', 'wheelHelp|wheelHelp',
   'lblArrows|tglArrows', 'arrowsHelp|arrowsHelp',
   'modulesH|modulesH', 'modulesHelp|modulesHelp', 'lblModPositions|modPositions', 'lblModDesktops|modDesktops',
   'menuH|menuH', 'menuHelp|menuHelp', 'lblMenuOn|tglMenuOn', 'lblMenuModifier|lblMenuModifier',
   'lblMenuButton|lblMenuButton', 'lblMenuWhole|tglMenuWhole', 'menuWholeHelp|menuWholeHelp',
   'lblMenuExclude|lblMenuExclude', 'menuExcludeHelp|menuExcludeHelp',
   'behaveH|behaveH', 'lblMove|tglMove', 'lblSave|tglSave', 'lblModOnly|tglModOnly', 'modOnlyHelp|modOnlyHelp',
   'lblNotify|tglNotify', 'managedH|managedH', 'onlyRulesHelp|onlyRulesHelp',
   'onlyRulesExeH|onlyRulesExeH', 'onlyRulesExeHelp|onlyRulesExeHelp', 'ignoreH|ignoreH',
   'ignExeHelp|ignExeHelp', 'ignTitleHelp|ignTitleHelp', 'managedSavedHint|managedSavedHint',
   'hkH|hkH', 'hkHelp|hkHelp', 'langH|langH', 'langHelp|langHelp', 'filesH|filesH',
   'btnOpenPositions|openIni', 'btnOpenConfig|openConfig', 'btnReload|reload'
  ].forEach(pair => { const [id, key] = pair.split('|'); set(id, key); });
  $('lblOnlyRules').innerHTML = t('onlyRules');
  $('btnAddRule').title = t('addRuleTip');
  $('btnSaveAll').title = t('saveAllTip');
  $('btnApplyAll').title = t('applyAllTip');
  [['thWindow', 'thWindowTip'], ['thIdentity', 'thIdentityTip'], ['thActive', 'thActiveTip'],
   ['thDesktop', 'thDesktopTip'], ['thX', 'thXTip'], ['thY', 'thYTip'],
   ['thWidth', 'thWidthTip'], ['thHeight', 'thHeightTip'],
   ['thProgram', 'thProgramTip'], ['thTitle', 'thTitleTip'], ['thWinDesktop', 'thWinDesktopTip'],
   ['thIdentity2', 'thIdentityTip'], ['thSaved', 'thSavedTip']
  ].forEach(([id, key]) => tip(id, key));
  document.querySelectorAll('th.selcol').forEach(el => { el.title = t('selColTip'); });
  updateForgetSel();
  document.querySelectorAll('input[name=lang]').forEach(r => { r.checked = r.value === lang; });
}

// ── settings and desktops tabs ─────────────────────────────────────────
const MANAGED_IDS = ['tglOnlyRules', 'txtRulesOnlyExe', 'txtIgnoreExe', 'txtIgnoreTitle'];

function renderSettings() {
  const s = st.settings;
  $('tglModPositions').checked = !!st.modules.positions;
  $('tglModDesktops').checked = !!st.modules.desktops;
  $('tglMenuOn').checked = !!s.menuOn;
  if (document.activeElement !== $('inMenuModifier')) $('inMenuModifier').value = s.modifier ?? '';
  if (document.activeElement !== $('inMenuButton')) $('inMenuButton').value = s.menuButton ?? '';
  $('tglMenuWhole').checked = !!s.menuWhole;
  if (document.activeElement !== $('inMenuExclude')) $('inMenuExclude').value = s.menuExclude ?? '';
  ['inMenuModifier', 'inMenuButton', 'tglMenuWhole', 'inMenuExclude'].forEach(id => { $(id).disabled = !s.menuOn; });
  $('tglMove').checked = !!s.move;
  $('tglSave').checked = !!s.autosave;
  $('tglModOnly').checked = !!s.modOnly;
  $('tglNotify').checked = !!s.notify;
  $('tglMove').disabled = !positionsOn();
  $('tglSave').disabled = !positionsOn();
  $('tglModOnly').disabled = !positionsOn() || !s.autosave;
  $('tglNotify').disabled = !positionsOn();
  $('tglNameInTray').checked = !!s.nameInTray;
  $('tglWheel').checked = !!s.wheel;
  $('tglArrows').checked = !!s.arrowIcons;
  $('dllNote').hidden = !!s.dll;
}
function renderManaged() {
  const ae = document.activeElement;
  if (ae && MANAGED_IDS.includes(ae.id)) return;   // not under the user's fingers
  $('tglOnlyRules').checked = !!st.settings.rulesOnly;
  $('txtRulesOnlyExe').value = (st.rulesOnlyExe || []).join('\n');
  $('txtIgnoreExe').value = st.ignoreExe.join('\n');
  $('txtIgnoreTitle').value = st.ignoreTitles.join('\n');
}
function postManaged() {
  const lines = id => $(id).value.split('\n').map(x => x.trim()).filter(Boolean);
  post({ action: 'setManaged', rulesOnly: $('tglOnlyRules').checked ? 1 : 0,
         rulesOnlyExe: lines('txtRulesOnlyExe'), ignoreExe: lines('txtIgnoreExe'), ignoreTitles: lines('txtIgnoreTitle') });
}
MANAGED_IDS.forEach(id => $(id).addEventListener('change', postManaged));
const setOpt = (section, name, value) => post({ action: 'setOption', section, name, value });
$('tglModPositions').addEventListener('change', e => post({ action: 'setModule', name: 'Positions', value: e.target.checked ? 1 : 0 }));
$('tglModDesktops').addEventListener('change', e => post({ action: 'setModule', name: 'Desktops', value: e.target.checked ? 1 : 0 }));
$('tglMenuOn').addEventListener('change', e => setOpt('Menu', 'Enabled', e.target.checked ? 1 : 0));
$('tglMenuWhole').addEventListener('change', e => setOpt('Menu', 'WholeWindow', e.target.checked ? 1 : 0));
$('inMenuModifier').addEventListener('change', e => setOpt('Menu', 'Modifier', e.target.value.trim()));
$('inMenuButton').addEventListener('change', e => setOpt('Menu', 'Button', e.target.value.trim()));
$('inMenuExclude').addEventListener('change', e => setOpt('Menu', 'Exclude', e.target.value.trim()));
$('tglNameInTray').addEventListener('change', e => setOpt('Desktops', 'NameInTray', e.target.checked ? 1 : 0));
$('tglWheel').addEventListener('change', e => setOpt('Desktops', 'Wheel', e.target.checked ? 1 : 0));
$('tglArrows').addEventListener('change', e => setOpt('Desktops', 'ArrowIcons', e.target.checked ? 1 : 0));
$('tglMove').addEventListener('change', e => post({ action: 'toggle', name: 'move', value: e.target.checked ? 1 : 0 }));
$('tglSave').addEventListener('change', e => post({ action: 'toggle', name: 'autosave', value: e.target.checked ? 1 : 0 }));
$('tglModOnly').addEventListener('change', e => post({ action: 'toggle', name: 'modOnly', value: e.target.checked ? 1 : 0 }));
$('tglNotify').addEventListener('change', e => post({ action: 'toggle', name: 'notify', value: e.target.checked ? 1 : 0 }));
$('btnSaveAll').addEventListener('click', () => post({ action: 'saveAll' }));
$('btnApplyAll').addEventListener('click', () => post({ action: 'applyAll' }));
$('btnOpenPositions').addEventListener('click', () => post({ action: 'openPositions' }));
$('btnOpenConfig').addEventListener('click', () => post({ action: 'openConfig' }));
$('btnReload').addEventListener('click', () => post({ action: 'reloadConfig' }));
document.querySelectorAll('input[name=lang]').forEach(r =>
  r.addEventListener('change', e => { if (e.target.checked) post({ action: 'setLang', lang: e.target.value }); }));

// ── hotkeys: the CapsLock layer (Settings) and the Win layer (Desktops) ─
const HK_ACTIONS = ['OpenUi', 'SaveActive', 'SaveAll', 'ApplyAll', 'ForgetActive', 'ToggleMove', 'Reload'];
const DHK = ['MoveNext', 'MovePrevious', 'MoveFollowNext', 'MoveFollowPrevious', 'MoveMenu', 'ShowName'];
const PREFIXES = ['SwitchToPrefix', 'MoveToPrefix', 'MoveFollowToPrefix'];

function renderHotkeys() {
  // never rebuild under the user's fingers - a state push can arrive while
  // an input has focus, and blur will re-sync anyway
  if (document.activeElement && document.activeElement.classList &&
      document.activeElement.classList.contains('hkkey')) return;
  const hk = st.settings.hotkeys || {};
  const mod = st.settings.modifier || 'CapsLock';
  $('hkList').innerHTML = HK_ACTIONS.map(name => `
    <div class="hkrow">
      <span class="hkcombo">${esc(mod)} +
        <input class="hkkey" data-name="${name}" value="${esc(hk[name] ?? '')}"></span>
      <span class="hklbl">${esc(t('hk' + name))}</span>
    </div>`).join('');
  const dhk = st.settings.desktopHotkeys || {};
  const rows = names => names.map(n => `
    <div class="hkrow">
      <input class="hkkey wide" data-name="${n}" value="${esc(dhk[n] ?? '')}">
      <span class="hklbl">${esc(t('hk' + n))}</span>
    </div>`).join('');
  $('dhkList').innerHTML = rows(DHK);
  $('prefixList').innerHTML = rows(PREFIXES);
}
document.addEventListener('change', e => {
  if (!e.target.classList || !e.target.classList.contains('hkkey')) return;
  post({ action: 'setHotkey', name: e.target.dataset.name, key: e.target.value.trim() });
});

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

function desktopOptions(sel) {
  const names = (st.desktops && st.desktops.names) || [];
  let o = `<option value="0"${!sel ? ' selected' : ''}>${esc(t('noDesktop'))}</option>`;
  const n = Math.max(names.length, sel || 0);
  for (let i = 1; i <= n; i++)
    o += `<option value="${i}"${i === sel ? ' selected' : ''}>${esc(names[i - 1] || i)}</option>`;
  return o;
}

function patternCell(r, isNew) {
  const a = esc(r.alias || '');
  const exe = r.exe ? (r.exeRegex ? 're:' : '') + r.exe : '';
  return `<span class="pre">${esc(t('appliesPre'))}</span>` +
    `<input type="text" class="r-pattern" data-alias="${a}" value="${esc(r.pattern || '')}" placeholder="${esc(t('patternPh'))}"${isNew ? ' data-new="1"' : ''}>` +
    `<span class="post">${esc(t('appliesPost'))}</span>` +
    `<label class="rx"><input type="checkbox" class="r-regex" data-alias="${a}"${r.regex ? ' checked' : ''}> ${esc(t('regexLbl'))}</label>` +
    `<span class="pre"> · ${esc(t('programLbl'))}</span>` +
    `<input type="text" class="r-exe" data-alias="${a}" value="${esc(exe)}" placeholder="${esc(t('exePh'))}">`;
}

function desktopCell(r) {
  if (!desktopsOn()) return '<td class="deskcell"></td>';
  if (!r) return '<td class="deskcell dim">–</td>';
  return `<td class="deskcell"><select class="r-desktop">${desktopOptions(Number(r.desktop) || 0)}</select>` +
    `<label><input type="checkbox" class="r-follow"${r.follow ? ' checked' : ''}> ${esc(t('followLbl'))}</label></td>`;
}

function posRow(row, idx, count) {
  const p = row.pos, r = row.rule;
  const key = p ? p.key : 'rule:' + r.alias;
  const section = p ? p.section : '';
  const isCur = curSetup === st.currentSetup;
  let applies, ident, active;
  if (row.kind === 'rule') {
    applies = patternCell(r, false);
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
  const canMove = p && isCur && positionsOn() && (row.kind !== 'rule' || r.enabled);
  const off = r && !r.enabled ? ' off' : '';
  const order = row.kind === 'rule'
    ? `<button class="tiny act-up" title="${esc(t('upTip'))}"${idx === 0 ? ' disabled' : ''}>▲</button>` +
      `<button class="tiny act-down" title="${esc(t('downTip'))}"${idx === count - 1 ? ' disabled' : ''}>▼</button>`
    : '';
  return `<tr class="${row.kind}${off}" data-section="${esc(section)}" data-key="${esc(key)}"${r ? ` data-alias="${esc(r.alias)}"` : ''}>
    <td class="selcol">${p ? `<input type="checkbox" class="rowsel"${selPos.has(section) ? ' checked' : ''}>` : ''}</td>
    <td class="applies" title="${esc(tip)}">${applies}${maxBadge}</td>
    <td>${ident}</td>
    <td class="active">${active}</td>
    ${desktopCell(r)}
    ${nums}
    <td class="actions">
      ${canMove ? `<button class="small act-move">${esc(t('moveNow'))}</button>` : ''}
      ${p ? `<button class="small act-forget">${esc(t('forget'))}</button>` : ''}
      ${row.kind === 'rule' ? `<button class="small act-delrule" title="${esc(t('deleteRuleTip'))}">${esc(t('deleteRule'))}</button>` : ''}
      ${order}
    </td></tr>`;
}

function newRuleRow() {
  return `<tr class="rule new">
    <td class="selcol"></td>
    <td class="applies">${patternCell({ alias: '', pattern: '', regex: 0, exe: '' }, true)}</td>
    <td><span class="badge rule">${esc(t('badgeRule'))}: ${esc(t('badgeNew'))}</span></td>
    <td class="active"><input type="checkbox" class="r-enabled" checked disabled></td>
    ${desktopCell({ desktop: 0, follow: 0 })}
    <td class="num dim nopos" colspan="4">${esc(t('noPosYet'))}</td>
    <td class="actions"></td></tr>`;
}

function editingRow() {
  const ae = document.activeElement;
  return !!(ae && $('posBody').contains(ae) && (ae.classList.contains('r-pattern') || ae.classList.contains('r-exe')));
}

function renderPositions() {
  const sel = $('setupSel');
  sel.innerHTML = setupList().map(s =>
    `<option value="${esc(s)}"${s === curSetup ? ' selected' : ''}>` +
    `${esc(s)}${s === st.currentSetup ? esc(t('thisSetup')) : ''}</option>`).join('');
  if (editingRow()) return;   // never rebuild under the user's fingers
  const rows = rowsForSetup();
  const body = $('posBody');
  if (!rows.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="10">${esc(t('posEmpty'))}</td></tr>`;
    selPos.clear();
    updateForgetSel();
    return;
  }
  const ruleCount = rows.filter(r => r.kind === 'rule').length;
  body.innerHTML = rows.map((row, i) => posRow(row, i, ruleCount)).join('');
  const withPos = rows.filter(r => r.pos);
  const shown = new Set(withPos.map(r => r.pos.section));
  for (const s of [...selPos]) if (!shown.has(s)) selPos.delete(s);
  $('selAllPos').checked = withPos.length > 0 && withPos.every(r => selPos.has(r.pos.section));
  updateForgetSel();
}
$('setupSel').addEventListener('change', e => { curSetup = e.target.value; renderPositions(); });

$('btnAddRule').addEventListener('click', () => {
  const body = $('posBody');
  const empty = body.querySelector('.empty-row');
  if (empty) empty.remove();
  if (!body.querySelector('tr.new')) body.insertAdjacentHTML('afterbegin', newRuleRow());
  body.querySelector('tr.new .r-pattern').focus();
});

function ruleFromRow(tr) {
  const desk = tr.querySelector('.r-desktop');
  const follow = tr.querySelector('.r-follow');
  const enabled = tr.querySelector('.r-enabled');
  return {
    pattern: tr.querySelector('.r-pattern').value.trim(),
    regex: tr.querySelector('.r-regex').checked ? 1 : 0,
    exe: tr.querySelector('.r-exe').value.trim(),
    desktop: desk ? Number(desk.value) : 0,
    follow: follow && follow.checked ? 1 : 0,
    enabled: enabled && enabled.checked ? 1 : 0
  };
}

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
  const editable = ['r-pattern', 'r-regex', 'r-exe', 'r-enabled', 'r-desktop', 'r-follow'].some(c => el.classList.contains(c));
  if (!editable) return;
  const r = ruleFromRow(tr);
  if (tr.classList.contains('new')) {
    if (!r.pattern && !r.exe) return;
    awaitingState = true;
    post({ action: 'addRule', pattern: r.pattern, regex: r.regex, exe: r.exe, desktop: r.desktop, follow: r.follow });
    return;
  }
  if (!r.pattern && !r.exe) return;   // a rule needs a text or a program
  awaitingState = true;
  post({ action: 'setRule', alias: tr.dataset.alias, ...r });
});
$('posBody').addEventListener('keydown', e => {
  const isField = e.target.classList.contains('r-pattern') || e.target.classList.contains('r-exe');
  if (!isField) return;
  if (e.key === 'Enter') {
    e.target.blur();                       // commit: change fires on blur
  } else if (e.key === 'Escape') {
    const tr = e.target.closest('tr');
    const r = st && st.rules.find(x => x.alias === tr.dataset.alias);
    e.target.value = r ? (e.target.classList.contains('r-exe') ? ((r.exeRegex ? 're:' : '') + r.exe) : r.pattern) : '';
    e.target.blur();
  }
});
$('posBody').addEventListener('focusout', e => {
  const isField = e.target.classList.contains('r-pattern') || e.target.classList.contains('r-exe');
  if (!isField) return;
  // re-sync the list once the field is left, unless an edit is on its way
  setTimeout(() => { if (!awaitingState && !editingRow()) renderPositions(); }, 0);
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
  const cl = e.target.classList;
  if (cl.contains('act-move')) {
    post({ action: 'moveKey', key: tr.dataset.key });
  } else if (cl.contains('act-forget')) {
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
  } else if (cl.contains('act-delrule')) {
    const alias = tr.dataset.alias;
    if (window.confirm(t('confirmDeleteRule').replace('{0}', alias)))
      post({ action: 'deleteRule', alias });
  } else if (cl.contains('act-up') || cl.contains('act-down')) {
    post({ action: 'moveRule', alias: tr.dataset.alias, dir: cl.contains('act-up') ? -1 : 1 });
  }
});

// ── open windows ───────────────────────────────────────────────────────
function renderWindows() {
  const body = $('winBody');
  if (!st.windows.length) {
    body.innerHTML = `<tr class="empty-row"><td colspan="6">${esc(t('winsEmpty'))}</td></tr>`;
    return;
  }
  const deskCell = w => {
    if (!desktopsOn()) return '<td class="deskcell"></td>';
    const cur = Number(w.desktop) || 0;
    const names = st.desktops.names || [];
    let o = '';
    for (let i = 1; i <= Math.max(names.length, cur); i++)
      o += `<option value="${i}"${i === cur ? ' selected' : ''}>${esc(names[i - 1] || i)}</option>`;
    return `<td class="deskcell">${cur ? `<select class="w-desktop">${o}</select>` : '<span class="dim">–</span>'}</td>`;
  };
  body.innerHTML = st.windows.map(w => w.own ? `
    <tr data-hwnd="${w.hwnd}" class="own" title="${esc(t('ownWinTip'))}">
      <td>${esc(w.exe)}</td>
      <td class="ellip">${esc(w.title)}</td>
      ${desktopsOn() ? `<td class="deskcell dim">${esc(w.desktop || '–')}</td>` : '<td class="deskcell"></td>'}
      <td><span class="dim">–</span></td>
      <td><span class="dim">–</span></td>
      <td class="actions">
        <button class="small" disabled>${esc(t('saveBtn'))}</button>
        <button class="small" disabled>${esc(t('moveHere'))}</button>
        <button class="small" disabled>${esc(t('newRuleBtn'))}</button>
      </td></tr>` : `
    <tr data-hwnd="${w.hwnd}">
      <td>${esc(w.exe)}</td>
      <td class="ellip" title="${esc(w.title)}">${esc(w.title)}${Number(w.n) > 1 ? ` <span class="dim">×${esc(w.n)}</span>` : ''}</td>
      ${deskCell(w)}
      <td>${w.rule ? `<span class="badge rule">${esc(t('badgeRule'))}: ${esc(w.rule)}</span>`
                   : w.managed ? `<span class="badge">${esc(t('badgeStd'))}</span>`
                   : `<span class="dim" title="${esc(t('unmanagedTip'))}">–</span>`}</td>
      <td>${w.saved ? `<span class="ok">${esc(t('savedYes'))}</span>` : '<span class="dim">–</span>'}</td>
      <td class="actions">
        <button class="small act-save" ${w.managed && positionsOn() ? '' : 'disabled'} title="${esc(t('saveTip'))}">${esc(t('saveBtn'))}</button>
        <button class="small act-movewin" ${w.saved ? '' : 'disabled'} title="${esc(t('moveTip'))}">${esc(t('moveHere'))}</button>
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
  else if (e.target.classList.contains('act-rule')) post({ action: 'ruleFromWin', hwnd });
});
$('winBody').addEventListener('change', e => {
  if (!e.target.classList.contains('w-desktop')) return;
  const hwnd = Number(e.target.closest('tr').dataset.hwnd);
  post({ action: 'moveWinDesktop', hwnd, desktop: Number(e.target.value) });
});

// ── status bar ─────────────────────────────────────────────────────────
function renderStatus() {
  const nCur = st.positions.filter(p => p.setup === st.currentSetup).length;
  let text = t('status')(nCur, st.positions.length, st.currentSetup);
  if (desktopsOn() && st.desktops.count) text += t('statusDesktops')(st.desktops.count, st.desktops.index);
  $('status').textContent = text;
  $('statusPause').innerHTML = positionsOn() && !st.settings.move
    ? `<span class="warn">${esc(t('paused'))}</span>` : '';
}

// ── start ──────────────────────────────────────────────────────────────
post({ action: 'ready' });
