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
let addPending = false;    // a NEW rule was posted; the next state names it
// Rules created from the list: shown in the setup they were created in even
// while they have neither desktop nor position (until another setup is
// picked) - otherwise a new rule would vanish before it could get either.
const revealed = new Set();

// ── interface strings ──────────────────────────────────────────────────
const STR = {
  en: {
    tabWindows: 'Windows', tabDesktops: 'Desktops', tabSettings: 'Settings',
    // the two sections
    sectRules: 'Windows with rules', sectFree: 'Windows without rules',
    sectRulesTip: 'What DalSegno acts on in the selected monitor setup: rules, and programs with a saved position. Click to fold.',
    sectFreeTip: 'Open windows no row above covers. They are left where they are. Click to fold.',
    openNow: n => `${n} open`, openNowTip: 'Open windows this row applies to right now:',
    // positions list
    setupLabel: 'Monitor setup:', thisSetup: ' (this)',
    thWindow: 'Applies to', thActive: 'Active', thDesktop: 'Desktop',
    thWidth: 'Width', thHeight: 'Height',
    thWindowTip: 'Which windows the row applies to - that is, which windows share the position. A rule\'s text and program are edited right here and saved when you leave the field. A program with several rows has several kinds of window (main window, dialogs, helper windows); the window class after the text tells them apart. Hover a row for the window the position was saved from.',
    thActiveTip: 'Untick to switch a row off without deleting it: its windows are then left alone, and its saved position waits until it is ticked again. Unticking a program row makes it a rule for the program (same window class), positions included.',
    thDesktopTip: 'The virtual desktop the row\'s windows are moved to when they appear or their title changes into matching. "follow" switches along. Picking a desktop on a program row makes it a rule for the program (same window class), positions included.',
    thXTip: 'Distance from the left edge of the desktop, in pixels.',
    thYTip: 'Distance from the top edge of the desktop, in pixels.',
    thWidthTip: 'Window width in pixels.', thHeightTip: 'Window height in pixels.',
    selColTip: 'Tick rows to remove them in one go.',
    removeSel: 'Remove selected',
    confirmRemoveSel: 'Remove {0} rows? A rule is deleted with its saved positions in every monitor setup; a program row loses its saved positions in every setup.',
    saveAll: 'Save all now', saveAllTip: "Save every open window's current position",
    applyAll: 'Move all now', applyAllTip: 'Move every open window to its saved position ({mod} + Home)',
    addRule: '+ Add rule', addRuleTip: 'A new rule row - type the text and press Enter',
    filterPh: 'Filter…',
    filterTip: 'Show only rows whose program, window class, rule text or saved-from title contains this text. Esc clears it.',
    posNoMatch: 'No rows match "{0}" in this monitor setup.',
    posEmpty: 'No rules and no saved positions for this monitor setup yet. Drag a window where you want it, save with {mod} + S, or hold {mod} and right-click a window.',
    badgeMax: 'maximized',
    moveNow: 'Move now', moveNowTip: 'Move the open windows this row applies to, to the saved position',
    moveNowNoTip: 'Nothing to move to: no saved position in this monitor setup',
    forget: 'Forget', forgetTip: 'Forget the position saved in this monitor setup - the row stays', sure: 'Sure?',
    removeRow: 'Remove',
    removeRuleTip: 'Delete the rule and its saved positions in every monitor setup',
    removeProgTip: 'Remove the program row: its saved positions in every monitor setup',
    confirmRemoveProg: 'Remove the row for {0}, and its saved positions in every monitor setup?',
    orderProgTip: 'Program rows come after every rule and are sorted by program',
    activeGoneTip: 'The rule no longer exists - this position can never apply again',
    appliesPre: 'windows with', appliesPost: 'in the title', programLbl: 'program',
    appliesRuleGone: 'rule "{0}" (no longer exists)', appliesStd: 'all {0} windows',
    appliesRule: 'windows with "{0}" in the title', appliesRuleExe: '{1} windows with "{0}" in the title',
    savedFromTip: 'Saved from: {0}', noPosYet: 'no position yet',
    inertTip: 'This rule has no desktop and no position in this monitor setup yet, so it does nothing here. Pick a desktop, or save a matching window with {mod} + S. Rules are shared by every setup; a rule is listed only in the setups where it has a desktop or a position.',
    patternPh: 'text in the title', exePh: '(any)', regexLbl: 'regex',
    computerLbl: 'computer', computersPh: '(all)',
    computersTip: 'The computers the rule applies on, comma-separated. Empty: every computer. The config is shared between computers through the synced folder.',
    foreignTip: 'This rule applies on {0} only, so it does nothing on {1}.',
    noDesktop: '(none)', followLbl: 'follow',
    confirmDeleteRule: 'Delete the rule for {0}, and its saved positions in every monitor setup?',
    upTip: 'Move the rule up - earlier rules win', downTip: 'Move the rule down',
    // windows without rules
    refresh: 'Refresh', refreshTip: 'Read the open windows again',
    thProgram: 'Program', thTitle: 'Title', thWinDesktop: 'Desktop',
    thProgramTip: 'Executable name of the process owning the window.',
    thTitleTip: 'The window title right now. Rules match against this.',
    thWinDesktopTip: 'The virtual desktop the window is on right now - pick another to move it there.',
    thNowTip: 'Where the window is right now - what a rule made from it would save.',
    makeRule: 'Make a rule…',
    makeRuleTip: 'What the rule applies to (all windows of the program, or windows with a text in the title), its desktop, and whether to save the window\'s position',
    freeEmpty: 'Every open window is covered by a row above.',
    freeNoMatch: 'No open window matches "{0}".',
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
    tglOnScreen: 'Keep Office windows on screen',
    onScreenHelp: 'If Word, Excel or another Office window opens entirely off your monitors, slide it onto the nearest screen.',
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
    statusFiltered: (shown, n) => ` · filter: ${shown} of ${n} rows shown`,
    statusInert: n => ` · ${n} rule${n === 1 ? '' : 's'} with no effect in this setup`,
    statusDesktops: (n, i) => ` · ${n} desktops, on ${i}`,
    paused: '⏸ automatic moving is off'
  },
  sv: {
    tabWindows: 'Fönster', tabDesktops: 'Skrivbord', tabSettings: 'Inställningar',
    sectRules: 'Fönster med regler', sectFree: 'Fönster utan regler',
    sectRulesTip: 'Det DalSegno agerar på i vald skärmuppsättning: regler, och program med sparad position. Klicka för att fälla ihop.',
    sectFreeTip: 'Öppna fönster som ingen rad ovan täcker. De lämnas där de är. Klicka för att fälla ihop.',
    openNow: n => `${n} öppna`, openNowTip: 'Öppna fönster raden gäller just nu:',
    setupLabel: 'Skärmuppsättning:', thisSetup: ' (denna)',
    thWindow: 'Gäller', thActive: 'Aktiv', thDesktop: 'Skrivbord',
    thWidth: 'Bredd', thHeight: 'Höjd',
    thWindowTip: 'Vilka fönster raden gäller - alltså vilka fönster som delar positionen. En regels text och program redigeras direkt här och sparas när du lämnar fältet. Ett program med flera rader har flera sorters fönster (huvudfönster, dialoger, hjälpfönster); fönsterklassen efter texten skiljer dem åt. Håll muspekaren över raden för att se fönstret positionen sparades från.',
    thActiveTip: 'Kryssa ur för att stänga av en rad utan att ta bort den: dess fönster lämnas då i fred, och den sparade positionen väntar tills raden kryssas i igen. Kryssar du ur en programrad blir den en regel för programmet (samma fönsterklass), med sina positioner.',
    thDesktopTip: 'Det virtuella skrivbord radens fönster flyttas till när de dyker upp eller deras titel ändras till att matcha. "följ efter" växlar också dit. Väljer du skrivbord på en programrad blir den en regel för programmet (samma fönsterklass), med sina positioner.',
    thXTip: 'Avstånd från skrivbordets vänsterkant, i bildpunkter.',
    thYTip: 'Avstånd från skrivbordets överkant, i bildpunkter.',
    thWidthTip: 'Fönstrets bredd i bildpunkter.', thHeightTip: 'Fönstrets höjd i bildpunkter.',
    selColTip: 'Kryssa i rader för att ta bort dem i ett svep.',
    removeSel: 'Ta bort markerade',
    confirmRemoveSel: 'Ta bort {0} rader? En regel tas bort med sina sparade positioner i alla skärmuppsättningar; en programrad förlorar sina sparade positioner i alla uppsättningar.',
    saveAll: 'Spara alla nu', saveAllTip: 'Spara alla öppna fönsters nuvarande positioner',
    applyAll: 'Flytta alla nu', applyAllTip: 'Flytta alla öppna fönster till sina sparade positioner ({mod} + Home)',
    addRule: '+ Lägg till regel', addRuleTip: 'En ny regelrad - skriv texten och tryck Enter',
    filterPh: 'Filtrera…',
    filterTip: 'Visa bara rader vars program, fönsterklass, regeltext eller ursprungsfönster innehåller texten. Esc rensar.',
    posNoMatch: 'Inga rader matchar "{0}" i den här skärmuppsättningen.',
    posEmpty: 'Inga regler och inga sparade positioner för den här skärmuppsättningen ännu. Dra ett fönster dit du vill ha det, spara med {mod} + S, eller håll {mod} och högerklicka på ett fönster.',
    badgeMax: 'maximerat',
    moveNow: 'Flytta nu', moveNowTip: 'Flytta de öppna fönster raden gäller till den sparade positionen',
    moveNowNoTip: 'Inget att flytta till: ingen sparad position i den här skärmuppsättningen',
    forget: 'Glöm', forgetTip: 'Glöm positionen som sparats i den här skärmuppsättningen - raden är kvar', sure: 'Säkert?',
    removeRow: 'Ta bort',
    removeRuleTip: 'Ta bort regeln och dess sparade positioner i alla skärmuppsättningar',
    removeProgTip: 'Ta bort programraden: dess sparade positioner i alla skärmuppsättningar',
    confirmRemoveProg: 'Ta bort raden för {0}, och dess sparade positioner i alla skärmuppsättningar?',
    orderProgTip: 'Programrader kommer efter alla regler och sorteras efter program',
    activeGoneTip: 'Regeln finns inte längre - den här positionen kan aldrig gälla igen',
    appliesPre: 'fönster med', appliesPost: 'i titeln', programLbl: 'program',
    appliesRuleGone: 'regeln "{0}" (finns inte längre)', appliesStd: 'alla {0}-fönster',
    appliesRule: 'fönster med "{0}" i titeln', appliesRuleExe: '{1}-fönster med "{0}" i titeln',
    savedFromTip: 'Sparat från: {0}', noPosYet: 'ingen position ännu',
    inertTip: 'Regeln har varken skrivbord eller position i den här skärmuppsättningen ännu och gör därför ingenting här. Välj ett skrivbord, eller spara ett matchande fönster med {mod} + S. Reglerna är gemensamma för alla uppsättningar; en regel visas bara i de uppsättningar där den har skrivbord eller position.',
    patternPh: 'text i titeln', exePh: '(alla)', regexLbl: 'regex',
    computerLbl: 'dator', computersPh: '(alla)',
    computersTip: 'De datorer regeln gäller på, kommaseparerade. Tomt: alla datorer. Inställningarna delas mellan datorerna via den synkade mappen.',
    foreignTip: 'Regeln gäller bara på {0} och gör därför ingenting på {1}.',
    noDesktop: '(inget)', followLbl: 'följ efter',
    confirmDeleteRule: 'Ta bort regeln för {0}, och dess sparade positioner i alla skärmuppsättningar?',
    upTip: 'Flytta regeln uppåt - tidigare regler vinner', downTip: 'Flytta regeln nedåt',
    refresh: 'Uppdatera', refreshTip: 'Läs in de öppna fönstren igen',
    thProgram: 'Program', thTitle: 'Titel', thWinDesktop: 'Skrivbord',
    thProgramTip: 'Namnet på programfilen som äger fönstret.',
    thTitleTip: 'Fönstrets titel just nu. Regler matchas mot den.',
    thWinDesktopTip: 'Det virtuella skrivbord fönstret ligger på just nu - välj ett annat för att flytta det dit.',
    thNowTip: 'Var fönstret ligger just nu - det en regel gjord av fönstret skulle spara.',
    makeRule: 'Gör regel…',
    makeRuleTip: 'Vad regeln ska gälla (alla programmets fönster, eller fönster med en text i titeln), dess skrivbord, och om fönstrets position ska sparas',
    freeEmpty: 'Alla öppna fönster täcks av en rad ovan.',
    freeNoMatch: 'Inget öppet fönster matchar "{0}".',
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
    tglOnScreen: 'Håll Office-fönster på skärmen',
    onScreenHelp: 'Om ett Word-, Excel- eller annat Office-fönster öppnas helt utanför skärmarna dras det in på närmaste skärm.',
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
    statusFiltered: (shown, n) => ` · filter: ${shown} av ${n} rader visas`,
    statusInert: n => ` · ${n} ${n === 1 ? 'regel' : 'regler'} utan verkan i denna uppsättning`,
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
  // a rule created from the list has neither desktop nor position yet: it
  // would fold away the moment it appears, so it is kept in view
  if (addPending && st) {
    const prev = new Set(st.rules.map(r => r.alias));
    const added = s.rules.find(r => !prev.has(r.alias));
    if (added) revealed.add(added.alias);
  }
  addPending = false;
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
  ['tabBtnWindows|tabWindows', 'tabBtnDesktops|tabDesktops', 'tabBtnSettings|tabSettings',
   'lblSetup|setupLabel', 'btnAddRule|addRule', 'btnSaveAll|saveAll', 'btnApplyAll|applyAll',
   'sectRulesLbl|sectRules', 'sectFreeLbl|sectFree',
   'thWindow|thWindow', 'thActive|thActive', 'thDesktop|thDesktop',
   'thWidth|thWidth', 'thHeight|thHeight',
   'btnRefresh|refresh', 'thProgram|thProgram', 'thTitle|thTitle',
   'thWinDesktop|thWinDesktop', 'thWidth2|thWidth', 'thHeight2|thHeight',
   'dllNote|dllNote', 'dhkH|dhkH', 'dhkHelp|dhkHelp', 'prefixH|prefixH', 'prefixHelp|prefixHelp',
   'taskbarH|taskbarH', 'lblNameInTray|tglNameInTray', 'lblWheel|tglWheel', 'wheelHelp|wheelHelp',
   'lblArrows|tglArrows', 'arrowsHelp|arrowsHelp',
   'modulesH|modulesH', 'modulesHelp|modulesHelp', 'lblModPositions|modPositions', 'lblModDesktops|modDesktops',
   'menuH|menuH', 'menuHelp|menuHelp', 'lblMenuOn|tglMenuOn', 'lblMenuModifier|lblMenuModifier',
   'lblMenuButton|lblMenuButton', 'lblMenuWhole|tglMenuWhole', 'menuWholeHelp|menuWholeHelp',
   'lblMenuExclude|lblMenuExclude', 'menuExcludeHelp|menuExcludeHelp',
   'behaveH|behaveH', 'lblMove|tglMove', 'lblSave|tglSave', 'lblModOnly|tglModOnly', 'modOnlyHelp|modOnlyHelp',
   'lblNotify|tglNotify', 'lblOnScreen|tglOnScreen', 'onScreenHelp|onScreenHelp', 'managedH|managedH', 'onlyRulesHelp|onlyRulesHelp',
   'onlyRulesExeH|onlyRulesExeH', 'onlyRulesExeHelp|onlyRulesExeHelp', 'ignoreH|ignoreH',
   'ignExeHelp|ignExeHelp', 'ignTitleHelp|ignTitleHelp', 'managedSavedHint|managedSavedHint',
   'hkH|hkH', 'hkHelp|hkHelp', 'langH|langH', 'langHelp|langHelp', 'filesH|filesH',
   'btnOpenPositions|openIni', 'btnOpenConfig|openConfig', 'btnReload|reload'
  ].forEach(pair => { const [id, key] = pair.split('|'); set(id, key); });
  $('lblOnlyRules').innerHTML = t('onlyRules');
  $('btnAddRule').title = t('addRuleTip');
  $('posFilter').placeholder = t('filterPh');
  $('posFilter').title = t('filterTip');
  $('btnSaveAll').title = t('saveAllTip');
  $('btnApplyAll').title = t('applyAllTip');
  $('btnRefresh').title = t('refreshTip');
  [['thWindow', 'thWindowTip'], ['thActive', 'thActiveTip'],
   ['thDesktop', 'thDesktopTip'], ['thX', 'thXTip'], ['thY', 'thYTip'],
   ['thWidth', 'thWidthTip'], ['thHeight', 'thHeightTip'],
   ['thProgram', 'thProgramTip'], ['thTitle', 'thTitleTip'], ['thWinDesktop', 'thWinDesktopTip'],
   ['thX2', 'thNowTip'], ['thY2', 'thNowTip'], ['thWidth2', 'thNowTip'], ['thHeight2', 'thNowTip'],
   ['sectRules', 'sectRulesTip'], ['sectFree', 'sectFreeTip']
  ].forEach(([id, key]) => tip(id, key));
  document.querySelectorAll('th.selcol').forEach(el => { el.title = t('selColTip'); });
  $('btnAddRule').textContent = t('addRule');
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
  $('tglOnScreen').checked = !!s.keepOnScreen;
  $('tglMove').disabled = !positionsOn();
  $('tglSave').disabled = !positionsOn();
  $('tglModOnly').disabled = !positionsOn() || !s.autosave;
  $('tglNotify').disabled = !positionsOn();
  $('tglOnScreen').disabled = !positionsOn();
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
$('tglOnScreen').addEventListener('change', e => post({ action: 'toggle', name: 'keepOnScreen', value: e.target.checked ? 1 : 0 }));
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
let posFilter = '';         // the toolbar filter, lower-cased

// A rule in words, the way the save dialog and the notifications put it:
// "windows with X in the title", "Viewer.exe windows with X in the title" or
// "all Viewer.exe windows". The rule's alias is its key in the config and
// positions files, generated from the text when the rule is created; it is
// never shown - the text is what the user knows the rule by.
function ruleText(r) {
  if (!r) return '';
  if (!r.pattern) return t('appliesStd').replace('{0}', r.exe);
  if (r.exe) return t('appliesRuleExe').replace('{0}', r.pattern).replace('{1}', r.exe);
  return t('appliesRule').replace('{0}', r.pattern);
}
const ruleByAlias = alias => (st && st.rules.find(r => r.alias === alias)) || null;

// The text a row can be found by: program, window class and saved-from
// title for a position; text and program for a rule.
function rowText(row) {
  const parts = [];
  if (row.rule) parts.push(row.rule.pattern, row.rule.exe, row.rule.cls);
  if (row.pos) parts.push(row.pos.key, row.pos.info);
  if (!row.pos && !row.rule) parts.push(row.kind);
  return parts.filter(Boolean).join(' ').toLowerCase();
}
const rowMatches = row => !posFilter || rowText(row).includes(posFilter);

function updateForgetSel() {
  const b = $('btnForgetSel');
  b.disabled = !selPos.size;
  b.textContent = t('removeSel') + (selPos.size ? ` (${selPos.size})` : '');
}
// a row's identity key: what the selection, Move now and Remove act on
const rowKey = row => row.pos ? row.pos.key : 'rule:' + row.rule.alias;

function rowsForSetup(setup = curSetup) {
  const pos = st.positions.filter(p => p.setup === setup);
  const byKey = new Map(pos.map(p => [p.key, p]));
  // inert: a rule with no desktop and no position in this setup - it does
  // nothing here (the rule table is shared by every setup)
  const pc = setupComputer(setup);
  const rows = st.rules.map(r => {
    const pos = byKey.get('rule:' + r.alias) || null;
    return { kind: 'rule', rule: r, pos, foreign: !ruleOnComputer(r, pc),
             inert: !pos && !(Number(r.desktop) > 0) };
  });
  const known = new Set(st.rules.map(r => 'rule:' + r.alias));
  // the rules in their own order (it decides which wins), then positions of
  // rules that no longer exist, then the program rows sorted by program and
  // class so that one program's rows sit together
  const rest = pos.filter(p => !known.has(p.key))
    .map(p => ({ kind: p.key.startsWith('rule:') ? 'gone' : 'std', rule: null, pos: p }));
  const cmp = (a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' });
  rest.sort((a, b) => (a.kind === 'gone') !== (b.kind === 'gone') ? (a.kind === 'gone' ? -1 : 1)
                    : cmp(a.pos.key.split('|')[0], b.pos.key.split('|')[0]) || cmp(a.pos.key, b.pos.key));
  return rows.concat(rest);
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
    `<input type="text" class="r-exe" data-alias="${a}" value="${esc(exe)}" placeholder="${esc(t('exePh'))}">` +
    `<span class="pre"> · ${esc(t('computerLbl'))}</span>` +
    `<input type="text" class="r-computers" data-alias="${a}" value="${esc(r.computers || '')}" placeholder="${esc(t('computersPh'))}" title="${esc(t('computersTip'))}">`;
}

// the computer a setup key belongs to (its last segment), and whether a
// rule applies there - a rule for other computers is listed dimmed
const setupComputer = setup => (String(setup || '').split('_').pop() || '').toLowerCase();
const ruleOnComputer = (r, pc) => !r.computers ||
  r.computers.split(',').map(s => s.trim().toLowerCase()).includes(pc);

function desktopCell(r, disabled = false) {
  if (!desktopsOn()) return '<td class="deskcell"></td>';
  const dis = disabled ? ' disabled' : '';
  return `<td class="deskcell"><select class="r-desktop"${dis}>${desktopOptions(Number(r.desktop) || 0)}</select>` +
    `<label><input type="checkbox" class="r-follow"${r.follow ? ' checked' : ''}${dis}> ${esc(t('followLbl'))}</label></td>`;
}

// programs with more than one row in the list being rendered: their rows
// carry the window class, which is what tells them apart
let multiExe = new Set();

// The open windows by identity key, so a row can say how many it applies
// to right now (the Windows-without-rules section shows the rest).
function openByKey() {
  const m = new Map();
  for (const w of st.windows) {
    if (w.own || !w.key) continue;
    if (!m.has(w.key)) m.set(w.key, []);
    m.get(w.key).push(w);
  }
  return m;
}
let openNow = new Map();
function openBadge(key) {
  const wins = openNow.get(key);
  if (!wins) return '';
  const n = wins.reduce((s, w) => s + (Number(w.n) || 1), 0);
  const titles = wins.map(w => w.title + (Number(w.n) > 1 ? ` ×${w.n}` : '')).join('\n');
  return `<span class="open" title="${esc(t('openNowTip') + '\n' + titles)}">· ${esc(t('openNow')(n))}</span>`;
}

// Every row has the same controls - tick box, Active, Desktop, Move now,
// Forget, Remove, ▲▼ - disabled where they cannot apply, so the eye reads
// one kind of row. idx/count: the rule's place among the rules ON SCREEN;
// the ▲▼ buttons step over the ones this setup does not list.
function posRow(row, idx, count) {
  const p = row.pos, r = row.rule;
  const key = rowKey(row);
  const section = p ? p.section : '';
  const isCur = curSetup === st.currentSetup;
  let applies, active, desk;
  if (row.kind === 'rule') {
    // a rule narrowed to one window class (a promoted program row) shows it
    applies = patternCell(r, false) + (r.cls ? `<span class="cls">${esc(r.cls)}</span>` : '');
    active = `<input type="checkbox" class="r-enabled" data-alias="${esc(r.alias)}"${r.enabled ? ' checked' : ''} title="${esc(t('thActiveTip'))}">`;
    desk = desktopCell(r);
  } else if (row.kind === 'gone') {
    // only the alias is left of a deleted rule - it is what the row is named by
    applies = esc(t('appliesRuleGone').replace('{0}', key.slice(5)));
    active = `<input type="checkbox" disabled title="${esc(t('activeGoneTip'))}">`;
    desk = desktopCell({ desktop: 0, follow: 0 }, true);
  } else {
    // exe|class: "all X windows", plus the class when the program has other
    // rows too (its dialogs and helper windows have classes of their own).
    // Active and Desktop are live: touching either turns the row into a rule
    // for the program and class (promoteProgram), positions included.
    const exe = key.split('|')[0], cls = key.split('|').slice(1).join('|');
    applies = esc(t('appliesStd').replace('{0}', exe)) +
      (multiExe.has(exe.toLowerCase()) ? `<span class="cls">${esc(cls)}</span>` : '');
    active = `<input type="checkbox" class="p-enabled" checked title="${esc(t('thActiveTip'))}">`;
    desk = desktopCell({ desktop: 0, follow: 0 });
  }
  // a position saved from a maximized window: the numbers are the rectangle
  // it restores to (which decides the monitor), and the window is maximized
  // there - the badge sits with the size it qualifies
  const maxBadge = p && String(p.max) === '1' ? ` <span class="badge">${esc(t('badgeMax'))}</span>` : '';
  const tip = row.foreign ? t('foreignTip').replace('{0}', r.computers).replace('{1}', setupComputer(curSetup))
    : row.inert ? t('inertTip') : p ? t('savedFromTip').replace('{0}', p.info || key) + '\n' + key : key;
  const nums = p
    ? `<td class="num">${esc(p.x)}</td><td class="num">${esc(p.y)}</td><td class="num">${esc(p.w)}</td><td class="num">${esc(p.h)}${maxBadge}</td>`
    : `<td class="num dim nopos" colspan="4">${esc(t('noPosYet'))}</td>`;
  const canMove = p && isCur && positionsOn() && (row.kind !== 'rule' || r.enabled);
  const off = r && !r.enabled ? ' off' : '';
  const isRule = row.kind === 'rule';
  const btn = (cls, label, tipKey, enabled) =>
    `<button class="small ${cls}" title="${esc(t(tipKey))}"${enabled ? '' : ' disabled'}>${esc(t(label))}</button>`;
  return `<tr class="${row.kind}${off}${row.inert ? ' inert' : ''}${row.foreign ? ' foreign' : ''}" data-section="${esc(section)}" data-key="${esc(key)}"${r ? ` data-alias="${esc(r.alias)}"` : ''}>
    <td class="selcol"><input type="checkbox" class="rowsel"${selPos.has(key) ? ' checked' : ''}></td>
    <td class="applies" title="${esc(tip)}">${applies}${openBadge(key)}</td>
    <td class="active">${active}</td>
    ${desk}
    ${nums}
    <td class="actions">
      ${btn('act-move', 'moveNow', canMove ? 'moveNowTip' : 'moveNowNoTip', canMove)}
      ${btn('act-forget', 'forget', 'forgetTip', !!p)}
      ${btn('act-delrule', 'removeRow', isRule ? 'removeRuleTip' : 'removeProgTip', true)}
      <button class="tiny act-up" title="${esc(t(isRule ? 'upTip' : 'orderProgTip'))}"${!isRule || idx === 0 ? ' disabled' : ''}>▲</button>
      <button class="tiny act-down" title="${esc(t(isRule ? 'downTip' : 'orderProgTip'))}"${!isRule || idx === count - 1 ? ' disabled' : ''}>▼</button>
    </td></tr>`;
}

function newRuleRow() {
  return `<tr class="rule new">
    <td class="selcol"></td>
    <td class="applies">${patternCell({ alias: '', pattern: '', regex: 0, exe: '', computers: st.computer || '' }, true)}</td>
    <td class="active"><input type="checkbox" class="r-enabled" checked disabled></td>
    ${desktopCell({ desktop: 0, follow: 0 })}
    <td class="num dim nopos" colspan="4">${esc(t('noPosYet'))}</td>
    <td class="actions"></td></tr>`;
}

// The rows this setup lists: a rule only where it has a desktop or a
// position (the rule table is shared by every setup), plus the rules just
// created here.
const listed = row => !row.inert || revealed.has(row.rule.alias);

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
  openNow = openByKey();
  renderFree();
  const all = rowsForSetup().filter(listed);
  const rows = all.filter(rowMatches);
  const body = $('posBody');
  $('sectRulesCount').textContent = posFilter && rows.length !== all.length ? `${rows.length} / ${all.length}` : `${all.length}`;
  if (!rows.length) {
    const msg = all.length ? t('posNoMatch').replace('{0}', $('posFilter').value.trim()) : t('posEmpty');
    body.innerHTML = `<tr class="empty-row"><td colspan="9">${esc(msg)}</td></tr>`;
    selPos.clear();
    updateForgetSel();
    return;
  }
  // the up/down buttons order the rules among the listed rules, filtered or not
  const rulesListed = all.filter(r => r.kind === 'rule');
  const exes = rows.filter(r => r.kind === 'std').map(r => r.pos.key.split('|')[0].toLowerCase());
  multiExe = new Set(exes.filter((e, i) => exes.indexOf(e) !== i));
  body.innerHTML = rows.map(row => posRow(row, rulesListed.indexOf(row), rulesListed.length)).join('');
  const shown = new Set(rows.map(rowKey));
  for (const k of [...selPos]) if (!shown.has(k)) selPos.delete(k);
  $('selAllPos').checked = rows.length > 0 && rows.every(r => selPos.has(rowKey(r)));
  updateForgetSel();
}
$('setupSel').addEventListener('change', e => { curSetup = e.target.value; revealed.clear(); renderPositions(); renderStatus(); });

// the filter lives in the toolbar, not the table, so a rebuild never steals
// its focus; the selection follows the visible rows (Forget selected only
// ever removes what is on screen)
$('posFilter').addEventListener('input', e => {
  posFilter = e.target.value.trim().toLowerCase();
  if (st) { renderPositions(); renderStatus(); }
});
$('posFilter').addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  e.target.value = '';
  posFilter = '';
  if (st) { renderPositions(); renderStatus(); }
});

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
    computers: (tr.querySelector('.r-computers') || { value: '' }).value.trim(),
    desktop: desk ? Number(desk.value) : 0,
    follow: follow && follow.checked ? 1 : 0,
    enabled: enabled && enabled.checked ? 1 : 0
  };
}

