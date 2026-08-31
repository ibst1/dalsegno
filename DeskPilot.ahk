;===============================================================================
; DeskPilot — v1.5.0 (2026-08-28)
;
; * Title bar menu item "Show on all desktops" — pins a window so it follows
;   you everywhere; checkable, and reflects the window's current state.
; * OSD showing the desktop name on every desktop switch.
; * Tray icon with the active desktop's number (icons\d1.ico - d9.ico).
; * Configurable hotkeys (Virtual desktop assistant config.ini):
;     move the active window to the next/previous/any desktop, with or
;     without following it, and switch to desktop 1-9.
;
; Detection reads Explorer's own registry values (no undocumented APIs):
;   HKCU\...\Explorer\VirtualDesktops\CurrentVirtualDesktop  (GUID, 16 bytes)
;   HKCU\...\Explorer\VirtualDesktops\VirtualDesktopIDs      (all GUIDs in order)
;   HKCU\...\Explorer\VirtualDesktops\Desktops\{GUID}\Name   (name, if renamed)
;
; Moving windows requires VirtualDesktopAccessor.dll (Ciantic, MIT license) in
; the script folder — the public IVirtualDesktopManager::MoveWindowToDesktop
; returns E_ACCESSDENIED for other processes' windows (verified on 22631).
; Without the dll everything except window moves still works; desktop
; switching then falls back to sending Ctrl+Win+arrow.
;
; Arguments:  /selftest  - write parsed state to selftest.txt and exit
;             /show      - show the OSD immediately at startup
;
; IPC: other scripts control desktops by posting the window message
; RegisterWindowMessage("DESKPILOT_CMD") to this script's hidden
; main window. wParam: 1=switch, 2=move active window, 3=move+follow,
; 4=show name OSD, 5=reload config, 6=next desktop, 7=previous,
; 100=ping (writes ping.txt - test hook). lParam: desktop N (cmd 1-3).
;===============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\WebView2.ahk
#Include lib\JSON.ahk
Persistent

VD_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops"
VDA_DLL := A_ScriptDir "\VirtualDesktopAccessor.dll"

g_konfigFil := A_ScriptDir "\DeskPilot config.ini"
g_regKortkommandon := []
g_uiWin := 0, g_uiCtrl := 0, g_uiCore := 0, g_uiReady := false
g_dllLaddad := FileExist(VDA_DLL) ? DllCall("LoadLibrary", "str", VDA_DLL, "ptr") != 0 : false
g_sistaGuid := ""    ; GUID at last poll — separates a switch from startup/rename
g_sistaLäge := ""    ; guid|name|count — update the tray only when something changed
g_sistaS := 0        ; last read status, used by the taskbar name label
g_osd := 0
g_bricka := 0        ; the name label on the taskbar
g_brickaText := ""   ; last rendered label content (avoids needless redraws)
g_namnITray := true
g_rullhjul := true   ; mouse wheel over the taskbar switches desktop
g_pilikoner := true  ; two tray icons (Skrivbordspil.ahk) that switch desktop
g_titelmeny := true  ; the modifier+right-click window menu is enabled
g_menyModifierare := "CapsLock" ; held down while right-clicking ([Mouse] MenuModifier)
g_menyKnapp := "RButton"        ; the button itself ([Mouse] MenuButton)
g_menyTangenter := []           ; what we actually registered, so a reload can undo it
g_egenMeny := ""     ; process regex for apps left completely untouched
g_helaFönstret := true  ; the menu opens anywhere in the window, not just the title bar
g_menyÖppen := false  ; the title bar menu is currently showing (drives click handling)
g_regler := []       ; [{mål, regex}] — windows that should always be moved
g_kändaFönster := Map()  ; hwnd → title, for the rule sweep's new/changed detection
g_språk := "en"      ; UI language: "en" or "sv" ([Display] Language)
g_skärmLäge := SkärmSnapshot()  ; monitor layout at startup (spurious-event filter)

if A_Args.Length && A_Args[1] = "/selftest" {
    s := LäsSkrivbordsStatus()
    ut := s ? "index=" s.index "`ncount=" s.count "`nname=" s.name "`nguid=" s.guid
        : "FEL: kunde inte läsa registret"
    LäsKonfig()
    lista := ""
    for tangent in g_regKortkommandon
        lista .= (lista = "" ? "" : ",") tangent
    ut .= "`ndll=" (g_dllLaddad ? "laddad" : "saknas")
    ut .= "`nlanguage=" g_språk
    ut .= "`nnamnITray=" (g_namnITray ? 1 : 0)
    ut .= "`nmus=rullhjul:" (g_rullhjul ? 1 : 0) " pilikoner:" (g_pilikoner ? 1 : 0)
        . " titelmeny:" (g_titelmeny ? 1 : 0)
    ut .= "`nregler=" g_regler.Length
    ut .= "`nhotkeys(" g_regKortkommandon.Length ")=" lista
    try FileDelete(A_ScriptDir "\selftest.txt")
    FileAppend(ut "`n", A_ScriptDir "\selftest.txt", "UTF-8")
    ExitApp
}

OnError(LoggaFel)
; dark theme for this process's menus (undocumented uxtheme ordinals 135/136),
; so the title bar menu follows the system theme instead of classic light
try {
    hUx := DllCall("LoadLibrary", "str", "uxtheme", "ptr")
    DllCall(DllCall("GetProcAddress", "ptr", hUx, "ptr", 135, "ptr"), "int", 1)   ; AllowDark
    DllCall(DllCall("GetProcAddress", "ptr", hUx, "ptr", 136, "ptr"))             ; FlushMenuThemes
}
LäsKonfig()          ; must run before InitTray so the menu gets the right language
InitTray()
UppdateraPilikoner()
OnMessage(DllCall("RegisterWindowMessage", "str", "DESKPILOT_CMD", "uint"), VdaKommando)
OnMessage(0x7E, SkärmbytesVakt)   ; WM_DISPLAYCHANGE: restart on monitor changes
OnMessage(0x404, TrayIkonKlick)   ; AHK_NOTIFYICON: left click = desktop picker
HotIf(MusÖverBricka)
Hotkey("LButton", BrickKlick, "On")   ; click on the name label = desktop picker
HotIf()
PollSkrivbord()      ; set the icon right away; the first call shows no OSD
SetTimer(PollSkrivbord, 250)
SetTimer(BrickaVakt, 250)   ; keeps the name label placed, visible and on top
SetTimer(RegelSvep, 1000)   ; applies window rules to new/retitled windows
SetTimer(ModifierarVakt, 5000)  ; clears a logically stuck menu modifier

if A_Args.Length && A_Args[1] = "/show"
    VisaOsd()

;--- detection -------------------------------------------------------------------

