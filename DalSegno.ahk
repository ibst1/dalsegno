#Requires AutoHotkey v2.0
#SingleInstance Force

; =============================================================================
;  DalSegno Window Keeper - back to the sign. Windows return to their marked
;  places. Works with every program.
;
;  Move a window by hand (drag and drop) and its position is saved
;  automatically. The next time a window with the same identity opens, it is
;  moved right back there. The script's own moves are NEVER saved - the
;  Windows event that triggers saving only fires for manual moves.
;
;  A window's identity is normally  program + window class + exact title.
;  In the config file (tray menu -> Settings) you can add TITLE RULES: all
;  windows whose title contains a given text then share one saved position
;  regardless of the rest of the title - that is how the old LIMS move script
;  worked, and it is needed for e.g. LIMS popup windows that carry a URL or
;  record id in the title.
;
;  Positions are stored per monitor setup AND computer, so laptop/docked and
;  different machines stay separate even though the script lives in OneDrive.
;
;  Hotkeys (§ = the key in the top-left corner on Nordic keyboards):
;    § + D           open the DalSegno window (GUI)
;    § + S           save the active window's position
;    § + Backspace   forget the active window's saved position
;    § + Home        move every open window to its saved position
;    § + F10         toggle: move new windows automatically
;    § + F5          restart the script
;
;    Ctrl + right-click on a window's title bar opens a DalSegno menu for
;    that window: save/restore/forget its position, or create a title rule
;    from it. (Plain right-click is left alone - DeskPilot owns it.)
;
;  The GUI (WebView2, same architecture as Encore/Expanto) shows saved
;  positions, open windows and rules. Left-clicking the tray icon opens it.
;  Interface language (English/Swedish) is selectable in the GUI and the
;  tray menu.
;
;  NOTE: if LIMS move runs at the same time and the LIMS titles are added as
;  title rules here, both scripts will fight over the same windows. Disable
;  automatic moving in one of them.
; =============================================================================

#Include "lib\WebView2.ahk"
#Include "lib\JSON.ahk"

; --- Files -------------------------------------------------------------------
; Both live next to the script. The UTF-16 BOM is required for the Windows ini
; functions to handle non-ASCII titles - without it they are read as garbage.
posIni    := A_ScriptDir "\DalSegno positions.ini"
configIni := A_ScriptDir "\DalSegno config.ini"

EnsureIniUtf16(posIni, "; DalSegno - saved window positions. Best not edited by hand.`n")
CreateConfigTemplate()

; --- Settings (on/off states are stored in the positions file, [General]) -----
moveEnabled     := IniRead(posIni, "General", "MoveWindows", 1) = 1
autoSaveEnabled := IniRead(posIni, "General", "AutoSave", 1) = 1
notifyEnabled   := IniRead(posIni, "General", "Notify", 1) = 1

; Interface language: "en" or "sv". First run follows the system UI language.
g_lang := IniRead(posIni, "General", "Language", "")
if (g_lang != "en" && g_lang != "sv")
    g_lang := SubStr(A_Language, -2) = "1d" ? "sv" : "en"   ; 041d/081d = Swedish

; --- Config (reloaded via the tray menu or the GUI) ---------------------------
ignoreExe    := []   ; exe names never to touch
ignoreTitles := []   ; title fragments never to touch
titleRules   := []   ; { alias, pattern, regex } - shared identity
rulesOnly    := false
LoadConfig()

; --- State --------------------------------------------------------------------
; winInfo: hwnd -> { seen, setup, done }
;   seen   tick when the window was first noticed. New windows get
;          PLACEMENT_GRACE_MS to receive their real title - LIMS popups and
;          others open with a temporary title that changes shortly after, and
;          without the grace period they would be stamped done before the
;          title becomes recognizable.
;   setup  the monitor setup the window was placed under. When it changes
;          (docking), done is reset so the window gets its saved position for
;          the new setup.
;   done   the window is fully handled and is never touched again.
winInfo := Map()
dupWarned := Map()        ; keys we have already shown a duplicate warning for
firstScan := true         ; windows that existed before startup are not moved
PLACEMENT_GRACE_MS := 10000

; --- GUI (WebView2) - created lazily on first open ----------------------------
g_uiWin := 0, g_uiCtrl := 0, g_uiCore := 0, g_uiReady := false

; --- Autosave: Windows tells us exactly when a drag ends ----------------------
; EVENT_SYSTEM_MOVESIZEEND fires when the user releases a window after moving
; or resizing it - but NOT when the script itself calls WinMove. So no logic
; is needed to tell our own moves from the user's.
moveEndCb := CallbackCreate(OnMoveEnd, "F", 7)
winEventHook := DllCall("SetWinEventHook",
    "uint", 0x000B, "uint", 0x000B,   ; EVENT_SYSTEM_MOVESIZEEND
    "ptr", 0, "ptr", moveEndCb,
    "uint", 0, "uint", 0,
    "uint", 0x2,                       ; OUTOFCONTEXT | SKIPOWNPROCESS
    "ptr")
; NOTE: the callback must return 0/empty - a nonzero return value tells AHK
; to CANCEL the exit (UnhookWinEvent returns 1 on success, which silently
; made the script refuse to close until the trailing 0 was added).
OnExit((*) => (DllCall("UnhookWinEvent", "ptr", winEventHook), 0))

SetTimer(ScanWindows, 800)

; --- Hotkeys ------------------------------------------------------------------
§ & d::OpenUi()
§ & s::SaveActive()
§ & Backspace::ForgetActive()
§ & Home::ApplyAll()
§ & F10::ToggleMove()
§ & F5::Reload

; Ctrl + right-click on a title bar: per-window menu (save/restore/forget/
; create rule). Plain right-click is untouched - DeskPilot uses it.
#HotIf MouseOverTitlebar()
^RButton::ShowTitleMenu()
#HotIf

