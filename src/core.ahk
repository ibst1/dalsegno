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
;   deskOld/deskSince  present while a title change is still waiting for the
;          desktop rules: the title before the change, and when it changed
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
        "cannotSaveSize", "Could not save - the window has no size yet (it is not shown).",
        "cannotSaveWrite", "Could not save - writing to the positions file failed (locked by OneDrive?):",
        "cannotSaveWin",  "Could not save the position.",
        "maximized",      "maximized",
        "appliesRule",    "windows with `"{1}`" in the title",
        "appliesRuleExe", "{2} windows with `"{1}`" in the title",
        "dlgExeOnly",     "only {1} windows",
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
        "renameTitle",    "DalSegno - rename desktop",
        "renamePrompt",   "New name for desktop {1} (empty = Windows' default):",
        "renameFailed",   "Could not rename the desktop",
        "dlgSaveTitle",   "DalSegno - save window position",
        "dlgEditRuleTitle", "DalSegno - edit rule",
        "dlgSaveIntro",   "What should this position apply to?",
        "dlgRuleIntro",   "This window matches the rule «{1}». Windows with the text below in the title share one position.",
        "dlgPre",         "Windows with",
        "dlgPost",        "in the title",
        "dlgRegex",       "The text is a regular expression",
        "dlgEnabled",     "Rule is active",
        "dlgThisComputer", "Only on this computer ({1})",
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
        "trayMove",       "Flytta nya fönster till sparade positioner ({mod} + {kToggleMove})",
        "trayAutoSave",   "Spara position när fönster flyttas för hand",
        "trayAutoSaveMod", "Spara position när fönster flyttas med {mod} nedtryckt",
        "trayToasts",     "Visa liten notis när position sparas",
        "traySaveAll",    "Spara alla öppna fönsters positioner",
        "trayApplyAll",   "Flytta alla öppna fönster till sina positioner ({mod} + {kApplyAll})",
        "trayShowName",   "Visa skrivbordsnamn",
        "trayLanguage",   "Språk",
        "trayConfig",     "Öppna konfigfilen…",
        "trayReload",     "Läs om inställningar",
        "trayPositions",  "Öppna filen med sparade positioner…",
        "trayAutostart",  "Starta med Windows",
        "trayRestart",    "Starta om ({mod} + {kReload})",
        "trayExit",       "Avsluta",
        "moveOn",         "Automatisk flyttning: PÅ",
        "moveOff",        "Automatisk flyttning: AV",
        "autoSaveOn",     "Sparar position vid manuell flytt: PÅ",
        "autoSaveOff",    "Sparar position vid manuell flytt: AV",
        "toastSaved",     "Fönsterposition sparad",
        "savedTitle",     "Position sparad",
        "savedAll",       "{1} fönsterpositioner sparade.",
        "movedAll",       "{1} fönster flyttades till sina sparade positioner.",
        "noMatch",        "Inget öppet fönster matchar den sparade positionen.",
        "forgot",         "Glömde positionen för:",
        "nothingForget",  "Ingen sparad position att glömma för det aktiva fönstret.",
        "cannotHandle",   "Det aktiva fönstret hanteras inte (saknar titel, är ignorerat, eller matchar ingen regel).",
        "cannotHandleWin", "Fönstret hanteras inte (saknar titel, är ignorerat, eller matchar ingen regel).",
        "cannotSaveMin",  "Kunde inte spara - fönstret är minimerat.",
        "cannotSaveGone", "Kunde inte spara - fönstret finns inte längre.",
        "cannotSaveSize", "Kunde inte spara - fönstret har ingen storlek ännu (det visas inte).",
        "cannotSaveWrite", "Kunde inte spara - skrivningen till positionsfilen misslyckades (låst av OneDrive?):",
        "cannotSaveWin",  "Kunde inte spara positionen.",
        "maximized",      "maximerat",
        "appliesRule",    "fönster med `"{1}`" i titeln",
        "appliesRuleExe", "{2}-fönster med `"{1}`" i titeln",
        "dlgExeOnly",     "bara {1}-fönster",
        "appliesRuleGone", "regeln `"{1}`" (finns inte längre)",
        "appliesStd",     "alla {1}-fönster",
        "menuSave",       "Spara fönstrets position…",
        "menuEditRule",   "Ändra regel…",
        "menuMove",       "Flytta till sparad position",
        "menuForget",     "Glöm sparad position",
        "menuMoveTo",     "Flytta till skrivbord",
        "menuMoveFollow", "Flytta och följ efter",
        "menuPin",        "Visa på alla skrivbord",
        "current",        "  (aktuellt)",
        "desktop",        "Skrivbord",
        "of",             "av",
        "windowTo",       "Fönster → ",
        "dllMissing",     "VirtualDesktopAccessor.dll saknas – kan inte flytta fönster",
        "moveFailed",     "Kunde inte flytta fönstret",
        "renameTitle",    "DalSegno - byt namn på skrivbord",
        "renamePrompt",   "Nytt namn för skrivbord {1} (tomt = Windows standardnamn):",
        "renameFailed",   "Kunde inte byta namn på skrivbordet",
        "dlgSaveTitle",   "DalSegno - spara fönstrets position",
        "dlgEditRuleTitle", "DalSegno - ändra regel",
        "dlgSaveIntro",   "Vad ska positionen gälla?",
        "dlgRuleIntro",   "Fönstret matchar regeln «{1}». Fönster med texten nedan i titeln delar en position.",
        "dlgPre",         "Fönster med",
        "dlgPost",        "i titeln",
        "dlgRegex",       "Texten är ett reguljärt uttryck",
        "dlgEnabled",     "Regeln är aktiv",
        "dlgThisComputer", "Bara på den här datorn ({1})",
        "dlgSavePos",     "Spara fönstrets nuvarande position",
        "dlgDesktop",     "Skrivbord:",
        "dlgNoDesktop",   "(inget)",
        "dlgFollow",      "följ efter",
        "dlgOk",          "OK",
        "dlgCancel",      "Avbryt",
        "ruleNotInTitle", "Texten finns inte i fönstrets titel - inget sparades:",
        "ruleShadowed",   "Regeln «{1}» sparades, men fönstret fångas av den tidigare regeln «{2}» som har företräde. Ändra ordningen i listan.",
        "ruleSaved",      "Regeln «{1}» = «{2}» skapad och fönstrets position sparad. Fönster med den texten i titeln hamnar nu här.",
        "ruleOff",        "Regeln «{1}» är avstängd - positionen sparades inte.",
        "ruleNoMatch",    "Regeln «{1}» matchar inte längre fönstret - positionen sparades inte.",
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
        {mod} + {kSaveActive}  -  spara det aktiva fönstrets position
        {mod} + {kSaveAll}  -  spara alla öppna fönsters positioner
        {mod} + {kForgetActive}  -  glöm det aktiva fönstrets sparade position
        {mod} + {kApplyAll}  -  flytta alla öppna fönster till sina sparade positioner
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

; On-screen feedback for the hotkeys and the menu actions: the overlay the
; Desktops module draws for desktop names, on the monitor the mouse is on.
; Windows notifications (TrayTip) are not used for this any more. Windows 11
; drops them silently under do-not-disturb, and for a process whose app id
; has no Start menu shortcut - which this one becomes once the GUI has been
; opened - so an action looked like it did nothing. A title other than the
; app's own becomes the first line.
Notify(text, title := "") {
    if (title != "" && title != Tr("appTitle"))
        text := title "`n" text
    ShowOsdText(text, true)
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
; KeepOnScreen: catch a window that opens ENTIRELY off every monitor (Office
; restores documents to coordinates a screen no longer covers) and slide it
; onto the nearest screen. office = Office apps only; all = every managed
; window; off = never.
KeepOnScreen=office

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
;   alias = [/exe:<program>] [/class:<window class>] [/desktop:<n>] [/follow] [/off] <text or re:regex>
; The text is matched anywhere in the title (re: for a regular expression);
; it may be empty when /exe: is given. /class: narrows a rule to one window
; class (quote it if it contains spaces) - what a program row in the list
; becomes when it is given a desktop or switched off. /desktop:<n> moves
; matching windows to that desktop when they appear (or their title changes
; into matching); /follow switches along. /off keeps the rule but switches it off.
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