; Reads the current desktop from the registry. Returns 0 if the values are
; missing (can happen right after logon before Explorer has written them).
LäsSkrivbordsStatus() {
    cur := RegRead(VD_KEY, "CurrentVirtualDesktop", "")
    ids := RegRead(VD_KEY, "VirtualDesktopIDs", "")
    if (cur = "" || ids = "")
        return 0
    count := StrLen(ids) // 32
    index := 0
    loop count
        if SubStr(ids, (A_Index - 1) * 32 + 1, 32) = cur {
            index := A_Index
            break
        }
    guid := HexTillGuid(cur)
    name := guid != "" ? RegRead(VD_KEY "\Desktops\" guid, "Name", "") : ""
    return {index: index, count: count, name: name, guid: guid}
}

; RegRead returns REG_BINARY as a hex string in byte order; the registry's
; Desktops keys use GUID string form where Data1-Data3 are little-endian.
HexTillGuid(hex) {
    if StrLen(hex) != 32
        return ""
    b := []
    loop 16
        b.Push(SubStr(hex, A_Index * 2 - 1, 2))
    return "{" b[4] b[3] b[2] b[1] "-" b[6] b[5] "-" b[8] b[7] "-" b[9] b[10] "-"
        . b[11] b[12] b[13] b[14] b[15] b[16] "}"
}

NamnFörIndex(i) {
    ids := RegRead(VD_KEY, "VirtualDesktopIDs", "")
    hex := SubStr(ids, (i - 1) * 32 + 1, 32)
    guid := StrLen(hex) = 32 ? HexTillGuid(hex) : ""
    namn := guid != "" ? RegRead(VD_KEY "\Desktops\" guid, "Name", "") : ""
    return namn != "" ? i " · " namn : T("desktop") " " i
}

PollSkrivbord() {
    global g_sistaGuid, g_sistaLäge, g_sistaS
    s := LäsSkrivbordsStatus()
    if !s
        return
    g_sistaS := s
    läge := s.guid "|" s.name "|" s.count
    if (läge = g_sistaLäge)
        return
    bytt := g_sistaGuid != "" && s.guid != g_sistaGuid
    g_sistaGuid := s.guid
    g_sistaLäge := läge
    UppdateraTray(s)
    UppdateraBricka()
    if bytt
        VisaOsd(s)
}

;--- hotkeys ---------------------------------------------------------------------

LäsKonfig() {
    global g_regKortkommandon, g_namnITray, g_brickaText, g_rullhjul, g_pilikoner
    global g_titelmeny, g_egenMeny, g_helaFönstret, g_språk
    global g_menyModifierare, g_menyKnapp, g_menyTangenter
    if !FileExist(g_konfigFil)
        SkrivStandardKonfig()
    g_språk := IniRead(g_konfigFil, "Display", "Language", "en") = "sv" ? "sv" : "en"
    g_namnITray := IniRead(g_konfigFil, "Display", "NameInTray", "1") != "0"
    g_brickaText := ""      ; force a redraw with any new setting
    if !g_namnITray
        DöljBricka()
    g_rullhjul := IniRead(g_konfigFil, "Mouse", "Wheel", "1") != "0"
    g_pilikoner := IniRead(g_konfigFil, "Mouse", "ArrowIcons", "1") != "0"
    g_titelmeny := IniRead(g_konfigFil, "Mouse", "TitleMenu", "1") != "0"
    HotIf(MusÖverFältet)
    Hotkey("WheelUp", RullaFöregående, g_rullhjul ? "On" : "Off")
    Hotkey("WheelDown", RullaNästa, g_rullhjul ? "On" : "Off")
    HotIf()
    g_egenMeny := IniRead(g_konfigFil, "Mouse", "TitleMenuExclude", "")
    g_helaFönstret := IniRead(g_konfigFil, "Mouse", "MenuWholeWindow", "1") != "0"
    LäsRegler()
    for tangent in g_regKortkommandon
        try Hotkey(tangent, "Off")
    g_regKortkommandon := []
    fel := ""
    enkla := [
        ["MoveNext", "!#Right", FlyttaRelativt.Bind(1, false)],
        ["MovePrevious", "!#Left", FlyttaRelativt.Bind(-1, false)],
        ["MoveFollowNext", "^!#Right", FlyttaRelativt.Bind(1, true)],
        ["MoveFollowPrevious", "^!#Left", FlyttaRelativt.Bind(-1, true)],
        ["MoveMenu", "!#Down", VisaFlyttMenyHotkey],
        ["ShowName", "", VisaOsdHotkey],
    ]
    for b in enkla {
        tangent := IniRead(g_konfigFil, "Hotkeys", b[1], b[2])
        if tangent != ""
            Registrera(b[1], tangent, b[3], &fel)
    }
    prefixar := [
        ["SwitchToPrefix", "^#", (n) => VäxlaTill.Bind(n)],
        ["MoveToPrefix", "!#", (n) => FlyttaAbsolut.Bind(n, false)],
        ["MoveFollowToPrefix", "^!#", (n) => FlyttaAbsolut.Bind(n, true)],
    ]
    for p in prefixar {
        pre := IniRead(g_konfigFil, "Hotkeys", p[1], p[2])
        if pre = ""
            continue
        loop 9
            Registrera(p[1], pre . A_Index, p[3](A_Index), &fel)
    }
    g_menyModifierare := Trim(IniRead(g_konfigFil, "Mouse", "MenuModifier", "CapsLock"))
    g_menyKnapp := Trim(IniRead(g_konfigFil, "Mouse", "MenuButton", "RButton"))
    ; the modifier is read on every click, so a bad name would throw there and
    ; silently kill the menu - check it once, here, where it can be reported
    try
        GetKeyState(g_menyModifierare, "P")
    catch {
        fel .= "MenuModifier: " g_menyModifierare "`n"
        g_menyModifierare := "CapsLock"
    }
    fel .= TillämpaMenyKortkommando()
    if fel != "" {
        TrayTip(T("invalidHotkeys") "`n" fel, "DeskPilot", "Iconx")
        try FileAppend(FormatTime() "  Invalid hotkeys: " StrReplace(fel, "`n", " / ") "`n"
            , A_ScriptDir "\error.log", "UTF-8")
    }
}

; The menu modifier can get logically stuck: several scripts hook the keyboard
; here, and when one of them swallows the key-UP event the system keeps the key
; registered as held. Every plain right-click then passes the criterion and
; opens our menu. A held modifier is a one-second gesture, so half a minute of
; continuous "down" is never real - send the missing up-event and reset the
; state. Keyboard assistant keeps a watchdog for the same phantom.
ModifierarVakt() {
    static sedan := 0
    nere := false
    try nere := GetKeyState(g_menyModifierare, "P")
    if !nere {
        sedan := 0
        return
    }
    if !sedan {
        sedan := A_TickCount
        return
    }
    if (A_TickCount - sedan > 30000) {
        try Send("{" g_menyModifierare " up}")
        sedan := 0
    }
}

; Registers the BUTTON only. The modifier is never registered as a compound
; prefix ("CapsLock & RButton"), it is read as physical key state in the
; criterion below - because registering a prefix makes AHK hold that key's
; events back from other scripts' hooks. That is exactly what killed § the
; moment DalSegno also claimed it (the first hook in the chain swallowed the
; press and the second never saw it, and § stopped typing at the same time),
; and it would break Keyboard assistant's CapsLock navigation layer the same
; way. Expanto reaches the same conclusion in its CapsHeld predicate.
;
; The button is configurable too, so a reload can change it and not just its
; state - whatever was registered last time has to be switched off first, and
; under the same #HotIf context it was created in, or the Off would address the
; criterion-less variant instead.
TillämpaMenyKortkommando() {
    global g_menyTangenter, g_menyKnapp
    fel := ""
    HotIf(MusÖverMålFönster)
    for tangent in g_menyTangenter
        try Hotkey(tangent, "Off")
    g_menyTangenter := []
    if (g_titelmeny && g_menyKnapp != "") {
        try {
            Hotkey(g_menyKnapp, MenyHögerNer, "On")
            Hotkey(g_menyKnapp " Up", VisaFönsterMeny, "On")
            g_menyTangenter := [g_menyKnapp, g_menyKnapp " Up"]
        } catch {
            fel .= "MenuButton: " g_menyKnapp "`n"
            try Hotkey(g_menyKnapp, "Off")   ; the down half may have taken
        }
    }
    HotIf()
    return fel
}

Registrera(namn, tangent, hanterare, &fel) {
    try {
        Hotkey(tangent, hanterare, "On")
        g_regKortkommandon.Push(tangent)
    } catch {
        fel .= namn ": " tangent "`n"
    }
}

SkrivStandardKonfig() {
    text := "
(
; Virtual desktop assistant - hotkeys
; AHK syntax: + = Shift, ^ = Ctrl, # = Win, ! = Alt.  Empty value = disabled.
; Changes are loaded via the tray menu: Reload configuration.
;
; The principle: Ctrl = switch, Alt = move the window, Ctrl+Alt = move and
; follow. Same for arrows (next/previous) and digits (desktop 1-9).
; Win+Ctrl+arrow already switches natively in Windows, hence no such line.
;   MoveNext=!#Right          Win+Alt+arrow      = move the window
;   MoveFollowNext=^!#Right   Win+Ctrl+Alt+arrow = move and follow
;   SwitchToPrefix=^#         Win+Ctrl+3         = switch to desktop 3
;   MoveToPrefix=!#           Win+Alt+3          = move the window to desktop 3
;   MoveFollowToPrefix=^!#    Win+Ctrl+Alt+3     = move and follow
;
; Note: ^#/!# + digit override Windows' taskbar shortcuts for pinned apps
; (switch-to and jump list respectively).
; Avoid ^! alone as a prefix - it is AltGr and breaks characters like @ and £.
[Hotkeys]
MoveNext=!#Right
MovePrevious=!#Left
MoveFollowNext=^!#Right
MoveFollowPrevious=^!#Left
SwitchToPrefix=^#
MoveToPrefix=!#
MoveFollowToPrefix=^!#
; MoveMenu opens the move menu (move / move and follow / always move) for
; the ACTIVE window - handy after Alt+Tab, when the title bar is far away.
MoveMenu=!#Down
ShowName=

[Display]
; Language of the visible UI: en or sv (English/Swedish). Also switchable
; from the tray menu.
Language=en
; NameInTray=1 shows the desktop name as text on the taskbar, to the left
; of the icon area (clock style). 0 turns it off.
NameInTray=1

[Mouse]
; Wheel=1: the mouse wheel over the taskbar switches desktop.
Wheel=1
; ArrowIcons=1: two extra tray icons (left/right arrow) that switch desktop
; on click. Drag them out of the icon overflow (the ^ chevron) once.
ArrowIcons=1
; TitleMenu=1: the window menu (DeskPilot's items, plus DalSegno's when that
; script is running) is enabled. The plain right-click is left to the app, so
; app title bar menus keep working exactly as before.
; TitleMenuExclude: process names (regex) for apps where the combination
; should pass through untouched. Empty = no exclusions.
TitleMenu=1
TitleMenuExclude=
; MenuModifier / MenuButton: hold the modifier and press the button. The
; modifier is read as physical key state, never registered as a hotkey prefix,
; so it can be a key other scripts already use - CapsLock works alongside
; Keyboard assistant's navigation layer and Expanto. Any key name works:
; CapsLock, Shift, Ctrl, §, XButton1. The button may be RButton, MButton,
; XButton1, XButton2.
MenuModifier=CapsLock
MenuButton=RButton
; MenuWholeWindow=1: the combination opens the menu anywhere in the window.
; Set to 0 to restrict it to the title bar (and the top ~44 px band of apps
; with custom-drawn title bars).
MenuWholeWindow=1

[Rules]
; Windows that should always be moved to a specific desktop. Easiest to
; create via right-click on the window's title bar, but editable here too:
;   RuleN=<desktop number> [/exe:<process regex>] [/follow] <title regex>
; /exe: matches the process executable name; /follow switches along when
; the rule moves a window. The title regex may be omitted if /exe: is given.
; Examples:
;   Rule1=3 (?i)^patienthistorik
;   Rule2=2 /exe:(?i)^spotify\.exe$ /follow
; Note: AHK's \w does not match åäö - write [\wåäöÅÄÖ] when needed.
)"
    FileAppend(text "`n", g_konfigFil, "UTF-16")
}

;--- UI strings ------------------------------------------------------------------

; All user-visible text. T("key") returns the string in the active language.
T(k) {
    static en := Map(
        "desktop", "Desktop", "of", "of", "windowTo", "Window → ",
        "dllMissing", "VirtualDesktopAccessor.dll missing – cannot move windows",
        "moveFailed", "Could not move the window",
        "menuMoveTo", "Move to desktop", "menuMoveFollow", "Move and follow",
        "menuAlwaysPre", "Always move `"", "menuAlwaysPost", "`" to",
        "menuPin", "Show on all desktops",
        "current", "  (current)",
        "ruleTitle", "New window rule",
        "rulePrompt1", "Regex matching titles of windows that should always be moved to ",
        "rulePrompt2", ".`nPre-filled: the exact current title. Tip: (?i) = case-insensitive.",
        "ruleInvalid", "Invalid regex – the rule was not saved",
        "ruleSaved", "Rule saved → ",
        "dsSave", "Save window position", "dsMove", "Move to saved position",
        "dsForget", "Forget saved position", "dsRule", "Create title rule…",
        "trayOpenUi", "Open DeskPilot…",
        "trayShowName", "Show desktop name", "trayOpenConfig", "Open configuration",
        "trayReloadConfig", "Reload configuration", "trayLanguage", "Language",
        "trayAutostart", "Start with Windows",
        "trayRestart", "Restart script", "trayExit", "Exit",
        "configLoaded", "Configuration loaded", "invalidHotkeys", "Invalid hotkeys:",
        "uiFail", "Could not start the GUI (WebView2 runtime missing?)",
        "rulesSaved", "Rules saved")
    static sv := Map(
        "desktop", "Skrivbord", "of", "av", "windowTo", "Fönster → ",
        "dllMissing", "VirtualDesktopAccessor.dll saknas – kan inte flytta fönster",
        "moveFailed", "Kunde inte flytta fönstret",
        "menuMoveTo", "Flytta till skrivbord", "menuMoveFollow", "Flytta och följ efter",
        "menuAlwaysPre", "Flytta alltid `"", "menuAlwaysPost", "`" till",
        "menuPin", "Visa på alla skrivbord",
        "current", "  (aktuellt)",
        "ruleTitle", "Ny fönsterregel",
        "rulePrompt1", "Regex som matchar titlar på fönster som alltid ska flyttas till ",
        "rulePrompt2", ".`nFörifyllt: exakt nuvarande titel. Tips: (?i) = skiftlägesokänslig.",
        "ruleInvalid", "Ogiltig regex – regeln sparades inte",
        "ruleSaved", "Regel sparad → ",
        "dsSave", "Spara fönstrets läge", "dsMove", "Flytta till sparat läge",
        "dsForget", "Glöm sparat läge", "dsRule", "Skapa titelregel…",
        "trayOpenUi", "Öppna DeskPilot…",
        "trayShowName", "Visa skrivbordsnamn", "trayOpenConfig", "Öppna konfigurationen",
        "trayReloadConfig", "Läs om konfigurationen", "trayLanguage", "Språk",
        "trayAutostart", "Starta med Windows",
        "trayRestart", "Starta om skriptet", "trayExit", "Avsluta",
        "configLoaded", "Konfigurationen inläst", "invalidHotkeys", "Ogiltiga kortkommandon:",
        "uiFail", "Kunde inte starta GUI:t (saknas WebView2-runtime?)",
        "rulesSaved", "Regler sparade")
    return (g_språk = "sv" ? sv : en).Get(k, k)
}

; Language switch from the tray menu: persist, reload, rebuild UI and
; restart the arrow helpers (they read the language at startup).
SättSpråk(lang, *) {
    global g_sistaLäge
    IniWrite(lang, g_konfigFil, "Display", "Language")
    LäsKonfig()
    InitTray()
    g_sistaLäge := ""      ; force tray tooltip/label refresh on next poll
    DetectHiddenWindows true
    SetTitleMatchMode 3
    for r in ["va", "ho"]
        if hwnd := WinExist("DeskPilotArrow " r)
            try WinClose(hwnd)
    SetTimer(UppdateraPilikoner, -600)   ; restart them once they have exited
}

;--- actions ---------------------------------------------------------------------

; Receiver for VDA_KOMMANDO (see the file header). Called e.g. from
; Keyboard assistant.
VdaKommando(wParam, lParam, msg, hwnd) {
    switch wParam {
        case 1: VäxlaTill(lParam)
        case 2: FlyttaAbsolut(lParam, false)
        case 3: FlyttaAbsolut(lParam, true)
        case 4: VisaOsd()
        case 5:
            LäsKonfig()
            InitTray()          ; the language may have changed
            UppdateraPilikoner()
        case 6: VäxlaRelativt(1)
        case 7: VäxlaRelativt(-1)
        case 8: ÖppnaUi()          ; open the settings GUI
        case 100:
            try FileDelete(A_ScriptDir "\ping.txt")
            try FileAppend("pong " lParam "`n", A_ScriptDir "\ping.txt", "UTF-8")
    }
    return 1
}

VisaOsdHotkey(*) {
    VisaOsd()
}

; Hotkey: opens the move menu for the ACTIVE window — the title bar menu is
; out of reach when you arrive at a window via Alt+Tab.
VisaFlyttMenyHotkey(*) {
    win := WinExist("A")
    if !win
        return
    try {
        if WinGetClass(win) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
            return
    } catch {
        return
    }
    s := LäsSkrivbordsStatus()
    if (!s || s.index = 0)
        return
    VisaFönstermenyn(win, s, true)
}

VäxlaTill(mål, *) {
    s := LäsSkrivbordsStatus()
    if !s || s.index = 0 || mål = s.index || mål < 1 || mål > s.count
        return
    BytSkrivbord(mål, s.index)
}

VäxlaRelativt(riktning) {
    s := LäsSkrivbordsStatus()
    if s && s.index
        VäxlaTill(s.index + riktning)
}

RullaFöregående(*) {
    VäxlaRelativt(-1)
}

RullaNästa(*) {
    VäxlaRelativt(1)
}

MusÖverFältet(*) {
    MouseGetPos , , &över
    try return WinGetClass(över) ~= "^(Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
    catch
        return false
}

; Starts/stops the two arrow icon processes (DeskPilotArrow.ahk) according to
; the config. The helpers tag their hidden windows "DeskPilotArrow va/ho".
UppdateraPilikoner() {
    DetectHiddenWindows true
    SetTitleMatchMode 3
    for r in ["va", "ho"] {
        hwnd := WinExist("DeskPilotArrow " r)
        if (g_pilikoner && !hwnd) {
            ; compiled: A_AhkPath is the exe itself — run the helper exe instead
            if A_IsCompiled {
                try Run('"' A_ScriptDir '\DeskPilotArrow.exe" ' r)
            } else {
                try Run('"' A_AhkPath '" "' A_ScriptDir '\DeskPilotArrow.ahk" ' r)
            }
        } else if (!g_pilikoner && hwnd) {
            try WinClose(hwnd)
        }
    }
}

FlyttaRelativt(riktning, följ, *) {
    s := LäsSkrivbordsStatus()
    if s && s.index != 0
        FlyttaAktivtFönster(s.index + riktning, följ, s)
}

FlyttaAbsolut(mål, följ, *) {
    s := LäsSkrivbordsStatus()
    if s && s.index != 0
        FlyttaAktivtFönster(mål, följ, s)
}

FlyttaAktivtFönster(mål, följ, s) {
    hwnd := WinExist("A")
    if !hwnd
        return
    try klass := WinGetClass(hwnd)
    catch
        return
    if klass ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
        return
    FlyttaFönsterTill(hwnd, mål, följ, s)
}

FlyttaFönsterTill(hwnd, mål, följ, s := 0) {
    if !IsObject(s)
        s := LäsSkrivbordsStatus()
    if (!s || s.index = 0 || mål < 1 || mål > s.count || mål = s.index)
        return
    if !g_dllLaddad {
        VisaOsdText(T("dllMissing"))
        return
    }
    if !DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber"
        , "ptr", hwnd, "int", mål - 1, "int") {
        VisaOsdText(T("moveFailed"))
        return
    }
    if följ {
        BytSkrivbord(mål, s.index)
        SetTimer(AktiveraFönster.Bind(hwnd), -400)
    } else {
        VisaOsdText(T("windowTo") NamnFörIndex(mål))
    }
}

; Switches desktop: directly via the dll, otherwise by sending Ctrl+Win+arrow
; one step at a time.
BytSkrivbord(mål, från) {
    if g_dllLaddad {
        DllCall("VirtualDesktopAccessor\GoToDesktopNumber", "int", mål - 1)
        return
    }
    diff := mål - från
    loop Abs(diff) {
        Send(diff > 0 ? "^#{Right}" : "^#{Left}")
        if A_Index < Abs(diff)
            Sleep(60)
    }
}

AktiveraFönster(hwnd) {
    try WinActivate(hwnd)
}

; The system DPI and font metrics are captured at process start, so the
; name label and OSD render at the wrong size after connecting/disconnecting
; monitors with a different scale — a clean restart is the simplest correct
; fix. Debounced: docking fires a burst of WM_DISPLAYCHANGE events.
SkärmbytesVakt(*) {
    SetTimer(OmstartEfterSkärmbyte, -2500)
}

; Docked DisplayPort monitors renegotiate periodically, firing spurious
; WM_DISPLAYCHANGE without any real change — reloading on each caused a
; restart loop (blinking tray icon/label). Only reload when the monitor
; layout actually differs from the one this instance started with.
OmstartEfterSkärmbyte() {
    if (SkärmSnapshot() = g_skärmLäge)
        return
    Reload()
}

SkärmSnapshot() {
    s := MonitorGetCount() "|" A_ScreenWidth "x" A_ScreenHeight
    loop MonitorGetCount() {
        try {
            MonitorGet(A_Index, &vä, &öv, &hö, &ne)
            s .= "|" vä "," öv "," hö "," ne
        }
    }
    return s
}

; Left click on the tray icon: a picker menu with all desktops. Returning a
; value eats the event so the menu's default item does not also fire;
; right-clicks fall through to AHK's normal tray menu handling.
TrayIkonKlick(wParam, lParam, msg, hwnd) {
    if (lParam = 0x202) {   ; WM_LBUTTONUP
        VisaSkrivbordsväljare()
        return 0
    }
}

VisaSkrivbordsväljare() {
    global g_menyÖppen
    if g_menyÖppen {   ; a second click closes the open menu instead
        DllCall("EndMenu")
        return
    }
    s := LäsSkrivbordsStatus()
    if (!s || s.index = 0)
        return
    m := Menu()
    loop s.count {
        n := A_Index
        m.Add(NamnFörIndex(n), VäljSkrivbord.Bind(n))
        if (n = s.index)
            m.Check(NamnFörIndex(n))
    }
    ; the click never activates us (tray icon / click-through label), so
    ; claim the foreground or the menu closes instantly
    TaFörgrund()
    g_menyÖppen := true
    m.Show()
    g_menyÖppen := false
}

; True when the cursor is inside the (visible) name label's rectangle —
; the label itself is click-through, so hit-testing never reports it.
MusÖverBricka(*) {
    try {
        if (!IsObject(g_bricka) || !DllCall("IsWindowVisible", "ptr", g_bricka.Hwnd))
            return false
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        WinGetPos(&bx, &by, &bb, &bh, g_bricka)
        return (mx >= bx && mx < bx + bb && my >= by && my < by + bh)
    } catch {
        return false
    }
}

BrickKlick(*) {
    VisaSkrivbordsväljare()
}

; Windows' foreground lock denies background processes; borrow rights from
; the current foreground window's thread and claim the foreground.
TaFörgrund() {
    trådVår := DllCall("GetCurrentThreadId", "uint")
    fg := DllCall("GetForegroundWindow", "ptr")
    trådFg := fg ? DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint") : 0
    if trådFg
        DllCall("AttachThreadInput", "uint", trådVår, "uint", trådFg, "int", 1)
    DllCall("SetForegroundWindow", "ptr", A_ScriptHwnd)
    if trådFg
        DllCall("AttachThreadInput", "uint", trådVår, "uint", trådFg, "int", 0)
}

VäljSkrivbord(n, *) {
    VäxlaTill(n)
}

;--- title bar menu and window rules --------------------------------------------

; True when the mouse is over a window we can offer the menu for. Runs as a
; hotkey criterion for every press of the menu combination, so everything here
; has to be quick — hence SendMessageTimeout with a short deadline in the title bar
; mode, so a hung window never freezes the mouse.
MusÖverMålFönster(hk := "", *) {
    static egenPid := DllCall("GetCurrentProcessId")
    ; while our menu is open: eat ALL right-clicks (the handler closes the
    ; menu). Without this fast path the hit test below can time out and let
    ; the click through physically, making the app show its own rendering of
    ; the system menu on top of ours.
    if g_menyÖppen
        return true
    ; the whole point of the physical read: no hook on the modifier, so no
    ; collision with whoever else uses it. Also the cheapest possible exit -
    ; this runs on every single right-click in the system, and for all but the
    ; held-modifier case it must cost nothing and let the click through.
    try {
        if !GetKeyState(g_menyModifierare, "P")
            return false
    } catch
        return false
    try {
        MouseGetPos , , &win
        if !win
            return false
        if WinGetClass(win) ~= "^(Shell_TrayWnd|Shell_SecondaryTrayWnd|Progman|WorkerW|#32768)$"
            return false   ; #32768 = open menus - never touch them
        ; ...but only the CLASSIC menu class is #32768. Apps draw their own
        ; caption menus as ordinary popups - Chromium as Chrome_WidgetWin_1,
        ; Terminal as a XAML popup - so the class test above sails straight
        ; past them. Treating one as a target window ate the click meant to
        ; dismiss it and stacked our menu on top of the app's own (the double
        ; menu, and the flicker when the two fought over the foreground); the
        ; popup has no title, so the rule item read: Always move "" to.
        if !ÄrRiktigtFönster(win)
            return false
        if WinGetPID(win) = egenPid
            return false
        ; windows parked on OTHER virtual desktops stay WS_VISIBLE but are
        ; DWM-cloaked, and WindowFromPoint happily returns such ghosts lying
        ; above the visible window in the z-order: the user clicks the window
        ; they SEE, we would target the invisible one (menu for the wrong
        ; window, e.g. a Terminal on another desktop). Physical clicks are
        ; routed past cloaked windows by the OS, so letting the click pass
        ; through reaches the window the user actually clicked.
        if ÄrCloakad(win)
            return false
        if ÄrEgenMenyApp(win)   ; TitleMenuExclude - leave these apps alone
            return false
        ; the menu is no longer tied to the title bar: the combination opens
        ; it anywhere in the window. That also retires the cross-process
        ; WM_NCHITTEST below, whose lparam sat in OUR DPI-virtualized coordinate
        ; space and was therefore meaningless to a per-monitor-aware app - the
        ; reason hit tests came back arbitrary on a mixed-DPI desktop.
        if g_helaFönstret
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
        ; the top band: apps with custom-drawn title bars (VS Code, the new
        ; Outlook) report HTCLIENT there, sometimes everywhere, so the band
        ; is accepted for every window.
        if (res = 1) {
            WinGetPos(, &wy, , , win)
            if ((my - wy) > Round(44 * A_ScreenDPI / 96))
                return false
            return true   ; Shift is the only variant, and it takes the band
        }
        return false
    } catch {
        return false
    }
}