; =============================================================================
;  Interface strings (English / Swedish)
; =============================================================================

Tr(id) {
    global g_lang
    static L := Map(
    "en", Map(
        "appTitle",       "DalSegno Window Keeper",
        "trayOpen",       "Open DalSegno Window Keeper (§ + D)",
        "trayMove",       "Move new windows to saved positions (§ + F10)",
        "trayAutoSave",   "Save position when a window is moved by hand",
        "trayToasts",     "Show a small toast when a position is saved",
        "trayApplyAll",   "Move all open windows to their positions (§ + Home)",
        "trayLanguage",   "Language",
        "trayConfig",     "Settings…",
        "trayReload",     "Reload settings",
        "trayPositions",  "Open saved positions…",
        "trayHotkeys",    "Hotkeys…",
        "trayRestart",    "Restart (§ + F5)",
        "trayExit",       "Exit",
        "moveOn",         "Automatic moving: ON",
        "moveOff",        "Automatic moving: OFF",
        "autoSaveOn",     "Saving on manual move: ON",
        "autoSaveOff",    "Saving on manual move: OFF",
        "toastSaved",     "Window position saved",
        "savedTitle",     "Position saved",
        "cannotHandle",   "The active window cannot be managed (no title, ignored, or matches no rule).",
        "cannotSave",     "Could not save - the window is minimized or maximized.",
        "cannotSaveWin",  "Could not save the position (window closed, minimized or maximized?).",
        "forgot",         "Forgot the position for:",
        "nothingForget",  "No saved position to forget for the active window.",
        "movedAll",       "{1} windows were moved to their saved positions.",
        "dupTitle",       "Duplicate windows",
        "dupText",        "Several windows share the same identity.`nNo new position is saved until only one remains.`n(Save deliberately with § + S.)",
        "noMatch",        "No open window matches that saved position.",
        "rulesSaved",     "Rules saved.",
        "configReloaded", "{1} title rules, {2} ignored programs, {3} ignored titles.",
        "configReloadedTitle", "Settings reloaded",
        "uiFail",         "Could not start the GUI (WebView2 runtime missing?).",
        "tmSave",         "Save window position",
        "tmMove",         "Move to saved position",
        "tmForget",       "Forget saved position",
        "tmRule",         "Create title rule…",
        "hkTitle",        "DalSegno Window Keeper - hotkeys",
        "hkText",         "
        (
        § + D            open the DalSegno window
        § + S            save the active window's position
        § + Backspace    forget the active window's saved position
        § + Home         move every open window to its saved position
        § + F10          toggle: move new windows automatically
        § + F5           restart the script

        Ctrl + right-click on a window's title bar opens a menu for
        that window: save, restore or forget its position, or create
        a title rule from it.

        Positions are also saved automatically every time you drag a
        window and drop it (can be turned off in the menu).
        )"),
    "sv", Map(
        "appTitle",       "DalSegno Fönsterlägen",
        "trayOpen",       "Öppna DalSegno Fönsterlägen (§ + D)",
        "trayMove",       "Flytta nya fönster till sparade lägen (§ + F10)",
        "trayAutoSave",   "Spara läge när fönster flyttas för hand",
        "trayToasts",     "Visa liten notis när läge sparas",
        "trayApplyAll",   "Flytta alla öppna fönster till sina lägen (§ + Home)",
        "trayLanguage",   "Språk",
        "trayConfig",     "Inställningar…",
        "trayReload",     "Läs om inställningar",
        "trayPositions",  "Öppna sparade lägen…",
        "trayHotkeys",    "Kortkommandon…",
        "trayRestart",    "Starta om (§ + F5)",
        "trayExit",       "Avsluta",
        "moveOn",         "Automatisk flyttning: PÅ",
        "moveOff",        "Automatisk flyttning: AV",
        "autoSaveOn",     "Sparar läge vid manuell flytt: PÅ",
        "autoSaveOff",    "Sparar läge vid manuell flytt: AV",
        "toastSaved",     "Fönsterläge sparat",
        "savedTitle",     "Läge sparat",
        "cannotHandle",   "Det aktiva fönstret hanteras inte (saknar titel, är ignorerat, eller matchar ingen regel).",
        "cannotSave",     "Kunde inte spara - fönstret är minimerat eller maximerat.",
        "cannotSaveWin",  "Kunde inte spara läget (fönstret stängt, minimerat eller maximerat?).",
        "forgot",         "Glömde läget för:",
        "nothingForget",  "Inget sparat läge att glömma för det aktiva fönstret.",
        "movedAll",       "{1} fönster flyttades till sina sparade lägen.",
        "dupTitle",       "Dubbla fönster",
        "dupText",        "Flera fönster med samma identitet är öppna.`nInget nytt läge sparas förrän bara ett är kvar.`n(Spara medvetet med § + S.)",
        "noMatch",        "Inget öppet fönster matchar det sparade läget.",
        "rulesSaved",     "Regler sparade.",
        "configReloaded", "{1} titelregler, {2} ignorerade program, {3} ignorerade titlar.",
        "configReloadedTitle", "Inställningar omlästa",
        "uiFail",         "Kunde inte starta GUI:t (saknas WebView2-runtime?).",
        "tmSave",         "Spara fönstrets läge",
        "tmMove",         "Flytta till sparat läge",
        "tmForget",       "Glöm sparat läge",
        "tmRule",         "Skapa titelregel…",
        "hkTitle",        "DalSegno Fönsterlägen - kortkommandon",
        "hkText",         "
        (
        § + D            öppna DalSegno-fönstret
        § + S            spara det aktiva fönstrets läge
        § + Backspace    glöm det aktiva fönstrets sparade läge
        § + Home         flytta alla öppna fönster till sina sparade lägen
        § + F10          av/på: flytta nya fönster automatiskt
        § + F5           starta om skriptet

        Ctrl + högerklick på ett fönsters titelrad öppnar en meny för
        just det fönstret: spara, återställ eller glöm läget, eller
        skapa en titelregel från det.

        Läget sparas också automatiskt varje gång du drar ett fönster
        och släpper det (kan stängas av i menyn).
        )"))
    return L[L.Has(g_lang) ? g_lang : "en"][id]
}

SetLanguage(lang) {
    global g_lang, posIni, g_uiWin
    if (lang != "en" && lang != "sv") || (lang = g_lang)
        return
    g_lang := lang
    IniWrite(lang, posIni, "General", "Language")
    BuildTrayMenu()
    A_IconTip := Tr("appTitle")
    if g_uiWin
        try g_uiWin.Title := Tr("appTitle")
    PushStateSoon()
}

; =============================================================================
;  Identity
; =============================================================================

; The window's identity key, or "" for windows that must not be managed:
; system windows, tool windows, cloaked UWP ghosts, our own windows, and
; anything ignored in the config file. When a title rule matches, the key
; becomes the rule's alias - independent of the program, so the same position
; applies to e.g. both Edge and Chrome.
KeyFor(hwnd) {
    global ignoreExe, ignoreTitles, titleRules, rulesOnly
    static ownPid := ProcessExist()
    static systemClasses := Map(
        "Progman", 1, "WorkerW", 1, "Shell_TrayWnd", 1, "Shell_SecondaryTrayWnd", 1,
        "NotifyIconOverflowWindow", 1, "Windows.UI.Core.CoreWindow", 1,
        "ForegroundStaging", 1, "XamlExplorerHostIslandWindow", 1,
        "TopLevelWindowForOverflowXamlIsland", 1, "tooltips_class32", 1)
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
        if IsCloaked(hwnd)
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
    for rule in titleRules
        if (rule.regex ? RegExMatch(title, rule.pattern) : InStr(title, rule.pattern))
            return "rule:" rule.alias
    return rulesOnly ? "" : exe "|" cls "|" title
}

; UWP apps leave invisible "cloaked" windows behind that would otherwise get
; positions saved and restored for no reason.
IsCloaked(hwnd) {
    cloaked := 0
    try DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "uint*", &cloaked, "uint", 4)
    return cloaked != 0
}

; Positions are kept separate per monitor count + virtual desktop width + computer.
SetupKey() {
    return MonitorGetCount() "x" SysGet(78) "_" A_ComputerName
}

; Ini section name: hash of the key + setup. The hash turns arbitrary titles
; (with =, [, ] and line breaks) into valid section names. The key is also
; stored in clear text inside the section and verified on read, so a hash
; collision can never yield a wrong position - only no position.
SectionFor(key) {
    return "K" Hash32(key) "_" SetupKey()
}

Hash32(s) {
    h := 5381
    loop parse s
        h := (h * 33 + Ord(A_LoopField)) & 0xFFFFFFFF
    return Format("{:08X}", h)
}

; =============================================================================
;  Saving and restoring positions
; =============================================================================

; Saves the window's current position under its key. False for minimized and
; maximized windows - minimized ones report -32000 and would end up off
; screen, and a maximized position is pointless to restore to.
SavePos(key, hwnd) {
    global posIni
    try {
        if WinGetMinMax(hwnd) != 0
            return false
        WinGetPos(&x, &y, &w, &h, hwnd)
        section := SectionFor(key)
        IniWrite(key, posIni, section, "Key")
        IniWrite(WinGetProcessName(hwnd) " | " SubStr(WinGetTitle(hwnd), 1, 60), posIni, section, "Info")
        IniWrite(x, posIni, section, "X")
        IniWrite(y, posIni, section, "Y")
        IniWrite(w, posIni, section, "W")
        IniWrite(h, posIni, section, "H")
        return true
    } catch
        return false
}

; The saved position for the key in the CURRENT monitor setup, or "" if none.
LoadPos(key) {
    global posIni
    section := SectionFor(key)
    if (IniRead(posIni, section, "Key", "") != key)
        return ""
    x := IniRead(posIni, section, "X", "")
    y := IniRead(posIni, section, "Y", "")
    w := IniRead(posIni, section, "W", "")
    h := IniRead(posIni, section, "H", "")
    if (x = "" || y = "" || w = "" || h = "")
        return ""
    return [Integer(x), Integer(y), Integer(w), Integer(h)]
}

; Moves the window to its saved position. True = the window is fully handled
; (a position existed, or the window is minimized/maximized and must be left
; alone). False = no saved position exists yet.
MoveToSaved(hwnd, key) {
    p := LoadPos(key)
    if (p = "")
        return false
    try {
        if WinGetMinMax(hwnd) != 0
            return true
        WinMove(p[1], p[2], p[3], p[4], hwnd)
        ; The move is done twice: otherwise width/height do not stick when the
        ; window jumps to a monitor with different resolution/scaling.
        Sleep 100
        WinMove(p[1], p[2], p[3], p[4], hwnd)
    }
    return true
}

; The timer: finds new windows and moves them to their saved positions.
ScanWindows() {
    global winInfo, firstScan, moveEnabled, PLACEMENT_GRACE_MS
    setup := SetupKey()
    alive := Map()
    for hwnd in WinGetList() {
        alive[hwnd] := true
        if !winInfo.Has(hwnd) {
            ; Windows that existed before the script started are left where
            ; they are - otherwise the whole desktop would get rearranged
            ; every time the script starts.
            winInfo[hwnd] := { seen: A_TickCount, setup: setup, done: firstScan }
        }
        info := winInfo[hwnd]
        if (info.setup != setup) {
            ; The monitor setup changed (docking etc.): give the window its
            ; saved position for the new setup.
            info.setup := setup
            info.done := false
            info.seen := A_TickCount
        }
        if (info.done || !moveEnabled)
            continue
        if (A_TickCount - info.seen > PLACEMENT_GRACE_MS) {
            info.done := true   ; never got a recognizable title - give up
            continue
        }
        key := KeyFor(hwnd)
        if (key = "")
            continue            ; the title may arrive later - keep watching
        if MoveToSaved(hwnd, key)
            info.done := true
        ; else: no saved position yet. Keep trying during the grace period -
        ; the title may change into one that HAS a position (LIMS popups).
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

; Called by Windows when the user has released a window after moving/resizing.
OnMoveEnd(hHook, event, hwnd, idObject, idChild, idThread, time) {
    global autoSaveEnabled, winInfo
    if (idObject != 0 || !autoSaveEnabled)   ; the window itself, not a child object
        return
    key := KeyFor(hwnd)
    if (key = "")
        return
    ; Duplicates: with two windows sharing the same key there is no telling
    ; which one should define the position - and saving the wrong one would
    ; drag BOTH there next time. Save nothing until only one remains (or save
    ; deliberately with § + S).
    if (CountForKey(key) > 1) {
        WarnDuplicate(key)
        return
    }
    ; With Aero snap (dragging to a screen edge) the window is resized just
    ; AFTER the drag ends - wait it out so the snapped position is saved.
    Sleep 150
    if SavePos(key, hwnd) {
        Toast(Tr("toastSaved"))
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true   ; do not move back what was just dropped
        PushStateSoon()
    }
}

CountForKey(key) {
    n := 0
    for hwnd in WinGetList()
        if (KeyFor(hwnd) = key)
            n++
    return n
}

; One tray notice per key per run - otherwise it would repeat on every drag
; for as long as the duplicate exists.
WarnDuplicate(key) {
    global dupWarned
    if dupWarned.Has(key)
        return
    dupWarned[key] := true
    TrayTip Tr("dupText"), Tr("dupTitle")
}

; Small tooltip at the mouse pointer - a TrayTip on every drag would be too
; intrusive.
Toast(text) {
    global notifyEnabled
    if !notifyEnabled
        return
    ToolTip text
    SetTimer(() => ToolTip(), -1200)
}

; =============================================================================
;  Commands (hotkeys + tray)
; =============================================================================

SaveActive() {
    global winInfo
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd
        return
    key := KeyFor(hwnd)
    if (key = "") {
        TrayTip Tr("cannotHandle"), Tr("appTitle")
        return
    }
    if SavePos(key, hwnd) {
        WinGetPos(&x, &y, &w, &h, hwnd)
        TrayTip SubStr(WinGetTitle(hwnd), 1, 60) "`n(" x ", " y ", " w " × " h ")", Tr("savedTitle")
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        PushStateSoon()
    } else
        TrayTip Tr("cannotSave"), Tr("appTitle")
}

; Removes the saved position for the CURRENT monitor setup. Positions for
; other setups (docked/undocked) remain.
ForgetActive() {
    global posIni
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd
        return
    key := KeyFor(hwnd)
    if (key = "" || LoadPos(key) = "") {
        TrayTip Tr("nothingForget"), Tr("appTitle")
        return
    }
    try IniDelete(posIni, SectionFor(key))
    TrayTip Tr("forgot") "`n" SubStr(WinGetTitle(hwnd), 1, 60), Tr("appTitle")
    PushStateSoon()
}

; Moves every open window that has a saved position - including the ones that
; existed before startup or are already marked done.
ApplyAll(*) {
    global winInfo
    n := 0
    for hwnd in WinGetList() {
        key := KeyFor(hwnd)
        if (key = "" || LoadPos(key) = "")
            continue
        if MoveToSaved(hwnd, key) {
            n++
            if winInfo.Has(hwnd)
                winInfo[hwnd].done := true
        }
    }
    TrayTip Format(Tr("movedAll"), n), Tr("appTitle")
}

; =============================================================================
;  Title bar menu (Ctrl + right-click)
; =============================================================================

; True when the mouse is on a window title bar (WM_NCHITTEST = HTCAPTION).
; Runs as a hotkey criterion on every Ctrl+right-click, hence
; SendMessageTimeout with a short deadline so a hung window never freezes
; the mouse. Same technique as DeskPilot; custom-drawn captions (VS Code,
; browsers, new Outlook) report HTCLIENT, so the top band is accepted too -
; the Ctrl modifier already makes the gesture deliberate.
MouseOverTitlebar(*) {
    static ownPid := ProcessExist()
    try {
        MouseGetPos , , &win
        if !win
            return false
        if WinGetClass(win) ~= "^(Shell_TrayWnd|Shell_SecondaryTrayWnd|Progman|WorkerW|#32768)$"
            return false   ; #32768 = open menus - never touch them
        if WinGetPID(win) = ownPid
            return false
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        res := 0
        if !DllCall("SendMessageTimeoutW", "ptr", win, "uint", 0x84, "ptr", 0
            , "ptr", ((my & 0xFFFF) << 16) | (mx & 0xFFFF)
            , "uint", 0x2, "uint", 50, "ptr*", &res)   ; SMTO_ABORTIFHUNG
            return false
        if (res = 2)   ; HTCAPTION
            return true
        if (res = 1) {   ; HTCLIENT: accept the top band for custom captions
            WinGetPos(, &wy, , , win)
            return (my - wy) <= Round(44 * A_ScreenDPI / 96)
        }
        return false
    } catch
        return false
}

ShowTitleMenu() {
    MouseGetPos , , &win
    if (!win || !WinExist(win))
        return
    key := KeyFor(win)
    title := "", exe := ""
    try title := WinGetTitle(win)
    try exe := WinGetProcessName(win)
    hasSaved := key != "" && LoadPos(key) != ""

    short := StrLen(title) > 40 ? SubStr(title, 1, 38) "…" : title
    short := StrReplace(short, "&", "&&")
    m := Menu()
    if (short != "") {
        m.Add(short, (*) => 0)   ; header row: which window this menu is about
        m.Disable(short)
        m.Add()
    }
    if (key != "") {
        m.Add(Tr("tmSave"), (*) => TmSave(win))
        m.Add(Tr("tmMove"), (*) => TmMove(win))
        if !hasSaved
            m.Disable(Tr("tmMove"))
        m.Add(Tr("tmForget"), (*) => TmForget(win))
        if !hasSaved
            m.Disable(Tr("tmForget"))
        m.Add()
    }
    m.Add(Tr("tmRule"), (*) => TmCreateRule(exe, title))
    m.Show()
}

TmSave(hwnd) {
    global winInfo
    key := KeyFor(hwnd)
    if (key != "" && SavePos(key, hwnd)) {
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        try TrayTip SubStr(WinGetTitle(hwnd), 1, 60), Tr("savedTitle")
        PushStateSoon()
    } else
        TrayTip Tr("cannotSaveWin"), Tr("appTitle")
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
    TrayTip Tr("forgot") "`n" SubStr(WinGetTitle(hwnd), 1, 60), Tr("appTitle")
    PushStateSoon()
}

; Opens the GUI on the Rules tab with a new rule prefilled from the window:
; the title as pattern, the exe name (sans .exe) as alias suggestion. The
; user trims the pattern down to the stable part and saves.
TmCreateRule(exe, title) {
    global g_uiReady
    alias := RegExReplace(StrLower(RegExReplace(exe, "i)\.exe$", "")), "[^a-z0-9]", "")
    payload := JSON.Dump(Map("alias", alias, "pattern", title))
    OpenUi()
    attempts := 0
    trySend() {
        global g_uiReady
        if g_uiReady {
            UiSend("window.prefillRule(" payload ")")
            return
        }
        if (++attempts <= 25)   ; the GUI needs a moment on first open
            SetTimer(trySend, -200)
    }
    SetTimer(trySend, -200)
}

; =============================================================================
;  Config file
; =============================================================================

; Writes a commented template the first time, so the file can be opened and
; filled in right away. The UTF-16 BOM is required for non-ASCII in ini files.
CreateConfigTemplate() {
    global configIni
    if FileExist(configIni)
        return
    template := "
(
; ═══════════════════════════════════════════════════════════════════════════
;  DalSegno Window Keeper - settings
;
;  This file can be edited from the GUI (Rules tab) or by hand. After a
;  manual edit: right-click the tray icon and pick "Reload settings" -
;  the script does not need to be restarted.
; ═══════════════════════════════════════════════════════════════════════════

[Settings]
; RulesOnly = 1 means ONLY windows matching a title rule below are managed
; (like the old LIMS move script). Default 0 = all windows are managed.
RulesOnly = 0

[TitleRules]
; One rule per line:   alias = text
;
;   The text is matched anywhere in the title, regardless of program. All
;   windows matching the same rule SHARE one saved position even when the
;   rest of the title differs. Needed for windows with varying titles, e.g.
;   LIMS popups with a URL or record id in the title.
;
;   The alias is the rule's name. Renaming it loses the rule's saved
;   position. Write  alias = re:pattern  for a regular expression.
;
; Remove the semicolon for the LIMS windows you want handled here (then
; disable automatic moving in LIMS move so the scripts do not fight over
; the same windows):
;patienthistory  = MED_PatientHistoryPopup
;preview         = Förhandsgranska
;attachments     = Manuellt tillagda bilagor
;comments        = Kommentarer
;referral        = Remissregistrering
;diagnosticsgene = MED_DiagnosticsGenePopup
;reqregresgene   = ReqRegResGenePopup
;reqregreschem   = ReqRegResChemPopup
;inquiryoverview = MED_InquiryOverview
;inquiry         = InquiryPopup
;answerreport    = AnswerReport
;textsummary     = Text Summary
;anamnesis       = Anamnestext

[IgnoreExe]
; Programs whose windows must never be touched. One per line: x = exename
;1 = mstsc.exe

[IgnoreTitles]
; Windows whose title contains the text are never touched. One per line: x = text
;1 = Bildfönster

)"
    try FileAppend(template, configIni, "UTF-16")
}

; A whole section as text. Empty string when the file or section is missing.
ConfigSection(name) {
    global configIni
    try return IniRead(configIni, name)
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

LoadConfig() {
    global ignoreExe, ignoreTitles, titleRules, rulesOnly, configIni
    rulesOnly := IniRead(configIni, "Settings", "RulesOnly", 0) = 1
    ignoreExe := []
    ignoreTitles := []
    titleRules := []

    for line in StrSplit(ConfigSection("IgnoreExe"), "`n") {
        p := SplitConfigLine(line)
        if (p != "" && p.value != "")
            ignoreExe.Push(p.value)
    }
    for line in StrSplit(ConfigSection("IgnoreTitles"), "`n") {
        p := SplitConfigLine(line)
        if (p != "" && p.value != "")
            ignoreTitles.Push(p.value)
    }
    for line in StrSplit(ConfigSection("TitleRules"), "`n") {
        p := SplitConfigLine(line)
        if (p = "" || p.value = "")
            continue
        isRegex := 0
        pattern := RegExReplace(p.value, "^re:", , &isRegex)
        if (pattern != "")
            titleRules.Push({ alias: p.key, pattern: pattern, regex: isRegex > 0 })
    }
}

OpenConfigFile(*) {
    global configIni
    CreateConfigTemplate()
    try Run('notepad.exe "' configIni '"')
}

ReloadConfig(*) {
    global titleRules, ignoreExe, ignoreTitles
    LoadConfig()
    TrayTip Format(Tr("configReloaded"), titleRules.Length, ignoreExe.Length, ignoreTitles.Length)
        , Tr("configReloadedTitle")
    PushStateSoon()
}

; The Windows ini functions write ANSI into new files - non-ASCII titles then
; turn to garbage. Create the file with a UTF-16 BOM before the first
; IniWrite, and Windows keeps writing UTF-16.
EnsureIniUtf16(file, header) {
    if !FileExist(file)
        try FileAppend(header, file, "UTF-16")
}

OpenPositionsFile(*) {
    global posIni
    try Run('notepad.exe "' posIni '"')
}

ShowHotkeys(*) {
    MsgBox Tr("hkText"), Tr("hkTitle")
}

; =============================================================================
;  Tray menu
; =============================================================================

A_IconTip := Tr("appTitle")
if FileExist(A_ScriptDir "\app.ico")
    TraySetIcon(A_ScriptDir "\app.ico")

; Left-clicking the tray icon opens the GUI (the menu is on right-click).
OnMessage 0x404, OnTrayClick
OnTrayClick(wParam, lParam, nMsg, hwnd) {
    if (lParam = 0x202) {   ; WM_LBUTTONUP
        OpenUi()
        return 1
    }
}

; Labels are stored in globals so the toggle handlers can check/uncheck the
; right items; the whole menu is rebuilt when the language changes.
g_lblMove := "", g_lblAutoSave := "", g_lblToasts := ""
BuildTrayMenu()

BuildTrayMenu() {
    global g_lblMove, g_lblAutoSave, g_lblToasts, g_lang
    global moveEnabled, autoSaveEnabled, notifyEnabled
    g_lblMove := Tr("trayMove")
    g_lblAutoSave := Tr("trayAutoSave")
    g_lblToasts := Tr("trayToasts")

    langMenu := Menu()
    langMenu.Add("English", (*) => SetLanguage("en"))
    langMenu.Add("Svenska", (*) => SetLanguage("sv"))
    langMenu.Check(g_lang = "sv" ? "Svenska" : "English")

    tray := A_TrayMenu
    tray.Delete()
    tray.Add(Tr("trayOpen"), (*) => OpenUi())
    tray.Default := Tr("trayOpen")
    tray.Add()
    tray.Add(g_lblMove, (*) => ToggleMove())
    tray.Add(g_lblAutoSave, (*) => ToggleAutoSave())
    tray.Add(g_lblToasts, (*) => ToggleToasts())
    tray.Add()
    tray.Add(Tr("trayApplyAll"), ApplyAll)
    tray.Add()
    tray.Add(Tr("trayConfig"), OpenConfigFile)
    tray.Add(Tr("trayReload"), ReloadConfig)
    tray.Add(Tr("trayPositions"), OpenPositionsFile)
    tray.Add(Tr("trayLanguage"), langMenu)
    tray.Add()
    tray.Add(Tr("trayHotkeys"), ShowHotkeys)
    tray.Add(Tr("trayRestart"), (*) => Reload())
    tray.Add(Tr("trayExit"), (*) => ExitApp())

    if moveEnabled
        tray.Check(g_lblMove)
    if autoSaveEnabled
        tray.Check(g_lblAutoSave)
    if notifyEnabled
        tray.Check(g_lblToasts)
}

ToggleMove() {
    global moveEnabled, posIni, g_lblMove
    moveEnabled := !moveEnabled
    IniWrite(moveEnabled ? 1 : 0, posIni, "General", "MoveWindows")
    if moveEnabled {
        A_TrayMenu.Check(g_lblMove)
        TrayTip Tr("moveOn")
    } else {
        A_TrayMenu.Uncheck(g_lblMove)
        TrayTip Tr("moveOff")
    }
    PushStateSoon()
}

ToggleAutoSave() {
    global autoSaveEnabled, posIni, g_lblAutoSave
    autoSaveEnabled := !autoSaveEnabled
    IniWrite(autoSaveEnabled ? 1 : 0, posIni, "General", "AutoSave")
    if autoSaveEnabled {
        A_TrayMenu.Check(g_lblAutoSave)
        TrayTip Tr("autoSaveOn")
    } else {
        A_TrayMenu.Uncheck(g_lblAutoSave)
        TrayTip Tr("autoSaveOff")
    }
    PushStateSoon()
}

ToggleToasts() {
    global notifyEnabled, posIni, g_lblToasts
    notifyEnabled := !notifyEnabled
    IniWrite(notifyEnabled ? 1 : 0, posIni, "General", "Notify")
    if notifyEnabled
        A_TrayMenu.Check(g_lblToasts)
    else
        A_TrayMenu.Uncheck(g_lblToasts)
    PushStateSoon()
}

; =============================================================================
;  GUI (WebView2) - same architecture as Encore/Expanto
;  Created lazily on first open; closing only hides it, so reopening is
;  instant. AHK -> JS: ExecuteScriptAsync("window.receiveState(...)").
;  JS -> AHK: chrome.webview.postMessage -> UiMessage.
; =============================================================================

OpenUi(*) {
    global g_uiWin, g_uiCtrl, g_uiCore
    if !g_uiWin {
        DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "str", "DalSegno.Application.1")
        g_uiWin := Gui("+Resize +MinSize640x420", Tr("appTitle"))
        g_uiWin.OnEvent("Close", (*) => (SaveUiGeometry(), g_uiWin.Hide()))
        g_uiWin.OnEvent("Size", UiResize)
        g_uiWin.Show(ReadUiGeometry())
        FitUiToScreen()
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g_uiWin.hwnd, "uint", 20, "int*", 1, "uint", 4)
        ; WM_SETICON covers the title bar, but with an explicit AppUserModelID
        ; the taskbar GROUP icon falls back to the window class icon
        ; (AutoHotkey's green H) - so the class icon is replaced too
        ; (GCLP_HICON/-SM).
        try {
            ico16 := LoadPicture(A_ScriptDir "\app.ico", "Icon1 w16 h16", &_it1)
            ico32 := LoadPicture(A_ScriptDir "\app.ico", "Icon1 w32 h32", &_it2)
            SendMessage(0x80, 0, ico16, , g_uiWin.hwnd)
            SendMessage(0x80, 1, ico32, , g_uiWin.hwnd)
            DllCall("SetClassLongPtr", "ptr", g_uiWin.hwnd, "int", -14, "ptr", ico32)   ; GCLP_HICON
            DllCall("SetClassLongPtr", "ptr", g_uiWin.hwnd, "int", -34, "ptr", ico16)   ; GCLP_HICONSM
        }
        try {
            ; Explicit user data folder: the default lands next to the host exe
            ; (AutoHotkey64.exe.WebView2) - not always writable, and shared with
            ; every other AHK script running WebView2 (Encore/Expanto), which
            ; gives 0x8007139F when two scripts collide over one profile.
            dataDir := EnvGet("LOCALAPPDATA") "\DalSegno\WebView2"
            try DirCreate(dataDir)
            g_uiCtrl := WebView2.create(g_uiWin.hwnd, , 0, dataDir, "", 0
                , A_ScriptDir "\lib\WebView2Loader.dll")
            g_uiCtrl.Fill()
            g_uiCore := g_uiCtrl.CoreWebView2
            g_uiCore.add_WebMessageReceived(UiMessage)
            g_uiCore.Navigate("file:///" StrReplace(A_ScriptDir "\ui\index.html", "\", "/"))
        } catch {
            g_uiWin.Destroy()
            g_uiWin := 0, g_uiCtrl := 0, g_uiCore := 0
            TrayTip Tr("uiFail"), Tr("appTitle")
            return
        }
    } else {
        g_uiWin.Show()
        FitUiToScreen()
        PushStateSoon()
    }
}

; The window geometry is remembered between sessions, but always clamped to
; the work area of the monitor it lands on - a window wider than the screen
; (e.g. saved on another setup) would put the buttons out of reach.
ReadUiGeometry() {
    global posIni
    w := 960, h := 620
    try {
        w := Integer(IniRead(posIni, "Window", "W", "960"))
        h := Integer(IniRead(posIni, "Window", "H", "620"))
    }
    x := IniRead(posIni, "Window", "X", "")
    y := IniRead(posIni, "Window", "Y", "")
    opt := "w" Max(640, w) " h" Max(420, h)
    if (x != "" && y != "")
        opt := "x" x " y" y " " opt
    return opt
}

SaveUiGeometry() {
    global g_uiWin, posIni
    if !g_uiWin
        return
    try {
        if (WinGetMinMax(g_uiWin.hwnd) != 0)   ; never store a max/minimized rect
            return
        ; Position from the window rect, size from the CLIENT rect:
        ; Gui.Show("w… h…") sizes the client area, so storing the outer size
        ; would grow the window by the title bar and borders every session.
        WinGetPos(&x, &y, , , g_uiWin.hwnd)
        WinGetClientPos( , , &w, &h, g_uiWin.hwnd)
        IniWrite(x, posIni, "Window", "X")
        IniWrite(y, posIni, "Window", "Y")
        IniWrite(w, posIni, "Window", "W")
        IniWrite(h, posIni, "Window", "H")
    }
}

FitUiToScreen() {
    global g_uiWin
    if !g_uiWin
        return
    try {
        if (WinGetMinMax(g_uiWin.hwnd) != 0)
            return
        WinGetPos(&x, &y, &w, &h, g_uiWin.hwnd)
        MonitorGetWorkArea(MonitorFromWindow(g_uiWin.hwnd), &wl, &wt, &wr, &wb)
        w := Min(w, wr - wl), h := Min(h, wb - wt)
        x := Min(Max(x, wl), wr - w), y := Min(Max(y, wt), wb - h)
        WinMove(x, y, w, h, g_uiWin.hwnd)
    }
}

MonitorFromWindow(hwnd) {
    hMon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")   ; NEAREST
    info := Buffer(40, 0)
    NumPut("UInt", 40, info, 0)
    if !DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", info)
        return 0   ; MonitorGetWorkArea(0) = primary monitor
    loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (ml = NumGet(info, 4, "Int") && mt = NumGet(info, 8, "Int"))
            return A_Index
    }
    return 0
}

UiResize(guiObj, minMax, w, h) {
    global g_uiCtrl
    if (minMax != -1 && IsObject(g_uiCtrl))
        try g_uiCtrl.Fill()
}

UiSend(script) {
    global g_uiReady, g_uiCore
    if (!g_uiReady || !IsObject(g_uiCore))
        return
    try g_uiCore.ExecuteScriptAsync(script)
    catch
        g_uiReady := false
}

UiMessage(sender, args) {
    global g_uiReady
    try msg := JSON.Load(args.WebMessageAsJson)
    catch
        return
    if (!(msg is Map) || !msg.Has("action"))
        return
    switch msg["action"] {
        case "ready":
            g_uiReady := true
            PushState()
        case "refresh":
            PushState()
        case "toggle":
            UiToggle(msg["name"], msg["value"])
        case "applyAll":
            ApplyAll()
            PushState()
        case "forget":
            UiForget(msg["section"])
        case "moveKey":
            UiMoveKey(msg["key"])
        case "saveWin":
            UiSaveWin(msg["hwnd"])
        case "moveWin":
            UiMoveWin(msg["hwnd"])
        case "saveRules":
            UiSaveRules(msg)
        case "setLang":
            SetLanguage(msg["lang"])
        case "openPositions":
            OpenPositionsFile()
        case "openConfig":
            OpenConfigFile()
    }
}

; Defers and coalesces updates: several changes in a row (e.g. ApplyAll) end
; up as a single push, and the slow ini reads stay out of event handlers that
; must be quick.
PushStateSoon() {
    global g_uiReady
    if g_uiReady
        SetTimer(PushState, -100)
}

PushState() {
    global g_uiReady, moveEnabled, autoSaveEnabled, notifyEnabled, rulesOnly, g_lang
    global titleRules, ignoreExe, ignoreTitles
    if !g_uiReady
        return
    rules := []
    for r in titleRules
        rules.Push(Map("alias", r.alias, "pattern", r.pattern, "regex", r.regex ? 1 : 0))
    state := Map("settings", Map("move", moveEnabled ? 1 : 0, "autosave", autoSaveEnabled ? 1 : 0
            , "notify", notifyEnabled ? 1 : 0, "rulesOnly", rulesOnly ? 1 : 0, "lang", g_lang)
        , "currentSetup", SetupKey()
        , "positions", ListPositions()
        , "rules", rules
        , "ignoreExe", ignoreExe
        , "ignoreTitles", ignoreTitles
        , "windows", ListWindows())
    UiSend("window.receiveState(" JSON.Dump(state) ")")
}

; Every saved position in the ini file, all monitor setups.
ListPositions() {
    global posIni
    list := []
    sections := ""
    try sections := IniRead(posIni)   ; without a section: the section name list
    for sec in StrSplit(sections, "`n") {
        if !RegExMatch(sec, "^K[0-9A-F]{8}_(.+)$", &m)
            continue   ; [General], [Window] etc. are not saved positions
        list.Push(Map("section", sec, "setup", m[1]
            , "info", IniRead(posIni, sec, "Info", "")
            , "key", IniRead(posIni, sec, "Key", "")
            , "x", IniRead(posIni, sec, "X", ""), "y", IniRead(posIni, sec, "Y", "")
            , "w", IniRead(posIni, sec, "W", ""), "h", IniRead(posIni, sec, "H", "")))
    }
    return list
}

; Every open window DalSegno can manage right now.
ListWindows() {
    list := []
    for hwnd in WinGetList() {
        key := KeyFor(hwnd)
        if (key = "")
            continue
        exe := "", title := ""
        try exe := WinGetProcessName(hwnd)
        try title := WinGetTitle(hwnd)
        list.Push(Map("hwnd", hwnd + 0, "exe", exe, "title", SubStr(title, 1, 80)
            , "rule", SubStr(key, 1, 5) = "rule:" ? SubStr(key, 6) : ""
            , "saved", LoadPos(key) != "" ? 1 : 0))
    }
    return list
}

UiToggle(name, value) {
    global moveEnabled, autoSaveEnabled, notifyEnabled
    v := value ? true : false
    switch name {
        case "move":
            if (moveEnabled != v)
                ToggleMove()
        case "autosave":
            if (autoSaveEnabled != v)
                ToggleAutoSave()
        case "notify":
            if (notifyEnabled != v)
                ToggleToasts()
    }
    PushState()
}

UiForget(section) {
    global posIni
    if !RegExMatch(section, "^K[0-9A-F]{8}_")   ; never touch [General]/[Window]
        return
    try IniDelete(posIni, section)
    PushState()
}

UiMoveKey(key) {
    for hwnd in WinGetList() {
        if (KeyFor(hwnd) = key) {
            MoveToSaved(hwnd, key)
            PushState()
            return
        }
    }
    TrayTip Tr("noMatch"), Tr("appTitle")
}

UiSaveWin(hwnd) {
    global winInfo
    hwnd := Integer(hwnd)
    key := KeyFor(hwnd)
    if (key != "" && SavePos(key, hwnd)) {
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        PushState()
    } else
        TrayTip Tr("cannotSaveWin"), Tr("appTitle")
}

UiMoveWin(hwnd) {
    global winInfo
    hwnd := Integer(hwnd)
    key := KeyFor(hwnd)
    if (key != "" && MoveToSaved(hwnd, key)) {
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        PushState()
    }
}

; Rewrites the rule sections in the config file from the GUI and reloads them.
; Comments INSIDE those three sections disappear on the first save - the file
; can still be edited by hand, the GUI is just the more convenient way.
UiSaveRules(msg) {
    global configIni
    try IniDelete(configIni, "TitleRules")
    try IniDelete(configIni, "IgnoreExe")
    try IniDelete(configIni, "IgnoreTitles")
    for r in msg["rules"] {
        alias := Trim(r["alias"]), pattern := Trim(r["pattern"])
        if (alias = "" || pattern = "")
            continue
        IniWrite((r["regex"] ? "re:" : "") pattern, configIni, "TitleRules", alias)
    }
    n := 0
    for v in msg["ignoreExe"]
        if (Trim(v) != "")
            IniWrite(Trim(v), configIni, "IgnoreExe", ++n)
    n := 0
    for v in msg["ignoreTitles"]
        if (Trim(v) != "")
            IniWrite(Trim(v), configIni, "IgnoreTitles", ++n)
    IniWrite(msg["rulesOnly"] ? 1 : 0, configIni, "Settings", "RulesOnly")
    LoadConfig()
    PushState()
    TrayTip Tr("rulesSaved"), Tr("appTitle")
}