; alias = [/exe:<program>] [/class:<window class>] [/computer:<name,name>] [/desktop:<n>] [/follow] [/off] <text or re:regex>
; "" when neither a text nor a program is given - a rule needs one of them.
; /class: takes a quoted value when the class has spaces ("GDI+ Hook Window
; Class"). /computer: limits the rule to those computers (the config is
; shared between machines through the synced folder); none = every computer.
ParseRuleValue(alias, value) {
    r := { alias: alias, pattern: "", regex: false, exe: "", exeRegex: false
        , cls: "", computers: "", desktop: 0, follow: false, enabled: true }
    rest := Trim(value)
    loop {
        if RegExMatch(rest, "^/exe:(\S+)\s*(.*)$", &m) {
            if (SubStr(m[1], 1, 3) = "re:")
                r.exe := SubStr(m[1], 4), r.exeRegex := true
            else
                r.exe := m[1]
            rest := m[2]
        } else if RegExMatch(rest, '^/class:(?:"([^"]*)"|(\S+))\s*(.*)$', &m) {
            r.cls := m[1] != "" ? m[1] : m[2], rest := m[3]
        } else if RegExMatch(rest, "^/computer:(\S+)\s*(.*)$", &m) {
            r.computers := m[1], rest := m[2]
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
    if (RuleClass(r) != "")
        v .= "/class:" (InStr(r.cls, " ") ? '"' r.cls '"' : r.cls) " "
    if (RuleComputers(r) != "")
        v .= "/computer:" RuleComputers(r) " "
    if r.desktop
        v .= "/desktop:" r.desktop " "
    if r.follow
        v .= "/follow "
    if !r.enabled
        v .= "/off "
    v .= (r.regex ? "re:" : "") r.pattern
    return Trim(v)
}

; The rule's window class condition, "" for none. Rules built before the
; class condition existed have no cls property at all.
RuleClass(r) {
    return r.HasProp("cls") ? r.cls : ""
}

; The computers a rule is limited to, "" for all; a comma-separated list as
; written in the config. Rules built before the flag existed have no property.
RuleComputers(r) {
    return r.HasProp("computers") ? Trim(r.computers, " ,") : ""
}

; Does the rule apply on THIS computer? Names compare case-insensitively.
RuleOnThisComputer(r) {
    list := RuleComputers(r)
    if (list = "")
        return true
    for name in StrSplit(list, ",")
        if (StrLower(Trim(name)) = StrLower(A_ComputerName))
            return true
    return false
}

LoadConfig() {
    global configIni, titleRules, ignoreExe, ignoreTitles, rulesOnlyExe, rulesOnly
    global g_modPositions, g_modDesktops, g_lang
    global g_modifier, g_menuButton, g_menuOn, g_menuWhole, g_menuExclude, g_hk
    CreateConfigTemplate()
    g_modPositions := IniRead(configIni, "Modules", "Positions", 1) != "0"
    g_modDesktops  := IniRead(configIni, "Modules", "Desktops", 1) != "0"
    g_lang := IniRead(configIni, "General", "Language", "sv") = "en" ? "en" : "sv"
    global g_trace
    g_trace := IniRead(configIni, "General", "Trace", 0) = 1
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
    PrunePositions()
    PruneEmptyRules()
    BuildTrayMenu()
    DesktopsLanguageChanged()
    Notify(Format(Tr("configReloaded"), titleRules.Length, ignoreExe.Length, ignoreTitles.Length)
        , Tr("configReloadedTitle"))
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

; A program row in the list ("all Notepad.exe windows" - the identity
; exe|class) given a desktop or switched off becomes a rule for exactly those
; windows: /exe:<exe> /class:<class>, no title text. Its saved positions, in
; every monitor setup, move under the rule's key so nothing is lost.
PromoteProgram(key, desktop, follow, enabled) {
    global posIni
    parts := StrSplit(key, "|", , 2)
    if (parts.Length < 2 || parts[1] = "" || parts[2] = "")
        return ""
    exe := parts[1], cls := parts[2]
    alias := SuggestAlias("", exe)
    WriteRule({ alias: alias, pattern: "", regex: false, exe: exe, exeRegex: false, cls: cls
        , computers: A_ComputerName, desktop: desktop, follow: follow, enabled: enabled })
    newKey := "rule:" alias
    for p in ListPositions() {
        if (p["key"] != key)
            continue
        sec := "K" Hash32(newKey) "_" p["setup"]
        try {
            IniWrite(newKey, posIni, sec, "Key")
            IniWrite(p["info"], posIni, sec, "Info")
            IniWrite(p["x"], posIni, sec, "X")
            IniWrite(p["y"], posIni, sec, "Y")
            IniWrite(p["w"], posIni, sec, "W")
            IniWrite(p["h"], posIni, sec, "H")
            IniWrite(p["max"], posIni, sec, "Max")
            IniDelete(posIni, p["section"])
        }
    }
    return alias
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

; A rule with no desktop and no saved position in ANY monitor setup does
; nothing - remove it. A rule that still has a position on another computer's
; setup is kept; that is why a rule can show no position here and stay listed.
PruneEmptyRules() {
    global titleRules
    havePos := Map()
    for p in ListPositions()
        if (SubStr(p["key"], 1, 5) = "rule:")
            havePos[SubStr(p["key"], 6)] := true
    removed := 0
    for r in titleRules.Clone()
        if (!havePos.Has(r.alias) && !(r.HasProp("desktop") ? r.desktop : 0))
            (DeleteRule(r.alias), removed += 1)
    if removed
        LoadConfig()
    return removed
}

; Invisible helper / message-only window classes that an old "Save all" swept
; into the positions file before the window filter caught them. They never
; show as real windows, so a saved position for them is dead weight - both
; BaseInfo (no new saves) and PrunePositions (clean the old ones) use this.
IsHelperClass(cls) {
    static exact := Map("SunAwtToolkit", 1, "OleMainThreadWndClass", 1
        , "OleDdeWndClass", 1, "MsoWorkPane", 1, "OfficePowerManagerWindow", 1
        , "UevAppMonitorWindowClass", 1, "UevAppWindowClass", 1
        , "MsoPeopleSearchMessages", 1, "MsoStdCompMgr", 1, "ThunderMain", 1
        , "OfficeChicletCreatorWndClass", 1)
    if exact.Has(cls)
        return true
    for prefix in ["NET-BroadcastEventWindow", "WMS Notif Engine", "ARC Event Window", "WMS Idle"]
        if (SubStr(cls, 1, StrLen(prefix)) = prefix)
            return true
    return false
}

; Alias for a new rule: the pattern folded to a-z0-9 and cut to 24 characters
; ("Report View" -> "reportview"), made unique among the existing
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
;   "Report View - 2026-09-04_run17.pdf" -> "Report View"
;   "Preview 4711 - intranet.example.org/…"          -> "Preview"
SuggestPattern(title) {
    ; a line break in a title (some Java apps) would make the dialog's Edit
    ; multi-line and split the ini value: one line, single spaces
    s := RegExReplace(title, "\s+", " ")
    s := RegExReplace(s, "\s+[-–|]\s+.*$", "")
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
        if (systemClasses.Has(cls) || IsHelperClass(cls))
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
        ; a rule for other computers does not exist here: its windows fall
        ; to the program identity, and its desktop is never applied
        if !RuleOnThisComputer(rule)
            return false
        if (rule.exe != "") {
            hit := rule.exeRegex ? (info.exe ~= rule.exe) : (StrLower(info.exe) = StrLower(rule.exe))
            if !hit
                return false
        }
        if (RuleClass(rule) != "" && StrLower(info.cls) != StrLower(rule.cls))
            return false
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
        if (r != "") {
            if (r.pattern = "")
                return Format(Tr("appliesStd"), r.exe)
            if (r.exe != "")
                return Format(Tr("appliesRuleExe"), r.pattern, r.exe)
            return Format(Tr("appliesRule"), r.pattern)
        }
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
    global winInfo, firstScan, g_modPositions, g_modDesktops, g_menuOpen
    ; Never while the window menu is up. The menu runs the thread per-monitor
    ; DPI aware, and a timer interrupting it inherits that: every coordinate
    ; read or written here would be in the wrong space - the setup key
    ; changed, every window looked new and was moved to its saved place
    ; (a maximized window snapped back to its old rectangle when
    ; "Edit rule" was picked). Checked directly, the menu flag as well.
    if g_menuOpen
        return
    ; and whatever context the interrupted thread left, the scan measures
    ; and moves in the system-aware one - the space every saved position is
    ; in - and hands the previous context back when it is done
    prevDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -2, "ptr")   ; SYSTEM_AWARE
    try ScanWindowsBody()
    finally {
        if prevDpi
            DllCall("SetThreadDpiAwarenessContext", "ptr", prevDpi, "ptr")
    }
}

ScanWindowsBody() {
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
            ; key: the identity the window was placed under; "*" for the
            ; windows found at start (never placed, never re-placed)
            winInfo[hwnd] := { seen: A_TickCount, setup: setup, done: firstScan, title: ""
                , key: firstScan ? "*" : "" }
            if !firstScan
                Trace("new window " TraceWin(hwnd))
        }
        info := winInfo[hwnd]
        ready := WindowReady(hwnd)
        if (title != "" && title != info.title) {
            Trace("title " hwnd " [" SubStr(info.title, 1, 40) "] -> [" SubStr(title, 1, 40) "]")
            ; a title that changes the window's IDENTITY (untitled -> titled,
            ; or into a rule) makes it a new placement: a Java app can sit
            ; untitled for a minute of loading before the real title comes.
            ; Never for a window the user has moved by hand: its title can
            ; leave the rule and come back (a document window flipping to a
            ; dialog title and back) and each return re-placed it where the
            ; rule says, undoing the move. Once moved by hand, it stays.
            if (g_modPositions && info.done && info.key != "*" && !info.HasProp("hand")) {
                k := KeyFor(hwnd)
                if (k != "" && k != info.key) {
                    info.done := false, info.seen := A_TickCount
                    Trace("identity " hwnd " [" info.key "] -> [" k "], placing again")
                }
            }
        }
        ; a window that is not real yet - no size (a Java frame is created
        ; 0x0 with its title and shown for real much later) - is neither
        ; placed nor timed: the grace periods start when it becomes real
        if !ready {
            info.seen := A_TickCount
            if info.HasProp("deskSince")
                info.deskSince := A_TickCount
        }
        ; the position BEFORE the desktop: a window sent to another desktop
        ; is cloaked and has no identity until the desktop is shown, and a
        ; slow app (Java) gets its place while it is still settling
        if g_modPositions {
            PositionsPlace(hwnd, info, setup)
            if ready
                KeepOnScreenGuard(hwnd)
        }
        if (g_modDesktops && title != "" && title != info.title) {
            if firstScan {
                ; the windows found at start: one look, as always
                DesktopRuleSweep(hwnd, title, "")
            } else if !info.HasProp("deskOld") {
                ; a new title: the desktop rules get a look. Not just once -
                ; for up to PLACEMENT_GRACE_MS (counted from when the window
                ; is real) the sweep is repeated until it can act: a window
                ; that has just appeared has no desktop yet (the DLL reports
                ; -1 for the first tens of ms; a Java frame is 0x0 until it
                ; is shown), and a single early attempt was silently lost.
                info.deskOld := info.title, info.deskSince := A_TickCount
            }
        }
        if (info.HasProp("deskOld") && ready) {
            swept := DesktopRuleSweep(hwnd, title, info.deskOld)
            Trace("desktop sweep " hwnd " -> " (swept ? "settled" : "retry"))
            if (swept || A_TickCount - info.deskSince > PLACEMENT_GRACE_MS)
                info.DeleteProp("deskOld"), info.DeleteProp("deskSince")
        }
        info.title := title
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
;
; "Physically down" is our own keyboard hook's bookkeeping, and that table
; can go stale: when another script reinstalls its hook ahead of ours (a
; modifier-layer script curing a stuck key of its own does exactly that)
; while the modifier is held, its key-UP can pass us by. The hook then
; believes the key is held for good - every plain "a" became Save all, "d"
; opened the window, Backspace forgot a position, F5 restarted the script,
; until the next real tap of the key refreshed the table.
;
; The OS's own state of the key is no help: a modifier-layer script that
; keeps CapsLock's toggle off hides the key from the OS entirely (it reads
; as up throughout a real hold). So the hold is bounded instead: the
; modifier counts for MOD_HOLD_MS from the moment our hook saw it go down.
; The position hotkeys are single presses, never long holds, so a real
; user never notices; a stale "down" is harmless once the time is up, and
; the next real press and release of the key clears it.
MOD_HOLD_MS := 10000
g_modDownSince := 0   ; tick of the down our hook saw; 0 while up

; The modifier by Raw Input - the second witness. The hook's physical state
; is what phantoms: after another script reinstalled its hook ahead of ours
; mid-hold, the hook believed CapsLock held for good, and with
; AutoSaveModifierOnly every window dropped by hand was SAVED - which is how
; a second computer, given three new screens, got rule positions nobody
; asked for and kept moving the windows back to them (2026-09-07). The
; ten-second cap above limits that; Raw Input removes it. Windows delivers
; every keyboard event to a registered window straight from the input
; thread, whether or not a hook later blocks it, so it sees the key-up the
; hook missed. Injected input (hDevice 0 - SendInput, keybd_event) never
; counts: the state must be the keyboard's alone. The cap stays as a net
; for the one case Raw Input misses too, a key-up on the secure desktop.
g_rawModDown := false   ; the modifier according to the keyboard
g_rawModTick := 0       ; when Raw Input last reported it; 0 = never (then the hook decides)
RegisterRawModifier()

RegisterRawModifier() {
    static RIDEV_INPUTSINK := 0x100      ; deliver even when we are not the focus
    ; RAWINPUTDEVICE: usUsagePage, usUsage (generic desktop 1, keyboard 6), dwFlags, hwndTarget
    rid := Buffer(A_PtrSize = 8 ? 16 : 12, 0)
    NumPut("UShort", 1, "UShort", 6, "UInt", RIDEV_INPUTSINK, rid)
    NumPut("Ptr", A_ScriptHwnd, rid, 8)
    if !DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", rid.Size) {
        TrayTip("Raw Input registration failed (error " A_LastError ") - the modifier is read from the hook", "DalSegno", "Iconx")
        return
    }
    ; MaxThreads above 1: a handler still running when the next event lands
    ; would otherwise drop it (the up half of a down/up pair); Critical
    ; keeps the events in order instead.
    OnMessage(0x00FF, OnRawInput, 8)     ; WM_INPUT
}