MenyHögerNer(*) {
    ; eats the click so the app never sees it; the menu comes on
    ; release, otherwise the button-up can accidentally pick the first row
}

; Our own window menu, on the configured combination (default CapsLock held
; with a right-click, see [Mouse] MenuModifier). It deliberately no longer touches
; the window's real system menu: appending our items to another process's HMENU
; meant the app rendered them inside its own caption menu too (Edge's menu grew
; by exactly our four rows), and taking the plain right-click leaked clicks
; whenever our menu's modal loop blocked the hotkey criterion - which is what
; produced the double menus, the flicker, and menus built for the app's own
; menu popup. The combination is ours alone, so none of that can arise.
VisaFönsterMeny(*) {
    global g_menyÖppen
    ; the menu's message loop lets a second press re-enter here;
    ; close instead of stacking. The check-and-set runs under Critical so a
    ; second thread cannot slip in between the test and the assignment.
    Critical "On"
    if g_menyÖppen {
        Critical "Off"
        DllCall("EndMenu")
        return
    }
    g_menyÖppen := true
    Critical "Off"
    try {
        MouseGetPos , , &win
        if (!win || !WinExist(win))
            return
        if !ÄrRiktigtFönster(win)   ; an app's own menu popup - not our target
            return
        s := LäsSkrivbordsStatus()
        if (!s || s.index = 0)
            return
        VisaFönstermenyn(win, s)
    } finally {
        g_menyÖppen := false
    }
}