// edits in a row are saved the moment the field is left (or Enter is pressed)
$('posBody').addEventListener('change', e => {
  const el = e.target;
  if (el.classList.contains('rowsel')) {
    const key = el.closest('tr').dataset.key;
    if (el.checked) selPos.add(key); else selPos.delete(key);
    $('selAllPos').checked = [...$('posBody').querySelectorAll('.rowsel')].every(c => c.checked);
    updateForgetSel();
    return;
  }
  const tr = el.closest('tr');
  if (!tr) return;
  if (tr.classList.contains('std')) {
    // a program row: Active or Desktop touched - it becomes a rule
    const desk = tr.querySelector('.r-desktop'), follow = tr.querySelector('.r-follow');
    awaitingState = true;
    post({ action: 'promoteProgram', key: tr.dataset.key,
           desktop: desk ? Number(desk.value) : 0, follow: follow && follow.checked ? 1 : 0,
           enabled: tr.querySelector('.p-enabled').checked ? 1 : 0 });
    return;
  }
  const editable = ['r-pattern', 'r-regex', 'r-exe', 'r-computers', 'r-enabled', 'r-desktop', 'r-follow'].some(c => el.classList.contains(c));
  if (!editable) return;
  const r = ruleFromRow(tr);
  if (tr.classList.contains('new')) {
    if (!r.pattern && !r.exe) return;
    awaitingState = true;
    addPending = true;
    post({ action: 'addRule', pattern: r.pattern, regex: r.regex, exe: r.exe, computers: r.computers, desktop: r.desktop, follow: r.follow });
    return;
  }
  if (!r.pattern && !r.exe) return;   // a rule needs a text or a program
  awaitingState = true;
  post({ action: 'setRule', alias: tr.dataset.alias, ...r });
});
$('posBody').addEventListener('keydown', e => {
  const isField = ['r-pattern', 'r-exe', 'r-computers'].some(c => e.target.classList.contains(c));
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
  const isField = ['r-pattern', 'r-exe', 'r-computers'].some(c => e.target.classList.contains(c));
  if (!isField) return;
  // re-sync the list once the field is left, unless an edit is on its way
  setTimeout(() => { if (!awaitingState && !editingRow()) renderPositions(); }, 0);
});
$('selAllPos').addEventListener('change', e => {
  $('posBody').querySelectorAll('tr[data-key]').forEach(tr => {
    if (e.target.checked) selPos.add(tr.dataset.key); else selPos.delete(tr.dataset.key);
  });
  renderPositions();
});
// Remove selected: a rule goes with its positions everywhere (deleteRule),
// a program row or a dead rule's position with its positions everywhere
// (forgetKey)
$('btnForgetSel').addEventListener('click', () => {
  if (!selPos.size) return;
  if (!window.confirm(t('confirmRemoveSel').replace('{0}', selPos.size))) return;
  for (const key of selPos) {
    const alias = key.startsWith('rule:') ? key.slice(5) : '';
    if (alias && ruleByAlias(alias)) post({ action: 'deleteRule', alias });
    else post({ action: 'forgetKey', key });
  }
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
    const r = alias ? ruleByAlias(alias) : null;
    if (r) {
      if (window.confirm(t('confirmDeleteRule').replace('{0}', ruleText(r))))
        post({ action: 'deleteRule', alias });
    } else {
      const key = tr.dataset.key;
      const what = key.startsWith('rule:') ? t('appliesRuleGone').replace('{0}', key.slice(5))
                                           : t('appliesStd').replace('{0}', key.split('|')[0]);
      if (window.confirm(t('confirmRemoveProg').replace('{0}', what)))
        post({ action: 'forgetKey', key });
    }
  } else if (cl.contains('act-up') || cl.contains('act-down')) {
    // one step in the list may be several in the rule table, when rules
    // this setup does not list lie in between: move past them all
    const dir = cl.contains('act-up') ? -1 : 1;
    const aliases = st.rules.map(r => r.alias);
    const shown = new Set(rowsForSetup().filter(r => r.kind === 'rule' && listed(r)).map(r => r.rule.alias));
    let i = aliases.indexOf(tr.dataset.alias), steps = 0;
    do { i += dir; steps++; } while (i >= 0 && i < aliases.length && !shown.has(aliases[i]));
    if (i < 0 || i >= aliases.length) return;
    for (let n = 0; n < steps; n++) post({ action: 'moveRule', alias: tr.dataset.alias, dir });
  }
});