OnRawInput(wParam, lParam, msg, hwnd) {
    Critical
    global g_rawModDown, g_rawModTick, g_modifier
    static RID_INPUT := 0x10000003, HDR := (A_PtrSize = 8 ? 24 : 16)   ; sizeof(RAWINPUTHEADER)
    static buf := Buffer(64)             ; header + RAWKEYBOARD is 40 bytes on x64
    size := buf.Size
    if (DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT, "Ptr", buf, "UInt*", &size, "UInt", HDR) = -1)
        return
    if (NumGet(buf, 0, "UInt") != 1)     ; dwType: RIM_TYPEKEYBOARD
        return
    ; RAWKEYBOARD: MakeCode, Flags, Reserved, VKey (UShort each), Message, ExtraInformation
    vk := NumGet(buf, HDR + 6, "UShort"), flags := NumGet(buf, HDR + 2, "UShort")
    name := RawKeyName(vk, NumGet(buf, HDR, "UShort"), flags)
    if (name != "") {
        if (StrLower(name) != StrLower(g_modifier))
            return
    } else {
        want := 0
        try want := GetKeyVK(g_modifier)
        if (!want || vk != want)
            return
    }
    if !NumGet(buf, 8, "Ptr")            ; hDevice 0: injected, not the keyboard
        return
    g_rawModDown := !(flags & 1)         ; RI_KEY_BREAK
    g_rawModTick := A_TickCount
}