; ─── DalSegno integration ────────────────────────────────────────────────
; DalSegno (the window position keeper) exposes a command interface over the
; DALSEGNO_CMD registered message: wParam = target window, lParam 0 = query
; (returns 1 = manageable, +2 = saved position exists), 1 = save position,
; 2 = move to saved, 3 = forget, 4 = create title rule.

; The hwnd is cached: the full hidden-window title scan is too slow to run
; on every menu open, and the whole query sits in the gap between the eaten
; click and the menu appearing. Misses are cached too (rescan at most every
; 3 s) - without DalSegno running, the scan would otherwise run on every
; single right-click.
DalSegnoFönster() {
    static cached := 0, senast := 0
    prev := A_DetectHiddenWindows
    DetectHiddenWindows true
    if (cached && WinExist(cached)) {   ; the main window is hidden
        DetectHiddenWindows prev
        return cached
    }
    cached := 0
    if (A_TickCount - senast > 3000) {
        senast := A_TickCount
        SetTitleMatchMode 2
        cached := WinExist("\DalSegno.ahk ahk_class AutoHotkey")
    }
    DetectHiddenWindows prev
    return cached
}

DalSegnoFlaggor(win) {
    ds := DalSegnoFönster()
    if !ds
        return 0
    static msg := DllCall("RegisterWindowMessage", "str", "DALSEGNO_CMD", "uint")
    res := 0
    if !DllCall("SendMessageTimeoutW", "ptr", ds, "uint", msg, "ptr", win, "ptr", 0
        , "uint", 0x2, "uint", 120, "ptr*", &res)   ; SMTO_ABORTIFHUNG
        return 0
    return res
}

