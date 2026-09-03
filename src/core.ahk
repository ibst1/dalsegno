; =============================================================================
;  DalSegno Window Manager - core
;
;  What both modules need: the config file, window identity, the rule table,
;  one window scan, the window menu with its dialog, the tray, language and
;  the error log. The modules (positions.ahk, desktops.ahk) hang off the
;  hooks defined here: PositionsPlace / DesktopRuleSweep from the scan,
;  their items in the window menu, their toggles in the tray.
; =============================================================================

; --- Files -------------------------------------------------------------------
; Both live next to the script. The UTF-16 BOM is required for the Windows ini
; functions to handle non-ASCII titles - without it they are read as garbage.
configIni := A_ScriptDir "\DalSegno config.ini"
posIni    := A_ScriptDir "\DalSegno positions.ini"

; --- Modules ----------------------------------------------------------------
g_modPositions := true
g_modDesktops  := true

; --- Settings (config file) ----------------------------------------------------
g_lang       := "sv"           ; [General] Language
g_modifier   := "CapsLock"     ; [Menu] Modifier - held for every hotkey and the menu
g_menuButton := "RButton"      ; [Menu] Button
g_menuOn     := true           ; [Menu] Enabled
g_menuWhole  := true           ; [Menu] WholeWindow - anywhere in the window, not just the title bar
g_menuExclude := ""            ; [Menu] Exclude - process regex left alone
g_menuKeys := []               ; what ApplyMenuHotkey registered, so a reload can undo it
g_menuOpen := false            ; our window menu is showing (drives click handling)
g_ruleDlg := 0                 ; the window menu's save/rule dialog, one at a time

; Action hotkeys: key names pressed together with the modifier ([Hotkeys]).
g_hk := Map("OpenUi", "d", "SaveActive", "s", "SaveAll", "a"
    , "ApplyAll", "Home", "ForgetActive", "Backspace"
    , "ToggleMove", "F10", "Reload", "F5")
g_actionKeys := []             ; the plain keys registered under the modifier

; --- Rules and which windows are managed --------------------------------------
titleRules   := []   ; { alias, pattern, regex, exe, exeRegex, desktop, follow, enabled }
ignoreExe    := []   ; exe names never to touch
ignoreTitles := []   ; title fragments never to touch
rulesOnlyExe := []   ; exe names managed ONLY through rules (browsers)
rulesOnly    := false

; --- Scan state ------------------------------------------------------------------
; winInfo: hwnd -> { seen, setup, done, title }
;   seen   tick when the window was first noticed; new windows get
;          PLACEMENT_GRACE_MS to receive their real title
;   setup  the monitor setup the window was placed under
;   done   fully handled by the positions module, never touched again
;   title  the title at the last scan - the desktop rules fire when a title
;          CHANGES into matching, not while it keeps matching
winInfo := Map()
firstScan := true
PLACEMENT_GRACE_MS := 10000

; =============================================================================
;  Interface strings (English / Swedish)
; =============================================================================