; Raw Input reports the generic VK_SHIFT / VK_CONTROL / VK_MENU; the side
; comes from the scan code (right Shift is 0x36) or the E0 prefix (right
; Ctrl and Alt). The Win keys and CapsLock have codes of their own; any
; other key is matched by virtual key in OnRawInput.
RawKeyName(vk, make, flags) {
    e0 := flags & 2                      ; RI_KEY_E0
    switch vk {
        case 0x14: return "CapsLock"
        case 0x10, 0xA0, 0xA1: return (make = 0x36 || vk = 0xA1) ? "RShift" : "LShift"
        case 0x11, 0xA2, 0xA3: return (e0 || vk = 0xA3) ? "RCtrl" : "LCtrl"
        case 0x12, 0xA4, 0xA5: return (e0 || vk = 0xA5) ? "RAlt" : "LAlt"
        case 0x5B: return "LWin"
        case 0x5C: return "RWin"
    }
    return ""
}

; Is the modifier physically down? Raw Input once it has spoken, the hook
; until then (and if registration failed).
ModifierPhysical() {
    global g_rawModDown, g_rawModTick
    if g_rawModTick
        return g_rawModDown
    try return GetKeyState(g_modifier, "P")
    return false
}

ModifierHeld(*) {
    global g_modDownSince
    try {
        if !ModifierPhysical()
            return false
        if !g_modDownSince
            g_modDownSince := A_TickCount   ; pressed since the last poll
        return A_TickCount - g_modDownSince < MOD_HOLD_MS
    } catch
        return false
}