DalSegnoKommando(win, åtgärd) {
    ds := DalSegnoFönster()
    if !ds
        return
    static msg := DllCall("RegisterWindowMessage", "str", "DALSEGNO_CMD", "uint")
    try PostMessage(msg, win, åtgärd, , ds)
}

; Tells an app's own menu popup from a real window. Style bits are NOT usable
; for this: Claude's window is 0x14C70000 - a real window with WS_CAPTION but
; WITHOUT WS_SYSMENU, even though GetSystemMenu serves it a menu just fine, so
; demanding those bits turned away legitimate windows. What every observed
; popup had in common instead: no title at all (the rule item came out as
; Always move "" to) and no system menu of its own. Every real window we want
; the menu for has a title, so the pair is safe.
ÄrRiktigtFönster(hwnd) {
    try {
        if (WinGetExStyle(hwnd) & 0x8000000)       ; WS_EX_NOACTIVATE - menus, OSDs
            return false
        if (WinGetTitle(hwnd) != "")
            return true
        return DllCall("GetSystemMenu", "ptr", hwnd, "int", 0, "ptr") != 0
    } catch
        return false
}

; DWM-cloaked = invisible despite WS_VISIBLE: windows parked on other
; virtual desktops, UWP ghosts. See the check in MusÖverMålFönster.
ÄrCloakad(hwnd) {
    cloaked := 0
    try DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "uint*", &cloaked, "uint", 4)
    return cloaked != 0
}

ÄrEgenMenyApp(win) {
    if g_egenMeny = ""
        return false
    try return WinGetProcessName(win) ~= g_egenMeny
    catch
        return false
}

TräffTest(win, x, y) {
    res := 0
    DllCall("SendMessageTimeoutW", "ptr", win, "uint", 0x84, "ptr", 0
        , "ptr", ((y & 0xFFFF) << 16) | (x & 0xFFFF), "uint", 0x2, "uint", 50, "ptr*", &res)
    return res
}

; True if the UI Automation element at the point is dead window surface
; (Pane/Window/TitleBar without a name). Currently unused — kept as a
; building block; a UIA guard with click re-sending was reverted (see
; VisaFönsterMeny).
UiaTomYta(x, y) {
    static uia := 0
    try {
        if !uia {
            DllCall("ole32\CoCreateInstance"
                , "ptr", VdaGuid("{FF48DBA4-60EF-4201-AA87-54103EEF594E}")   ; CUIAutomation
                , "ptr", 0, "uint", 0x17
                , "ptr", VdaGuid("{00000000-0000-0000-C000-000000000046}")
                , "ptr*", &pUnk := 0, "hresult")
            uia := ComObjQuery(pUnk, "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
            ObjRelease(pUnk)
        }
        ComCall(7, uia, "int64", (x & 0xFFFFFFFF) | (y << 32), "ptr*", &pEl := 0)
        if !pEl
            return true
        el := ComValue(13, pEl)
        ComCall(21, el, "int*", &typ := 0)     ; get_CurrentControlType
        ComCall(23, el, "ptr*", &pB := 0)      ; get_CurrentName
        namn := pB ? StrGet(pB) : ""
        if pB
            DllCall("oleaut32\SysFreeString", "ptr", pB)
        return (typ = 50032 || typ = 50033 || typ = 50037) && namn = ""
    } catch {
        return true
    }
}

VdaGuid(s) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", s, "ptr", buf, "hresult")
    return buf
}

; The window menu: DeskPilot's own items, plus DalSegno's when that script is
; running. Shown at the mouse for Shift+right-click, anchored near the window
; for the MoveMenu hotkey.
VisaFönstermenyn(win, s, vidFönstret := false) {
    titel := ""
    try titel := WinGetTitle(win)
    kort := StrLen(titel) > 40 ? SubStr(titel, 1, 38) "…" : titel
    kort := StrReplace(kort, "&", "&&")
    flytta := Menu(), följ := Menu(), alltid := Menu()
    loop s.count {
        n := A_Index
        etikett := NamnFörIndex(n) (n = s.index ? T("current") : "")
        flytta.Add(etikett, FlyttaMenyVal.Bind(win, n, false))
        följ.Add(etikett, FlyttaMenyVal.Bind(win, n, true))
        alltid.Add(NamnFörIndex(n), NyRegelVal.Bind(win, n))
        if (n = s.index) {
            flytta.Disable(etikett)
            följ.Disable(etikett)
        }
    }
    m := Menu()
    m.Add(T("menuMoveTo"), flytta)
    m.Add(T("menuMoveFollow"), följ)
    m.Add(T("menuAlwaysPre") kort T("menuAlwaysPost"), alltid)
    if g_dllLaddad {
        m.Add(T("menuPin"), VäxlaPinning.Bind(win))
        if ÄrPinnat(win)
            m.Check(T("menuPin"))
    }
    ; DalSegno integration - same submenu as in the real system menu path
    dsFlaggor := DalSegnoFlaggor(win)
    if dsFlaggor {
        harPos := dsFlaggor & 2
        dsm := Menu()
        dsm.Add(T("dsSave"), (*) => DalSegnoKommando(win, 1))
        dsm.Add(T("dsMove"), (*) => DalSegnoKommando(win, 2))
        dsm.Add(T("dsForget"), (*) => DalSegnoKommando(win, 3))
        dsm.Add(T("dsRule"), (*) => DalSegnoKommando(win, 4))
        if !harPos {
            dsm.Disable(T("dsMove"))
            dsm.Disable(T("dsForget"))
        }
        m.Add("DalSegno", dsm)
    }
    ; the eaten click never activated anything, so without claiming the
    ; foreground Windows' foreground lock closes the menu immediately
    TaFörgrund()
    ; DPI: a menu is rendered - and the coordinates handed to it interpreted -
    ; in the DPI awareness of the calling thread. The script as a whole is
    ; SYSTEM DPI aware, and everything else it positions (the taskbar label,
    ; the OSD) is built on that, so the awareness is switched per-monitor-v2
    ; only for as long as the menu is up and then restored. Without it, on any
    ; monitor whose scaling differs from the primary one the menu came out at
    ; the wrong size and was placed by virtualized coordinates that resolve
    ; against the wrong monitor - it opened off-screen on the far monitors and
    ; oversized on the 125% one, while the log showed it opening perfectly.
    prevDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try {
        if vidFönstret {
            x := 0, y := 0
            try WinGetPos(&x, &y, , , win)
            CoordMode("Menu", "Screen")
            m.Show(x + 60, y + 50)
        } else {
            m.Show()
        }
    } finally {
        if prevDpi
            DllCall("SetThreadDpiAwarenessContext", "ptr", prevDpi, "ptr")
    }
}

FlyttaMenyVal(win, n, följ, *) {
    FlyttaFönsterTill(win, n, följ)
}

; Is this window pinned to every desktop? Every caller goes through here, because
; an older VirtualDesktopAccessor.dll may not export IsPinnedWindow at all — and an
; unguarded DllCall in the menu builder would take the whole title bar menu down
; with it, not just the pin item.
ÄrPinnat(win) {
    global g_dllLaddad
    if !g_dllLaddad
        return false
    r := 0
    try r := DllCall("VirtualDesktopAccessor\IsPinnedWindow", "ptr", win, "int")
    return r = 1
}

; Toggle "show on all desktops" (window pinning) via the dll. The change is
; visible instantly, so no OSD feedback is needed.
VäxlaPinning(win, *) {
    global g_dllLaddad
    if (!g_dllLaddad || !WinExist(win))
        return
    try {
        if ÄrPinnat(win)
            DllCall("VirtualDesktopAccessor\UnPinWindow", "ptr", win)
        else
            DllCall("VirtualDesktopAccessor\PinWindow", "ptr", win)
    }
}