// ── windows without rules ──────────────────────────────────────────────
// The open windows no row of the first section covers - in the CURRENT
// setup, whatever setup the dropdown shows: this section is the here and
// now. DalSegno's own window is never listed; it needs no rule.
function renderFree() {
  const body = $('winBody');
  const covered = new Set(rowsForSetup(st.currentSetup).filter(listed)
    .map(r => r.pos ? r.pos.key : 'rule:' + r.rule.alias));
  const all = st.windows.filter(w => !w.own && !covered.has(w.key));
  const rows = all.filter(w => !posFilter || (w.exe + ' ' + w.title).toLowerCase().includes(posFilter));
  $('sectFreeCount').textContent = posFilter && rows.length !== all.length ? `${rows.length} / ${all.length}` : `${all.length}`;
  if (!rows.length) {
    const msg = all.length ? t('freeNoMatch').replace('{0}', $('posFilter').value.trim()) : t('freeEmpty');
    body.innerHTML = `<tr class="empty-row"><td colspan="8">${esc(msg)}</td></tr>`;
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
  const num = v => `<td class="num">${v === '' || v === undefined ? '<span class="dim">–</span>' : esc(v)}</td>`;
  body.innerHTML = rows.map(w => `
    <tr data-hwnd="${w.hwnd}">
      <td>${esc(w.exe)}</td>
      <td class="title" title="${esc(w.title)}">${esc(w.title)}${Number(w.n) > 1 ? ` <span class="dim">×${esc(w.n)}</span>` : ''}</td>
      ${deskCell(w)}
      ${num(w.x)}${num(w.y)}${num(w.w)}${num(w.h)}
      <td class="actions">
        <button class="small act-rule" title="${esc(t('makeRuleTip'))}">${esc(t('makeRule'))}</button>
      </td></tr>`).join('');
}
$('btnRefresh').addEventListener('click', () => post({ action: 'refresh' }));
$('winBody').addEventListener('click', e => {
  const tr = e.target.closest('tr');
  if (!tr || !tr.dataset.hwnd) return;
  if (e.target.classList.contains('act-rule')) post({ action: 'ruleFromWin', hwnd: Number(tr.dataset.hwnd) });
});

// the section headers fold their table; the choice is remembered per browser
const folded = (() => { try { return JSON.parse(localStorage.getItem('folded') || '{}'); } catch { return {}; } })();
function applyFolds() {
  document.querySelectorAll('.sect').forEach(h => {
    const on = !!folded[h.dataset.sect];
    h.classList.toggle('collapsed', on);
    h.nextElementSibling.hidden = on;
  });
}
document.querySelectorAll('.sect').forEach(h => h.addEventListener('click', () => {
  folded[h.dataset.sect] = !folded[h.dataset.sect];
  try { localStorage.setItem('folded', JSON.stringify(folded)); } catch {}
  applyFolds();
}));
applyFolds();
$('winBody').addEventListener('change', e => {
  if (!e.target.classList.contains('w-desktop')) return;
  const hwnd = Number(e.target.closest('tr').dataset.hwnd);
  post({ action: 'moveWinDesktop', hwnd, desktop: Number(e.target.value) });
});

// ── status bar ─────────────────────────────────────────────────────────
function renderStatus() {
  const nCur = st.positions.filter(p => p.setup === st.currentSetup).length;
  let text = t('status')(nCur, st.positions.length, st.currentSetup);
  const all = rowsForSetup();
  if (posFilter) {
    const shown = all.filter(listed);
    text += t('statusFiltered')(shown.filter(rowMatches).length, shown.length);
  }
  const inert = all.filter(r => !listed(r)).length;
  if (inert) text += t('statusInert')(inert);
  if (desktopsOn() && st.desktops.count) text += t('statusDesktops')(st.desktops.count, st.desktops.index);
  $('status').textContent = text;
  $('statusPause').innerHTML = positionsOn() && !st.settings.move
    ? `<span class="warn">${esc(t('paused'))}</span>` : '';
}

// ── start ──────────────────────────────────────────────────────────────
post({ action: 'ready' });