; The menu accepts the modifier held PHYSICALLY or LOGICALLY. CapsModifier
; expresses a held CapsLock as an INJECTED RCtrl: it never shows as physically
; down (GetKeyState ,"P" = 0, and Raw Input skips injected input) but it IS a
; logical modifier - so `>^` hotkeys fire on it, and the menu must too. The
; menu uses this; auto-save keeps the strict physical ModifierHeld, so a
; logical-only match never triggers a silent save. The logical read is live,
; so there is no 10 s cap on it.
ModifierActive() {
    global g_modifier
    if ModifierHeld()
        return true
    try return GetKeyState(g_modifier)
    return false
}

; Tracks the modifier's transitions for ModifierHeld: cleared when the key
; is up, stamped when it is seen down. No synthetic key events and no hook
; reinstalls - both would interfere with the script that owns the key.
ModifierWatchdog() {
    global g_modDownSince
    down := false
    try down := ModifierPhysical()
    if !down
        g_modDownSince := 0
    else if !g_modDownSince
        g_modDownSince := A_TickCount
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
        ; without it fires only when NO modifier is held, and Sostenuto
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
; (Sostenuto expresses CapsLock as RCtrl). Gating belongs to
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
            Notify(Tr("badMenuHotkey") "`n" g_menuButton, Tr("appTitle"))
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
    if !ModifierActive()
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
    Notify(Tr("forgot") "`n" DescribeKey(key), Tr("appTitle"))
    PushStateSoon()
}