NyRegelVal(win, n, *) {
    global g_kändaFönster
    titel := ""
    try titel := WinGetTitle(win)
    ib := InputBox(T("rulePrompt1") NamnFörIndex(n) T("rulePrompt2")
        , T("ruleTitle"), "w640 h150", "^" RegExEscape(titel) "$")
    if (ib.Result != "OK" || ib.Value = "")
        return
    try {
        RegExMatch("", ib.Value)
    } catch {
        VisaOsdText(T("ruleInvalid"))
        return
    }
    i := 1
    while IniRead(g_konfigFil, "Rules", "Rule" i, "") != ""
        i++
    IniWrite(n " " ib.Value, g_konfigFil, "Rules", "Rule" i)
    LäsRegler()
    g_kändaFönster := Map()   ; reset so the rule is applied in the next sweep
    VisaOsdText(T("ruleSaved") NamnFörIndex(n))
}

RegExEscape(s) {
    return RegExReplace(s, "[\\.*?+\[\]{}()|^$]", "\$0")
}

; Rule format: RuleN=<desktop> [/exe:<process regex>] [/follow] <title regex>
; The title regex may be empty when /exe: is given (any window of that
; process). /follow switches along when the rule moves a window.
LäsRegler() {
    global g_regler
    g_regler := []
    sektion := IniRead(g_konfigFil, "Rules", , "")
    loop parse sektion, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^Rule\d+\s*=\s*(\d+)\s*(.*)$", &m)
            continue
        rest := Trim(m[2]), exe := "", följ := false
        loop {
            if RegExMatch(rest, "^/exe:(\S+)\s*(.*)$", &e) {
                exe := e[1], rest := e[2]
                continue
            }
            if RegExMatch(rest, "^/follow(?:\s+(.*))?$", &f) {
                följ := true, rest := f[1]
                continue
            }
            break
        }
        rest := Trim(rest)
        if (exe = "" && rest = "")
            continue   ; a rule needs at least an exe or a title pattern
        g_regler.Push({mål: Integer(m[1]), exe: exe, följ: följ, regex: rest})
    }
}

; Walks the windows once a second and moves those that are new (or just got
; a title) and match a rule. Windows moved back manually are left alone —
; a rule only triggers when the title CHANGES into matching.
RegelSvep() {
    global g_kändaFönster
    static egenPid := DllCall("GetCurrentProcessId")
    if (!g_regler.Length || !g_dllLaddad)
        return
    nya := Map()
    for hwnd in WinGetList() {
        titel := ""
        try titel := WinGetTitle(hwnd)
        nya[hwnd] := titel
        if titel = ""
            continue
        gammal := g_kändaFönster.Get(hwnd, "")
        if (gammal = titel)
            continue
        try {
            if WinGetPID(hwnd) = egenPid
                continue
        } catch {
            continue
        }
        for regel in g_regler {
            try {
                if (regel.exe != "" && !(WinGetProcessName(hwnd) ~= regel.exe))
                    continue
                if (regel.regex != "") {
                    if !(titel ~= regel.regex)
                        continue
                    if (gammal != "" && gammal ~= regel.regex)
                        continue   ; matched before too - no new event
                } else if (gammal != "") {
                    continue       ; exe-only rules act on new windows only
                }
            } catch {
                continue   ; broken regex in the config - skip the rule
            }
            nr := DllCall("VirtualDesktopAccessor\GetWindowDesktopNumber", "ptr", hwnd, "int")
            if (nr >= 0 && nr != regel.mål - 1) {
                if (DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber"
                    , "ptr", hwnd, "int", regel.mål - 1, "int") && regel.följ) {
                    VäxlaTill(regel.mål)
                    SetTimer(AktiveraFönster.Bind(hwnd), -400)
                }
            }
            break
        }
    }
    g_kändaFönster := nya
}

;--- taskbar name label ----------------------------------------------------------

BrickaVakt() {
    UppdateraBricka()
}

; Shows the desktop name the way the clock shows time/date: bare text on the
; taskbar, just left of the icon area. The label is made a CHILD WINDOW of
; Shell_TrayWnd (SetParent) — then it always sits on top of the bar
; regardless of z-order (clicking the bar used to cover it), follows it
; through auto-hide and is covered by fullscreen windows just like the bar
; itself. The background is a key color close to the bar's tone (TransColor)
; so only the text shows. -DPIScale keeps all coordinates in physical pixels.
UppdateraBricka() {
    ; DPI: the taskbar belongs to Explorer, which is per-monitor aware, while
    ; this script is system-DPI aware - so on a mixed-scaling desktop its rect
    ; comes back in a space that does not line up with the monitors. Measured
    ; on this setup: the bar reports x=1920 system-aware and x=0 per-monitor,
    ; which placed the label at x=4775, outside the 3840-wide primary monitor.
    ; Reading the bar, its icon area and placing the label all happen under
    ; per-monitor-v2 so the three agree; the context is restored on the way
    ; out, since everything else in the script is built on system awareness.
    prevDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try
        UppdateraBrickaKärna()
    finally {
        if prevDpi
            DllCall("SetThreadDpiAwarenessContext", "ptr", prevDpi, "ptr")
    }
}

UppdateraBrickaKärna() {
    global g_bricka, g_brickaText
    ; never touch the label while one of our menus is open: the timer fires
    ; inside the menu's modal loop, and Show/SetWindowPos dismisses the menu
    if g_menyÖppen
        return
    ; the poll and guard timers can interrupt each other mid-rebuild —
    ; without a latch, Destroy() runs before g_bricka is repointed
    static upptagen := false
    if upptagen
        return
    upptagen := true
    try UppdateraBrickaInre()
    upptagen := false
}