Tr(id) {
    global g_lang, g_modifier, g_hk
    static L := Map(
    "en", Map(
        "appTitle",       "DalSegno Window Manager",
        "trayOpen",       "Open DalSegno ({mod} + {kOpenUi})",
        "trayMove",       "Move new windows to saved positions ({mod} + {kToggleMove})",
        "trayAutoSave",   "Save position when a window is moved by hand",
        "trayAutoSaveMod", "Save position when a window is moved with {mod} held",
        "trayToasts",     "Show a small toast when a position is saved",
        "traySaveAll",    "Save all open windows' positions",
        "trayApplyAll",   "Move all open windows to their positions ({mod} + {kApplyAll})",
        "trayShowName",   "Show desktop name",
        "trayLanguage",   "Language",
        "trayConfig",     "Open the config file…",
        "trayReload",     "Reload settings",
        "trayPositions",  "Open the saved positions file…",
        "trayAutostart",  "Start with Windows",
        "trayRestart",    "Restart ({mod} + {kReload})",
        "trayExit",       "Exit",
        "moveOn",         "Automatic moving: ON",
        "moveOff",        "Automatic moving: OFF",
        "autoSaveOn",     "Saving on manual move: ON",
        "autoSaveOff",    "Saving on manual move: OFF",
        "toastSaved",     "Window position saved",
        "savedTitle",     "Position saved",
        "savedAll",       "{1} window positions saved.",
        "movedAll",       "{1} windows were moved to their saved positions.",
        "noMatch",        "No open window matches that saved position.",
        "forgot",         "Forgot the position for:",
        "nothingForget",  "No saved position to forget for the active window.",
        "cannotHandle",   "The active window cannot be managed (no title, ignored, or matches no rule).",
        "cannotHandleWin", "The window cannot be managed (no title, ignored, or matches no rule).",
        "cannotSaveMin",  "Could not save - the window is minimized.",
        "cannotSaveGone", "Could not save - the window no longer exists.",
        "cannotSaveWrite", "Could not save - writing to the positions file failed (locked by OneDrive?):",
        "cannotSaveWin",  "Could not save the position.",
        "maximized",      "maximized",
        "appliesRule",    "windows with `"{1}`" in the title",
        "appliesRuleGone", "rule `"{1}`" (no longer exists)",
        "appliesStd",     "all {1} windows",
        "menuSave",       "Save window position…",
        "menuEditRule",   "Edit rule…",
        "menuMove",       "Move to saved position",
        "menuForget",     "Forget saved position",
        "menuMoveTo",     "Move to desktop",
        "menuMoveFollow", "Move and follow",
        "menuPin",        "Show on all desktops",
        "current",        "  (current)",
        "desktop",        "Desktop",
        "of",             "of",
        "windowTo",       "Window → ",
        "dllMissing",     "VirtualDesktopAccessor.dll missing – cannot move windows",
        "moveFailed",     "Could not move the window",
        "dlgSaveTitle",   "DalSegno - save window position",
        "dlgEditRuleTitle", "DalSegno - edit rule",
        "dlgSaveIntro",   "What should this position apply to?",
        "dlgRuleIntro",   "This window matches the rule «{1}». Windows with the text below in the title share one position.",
        "dlgPre",         "Windows with",
        "dlgPost",        "in the title",
        "dlgRegex",       "The text is a regular expression",
        "dlgEnabled",     "Rule is active",
        "dlgSavePos",     "Save this window's current position",
        "dlgDesktop",     "Desktop:",
        "dlgNoDesktop",   "(none)",
        "dlgFollow",      "follow",
        "dlgOk",          "OK",
        "dlgCancel",      "Cancel",
        "ruleNotInTitle", "The text is not part of this window's title - nothing saved:",
        "ruleShadowed",   "Rule «{1}» saved, but this window is caught by the earlier rule «{2}», which takes precedence. Reorder the rules in the list.",
        "ruleSaved",      "Rule «{1}» = «{2}» created and the window's position saved. Windows with that text in the title now land here.",
        "ruleOff",        "Rule «{1}» is switched off - the position was not saved.",
        "ruleNoMatch",    "Rule «{1}» no longer matches this window - the position was not saved.",
        "badMenuHotkey",  "Button in the settings is not a valid button:",
        "badHotkey",      "Not a valid key name:",
        "dupHotkey",      "Already used by another hotkey:",
        "invalidHotkeys", "Invalid hotkeys:",
        "configReloaded", "{1} rules, {2} ignored programs, {3} ignored titles.",
        "configReloadedTitle", "Settings reloaded",
        "uiFail",         "Could not start the GUI (WebView2 runtime missing?).",
        "hkTitle",        "DalSegno Window Manager - hotkeys",
        "hkText",         "
        (
        {mod} + {kOpenUi}  -  open the DalSegno window
        {mod} + {kSaveActive}  -  save the active window's position
        {mod} + {kSaveAll}  -  save all open windows' positions
        {mod} + {kForgetActive}  -  forget the active window's saved position
        {mod} + {kApplyAll}  -  move every open window to its saved position
        {mod} + {kToggleMove}  -  toggle: move new windows automatically
        {mod} + {kReload}  -  restart the script
        {mod} + right-click  -  the window menu

        Desktop hotkeys (Win+Alt+arrows, Win+Ctrl+digit…) are on the
        Desktops tab of the DalSegno window.
        )"),
    "sv", Map(
        "appTitle",       "DalSegno Window Manager",
        "trayOpen",       "Öppna DalSegno ({mod} + {kOpenUi})",
        "trayMove",       "Flytta nya fönster till sparade lägen ({mod} + {kToggleMove})",
        "trayAutoSave",   "Spara läge när fönster flyttas för hand",
        "trayAutoSaveMod", "Spara läge när fönster flyttas med {mod} nedtryckt",
        "trayToasts",     "Visa liten notis när läge sparas",
        "traySaveAll",    "Spara alla öppna fönsters lägen",
        "trayApplyAll",   "Flytta alla öppna fönster till sina lägen ({mod} + {kApplyAll})",
        "trayShowName",   "Visa skrivbordsnamn",
        "trayLanguage",   "Språk",
        "trayConfig",     "Öppna konfigfilen…",
        "trayReload",     "Läs om inställningar",
        "trayPositions",  "Öppna filen med sparade lägen…",
        "trayAutostart",  "Starta med Windows",
        "trayRestart",    "Starta om ({mod} + {kReload})",
        "trayExit",       "Avsluta",
        "moveOn",         "Automatisk flyttning: PÅ",
        "moveOff",        "Automatisk flyttning: AV",
        "autoSaveOn",     "Sparar läge vid manuell flytt: PÅ",
        "autoSaveOff",    "Sparar läge vid manuell flytt: AV",
        "toastSaved",     "Fönsterläge sparat",
        "savedTitle",     "Läge sparat",
        "savedAll",       "{1} fönsterlägen sparade.",
        "movedAll",       "{1} fönster flyttades till sina sparade lägen.",
        "noMatch",        "Inget öppet fönster matchar det sparade läget.",
        "forgot",         "Glömde läget för:",
        "nothingForget",  "Inget sparat läge att glömma för det aktiva fönstret.",
        "cannotHandle",   "Det aktiva fönstret hanteras inte (saknar titel, är ignorerat, eller matchar ingen regel).",
        "cannotHandleWin", "Fönstret hanteras inte (saknar titel, är ignorerat, eller matchar ingen regel).",
        "cannotSaveMin",  "Kunde inte spara - fönstret är minimerat.",
        "cannotSaveGone", "Kunde inte spara - fönstret finns inte längre.",
        "cannotSaveWrite", "Kunde inte spara - skrivningen till positionsfilen misslyckades (låst av OneDrive?):",
        "cannotSaveWin",  "Kunde inte spara läget.",
        "maximized",      "maximerat",
        "appliesRule",    "fönster med `"{1}`" i titeln",
        "appliesRuleGone", "regeln `"{1}`" (finns inte längre)",
        "appliesStd",     "alla {1}-fönster",
        "menuSave",       "Spara fönstrets läge…",
        "menuEditRule",   "Ändra regel…",
        "menuMove",       "Flytta till sparat läge",
        "menuForget",     "Glöm sparat läge",
        "menuMoveTo",     "Flytta till skrivbord",
        "menuMoveFollow", "Flytta och följ efter",
        "menuPin",        "Visa på alla skrivbord",
        "current",        "  (aktuellt)",
        "desktop",        "Skrivbord",
        "of",             "av",
        "windowTo",       "Fönster → ",
        "dllMissing",     "VirtualDesktopAccessor.dll saknas – kan inte flytta fönster",
        "moveFailed",     "Kunde inte flytta fönstret",
        "dlgSaveTitle",   "DalSegno - spara fönstrets läge",
        "dlgEditRuleTitle", "DalSegno - ändra regel",
        "dlgSaveIntro",   "Vad ska läget gälla?",
        "dlgRuleIntro",   "Fönstret matchar regeln «{1}». Fönster med texten nedan i titeln delar ett läge.",
        "dlgPre",         "Fönster med",
        "dlgPost",        "i titeln",
        "dlgRegex",       "Texten är ett reguljärt uttryck",
        "dlgEnabled",     "Regeln är aktiv",
        "dlgSavePos",     "Spara fönstrets nuvarande läge",
        "dlgDesktop",     "Skrivbord:",
        "dlgNoDesktop",   "(inget)",
        "dlgFollow",      "följ efter",
        "dlgOk",          "OK",
        "dlgCancel",      "Avbryt",
        "ruleNotInTitle", "Texten finns inte i fönstrets titel - inget sparades:",
        "ruleShadowed",   "Regeln «{1}» sparades, men fönstret fångas av den tidigare regeln «{2}» som har företräde. Ändra ordningen i listan.",
        "ruleSaved",      "Regeln «{1}» = «{2}» skapad och fönstrets läge sparat. Fönster med den texten i titeln hamnar nu här.",
        "ruleOff",        "Regeln «{1}» är avstängd - läget sparades inte.",
        "ruleNoMatch",    "Regeln «{1}» matchar inte längre fönstret - läget sparades inte.",
        "badMenuHotkey",  "Knappen i inställningarna är inte en giltig knapp:",
        "badHotkey",      "Ogiltigt tangentnamn:",
        "dupHotkey",      "Används redan av ett annat kortkommando:",
        "invalidHotkeys", "Ogiltiga kortkommandon:",
        "configReloaded", "{1} regler, {2} ignorerade program, {3} ignorerade titlar.",
        "configReloadedTitle", "Inställningar omlästa",
        "uiFail",         "Kunde inte starta GUI:t (saknas WebView2-runtime?).",
        "hkTitle",        "DalSegno Window Manager - kortkommandon",
        "hkText",         "
        (
        {mod} + {kOpenUi}  -  öppna DalSegno-fönstret
        {mod} + {kSaveActive}  -  spara det aktiva fönstrets läge
        {mod} + {kSaveAll}  -  spara alla öppna fönsters lägen
        {mod} + {kForgetActive}  -  glöm det aktiva fönstrets sparade läge
        {mod} + {kApplyAll}  -  flytta alla öppna fönster till sina sparade lägen
        {mod} + {kToggleMove}  -  av/på: flytta nya fönster automatiskt
        {mod} + {kReload}  -  starta om skriptet
        {mod} + högerklick  -  fönstermenyn

        Skrivbordens kortkommandon (Win+Alt+pilar, Win+Ctrl+siffra…)
        finns på fliken Skrivbord i DalSegno-fönstret.
        )"))
    txt := L[L.Has(g_lang) ? g_lang : "en"][id]
    ; the modifier and the keys are configurable, so labels carry placeholders
    if InStr(txt, "{mod}")
        txt := StrReplace(txt, "{mod}", g_modifier)
    if InStr(txt, "{k")
        for namn, key in g_hk
            txt := StrReplace(txt, "{k" namn "}", key != "" ? key : "-")
    return txt
}

SetLanguage(lang) {
    global g_lang, configIni, g_uiWin
    if (lang != "en" && lang != "sv") || (lang = g_lang)
        return
    g_lang := lang
    IniWrite(lang, configIni, "General", "Language")
    BuildTrayMenu()
    A_IconTip := Tr("appTitle")
    if g_uiWin
        try g_uiWin.Title := Tr("appTitle")
    DesktopsLanguageChanged()
    PushStateSoon()
}

; =============================================================================
;  Config file
; =============================================================================

CreateConfigTemplate() {
    global configIni
    if FileExist(configIni)
        return
    template := "
(
; ═══════════════════════════════════════════════════════════════════════════
;  DalSegno Window Manager - settings
;
;  Edit from the GUI (tray icon → Open DalSegno) or by hand. After a manual
;  edit: right-click the tray icon and pick "Reload settings".
; ═══════════════════════════════════════════════════════════════════════════

[Modules]
; Positions: saved window positions (per monitor setup and computer).
; Desktops: virtual desktops - switching, moving, OSD, taskbar label.
Positions=1
Desktops=1

[Menu]
; Hold Modifier and press Button anywhere in a window for the window menu.
; The modifier is read as physical key state and never registered as a
; hotkey prefix, so it can be a key other scripts already use.
Modifier=CapsLock
Button=RButton
Enabled=1
; WholeWindow=0 restricts the menu to the title bar (and the top band of
; apps with custom title bars).
WholeWindow=1
; Exclude: process names (regex) for apps where the combination should pass
; through untouched. Empty = no exclusions.
Exclude=

[Positions]
MoveWindows=1
AutoSave=1
; AutoSaveModifierOnly=1: a hand-moved window only gets its position saved
; when the modifier is held while dropping it.
AutoSaveModifierOnly=1
Notify=1
; RulesOnly=1 means ONLY windows matching a rule are managed (positions).
RulesOnly=0

[Desktops]
; NameInTray=1 shows the desktop name as text on the taskbar, left of the
; icon area. Wheel=1: the mouse wheel over the taskbar switches desktop.
; ArrowIcons=1: two extra tray icons (left/right arrow) that switch desktop.
NameInTray=1
Wheel=1
ArrowIcons=0

[Hotkeys]
; Position hotkeys: keys pressed together with the menu modifier. Empty =
; disabled.
OpenUi=d
SaveActive=s
SaveAll=a
ApplyAll=Home
ForgetActive=Backspace
ToggleMove=F10
Reload=F5
; Desktop hotkeys, AutoHotkey syntax: + Shift, ^ Ctrl, # Win, ! Alt.
; The principle: Ctrl = switch, Alt = move the window, Ctrl+Alt = move and
; follow. Prefixes are combined with digits 1-9.
; Note: ^#/!# + digit override Windows' taskbar shortcuts for pinned apps.
; Avoid ^! alone as a prefix - it is AltGr and breaks characters like @.
MoveNext=!#Right
MovePrevious=!#Left
MoveFollowNext=^!#Right
MoveFollowPrevious=^!#Left
SwitchToPrefix=^#
MoveToPrefix=!#
MoveFollowToPrefix=^!#
MoveMenu=!#Down
ShowName=

[Rules]
; One rule per line:
;   alias = [/exe:<program>] [/desktop:<n>] [/follow] [/off] <text or re:regex>
; The text is matched anywhere in the title (re: for a regular expression);
; it may be empty when /exe: is given. /desktop:<n> moves matching windows
; to that desktop when they appear (or their title changes into matching);
; /follow switches along. /off keeps the rule but switches it off.
; The alias names the rule and its saved positions. Order matters: the first
; matching rule wins. Easiest to create from the window menu.
; Examples:
;   preview = Print preview
;   spotify = /exe:spotify.exe /desktop:2 /follow

[RulesOnlyExe]
; Programs handled ONLY through rules - their other windows are left alone.
; The natural setting for a browser: every popup is a separate window that
; would otherwise share one position with all the browser's windows.
; One per line: x = exename
;1 = msedge.exe

[IgnoreExe]
; Programs whose windows must never be touched. One per line: x = exename
;1 = mstsc.exe

[IgnoreTitles]
; Windows whose title contains the text are never touched. One per line: x = text
;1 = Bildfönster

[General]
; Language of the visible UI: en or sv. Also in the tray menu.
Language=sv

)"
    try FileAppend(template, configIni, "UTF-16")
}

; A whole section as text. Empty string when the file or section is missing.
; A sharing violation - OneDrive syncing the file right after it was written,
; which is exactly when a reload happens - is retried briefly: an empty result
; here would silently load NO rules.
ConfigSection(name) {
    global configIni
    loop 6 {
        try return IniRead(configIni, name)
        catch as e {
            ; a missing section is a plain Error, not an OSError - only the
            ; sharing/lock/access-denied codes are worth waiting for
            if !(e is OSError && (e.Number = 32 || e.Number = 33 || e.Number = 5))
                return ""
            Sleep 150
        }
    }
    return ""
}

; "key = value" -> { key, value }. "" for blank lines and comments.
SplitConfigLine(line) {
    line := Trim(line)
    if (line = "" || SubStr(line, 1, 1) = ";")
        return ""
    p := StrSplit(line, "=", , 2)
    if (p.Length < 2)
        return ""
    return { key: Trim(p[1]), value: Trim(p[2]) }
}

ConfigList(section) {
    list := []
    for line in StrSplit(ConfigSection(section), "`n") {
        p := SplitConfigLine(line)
        if (p != "" && p.value != "")
            list.Push(p.value)
    }
    return list
}

; alias = [/exe:<program>] [/desktop:<n>] [/follow] [/off] <text or re:regex>
; "" when neither a text nor a program is given - a rule needs one of them.
ParseRuleValue(alias, value) {
    r := { alias: alias, pattern: "", regex: false, exe: "", exeRegex: false
        , desktop: 0, follow: false, enabled: true }
    rest := Trim(value)
    loop {
        if RegExMatch(rest, "^/exe:(\S+)\s*(.*)$", &m) {
            if (SubStr(m[1], 1, 3) = "re:")
                r.exe := SubStr(m[1], 4), r.exeRegex := true
            else
                r.exe := m[1]
            rest := m[2]
        } else if RegExMatch(rest, "^/desktop:(\d+)\s*(.*)$", &m) {
            r.desktop := Integer(m[1]), rest := m[2]
        } else if RegExMatch(rest, "^/follow(?:\s+(.*))?$", &m) {
            r.follow := true, rest := m[1]
        } else if RegExMatch(rest, "^/off(?:\s+(.*))?$", &m) {
            r.enabled := false, rest := m[1]
        } else
            break
    }
    rest := Trim(rest)
    if (SubStr(rest, 1, 3) = "re:")
        r.pattern := SubStr(rest, 4), r.regex := true
    else
        r.pattern := rest
    return (r.pattern = "" && r.exe = "") ? "" : r
}

RuleValue(r) {
    v := ""
    if (r.exe != "")
        v .= "/exe:" (r.exeRegex ? "re:" : "") r.exe " "
    if r.desktop
        v .= "/desktop:" r.desktop " "
    if r.follow
        v .= "/follow "
    if !r.enabled
        v .= "/off "
    v .= (r.regex ? "re:" : "") r.pattern
    return Trim(v)
}

LoadConfig() {
    global configIni, titleRules, ignoreExe, ignoreTitles, rulesOnlyExe, rulesOnly
    global g_modPositions, g_modDesktops, g_lang
    global g_modifier, g_menuButton, g_menuOn, g_menuWhole, g_menuExclude, g_hk
    CreateConfigTemplate()
    g_modPositions := IniRead(configIni, "Modules", "Positions", 1) != "0"
    g_modDesktops  := IniRead(configIni, "Modules", "Desktops", 1) != "0"
    g_lang := IniRead(configIni, "General", "Language", "sv") = "en" ? "en" : "sv"
    g_modifier := Trim(IniRead(configIni, "Menu", "Modifier", "CapsLock"))
    g_menuButton := Trim(IniRead(configIni, "Menu", "Button", "RButton"))
    g_menuOn := IniRead(configIni, "Menu", "Enabled", 1) != "0"
    g_menuWhole := IniRead(configIni, "Menu", "WholeWindow", 1) != "0"
    g_menuExclude := IniRead(configIni, "Menu", "Exclude", "")
    try
        GetKeyState(g_modifier, "P")   ; read on every keypress - verify once here
    catch
        g_modifier := "CapsLock"
    for namn in ["OpenUi", "SaveActive", "SaveAll", "ApplyAll", "ForgetActive", "ToggleMove", "Reload"]
        g_hk[namn] := Trim(IniRead(configIni, "Hotkeys", namn, g_hk[namn]))
    rulesOnly := IniRead(configIni, "Positions", "RulesOnly", 0) = 1
    ignoreExe := ConfigList("IgnoreExe")
    ignoreTitles := ConfigList("IgnoreTitles")
    rulesOnlyExe := ConfigList("RulesOnlyExe")
    titleRules := []
    for line in StrSplit(ConfigSection("Rules"), "`n") {
        p := SplitConfigLine(line)
        if (p = "")
            continue
        r := ParseRuleValue(p.key, p.value)
        if (r != "")
            titleRules.Push(r)
    }
    PositionsLoadConfig()
    DesktopsLoadConfig()
    ApplyMenuHotkey()
    ApplyActionHotkeys()
}

ReloadConfig(*) {
    global titleRules, ignoreExe, ignoreTitles
    LoadConfig()
    BuildTrayMenu()
    DesktopsLanguageChanged()
    TrayTip Format(Tr("configReloaded"), titleRules.Length, ignoreExe.Length, ignoreTitles.Length)
        , Tr("configReloadedTitle")
    PushStateSoon()
}

OpenConfigFile(*) {
    global configIni
    CreateConfigTemplate()
    try Run('notepad.exe "' configIni '"')
}

; --- rule table edits (the GUI and the dialog write through these) ---------

RuleByAlias(alias) {
    global titleRules
    for r in titleRules
        if (r.alias = alias)
            return r
    return ""
}

; Writes one rule's line. An existing alias keeps its place in the section
; (the ini API rewrites the value in place); a new one is appended.
WriteRule(r) {
    global configIni
    IniWrite(RuleValue(r), configIni, "Rules", r.alias)
}

; Rewrites the whole [Rules] section in the given order. Order matters -
; the first matching rule wins - and the ini API cannot move a key, so
; reordering rewrites everything (comments inside the section are lost).
WriteRulesInOrder(rules) {
    global configIni
    try IniDelete(configIni, "Rules")
    for r in rules
        IniWrite(RuleValue(r), configIni, "Rules", r.alias)
}

; Deletes the rule and every position saved under it, in all monitor setups -
; a position without its rule could never apply again.
DeleteRule(alias) {
    global configIni, posIni
    try IniDelete(configIni, "Rules", alias)
    for p in ListPositions()
        if (p["key"] = "rule:" alias)
            try IniDelete(posIni, p["section"])
}

; Alias for a new rule: the pattern folded to a-z0-9 and cut to 24 characters
; ("Whole Genome View" -> "wholegenomeview"), made unique among the existing
; rules. The exe name is the fallback for a pattern without letters.
SuggestAlias(pattern, exe) {
    global titleRules
    base := SubStr(FoldAscii(pattern), 1, 24)
    if (base = "")
        base := FoldAscii(RegExReplace(exe, "i)\.exe$", ""))
    if (base = "")
        base := "rule"
    taken := Map()
    for r in titleRules
        taken[StrLower(r.alias)] := true
    if !taken.Has(base)
        return base
    n := 2
    while taken.Has(base n)
        n++
    return base n
}

FoldAscii(s) {
    static from := "åäöéèüáàóòíìúùñçÅÄÖÉÈÜÁÀÓÒÍÌÚÙÑÇ", to := "aaoeeuaaooiiuuncaaoeeuaaooiiuunc"
    loop parse from
        s := StrReplace(s, A_LoopField, SubStr(to, A_Index, 1), true)
    return RegExReplace(StrLower(s), "[^a-z0-9]", "")
}

; The part of a title that tends to stay the same from window to window: the
; text before the first " - ", " – " or " | " separator, minus trailing words
; that carry digits (sample ids, counters).
;   "Whole Genome View - 26MD12102_260901.cyhd_Accel.ND.cychp" -> "Whole Genome View"
;   "Förhandsgranska 26MD12097 - lims-lab1.i.skane.se/…"        -> "Förhandsgranska"
SuggestPattern(title) {
    s := RegExReplace(title, "\s+[-–|]\s+.*$", "")
    s := RegExReplace(s, "(\s+\S*\d\S*)+\s*$", "")
    s := Trim(s, " `t:-–")
    return (s != "") ? s : title
}

; =============================================================================
;  Window identity
; =============================================================================

; The facts about a window that decide whether it may be touched at all: ""
; for system windows, tool windows, cloaked UWP ghosts, our own windows and
; anything on the ignore lists; otherwise { title, cls, exe }. A window that
; passes here but gets no key from KeyFor can still be given one by a rule -
; which is what the window menu's save dialog offers for it.
; allowCloaked: the Windows tab lists windows parked on other virtual
; desktops too (cloaked, but real); the scan and the menu never touch them.
BaseInfo(hwnd, allowCloaked := false) {
    global ignoreExe, ignoreTitles
    static ownPid := ProcessExist()
    ; IME / MSCTFIME UI: every process's "Default IME" helper window - titled,
    ; WS_VISIBLE, and pure furniture; they filled the Windows tab and would
    ; get positions from Save all
    static systemClasses := Map(
        "Progman", 1, "WorkerW", 1, "Shell_TrayWnd", 1, "Shell_SecondaryTrayWnd", 1,
        "NotifyIconOverflowWindow", 1, "Windows.UI.Core.CoreWindow", 1,
        "ForegroundStaging", 1, "XamlExplorerHostIslandWindow", 1,
        "TopLevelWindowForOverflowXamlIsland", 1, "tooltips_class32", 1,
        "IME", 1, "MSCTFIME UI", 1)
    title := "", cls := "", exe := ""
    try {
        title := WinGetTitle(hwnd)
        if (title = "" || WinGetPID(hwnd) = ownPid)
            return ""
        cls := WinGetClass(hwnd)
        if systemClasses.Has(cls)
            return ""
        if WinGetExStyle(hwnd) & 0x80   ; WS_EX_TOOLWINDOW
            return ""
        if (!allowCloaked && IsCloaked(hwnd))
            return ""
        exe := WinGetProcessName(hwnd)
    } catch
        return ""
    for e in ignoreExe
        if (StrLower(e) = StrLower(exe))
            return ""
    for frag in ignoreTitles
        if InStr(title, frag)
            return ""
    return { title: title, cls: cls, exe: exe }
}

; The window's identity key, or "" for windows without one: everything
; BaseInfo rejects, plus windows of rules-only programs (and, in rules-only
; mode, every window) that match no active rule. When a rule matches, the key
; is the rule's alias - independent of the program.
KeyFor(hwnd) {
    info := BaseInfo(hwnd)
    return (info = "") ? "" : KeyForInfo(info)
}

KeyForInfo(info) {
    global titleRules, rulesOnly
    for rule in titleRules
        if (rule.enabled && RuleMatches(rule, info))
            return "rule:" rule.alias
    ; Programs listed under [RulesOnlyExe] get no program-wide identity: a
    ; browser's popups are separate windows that would otherwise all share one
    ; position with every other window of the browser.
    if IsRulesOnly(info.exe)
        return ""
    ; Deliberately WITHOUT the title: titles embed documents, tabs and record
    ; ids, so an exact-title identity would almost never match a new window.
    ; All normal windows of an app share one position - the last one the user
    ; moved defines it. Rules carve out per-popup exceptions.
    return rulesOnly ? "" : info.exe "|" info.cls
}

; Does the rule match this window? A user-typed pattern may be a broken
; regex - that must never take the scan timer down, so it simply does not
; match.
RuleMatches(rule, info) {
    try {
        if (rule.exe != "") {
            hit := rule.exeRegex ? (info.exe ~= rule.exe) : (StrLower(info.exe) = StrLower(rule.exe))
            if !hit
                return false
        }
        if (rule.pattern = "")
            return true
        return rule.regex ? RegExMatch(info.title, rule.pattern) : InStr(info.title, rule.pattern)
    }
    return false
}

; The title part alone - for "did the OLD title match too" questions.
RuleTitleMatches(rule, title) {
    try return rule.regex ? RegExMatch(title, rule.pattern) : InStr(title, rule.pattern)
    return false
}

IsRulesOnly(exe) {
    global rulesOnlyExe
    for e in rulesOnlyExe
        if (StrLower(e) = StrLower(exe))
            return true
    return false
}

; UWP apps leave invisible "cloaked" windows behind; windows parked on other
; virtual desktops are cloaked too.
IsCloaked(hwnd) {
    cloaked := 0
    try DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "uint*", &cloaked, "uint", 4)
    return cloaked != 0
}

; What a saved position applies to, in words: the rule's text or the program -
; never the one window it happened to be saved from.
DescribeKey(key) {
    if (SubStr(key, 1, 5) = "rule:") {
        alias := SubStr(key, 6)
        r := RuleByAlias(alias)
        if (r != "")
            return Format(Tr("appliesRule"), r.pattern != "" ? r.pattern : r.exe)
        return Format(Tr("appliesRuleGone"), alias)
    }
    return Format(Tr("appliesStd"), StrSplit(key, "|")[1])
}

; The pattern of the rule a key refers to, "" for program identities and for
; rules that no longer exist.
PatternFor(key) {
    if (SubStr(key, 1, 5) != "rule:")
        return ""
    r := RuleByAlias(SubStr(key, 6))
    return r != "" ? (r.pattern != "" ? r.pattern : r.exe) : ""
}

; =============================================================================
;  The window scan - one timer feeding both modules
; =============================================================================

ScanWindows() {
    global winInfo, firstScan, g_modPositions, g_modDesktops
    setup := SetupKey()
    alive := Map()
    for hwnd in WinGetList() {
        alive[hwnd] := true
        title := ""
        try title := WinGetTitle(hwnd)
        if !winInfo.Has(hwnd) {
            ; Windows that existed before the script started are not placed -
            ; otherwise the whole desktop would get rearranged on every start.
            ; The desktop rules DO see them once (old title = ""), as they
            ; always have.
            winInfo[hwnd] := { seen: A_TickCount, setup: setup, done: firstScan, title: "" }
        }
        info := winInfo[hwnd]
        if (g_modDesktops && title != "" && title != info.title)
            DesktopRuleSweep(hwnd, title, info.title)
        info.title := title
        if g_modPositions
            PositionsPlace(hwnd, info, setup)
    }
    ; Prune closed windows so the map does not grow all day.
    stale := []
    for hwnd in winInfo
        if !alive.Has(hwnd)
            stale.Push(hwnd)
    for hwnd in stale
        winInfo.Delete(hwnd)
    firstScan := false
}

; =============================================================================
;  Modifier and hotkeys
; =============================================================================

; True while the configured modifier is physically down. Reading the physical
; state is what lets the modifier be a key another script already hooks: we
; never ask to receive its events, we just look at it.
ModifierHeld(*) {
    try
        return GetKeyState(g_modifier, "P")
    catch
        return false
}

; The modifier can get logically stuck (a keyboard hook swallowing the key-UP
; leaves the system convinced it is held). A real hold is seconds long, so
; after half a minute of continuous "down" the missing up-event is sent.
ModifierWatchdog() {
    static since := 0
    down := ModifierHeld()
    if !down {
        since := 0
        return
    }
    if !since {
        since := A_TickCount
        return
    }
    if (A_TickCount - since > 30000) {
        try Send("{" g_modifier " up}")
        since := 0
    }
}

; The position actions, on the modifier. The keys come from [Hotkeys] and can
; change on any settings reload, so whatever was registered last time is
; switched off first, under the same #HotIf context. They are plain keys
; under a criterion that reads the modifier's physical state, never
; "Modifier & key" - a prefix registration makes AutoHotkey hold the key back
; from other scripts' hooks.
ApplyActionHotkeys() {
    global g_actionKeys, g_hk, g_modPositions
    static handlers := Map("OpenUi", (*) => OpenUi(), "SaveActive", (*) => SaveActive()
        , "SaveAll", (*) => SaveAll(), "ApplyAll", (*) => ApplyAll()
        , "ForgetActive", (*) => ForgetActive()
        , "ToggleMove", (*) => ToggleMove(), "Reload", (*) => Reload())
    static positionsOnly := Map("SaveActive", 1, "SaveAll", 1, "ApplyAll", 1, "ForgetActive", 1, "ToggleMove", 1)
    HotIf(ModifierHeld)
    for k in g_actionKeys
        try Hotkey(k, "Off")
    g_actionKeys := []
    for namn, handler in handlers {
        key := g_hk.Has(namn) ? g_hk[namn] : ""
        if (key = "" || (positionsOnly.Has(namn) && !g_modPositions))
            continue
        ; * is not optional, for the same reason as the menu button: a hotkey
        ; without it fires only when NO modifier is held, and CapsModifier
        ; expresses a held CapsLock as RCtrl - so CapsLock+D arrives as
        ; Ctrl+D and a bare "d" never matches. The criterion (the modifier
        ; physically down) is what gates it; Ctrl+D on its own passes through.
        try {
            Hotkey("*" key, handler, "On")
            g_actionKeys.Push("*" key)
        }
    }
    HotIf()
}

; (Re)registers the menu BUTTON. * is not optional: a hotkey without it fires
; only when NO modifier is held, and the menu modifier may well be one
; (CapsModifier expresses CapsLock as RCtrl). Gating belongs to
; MouseOverWindow, which reads the physical state.
ApplyMenuHotkey() {
    global g_menuKeys, g_menuButton, g_menuOn
    HotIf(MouseOverWindow)
    for k in g_menuKeys
        try Hotkey(k, "Off")
    g_menuKeys := []
    if (g_menuOn && g_menuButton != "") {
        btn := "*" g_menuButton
        try {
            Hotkey(btn, MenuKeyDown, "On")
            Hotkey(btn " Up", ShowWindowMenu, "On")
            g_menuKeys := [btn, btn " Up"]
        } catch {
            try Hotkey(btn, "Off")   ; the down half may have taken
            TrayTip Tr("badMenuHotkey") "`n" g_menuButton, Tr("appTitle")
        }
    }
    HotIf()
}

; =============================================================================
;  The window menu
; =============================================================================

; True when the cursor is over a window we can offer the menu for. Runs as a
; hotkey criterion for every press of the button, so everything here has to
; be quick - no cross-process messages except the short-deadline hit test in
; title-bar mode.
MouseOverWindow(*) {
    static ownPid := DllCall("GetCurrentProcessId")
    if g_menuOpen
        return true            ; while our menu is up, eat every press
    if !ModifierHeld()
        return false           ; cheapest exit - this runs on every right-click
    try {
        MouseGetPos , , &win
        if !win
            return false
        if WinGetClass(win) ~= "^(Shell_TrayWnd|Shell_SecondaryTrayWnd|Progman|WorkerW|#32768)$"
            return false
        ; an app's own menu popup has no title and no system menu; a real
        ; window has at least one of the two
        if !IsRealWindow(win)
            return false
        ; our own windows are normally not targets - but the GUI is an ordinary
        ; window someone may want to save a position for, or move
        if (WinGetPID(win) = ownPid && !(IsObject(g_uiWin) && win = g_uiWin.Hwnd))
            return false
        ; windows parked on OTHER virtual desktops stay WS_VISIBLE but are
        ; DWM-cloaked, and WindowFromPoint returns such ghosts above the
        ; visible window; letting the click through reaches the one seen
        if IsCloaked(win)
            return false
        if (g_menuExclude != "") {
            try {
                if (WinGetProcessName(win) ~= g_menuExclude)
                    return false
            }
        }
        if g_menuWhole
            return true
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        res := 0
        if !DllCall("SendMessageTimeoutW", "ptr", win, "uint", 0x84, "ptr", 0
            , "ptr", ((my & 0xFFFF) << 16) | (mx & 0xFFFF)
            , "uint", 0x2, "uint", 50, "ptr*", &res)   ; SMTO_ABORTIFHUNG
            return false
        if (res = 2)   ; HTCAPTION
            return true
        if (res = 1) {   ; HTCLIENT: the top band of apps with custom title bars
            WinGetPos(, &wy, , , win)
            return (my - wy) <= Round(44 * A_ScreenDPI / 96)
        }
        return false
    } catch {
        return false
    }
}

; Tells an app's own menu popup from a real window: every observed popup had
; no title and no system menu of its own; every real window we want the menu
; for has a title.
IsRealWindow(hwnd) {
    try {
        if (WinGetExStyle(hwnd) & 0x8000000)       ; WS_EX_NOACTIVATE - menus, OSDs
            return false
        if (WinGetTitle(hwnd) != "")
            return true
        return DllCall("GetSystemMenu", "ptr", hwnd, "int", 0, "ptr") != 0
    } catch
        return false
}

MenuKeyDown(*) {
    ; eats the click so the app never sees it; the menu comes on release,
    ; otherwise the button-up can accidentally pick the first row
}

ShowWindowMenu(*) {
    global g_menuOpen
    Critical "On"
    if g_menuOpen {
        Critical "Off"
        DllCall("EndMenu")
        return
    }
    g_menuOpen := true
    Critical "Off"
    try {
        MouseGetPos , , &win
        if (!win || !WinExist(win) || !IsRealWindow(win))
            return
        BuildWindowMenu(win, false)
    } finally {
        g_menuOpen := false
    }
}

; The MoveMenu hotkey: the menu for the ACTIVE window, anchored near it -
; the mouse is out of reach when you arrive at a window via Alt+Tab.
ShowMenuForActive(*) {
    global g_menuOpen
    win := WinExist("A")
    if (!win || !IsRealWindow(win))
        return
    try {
        if WinGetClass(win) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
            return
    } catch {
        return
    }
    g_menuOpen := true
    try BuildWindowMenu(win, true)
    finally g_menuOpen := false
}

; Positions items first, desktops items after a separator. Each module
; contributes only while it is on. Shown at the mouse, or anchored near the
; window for the hotkey variant.
BuildWindowMenu(win, atWindow) {
    global g_modPositions, g_modDesktops
    m := Menu()
    added := false
    if g_modPositions {
        key := ""
        try key := KeyFor(win)
        info := ""
        try info := BaseInfo(win)
        if (key != "" || info != "") {
            hasPos := key != "" && LoadPos(key) != ""
            isRule := SubStr(key, 1, 5) = "rule:"
            ; one save item; the dialog behind it settles what the position
            ; applies to, and for a rule-matched window it edits the rule -
            ; the label says which of the two it will be
            m.Add(Tr(isRule ? "menuEditRule" : "menuSave"), (*) => SetTimer(TmSaveOrRule.Bind(win), -1))
            m.Add(Tr("menuMove"), (*) => SetTimer(TmMove.Bind(win), -1))
            m.Add(Tr("menuForget"), (*) => SetTimer(TmForget.Bind(win), -1))
            if !hasPos {
                m.Disable(Tr("menuMove"))
                m.Disable(Tr("menuForget"))
            }
            added := true
        }
    }
    if g_modDesktops {
        if added
            m.Add()
        added := DesktopMenuItems(m, win) || added
    }
    if !added
        return
    ; the eaten click never activated anything, so without claiming the
    ; foreground Windows' foreground lock closes the menu immediately
    TakeForeground()
    ; A menu is rendered - and the coordinates handed to it interpreted - in
    ; the calling thread's DPI awareness. This script is SYSTEM DPI aware,
    ; which inflates every monitor but the primary one on a mixed-scaling
    ; desktop, so the menu came out the wrong size and off-screen. Per-monitor
    ; for the duration of the menu only.
    prevDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        if atWindow {
            x := 0, y := 0
            try WinGetPos(&x, &y, , , win)
            CoordMode("Menu", "Screen")
            m.Show(x + 60, y + 50)
        } else
            m.Show()
    } finally {
        if prevDpi
            DllCall("SetThreadDpiAwarenessContext", "ptr", prevDpi, "ptr")
    }
}

; Windows' foreground lock denies background processes; borrow rights from the
; current foreground window's thread and claim the foreground.
TakeForeground() {
    ourThread := DllCall("GetCurrentThreadId", "uint")
    fg := DllCall("GetForegroundWindow", "ptr")
    fgThread := fg ? DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint") : 0
    if fgThread
        DllCall("AttachThreadInput", "uint", ourThread, "uint", fgThread, "int", 1)
    DllCall("SetForegroundWindow", "ptr", A_ScriptHwnd)
    if fgThread
        DllCall("AttachThreadInput", "uint", ourThread, "uint", fgThread, "int", 0)
}

TmMove(hwnd) {
    key := KeyFor(hwnd)
    if (key != "")
        MoveToSaved(hwnd, key)
}

TmForget(hwnd) {
    global posIni
    key := KeyFor(hwnd)
    if (key = "" || LoadPos(key) = "")
        return
    try IniDelete(posIni, SectionFor(key))
    TrayTip Tr("forgot") "`n" DescribeKey(key), Tr("appTitle")
    PushStateSoon()
}

; Saves the window under the key and says what the position now applies to.
SaveUnderKey(hwnd, key) {
    global winInfo
    if SavePos(key, hwnd) {
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        TrayTip DescribeKey(key), Tr("savedTitle")
        PushStateSoon()
    } else
        TrayTip SaveErrorText(), Tr("appTitle")
}

; =============================================================================
;  The save / rule dialog
; =============================================================================

; The window menu's save item: ONE dialog that settles what the position
; applies to, and - with the Desktops module on - which desktop the rule's
; windows go to.
;   - A window matching an active rule gets "Edit rule": the rule's text,
;     regex flag, Active tick and desktop, plus whether to store this
;     window's position under the rule (ticked by default).
;   - Any other window gets the choice between all windows of its program and
;     a new rule from the title, with the stable part of the title suggested.
;     Rules-only programs (and rules-only mode) get the title option only.
;     Picking a desktop for "all windows of the program" creates a program
;     rule, so the decision shows up as a row in the list.
; The OK handler only reads the controls and validates; the work runs in a
; timer thread after the dialog is hidden, and the Gui is destroyed there.
; Doing it inside the button's own event handler - Destroy, then a config
; reload allocating new rule objects - corrupted a rule object's property
; table; deferring past the handler's return cured it.
TmSaveOrRule(hwnd) {
    global g_ruleDlg, rulesOnly, g_modDesktops
    info := BaseInfo(hwnd)
    if (info = "") {
        TrayTip Tr("cannotHandleWin"), Tr("appTitle")
        return
    }
    key := KeyFor(hwnd)
    rule := SubStr(key, 1, 5) = "rule:" ? RuleByAlias(SubStr(key, 6)) : ""
    if g_ruleDlg
        try g_ruleDlg.Destroy()
    g := Gui("+AlwaysOnTop", Tr(rule ? "dlgEditRuleTitle" : "dlgSaveTitle"))
    g_ruleDlg := g
    g.SetFont("s10", "Segoe UI")
    g.MarginX := 16, g.MarginY := 14
    ctl := Map()
    if rule {
        g.AddText("w560", Format(Tr("dlgRuleIntro"), rule.alias))
        g.AddText("xm y+14", Tr("dlgPre"))
        ctl["pattern"] := g.AddEdit("x+6 yp-4 w360", rule.pattern)
        g.AddText("x+6 yp+4", Tr("dlgPost"))
        ctl["regex"] := g.AddCheckbox("xm y+12", Tr("dlgRegex"))
        ctl["regex"].Value := rule.regex ? 1 : 0
        ctl["enabled"] := g.AddCheckbox("xm y+6", Tr("dlgEnabled"))
        ctl["enabled"].Value := rule.enabled ? 1 : 0
    } else {
        g.AddText("w560", Tr("dlgSaveIntro"))
        progOption := !rulesOnly && !IsRulesOnly(info.exe)
        if progOption {
            ctl["prog"] := g.AddRadio("xm y+14 Checked", Format(Tr("appliesStd"), info.exe))
            ctl["byTitle"] := g.AddRadio("xm y+8", Tr("dlgPre"))
        } else
            g.AddText("xm y+14", Tr("dlgPre"))
        ctl["pattern"] := g.AddEdit("x+6 yp-4 w360", SuggestPattern(info.title))
        g.AddText("x+6 yp+4", Tr("dlgPost"))
        ctl["regex"] := g.AddCheckbox("xm y+12", Tr("dlgRegex"))
        if progOption   ; clicking into the text is choosing the rule
            ctl["pattern"].OnEvent("Focus", (*) => ctl["byTitle"].Value := 1)
    }
    ; the desktop row: which desktop the rule's windows go to
    if g_modDesktops {
        names := DesktopNames()
        if names.Length {
            g.AddText("xm y+12", Tr("dlgDesktop"))
            items := [Tr("dlgNoDesktop")]
            for n in names
                items.Push(n)
            ctl["desktop"] := g.AddDropDownList("x+6 yp-4 w220", items)
            ctl["desktop"].Choose((rule && rule.desktop) ? rule.desktop + 1 : 1)
            ctl["follow"] := g.AddCheckbox("x+10 yp+4", Tr("dlgFollow"))
            ctl["follow"].Value := (rule && rule.follow) ? 1 : 0
        }
    }
    ctl["save"] := g.AddCheckbox("xm y+12 Checked", Tr("dlgSavePos"))
    ok := g.AddButton("xm y+18 w100 Default", Tr("dlgOk"))
    cancel := g.AddButton("x+8 w100", Tr("dlgCancel"))
    ok.OnEvent("Click", (*) => RuleDialogOk(g, hwnd, rule ? rule.alias : "", ctl, info))
    cancel.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    ; centered on the monitor the window is on, not on the primary one
    g.Show("Hide")
    WinGetPos(, , &gw, &gh, g.Hwnd)
    MonitorGetWorkArea(MonitorFromWindow(hwnd), &l, &t, &r, &b)
    g.Show(Format("x{} y{}", l + (r - l - gw) // 2, t + (b - t - gh) // 2))
    if rule
        ctl["pattern"].Focus()
}

RuleDialogOk(g, hwnd, alias, ctl, info) {
    pattern := Trim(ctl["pattern"].Value)
    regex := ctl["regex"].Value ? true : false
    enabled := true, useProg := false
    keepPos := ctl["save"].Value ? true : false
    desktop := ctl.Has("desktop") ? ctl["desktop"].Value - 1 : 0
    follow := ctl.Has("follow") && ctl["follow"].Value ? true : false
    if (alias != "") {
        if (pattern = "")
            return
        enabled := ctl["enabled"].Value ? true : false
    } else if (ctl.Has("prog") && ctl["prog"].Value) {
        useProg := true
    } else {
        if (pattern = "")
            return
        matches := false
        try matches := regex ? RegExMatch(info.title, pattern) : InStr(info.title, pattern)
        if !matches {
            TrayTip Tr("ruleNotInTitle") "`n" pattern, Tr("appTitle")
            return                      ; the dialog stays open for a correction
        }
    }
    g.Hide()
    SetTimer(RuleDialogApply.Bind(hwnd, alias, pattern, regex, enabled, keepPos, useProg
        , desktop, follow, info.exe), -1)
}

RuleDialogApply(hwnd, alias, pattern, regex, enabled, keepPos, useProg, desktop, follow, exe) {
    global g_ruleDlg
    if g_ruleDlg {
        try g_ruleDlg.Destroy()
        g_ruleDlg := 0
    }
    if (alias != "") {
        r := RuleByAlias(alias)
        if (r = "")
            return
        r.pattern := pattern, r.regex := regex, r.enabled := enabled
        r.desktop := desktop, r.follow := follow
        WriteRule(r)
        LoadConfig()
        ; the position is saved BEFORE the window is sent to its desktop: a
        ; window on another desktop is cloaked, and cloaked windows have no
        ; identity
        if (keepPos && enabled) {
            key := KeyFor(hwnd)
            if (key = "rule:" alias)
                SaveUnderKey(hwnd, key)
            else if (SubStr(key, 1, 5) = "rule:")
                TrayTip Format(Tr("ruleShadowed"), alias, SubStr(key, 6)), Tr("appTitle")
            else
                TrayTip Format(Tr("ruleNoMatch"), alias), Tr("appTitle")
        } else if (keepPos && !enabled)
            TrayTip Format(Tr("ruleOff"), alias), Tr("appTitle")
        if (enabled && desktop)
            DesktopApplyToWindow(hwnd, desktop, follow)
        PushStateSoon()
        return
    }
    if useProg {
        if desktop {
            ; a desktop for all windows of the program: a program rule, so
            ; that the decision shows up as a row in the list
            CreateRuleAndSave(hwnd, "", false, exe, desktop, follow, keepPos)
            return
        }
        key := KeyFor(hwnd)
        if (key = "")
            TrayTip Tr("cannotHandleWin"), Tr("appTitle")
        else if keepPos
            SaveUnderKey(hwnd, key)
        return
    }
    CreateRuleAndSave(hwnd, pattern, regex, "", desktop, follow, keepPos)
}

; Writes a rule for the pattern (or the program, when the pattern is empty) -
; or reuses an identical existing one, switching it back on if it was ticked
; off - reloads, applies the desktop, and saves the window's position under
; it.
; NOTE: the parameter is keepPos, not savePos - AutoHotkey names are case
; insensitive, and a parameter called savePos shadows the function SavePos
; inside the body ("Integer has no method named Call").
CreateRuleAndSave(hwnd, pattern, regex, exe, desktop, follow, keepPos) {
    global configIni, titleRules, winInfo
    alias := ""
    for r in titleRules
        if (r.regex = regex && r.pattern == pattern && (pattern != "" ? r.exe = "" : StrLower(r.exe) = StrLower(exe))) {
            alias := r.alias
            r.enabled := true, r.desktop := desktop, r.follow := follow
            WriteRule(r)
            break
        }
    if (alias = "") {
        alias := SuggestAlias(pattern, exe)
        WriteRule({ alias: alias, pattern: pattern, regex: regex, exe: pattern = "" ? exe : ""
            , exeRegex: false, desktop: desktop, follow: follow, enabled: true })
    }
    LoadConfig()
    ; identity and position first, the desktop move last: a window sent to
    ; another desktop is cloaked, and cloaked windows have no identity
    key := KeyFor(hwnd)
    if (key = "") {
        TrayTip Tr("cannotHandleWin"), Tr("appTitle")
        return
    }
    if (key != "rule:" alias) {
        ; rules match in order, and an earlier one also fits this window
        TrayTip Format(Tr("ruleShadowed"), alias, SubStr(key, 6)), Tr("appTitle")
        PushStateSoon()
        return
    }
    if keepPos {
        if SavePos(key, hwnd) {
            if winInfo.Has(hwnd)
                winInfo[hwnd].done := true
            TrayTip Format(Tr("ruleSaved"), alias, pattern != "" ? pattern : exe), Tr("appTitle")
        } else
            TrayTip SaveErrorText(), Tr("appTitle")
    }
    if desktop
        DesktopApplyToWindow(hwnd, desktop, follow)
    PushStateSoon()
}

; =============================================================================
;  Tray
; =============================================================================

; Labels are stored in globals so the toggle handlers can check/uncheck the
; right items; the whole menu is rebuilt when the language changes.
g_lblMove := "", g_lblAutoSave := "", g_lblToasts := ""

BuildTrayMenu() {
    global g_lblMove, g_lblAutoSave, g_lblToasts, g_lang
    global moveEnabled, autoSaveEnabled, notifyEnabled, g_autoSaveModOnly
    global g_modPositions, g_modDesktops
    g_lblMove := Tr("trayMove")
    g_lblAutoSave := Tr(g_autoSaveModOnly ? "trayAutoSaveMod" : "trayAutoSave")
    g_lblToasts := Tr("trayToasts")

    langMenu := Menu()
    langMenu.Add("English", (*) => SetLanguage("en"))
    langMenu.Add("Svenska", (*) => SetLanguage("sv"))
    langMenu.Check(g_lang = "sv" ? "Svenska" : "English")

    tray := A_TrayMenu
    tray.Delete()
    tray.Add(Tr("trayOpen"), (*) => OpenUi())
    tray.Default := Tr("trayOpen")
    if g_modDesktops {
        tray.Add(Tr("trayShowName"), (*) => ShowOsd())
    }
    if g_modPositions {
        tray.Add()
        tray.Add(g_lblMove, (*) => ToggleMove())
        tray.Add(g_lblAutoSave, (*) => ToggleAutoSave())
        tray.Add(g_lblToasts, (*) => ToggleToasts())
        tray.Add()
        tray.Add(Tr("traySaveAll"), SaveAll)
        tray.Add(Tr("trayApplyAll"), ApplyAll)
        if moveEnabled
            tray.Check(g_lblMove)
        if autoSaveEnabled
            tray.Check(g_lblAutoSave)
        if notifyEnabled
            tray.Check(g_lblToasts)
    }
    tray.Add()
    tray.Add(Tr("trayConfig"), OpenConfigFile)
    tray.Add(Tr("trayReload"), ReloadConfig)
    tray.Add(Tr("trayPositions"), OpenPositionsFile)
    tray.Add(Tr("trayLanguage"), langMenu)
    tray.Add(Tr("trayAutostart"), ToggleAutostart)
    if FileExist(AutostartShortcut())
        tray.Check(Tr("trayAutostart"))
    tray.Add()
    tray.Add(Tr("trayRestart"), (*) => Reload())
    tray.Add(Tr("trayExit"), (*) => ExitApp())
    tray.ClickCount := 1
    A_IconTip := Tr("appTitle")
    if !g_modDesktops && FileExist(A_ScriptDir "\app.ico")
        TraySetIcon(A_ScriptDir "\app.ico")
}

; Left-clicking the tray icon: the desktop picker when Desktops is on (the
; frequent action), the GUI otherwise. Returning a value eats the event.
OnTrayClick(wParam, lParam, nMsg, hwnd) {
    global g_modDesktops
    if (lParam = 0x202) {   ; WM_LBUTTONUP
        if g_modDesktops
            ShowDesktopPicker()
        else
            OpenUi()
        return 0
    }
}

ShowHotkeys(*) {
    MsgBox Tr("hkText"), Tr("hkTitle")
}

AutostartShortcut() {
    return A_Startup "\DalSegno.lnk"
}

; Tray toggle: create or remove a shortcut in the user's Startup folder. The
; shortcut points at the SCRIPT, not at AutoHotkey with the script as an
; argument - the Store edition's exe path carries its version number and
; changes with every update.
ToggleAutostart(*) {
    lnk := AutostartShortcut()
    if FileExist(lnk) {
        try FileDelete(lnk)
    } else {
        try FileCreateShortcut(A_ScriptFullPath, lnk, A_ScriptDir)
    }
    BuildTrayMenu()
}

; =============================================================================
;  Error log
; =============================================================================

; Log per machine, outside the synced folder: these folders live in OneDrive
; on two computers, and a shared error.log interleaves lines from both.
; NOTE: under the Microsoft Store edition of AutoHotkey the write is
; virtualized - the file actually lands in
; %LOCALAPPDATA%\Packages\53721Descolada.AutoHotkeyv2StoreEdition_*\LocalCache\Local\DalSegno\.
ErrorLogPath() {
    static path := ""
    if (path != "")
        return path
    dir := EnvGet("LOCALAPPDATA") "\DalSegno"
    try DirCreate(dir)
    return path := dir "\error.log"
}

; Silent tray apps need a trace when something breaks; no dialog, or a
; crashing timer would spam a box every 250 ms.
LogError(err, mode) {
    try FileAppend(FormatTime() "  " err.Message " (" err.File ":" err.Line ")`n"
        , ErrorLogPath(), "UTF-8")
    return 1
}