; Saves the window under the key and says what the position now applies to.
SaveUnderKey(hwnd, key) {
    global winInfo
    if SavePos(key, hwnd) {
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        Notify(DescribeKey(key), Tr("savedTitle"))
        PushStateSoon()
    } else
        Notify(SaveErrorText(), Tr("appTitle"))
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
        Notify(Tr("cannotHandleWin"), Tr("appTitle"))
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
        ctl["pattern"] := g.AddEdit("x+6 yp-4 w400 r1", rule.pattern)
        g.AddText("x+6 yp+4", Tr("dlgPost"))
        ctl["regex"] := g.AddCheckbox("xm y+12", Tr("dlgRegex"))
        ctl["regex"].Value := rule.regex ? 1 : 0
        ; the program condition: the rule's own program, or this window's
        ; when the rule has none yet (regex programs are left to the list)
        if !rule.exeRegex {
            ctl["exeOnly"] := g.AddCheckbox("xm y+6", Format(Tr("dlgExeOnly"), rule.exe != "" ? rule.exe : info.exe))
            ctl["exeOnly"].Value := rule.exe != "" ? 1 : 0
        }
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
        ctl["pattern"] := g.AddEdit("x+6 yp-4 w400 r1", SuggestPattern(info.title))
        g.AddText("x+6 yp+4", Tr("dlgPost"))
        ctl["regex"] := g.AddCheckbox("xm y+12", Tr("dlgRegex"))
        ; program AND title: "Viewer.exe windows with Settings in the title" -
        ; ticked by default, a title alone is rarely what is meant
        ctl["exeOnly"] := g.AddCheckbox("xm y+6 Checked", Format(Tr("dlgExeOnly"), info.exe))
        if progOption {   ; clicking into the text is choosing the rule
            ctl["pattern"].OnEvent("Focus", (*) => ctl["byTitle"].Value := 1)
            ctl["exeOnly"].OnEvent("Click", (*) => ctl["byTitle"].Value := 1)
        }
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
    pattern := Trim(RegExReplace(ctl["pattern"].Value, "\s*[\r\n]+\s*", " "))
    regex := ctl["regex"].Value ? true : false
    enabled := true, useProg := false
    keepPos := ctl["save"].Value ? true : false
    desktop := ctl.Has("desktop") ? ctl["desktop"].Value - 1 : 0
    follow := ctl.Has("follow") && ctl["follow"].Value ? true : false
    ; the program condition of a title rule; "" = the rule keeps what it has
    ; (a regex program has no checkbox), "-" = no program condition
    exeCond := ctl.Has("exeOnly") ? (ctl["exeOnly"].Value ? info.exe : "-") : ""
    if (alias != "") {
        if (pattern = "" && exeCond = "-")
            return                      ; a rule needs a text or a program
        enabled := ctl["enabled"].Value ? true : false
    } else if (ctl.Has("prog") && ctl["prog"].Value) {
        useProg := true
    } else {
        if (pattern = "" && exeCond = "-")
            return
        matches := pattern = ""
        try matches := matches || (regex ? RegExMatch(info.title, pattern) : InStr(info.title, pattern))
        if !matches {
            Notify(Tr("ruleNotInTitle") "`n" pattern, Tr("appTitle"))
            return                      ; the dialog stays open for a correction
        }
    }
    g.Hide()
    thisPc := true
    SetTimer(RuleDialogApply.Bind(hwnd, alias, pattern, regex, enabled, keepPos, useProg
        , desktop, follow, info.exe, exeCond, thisPc), -1)
}