UppdateraBrickaInre() {
    global g_bricka, g_brickaText
    s := g_sistaS
    if (!g_namnITray || !IsObject(s)) {
        DöljBricka()
        return
    }
    fält := WinExist("ahk_class Shell_TrayWnd")
    if !fält {
        DöljBricka()
        return
    }
    try WinGetPos(&fältX, &fältY, &fältBredd, &fältHöjd, fält)
    catch
        return
    if BrickaSkaDöljas(fältY) {
        DöljBricka()
        return
    }
    try ControlGetPos(&ikonX, , , , "TrayNotifyWnd1", fält)
    catch
        ikonX := fältBredd - 260   ; rough fallback if the control disappears
    ljust := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        , "SystemUsesLightTheme", 0)
    rad1 := s.name != "" ? s.name : T("desktop") " " s.index
    rad2 := s.name != "" ? T("desktop") " " s.index " " T("of") " " s.count : ""
    ; The app buttons grow rightwards as windows are opened and eventually
    ; reach the strip we live in, drawing them underneath the label. Try the
    ; forms from richest to barest and take the first one whose left edge
    ; lands on free bar: two lines, then one compact line, then just the
    ; counter. Only if even that collides does the label go away, because
    ; vanishing exactly when many windows are open is the worst answer.
    ;
    ; MSTaskListWClass1 is NOT usable for this: on Windows 11 it is a
    ; vestigial control that reported the buttons ending at 761 while they
    ; actually reached 1082. The buttons are XAML, so the only honest probe
    ; is asking UI Automation what sits at a given point.
    marginal := Round(12 * BrickaDpi(fält) / 96)
    mittY := fältY + fältHöjd // 2
    former := [[rad1, rad2]]
    if (rad2 != "")
        former.Push([rad1 " " s.index "/" s.count, ""])
    former.Push([s.index "/" s.count, ""])
    rad1 := "", rad2 := ""
    for f in former {
        bredd := BrickaBredd(f[1], f[2], fält)
        if !UiaKnappVid(fältX + ikonX - bredd - marginal, mittY) {
            rad1 := f[1], rad2 := f[2]
            break
        }
    }
    if (rad1 = "") {
        DöljBricka()
        return
    }
    innehåll := rad1 "|" rad2 "|" ljust
    if (innehåll != g_brickaText || !IsObject(g_bricka)
        || !DllCall("IsWindow", "ptr", g_bricka.Hwnd)) {
        g_brickaText := innehåll
        if IsObject(g_bricka)
            try g_bricka.Destroy()
        skala := BrickaDpi(fält) / 96
        nyckel := ljust ? "EEEEEE" : "202020"
        ; a topmost STAND-ALONE window: as a taskbar child the composition
        ; surface repainted over the label on every tray icon animation
        ; (OneDrive sync spinner etc.) — a separate top-level window can
        ; never be painted over by it. Click-through (E0x20); clicks are
        ; caught by an LButton hook hotkey over the label's rect.
        b := Gui("-DPIScale -Caption +ToolWindow +AlwaysOnTop +E0x08000000 +E0x20"
            , "VDA namnbricka")
        b.BackColor := nyckel
        b.MarginX := Round(10 * skala), b.MarginY := Round(3 * skala)
        b.SetFont("s9 q4 c" (ljust ? "1A1A1A" : "F5F5F5"), "Segoe UI Variable Display")
        b.Add("Text", "Center", rad2 != "" ? rad1 "`n" rad2 : rad1)
        b.Show("NoActivate Hide AutoSize")
        WinSetTransColor(nyckel, b)
        g_bricka := b
    }
    g_bricka.GetPos(, , &bb, &bh)
    g_bricka.Show("NoActivate x" (fältX + ikonX - bb - Round(12 * BrickaDpi(fält) / 96))
        . " y" (fältY + (fältHöjd - bh) // 2))
    ; clicking the taskbar raises it within the topmost band — re-assert
    DllCall("SetWindowPos", "ptr", g_bricka.Hwnd, "ptr", 0
        , "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)   ; TOP, NOMOVE|NOSIZE|NOACTIVATE
}

; Is a taskbar button sitting at this screen point? UIA_ButtonControlTypeId
; is 50000. Answers false on any failure: a missing answer must not be what
; makes the label disappear. Cached briefly - the guard timer asks four times
; a second and the taskbar does not rearrange that fast.
UiaKnappVid(x, y) {
    static senast := 0, senastNyckel := "", senastSvar := false
    nyckel := x "," y
    if (nyckel = senastNyckel && A_TickCount - senast < 1000)
        return senastSvar
    svar := false
    try {
        typ := UiaTypVid(x, y)
        svar := (typ = 50000)
    }
    senast := A_TickCount, senastNyckel := nyckel, senastSvar := svar
    return svar
}

UiaTypVid(x, y) {
    static uia := 0
    if !uia {
        DllCall("ole32\CoCreateInstance"
            , "ptr", VdaGuid("{FF48DBA4-60EF-4201-AA87-54103EEF594E}")   ; CUIAutomation
            , "ptr", 0, "uint", 0x17
            , "ptr", VdaGuid("{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
            , "ptr*", &p := 0, "hresult")
        uia := ComValue(13, p)
    }
    ComCall(7, uia, "int64", (x & 0xFFFFFFFF) | (y << 32), "ptr*", &pEl := 0)
    if !pEl
        return 0
    el := ComValue(13, pEl)
    ComCall(21, el, "int*", &typ := 0)     ; get_CurrentControlType
    return typ
}

; How wide the label would be with this content, measured by rendering it in
; a hidden throwaway Gui with the same font and margins. Cached, since the
; guard timer asks four times a second and the answer only changes with the
; text or the scale.
BrickaBredd(rad1, rad2, fält) {
    static cache := Map()
    skala := BrickaDpi(fält) / 96
    nyckel := rad1 "|" rad2 "|" skala
    if cache.Has(nyckel)
        return cache[nyckel]
    b := 0
    try {
        g := Gui("-DPIScale -Caption +ToolWindow +E0x08000000")
        g.MarginX := Round(10 * skala), g.MarginY := Round(3 * skala)
        g.SetFont("s9 q4", "Segoe UI Variable Display")
        g.Add("Text", "Center", rad2 != "" ? rad1 "`n" rad2 : rad1)
        g.Show("NoActivate Hide AutoSize")
        g.GetPos(, , &b)
        g.Destroy()
    }
    if (cache.Count > 40)
        cache.Clear()
    return cache[nyckel] := b
}

; The taskbar's own DPI - what the label must be scaled by. Its monitor is
; not necessarily the primary one, so A_ScreenDPI is the wrong number.
BrickaDpi(fält) {
    dpi := 0
    try dpi := DllCall("GetDpiForWindow", "ptr", fält, "uint")
    return dpi ? dpi : A_ScreenDPI
}

; A stand-alone label must handle what a taskbar child got for free:
; hide when the taskbar is auto-hidden or a fullscreen window covers the
; monitor it sits on. Called from within the per-monitor-aware section, so
; every rectangle here is in the same space.
BrickaSkaDöljas(fältY) {
    ; auto-hidden: the bar has slid below the bottom edge of ITS monitor
    botten := A_ScreenHeight
    try {
        fält := WinExist("ahk_class Shell_TrayWnd")
        if fält {
            WinGetPos(&fx, &fy, &fb, &fh, fält)
            loop MonitorGetCount() {
                MonitorGet(A_Index, &mv, &mö, &mh, &mn)
                if (fx + fb // 2 >= mv && fx + fb // 2 < mh) {
                    botten := mn
                    break
                }
            }
        }
    }
    if (fältY + 8 > botten)
        return true
    fg := WinExist("A")
    if !fg
        return false
    try {
        if WinGetClass(fg) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
            return false
        WinGetPos(&ax, &ay, &ab, &ah, fg)
        MonitorGet(MonitorGetPrimary(), &mv, &mö, &mh, &mn)
        return (ax <= mv && ay <= mö && ax + ab >= mh && ay + ah >= mn)
    } catch {
        return false
    }
}

DöljBricka() {
    global g_bricka
    if IsObject(g_bricka)
        g_bricka.Hide()
}

;--- tray and OSD ----------------------------------------------------------------

UppdateraTray(s) {
    fil := s.index = 0 ? "d_unknown.ico" : s.index > 9 ? "d_more.ico" : "d" s.index ".ico"
    sökväg := A_ScriptDir "\icons\" fil
    if FileExist(sökväg)
        TraySetIcon(sökväg, , 1)
    A_IconTip := OsdText(s) " (" T("of") " " s.count ")"
}

OsdText(s) {
    return s.name != "" ? s.index " · " s.name : T("desktop") " " s.index
}

VisaOsd(s := 0) {
    if !s
        s := LäsSkrivbordsStatus()
    if !s
        return
    VisaOsdText(OsdText(s))
}

VisaOsdText(text) {
    global g_osd
    if IsObject(g_osd) {
        g_osd.Destroy()
        g_osd := 0
    }
    osd := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x20")
    osd.BackColor := "1E293B"
    osd.MarginX := 34, osd.MarginY := 18
    osd.SetFont("s20 w700 cWhite", "Segoe UI")
    osd.Add("Text", "Center", text)
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", osd.Hwnd
        , "uint", 33, "uint*", 2, "uint", 4)   ; DWMWA_WINDOW_CORNER_PREFERENCE = ROUND

    ; place on the monitor holding the mouse, a bit down from the top edge
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    skärm := 1
    loop MonitorGetCount() {
        MonitorGet(A_Index, &vä, &öv, &hö, &ne)
        if (mx >= vä && mx < hö && my >= öv && my < ne) {
            skärm := A_Index
            break
        }
    }
    MonitorGetWorkArea(skärm, &vä, &öv, &hö, &ne)
    osd.Show("NoActivate Hide AutoSize")
    osd.GetPos(, , &b, &h)
    osd.Show("NoActivate x" (vä + (hö - vä - b) // 2) " y" (öv + Round((ne - öv) * 0.10)))
    WinSetTransparent(242, osd)
    g_osd := osd
    SetTimer(DöljOsd, -1500)
}

DöljOsd() {
    global g_osd
    if IsObject(g_osd) {
        g_osd.Destroy()
        g_osd := 0
    }
}

; =============================================================================
;  Settings GUI (WebView2) - same architecture as DalSegno: one state object
;  pushed into window.receiveState, {action:…} messages posted back.
; =============================================================================

ÖppnaUi(*) {
    global g_uiWin, g_uiCtrl, g_uiCore
    if g_uiWin {
        g_uiWin.Show()
        PassaUiTillSkärm()
        SkickaUiTillstånd()
        return
    }
    DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "str", "DeskPilot.Application.1")
    g_uiWin := Gui("+Resize +MinSize640x460", "DeskPilot")
    g_uiWin.OnEvent("Close", (*) => (SparaUiGeometri(), g_uiWin.Hide()))
    g_uiWin.OnEvent("Size", UiStorlek)
    g_uiWin.Show(LäsUiGeometri())
    PassaUiTillSkärm()
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g_uiWin.hwnd, "uint", 20, "int*", 1, "uint", 4)
    try {
        ico := LoadPicture(A_ScriptDir "\icons\app.ico", "Icon1 w32 h32", &_t)
        SendMessage(0x80, 1, ico, , g_uiWin.hwnd)
        DllCall("SetClassLongPtr", "ptr", g_uiWin.hwnd, "int", -14, "ptr", ico)
    }
    try {
        ; own user data folder - an empty one falls back to Edge's profile,
        ; which cannot be shared with a running browser
        dataDir := EnvGet("LOCALAPPDATA") "\DeskPilot\WebView2"
        try DirCreate(dataDir)
        g_uiCtrl := WebView2.create(g_uiWin.hwnd, , 0, dataDir, "", 0
            , A_ScriptDir "\lib\WebView2Loader.dll")
        g_uiCtrl.Fill()
        g_uiCore := g_uiCtrl.CoreWebView2
        g_uiCore.add_WebMessageReceived(UiMeddelande)
        g_uiCore.Navigate("file:///" StrReplace(A_ScriptDir "\ui\index.html", "\", "/"))
    } catch as e {
        g_uiWin.Destroy()
        g_uiWin := 0, g_uiCtrl := 0, g_uiCore := 0
        TrayTip(T("uiFail") " (" e.Message ")", "DeskPilot", "Iconx")
    }
}

UiStorlek(gui, minMax, w, h) {
    global g_uiCtrl
    if (minMax != -1 && IsObject(g_uiCtrl))
        try g_uiCtrl.Fill()
}

LäsUiGeometri() {
    b := 980, h := 660
    try {
        b := Integer(IniRead(g_konfigFil, "Window", "W", "980"))
        h := Integer(IniRead(g_konfigFil, "Window", "H", "660"))
    }
    x := IniRead(g_konfigFil, "Window", "X", "")
    y := IniRead(g_konfigFil, "Window", "Y", "")
    opt := "w" Max(640, b) " h" Max(460, h)
    return (x != "" && y != "") ? "x" x " y" y " " opt : opt
}

SparaUiGeometri() {
    global g_uiWin
    if !g_uiWin
        return
    try {
        if (WinGetMinMax(g_uiWin.hwnd) != 0)
            return
        ; position from the window rect, size from the CLIENT rect - Show("w…")
        ; sizes the client area, so storing the outer size grows the window
        WinGetPos(&x, &y, , , g_uiWin.hwnd)
        WinGetClientPos(, , &b, &h, g_uiWin.hwnd)
        IniWrite(x, g_konfigFil, "Window", "X"), IniWrite(y, g_konfigFil, "Window", "Y")
        IniWrite(b, g_konfigFil, "Window", "W"), IniWrite(h, g_konfigFil, "Window", "H")
    }
}

PassaUiTillSkärm() {
    global g_uiWin
    if !g_uiWin
        return
    try {
        if (WinGetMinMax(g_uiWin.hwnd) != 0)
            return
        WinGetPos(&x, &y, &b, &h, g_uiWin.hwnd)
        MonitorGetWorkArea(SkärmFörFönster(g_uiWin.hwnd), &vä, &öv, &hö, &ne)
        b := Min(b, hö - vä), h := Min(h, ne - öv)
        WinMove(Min(Max(x, vä), hö - b), Min(Max(y, öv), ne - h), b, h, g_uiWin.hwnd)
    }
}

SkärmFörFönster(hwnd) {
    try {
        WinGetPos(&x, &y, &b, &h, hwnd)
        mx := x + b // 2, my := y + h // 2
        loop MonitorGetCount() {
            MonitorGet(A_Index, &vä, &öv, &hö, &ne)
            if (mx >= vä && mx < hö && my >= öv && my < ne)
                return A_Index
        }
    }
    return MonitorGetPrimary()
}

UiSkicka(skript) {
    global g_uiReady, g_uiCore
    if (!g_uiReady || !IsObject(g_uiCore))
        return
    try g_uiCore.ExecuteScriptAsync(skript)
    catch
        g_uiReady := false
}

SkickaUiTillstånd() {
    global g_uiReady, g_regler
    if !g_uiReady
        return
    s := LäsSkrivbordsStatus()
    regler := []
    for r in g_regler
        regler.Push(Map("desktop", r.mål, "exe", r.exe, "title", r.regex
            , "follow", r.följ ? 1 : 0))
    hk := Map()
    for namn in ["MoveNext", "MovePrevious", "MoveFollowNext", "MoveFollowPrevious"
        , "MoveMenu", "ShowName", "SwitchToPrefix", "MoveToPrefix", "MoveFollowToPrefix"]
        hk[namn] := IniRead(g_konfigFil, "Hotkeys", namn, "")
    tillstånd := Map(
        "desktops", Map("count", s ? s.count : 0, "index", s ? s.index : 0)
        , "settings", Map(
            "lang", g_språk
            , "nameInTray", g_namnITray ? 1 : 0
            , "wheel", g_rullhjul ? 1 : 0
            , "arrowIcons", g_pilikoner ? 1 : 0
            , "titleMenu", g_titelmeny ? 1 : 0
            , "menuModifier", g_menyModifierare
            , "menuButton", g_menyKnapp
            , "wholeWindow", g_helaFönstret ? 1 : 0
            , "exclude", g_egenMeny)
        , "hotkeys", hk
        , "rules", regler
        , "windows", ListaFönster())
    UiSkicka("window.receiveState(" JSON.Dump(tillstånd) ")")
}

; Windows worth offering a rule for: titled, not ours, not shell furniture.
ListaFönster() {
    lista := []
    for hwnd in WinGetList() {
        try {
            titel := WinGetTitle(hwnd)
            if (titel = "" || !ÄrRiktigtFönster(hwnd))
                continue
            if WinGetClass(hwnd) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
                continue
            lista.Push(Map("hwnd", hwnd, "exe", WinGetProcessName(hwnd)
                , "title", SubStr(titel, 1, 90), "desktop", SkrivbordFörFönster(hwnd)))
        }
    }
    return lista
}

SkrivbordFörFönster(hwnd) {
    if !g_dllLaddad
        return ""
    n := 0
    try n := DllCall("VirtualDesktopAccessor\GetWindowDesktopNumber", "ptr", hwnd, "int")
    return (n >= 0 && n < 99) ? n + 1 : ""
}

UiMeddelande(sender, args) {
    global g_uiReady
    try msg := JSON.Load(args.WebMessageAsJson)
    catch
        return
    switch msg["action"] {
        case "ready":
            g_uiReady := true
            SkickaUiTillstånd()
        case "refresh":
            SkickaUiTillstånd()
        case "setOption":
            UiSättVal(msg["name"], msg["value"])
        case "setHotkey":
            UiSättKortkommando(msg["name"], msg["key"])
        case "setLang":
            IniWrite(msg["lang"] = "sv" ? "sv" : "en", g_konfigFil, "Display", "Language")
            LäsOmKonfig()
        case "saveRules":
            UiSparaRegler(msg["rules"])
        case "openConfig":
            try Run('notepad.exe "' g_konfigFil '"')
        case "reloadConfig":
            LäsOmKonfig()
    }
}

UiSättVal(namn, värde) {
    sektion := (namn = "NameInTray" || namn = "Language") ? "Display" : "Mouse"
    IniWrite(värde, g_konfigFil, sektion, namn)
    LäsOmKonfig()
}

; A hotkey edited in the GUI. Written first, then the whole configuration is
; re-read - LäsKonfig already validates every hotkey and reports the bad ones,
; so there is no second, divergent validator here.
UiSättKortkommando(namn, tangent) {
    IniWrite(tangent, g_konfigFil, "Hotkeys", namn)
    LäsOmKonfig()
}

UiSparaRegler(regler) {
    ; the ini section is rewritten wholesale: rule order is meaningful (first
    ; match wins) and editing in place would not preserve it
    try IniDelete(g_konfigFil, "Rules")
    n := 0
    for r in regler {
        rad := r["desktop"]
        if (r["exe"] != "")
            rad .= " /exe:" r["exe"]
        if r["follow"]
            rad .= " /follow"
        if (r["title"] != "")
            rad .= " " r["title"]
        IniWrite(rad, g_konfigFil, "Rules", "Rule" (++n))
    }
    LäsOmKonfig()
    TrayTip(T("rulesSaved"), "DeskPilot")
}

InitTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add(T("trayOpenUi"), (*) => ÖppnaUi())
    A_TrayMenu.Default := T("trayOpenUi")
    A_TrayMenu.Add()
    A_TrayMenu.Add(T("trayShowName"), (*) => VisaOsd())
    A_TrayMenu.Add()
    A_TrayMenu.Add(T("trayOpenConfig"), (*) => Run('notepad.exe "' g_konfigFil '"'))
    A_TrayMenu.Add(T("trayReloadConfig"), LäsOmKonfig)
    språkMeny := Menu()
    språkMeny.Add("English", SättSpråk.Bind("en"))
    språkMeny.Add("Svenska", SättSpråk.Bind("sv"))
    språkMeny.Check(g_språk = "sv" ? "Svenska" : "English")
    A_TrayMenu.Add(T("trayLanguage"), språkMeny)
    A_TrayMenu.Add(T("trayAutostart"), VäxlaAutostart)
    if FileExist(AutostartGenväg())
        A_TrayMenu.Check(T("trayAutostart"))
    A_TrayMenu.Add()
    A_TrayMenu.Add(T("trayRestart"), (*) => Reload())
    A_TrayMenu.Add(T("trayExit"), (*) => ExitApp())
    A_TrayMenu.Default := T("trayShowName")
    A_TrayMenu.ClickCount := 1
}

LäsOmKonfig(*) {
    ; an open GUI must not keep showing the values it just replaced
    SetTimer(SkickaUiTillstånd, -120)
    LäsKonfig()
    InitTray()          ; the language may have changed in the config file
    UppdateraPilikoner()
    TrayTip(T("configLoaded"), "DeskPilot")
}

AutostartGenväg() {
    return A_Startup "\DeskPilot.lnk"
}

; Tray toggle: create or remove a shortcut in the user's Startup folder.
VäxlaAutostart(*) {
    länk := AutostartGenväg()
    if FileExist(länk) {
        try FileDelete(länk)
    } else {
        try {
            if A_IsCompiled
                FileCreateShortcut(A_ScriptFullPath, länk, A_ScriptDir)
            else
                FileCreateShortcut(A_AhkPath, länk, A_ScriptDir, '"' A_ScriptFullPath '"')
        }
    }
    InitTray()   ; refresh the check mark
}

; Silent tray apps need a trace when something breaks; no dialog, or a
; crashing timer would spam a box every 250 ms.
LoggaFel(err, mode) {
    try FileAppend(FormatTime() "  " err.Message " (" err.File ":" err.Line ")`n"
        , A_ScriptDir "\error.log", "UTF-8")
    return 1
}