RuleDialogApply(hwnd, alias, pattern, regex, enabled, keepPos, useProg, desktop, follow, exe, exeCond, thisPc) {
    global g_ruleDlg
    if g_ruleDlg {
        try g_ruleDlg.Destroy()
        g_ruleDlg := 0
    }
    ; the computers a new rule is for; "" = all
    computers := thisPc ? A_ComputerName : ""
    if (alias != "") {
        r := RuleByAlias(alias)
        if (r = "")
            return
        r.pattern := pattern, r.regex := regex, r.enabled := enabled
        r.desktop := desktop, r.follow := follow
        ; ticked: keep a list that already names this computer, otherwise
        ; this computer alone; cleared: every computer
        if !thisPc
            r.computers := ""
        else if (RuleComputers(r) = "" || !RuleOnThisComputer(r))
            r.computers := A_ComputerName
        if (exeCond = "-")
            r.exe := "", r.exeRegex := false
        else if (exeCond != "" && r.exe = "")
            r.exe := exeCond, r.exeRegex := false
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
                Notify(Format(Tr("ruleShadowed"), alias, SubStr(key, 6)), Tr("appTitle"))
            else
                Notify(Format(Tr("ruleNoMatch"), alias), Tr("appTitle"))
        } else if (keepPos && !enabled)
            Notify(Format(Tr("ruleOff"), alias), Tr("appTitle"))
        if (enabled && desktop)
            DesktopApplyToWindow(hwnd, desktop, follow)
        PushStateSoon()
        return
    }
    if useProg {
        if desktop {
            ; a desktop for all windows of the program: a program rule, so
            ; that the decision shows up as a row in the list
            CreateRuleAndSave(hwnd, "", false, exe, desktop, follow, keepPos, computers)
            return
        }
        key := KeyFor(hwnd)
        if (key = "")
            Notify(Tr("cannotHandleWin"), Tr("appTitle"))
        else if keepPos
            SaveUnderKey(hwnd, key)
        return
    }
    CreateRuleAndSave(hwnd, pattern, regex, exeCond = "-" ? "" : exeCond, desktop, follow, keepPos, computers)
}

; Writes a rule for the pattern (or the program, when the pattern is empty) -
; or reuses an identical existing one, switching it back on if it was ticked
; off - reloads, applies the desktop, and saves the window's position under
; it.
; NOTE: the parameter is keepPos, not savePos - AutoHotkey names are case
; insensitive, and a parameter called savePos shadows the function SavePos
; inside the body ("Integer has no method named Call").
CreateRuleAndSave(hwnd, pattern, regex, exe, desktop, follow, keepPos, computers := "") {
    global configIni, titleRules, winInfo
    alias := ""
    for r in titleRules
        if (r.regex = regex && r.pattern == pattern && !r.exeRegex && StrLower(r.exe) = StrLower(exe)
            && RuleClass(r) = "") {
            alias := r.alias
            r.enabled := true, r.desktop := desktop, r.follow := follow
            ; an identical rule made on another computer gains this one
            ; rather than getting a twin; "" widens it to every computer
            if (computers = "")
                r.computers := ""
            else if !RuleOnThisComputer(r)
                r.computers := RuleComputers(r) "," computers
            WriteRule(r)
            break
        }
    if (alias = "") {
        alias := SuggestAlias(pattern, exe)
        WriteRule({ alias: alias, pattern: pattern, regex: regex, exe: exe
            , exeRegex: false, cls: "", computers: computers, desktop: desktop, follow: follow, enabled: true })
    }
    LoadConfig()
    ; identity and position first, the desktop move last: a window sent to
    ; another desktop is cloaked, and cloaked windows have no identity
    key := KeyFor(hwnd)
    if (key = "") {
        Notify(Tr("cannotHandleWin"), Tr("appTitle"))
        return
    }
    if (key != "rule:" alias) {
        ; rules match in order, and an earlier one also fits this window
        Notify(Format(Tr("ruleShadowed"), alias, SubStr(key, 6)), Tr("appTitle"))
        PushStateSoon()
        return
    }
    if keepPos {
        if SavePos(key, hwnd) {
            if winInfo.Has(hwnd)
                winInfo[hwnd].done := true
            Notify(Format(Tr("ruleSaved"), alias, pattern != "" ? pattern : exe), Tr("appTitle"))
        } else
            Notify(SaveErrorText(), Tr("appTitle"))
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

; Placement trace, on with [General] Trace=1: what the scan decides for each
; window (identity, saved position, moves and their outcome), next to the
; error log. For the "it went to the wrong place" reports.
g_trace := false
Trace(msg) {
    global g_trace
    if !g_trace
        return
    try FileAppend(FormatTime(, "HH:mm:ss") "." Mod(A_TickCount, 1000) "  " msg "`n"
        , TracePath(), "UTF-8")
}

TracePath() {
    static path := ""
    if (path != "")
        return path
    dir := EnvGet("LOCALAPPDATA") "\DalSegno"
    try DirCreate(dir)
    return path := dir "\trace.log"
}

; A window that exists for real: it has a size. Java creates its frames 0x0
; (already titled) and gives them their bounds when it finally shows them -
; anything done to the 0x0 frame is overwritten then, and the desktop
; manager does not know it yet either.
WindowReady(hwnd) {
    try {
        WinGetPos(, , &w, &h, hwnd)
        return w > 0 && h > 0
    }
    return false
}

; Short description of a window for the trace: hwnd, program, class, title.
TraceWin(hwnd) {
    s := hwnd
    try s .= " " WinGetProcessName(hwnd) "|" WinGetClass(hwnd) " [" SubStr(WinGetTitle(hwnd), 1, 40) "]"
    return s
}

; Silent tray apps need a trace when something breaks; no dialog, or a
; crashing timer would spam a box every 250 ms.
LogError(err, mode) {
    try FileAppend(FormatTime() "  " err.Message " (" err.File ":" err.Line ")`n"
        , ErrorLogPath(), "UTF-8")
    return 1
}
