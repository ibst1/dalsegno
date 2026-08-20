;===============================================================================
; DeskPilot — v1.0.0 (2026-08-20)
;
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
Persistent

VD_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops"
VDA_DLL := A_ScriptDir "\VirtualDesktopAccessor.dll"

g_konfigFil := A_ScriptDir "\DeskPilot config.ini"
g_regKortkommandon := []
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
g_titelmeny := true  ; right-click on a window title bar shows the move menu
g_egenMeny := ""     ; process regex for apps whose title clicks are left untouched
g_bandAppar := "(?i)^olk\.exe$"  ; apps where plain clicks in the top band also count
g_menyÖppen := false  ; the title bar menu is currently showing (drives click handling)
g_regler := []       ; [{mål, regex}] — windows that should always be moved
g_kändaFönster := Map()  ; hwnd → title, for the rule sweep's new/changed detection
g_språk := "en"      ; UI language: "en" or "sv" ([Display] Language)

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
PollSkrivbord()      ; set the icon right away; the first call shows no OSD
SetTimer(PollSkrivbord, 250)
SetTimer(BrickaVakt, 500)   ; keeps the name label placed and visible
SetTimer(RegelSvep, 1000)   ; applies window rules to new/retitled windows

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
    global g_titelmeny, g_egenMeny, g_bandAppar, g_språk
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
    g_bandAppar := IniRead(g_konfigFil, "Mouse", "TitleMenuBand", "(?i)^olk\.exe$")
    HotIf(MusÖverTitelrad)
    Hotkey("RButton", TitelHögerNer, g_titelmeny ? "On" : "Off")
    Hotkey("RButton Up", VisaFönsterMeny, g_titelmeny ? "On" : "Off")
    Hotkey("+RButton", TitelHögerNer, g_titelmeny ? "On" : "Off")
    Hotkey("+RButton Up", VisaFönsterMeny, g_titelmeny ? "On" : "Off")
    HotIf()
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
    if fel != "" {
        TrayTip(T("invalidHotkeys") "`n" fel, "DeskPilot", "Iconx")
        try FileAppend(FormatTime() "  Invalid hotkeys: " StrReplace(fel, "`n", " / ") "`n"
            , A_ScriptDir "\error.log", "UTF-8")
    }
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
; TitleMenu=1: right-clicking a window title bar shows the window's real
; system menu - including the app's and e.g. PowerToys' own additions (Edge
; puts its special items in exactly that menu) - with the desktop move items
; at the bottom. TitleMenuExclude: process names (regex) for apps where the
; right-click should instead pass through completely untouched (the move
; menu is then reached with Shift+right-click). Empty = no exclusions.
TitleMenu=1
TitleMenuExclude=
; TitleMenuBand: apps (process regex) with a custom-drawn title bar that
; reports client area everywhere (e.g. the new Outlook) - there a plain
; right-click in the window's top band (about 44 px) always shows the move
; menu. Note: any app-specific right-click menus inside that band (e.g. the
; search box's) cannot be reached there.
TitleMenuBand=(?i)^olk\.exe$

[Rules]
; Windows that should always be moved to a specific desktop. Easiest to
; create via right-click on the window's title bar, but editable here too:
;   RuleN=<desktop number> <regex matching the window title>
; Example:  Rule1=3 (?i)^patienthistorik
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
        "current", "  (current)",
        "ruleTitle", "New window rule",
        "rulePrompt1", "Regex matching titles of windows that should always be moved to ",
        "rulePrompt2", ".`nPre-filled: the exact current title. Tip: (?i) = case-insensitive.",
        "ruleInvalid", "Invalid regex – the rule was not saved",
        "ruleSaved", "Rule saved → ",
        "trayShowName", "Show desktop name", "trayOpenConfig", "Open configuration",
        "trayReloadConfig", "Reload configuration", "trayLanguage", "Language",
        "trayRestart", "Restart script", "trayExit", "Exit",
        "configLoaded", "Configuration loaded", "invalidHotkeys", "Invalid hotkeys:")
    static sv := Map(
        "desktop", "Skrivbord", "of", "av", "windowTo", "Fönster → ",
        "dllMissing", "VirtualDesktopAccessor.dll saknas – kan inte flytta fönster",
        "moveFailed", "Kunde inte flytta fönstret",
        "menuMoveTo", "Flytta till skrivbord", "menuMoveFollow", "Flytta och följ efter",
        "menuAlwaysPre", "Flytta alltid `"", "menuAlwaysPost", "`" till",
        "current", "  (aktuellt)",
        "ruleTitle", "Ny fönsterregel",
        "rulePrompt1", "Regex som matchar titlar på fönster som alltid ska flyttas till ",
        "rulePrompt2", ".`nFörifyllt: exakt nuvarande titel. Tips: (?i) = skiftlägesokänslig.",
        "ruleInvalid", "Ogiltig regex – regeln sparades inte",
        "ruleSaved", "Regel sparad → ",
        "trayShowName", "Visa skrivbordsnamn", "trayOpenConfig", "Öppna konfigurationen",
        "trayReloadConfig", "Läs om konfigurationen", "trayLanguage", "Språk",
        "trayRestart", "Starta om skriptet", "trayExit", "Avsluta",
        "configLoaded", "Konfigurationen inläst", "invalidHotkeys", "Ogiltiga kortkommandon:")
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
    VisaReplikaMeny(win, s, true)
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
            try Run('"' A_AhkPath '" "' A_ScriptDir '\DeskPilotArrow.ahk" ' r)
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

;--- title bar menu and window rules --------------------------------------------

; True when the mouse is on a window title bar (WM_NCHITTEST = HTCAPTION).
; Runs as a hotkey criterion for every right-click — hence SendMessageTimeout
; with a short deadline so a hung window never freezes the mouse.
MusÖverTitelrad(hk := "", *) {
    static egenPid := DllCall("GetCurrentProcessId")
    ; while our menu is open: eat ALL right-clicks (the handler closes the
    ; menu). Without this fast path the hit test below can time out and let
    ; the click through physically, making the app show its own rendering of
    ; the system menu on top of ours.
    if g_menyÖppen
        return true
    try {
        MouseGetPos , , &win
        if !win
            return false
        if WinGetClass(win) ~= "^(Shell_TrayWnd|Shell_SecondaryTrayWnd|Progman|WorkerW|#32768)$"
            return false   ; #32768 = open menus - never touch them
        if WinGetPID(win) = egenPid
            return false
        ; apps with their own caption menu (Edge/Chrome): let plain right-
        ; clicks pass PHYSICALLY untouched (synthetic NC clicks are ignored
        ; by Chromium); only the Shift variant is captured there
        if (!InStr(hk, "+") && ÄrEgenMenyApp(win))
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
        ; the top band: apps with custom-drawn title bars (VS Code, the new
        ; Outlook) report HTCLIENT there, sometimes everywhere. The Shift
        ; variant accepts the band for all windows; plain clicks only for
        ; the band apps (TitleMenuBand).
        if (res = 1) {
            WinGetPos(, &wy, , , win)
            if ((my - wy) > Round(44 * A_ScreenDPI / 96))
                return false
            return InStr(hk, "+") ? true : ÄrBandApp(win)
        }
        return false
    } catch {
        return false
    }
}

TitelHögerNer(*) {
    ; eats the right-click so the native menu never shows; the menu comes on
    ; release, otherwise the button-up can accidentally pick the first row
}

; Shows the window's REAL system menu with our move items temporarily
; appended at the bottom — the same technique Explorer uses for its taskbar
; thumbnail menus: TrackPopupMenu with TPM_RETURNCMD returns the selection
; to us; standard items (and injected ones, e.g. PowerToys) are forwarded
; as WM_SYSCOMMAND. Apps with a fully custom caption menu (Edge/Chrome) get
; the click untouched; Shift+right-click shows our menu even there.
VisaFönsterMeny(*) {
    static FLYTTA_BAS := 0xBE20, FÖLJ_BAS := 0xBE40, REGEL_BAS := 0xBE60
    global g_menyÖppen
    ; the TrackPopupMenu loop pumps messages, so a new right-click during an
    ; open menu re-enters here and stacks menus — close instead
    if g_menyÖppen {
        DllCall("EndMenu")
        return
    }
    MouseGetPos , , &win
    if (!win || !WinExist(win))
        return
    s := LäsSkrivbordsStatus()
    if (!s || s.index = 0)
        return
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    lp := ((my & 0xFFFF) << 16) | (mx & 0xFFFF)
    ; band clicks (e.g. Outlook) go straight to our menu. Re-sending the
    ; click to interactive elements was tried and reverted: the new
    ; Outlook's band is window frame at the composition layer, so re-sent
    ; clicks made the system show the app's own light system menu over ours.
    hSys := DllCall("GetSystemMenu", "ptr", win, "int", 0, "ptr")
    if !hSys {
        VisaReplikaMeny(win, s)
        return
    }
    ; let the window (and any injectors) refresh the menu, then adjust the
    ; standard items' states to the window's current state
    DllCall("SendMessageTimeoutW", "ptr", win, "uint", 0x116, "ptr", hSys, "ptr", 0
        , "uint", 0x2, "uint", 100, "ptr*", &tmp := 0)   ; WM_INITMENU
    JusteraStandardLägen(win, hSys)
    RensaVåraPoster(hSys)   ; clean up any leftovers from a previous instance

    ; the X bitmap on the Stäng row renders clipped/squeezed in some windows
    ; (VS Code) when we show the menu — remove it temporarily
    stängBmp := 0
    mii := Buffer(80, 0)
    NumPut("UInt", 80, mii, 0)
    NumPut("UInt", 0x80, mii, 4)                    ; MIIM_BITMAP
    if DllCall("GetMenuItemInfoW", "ptr", hSys, "uint", 0xF060, "int", 0, "ptr", mii) {
        stängBmp := NumGet(mii, 72, "Ptr")
        if (stängBmp != 0) {
            NumPut("Ptr", 0, mii, 72)
            DllCall("SetMenuItemInfoW", "ptr", hSys, "uint", 0xF060, "int", 0, "ptr", mii)
        }
    }

    hFlytta := DllCall("CreatePopupMenu", "ptr")
    hFölj := DllCall("CreatePopupMenu", "ptr")
    hAlltid := DllCall("CreatePopupMenu", "ptr")
    loop Min(s.count, 9) {
        n := A_Index
        grå := n = s.index ? 0x1 : 0     ; MF_GRAYED on the current desktop
        DllCall("AppendMenuW", "ptr", hFlytta, "uint", grå, "uptr", FLYTTA_BAS + n
            , "wstr", NamnFörIndex(n))
        DllCall("AppendMenuW", "ptr", hFölj, "uint", grå, "uptr", FÖLJ_BAS + n
            , "wstr", NamnFörIndex(n))
        DllCall("AppendMenuW", "ptr", hAlltid, "uint", 0, "uptr", REGEL_BAS + n
            , "wstr", NamnFörIndex(n))
    }
    titel := ""
    try titel := WinGetTitle(win)
    kort := StrLen(titel) > 40 ? SubStr(titel, 1, 38) "…" : titel
    kort := StrReplace(kort, "&", "&&")
    DllCall("AppendMenuW", "ptr", hSys, "uint", 0x800, "uptr", 0, "ptr", 0)   ; separator
    DllCall("AppendMenuW", "ptr", hSys, "uint", 0x10, "uptr", hFlytta, "wstr", T("menuMoveTo"))
    DllCall("AppendMenuW", "ptr", hSys, "uint", 0x10, "uptr", hFölj, "wstr", T("menuMoveFollow"))
    DllCall("AppendMenuW", "ptr", hSys, "uint", 0x10, "uptr", hAlltid
        , "wstr", T("menuAlwaysPre") kort T("menuAlwaysPost"))

    ; foreground fix: without it the menu closes immediately when Windows'
    ; foreground lock denies a background process. Attach to the FOREGROUND
    ; window's thread (it holds the rights) — the target window is not
    ; enough when it is itself in the background, since our eaten click
    ; never activated it.
    trådVår := DllCall("GetCurrentThreadId", "uint")
    fg := DllCall("GetForegroundWindow", "ptr")
    trådFg := fg ? DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint") : 0
    if trådFg
        DllCall("AttachThreadInput", "uint", trådVår, "uint", trådFg, "int", 1)
    DllCall("SetForegroundWindow", "ptr", A_ScriptHwnd)
    if trådFg
        DllCall("AttachThreadInput", "uint", trådVår, "uint", trådFg, "int", 0)
    g_menyÖppen := true
    val := DllCall("TrackPopupMenuEx", "ptr", hSys
        , "uint", 0x182, "int", mx, "int", my, "ptr", A_ScriptHwnd, "ptr", 0, "int")
    g_menyÖppen := false
    PostMessage(0x0, 0, 0, , A_ScriptHwnd)   ; WM_NULL - classic menu teardown fix

    RensaVåraPoster(hSys)                 ; remove our items again
    if (stängBmp != 0) {                  ; restore the Stäng row's bitmap
        NumPut("Ptr", stängBmp, mii, 72)
        DllCall("SetMenuItemInfoW", "ptr", hSys, "uint", 0xF060, "int", 0, "ptr", mii)
    }
    for h in [hFlytta, hFölj, hAlltid]
        DllCall("DestroyMenu", "ptr", h)

    if !val
        return
    if (val > FLYTTA_BAS && val <= FLYTTA_BAS + 9)
        FlyttaFönsterTill(win, val - FLYTTA_BAS, false)
    else if (val > FÖLJ_BAS && val <= FÖLJ_BAS + 9)
        FlyttaFönsterTill(win, val - FÖLJ_BAS, true)
    else if (val > REGEL_BAS && val <= REGEL_BAS + 9)
        NyRegelVal(win, val - REGEL_BAS)
    else
        PostMessage(0x112, val, lp, , win)   ; standard/injected items → the window
}

; Removes our appended items (and the separator) from the end of a system
; menu. String-based so leftovers from a killed earlier instance are also
; cleaned up.
RensaVåraPoster(hSys) {
    borttaget := false
    loop {
        antal := DllCall("GetMenuItemCount", "ptr", hSys, "int")
        if antal <= 0
            return
        buf := Buffer(512, 0)
        DllCall("GetMenuStringW", "ptr", hSys, "uint", antal - 1, "ptr", buf
            , "int", 255, "uint", 0x400)
        txt := StrGet(buf)
        ; match BOTH languages: leftovers may predate a language switch
        if (txt = "Flytta till skrivbord" || txt = "Flytta och följ efter"
            || SubStr(txt, 1, 14) = "Flytta alltid "
            || txt = "Move to desktop" || txt = "Move and follow"
            || SubStr(txt, 1, 12) = "Always move ") {
            DllCall("RemoveMenu", "ptr", hSys, "uint", antal - 1, "uint", 0x400)
            borttaget := true
            continue
        }
        if (borttaget && txt = "") {
            DllCall("RemoveMenu", "ptr", hSys, "uint", antal - 1, "uint", 0x400)
            borttaget := false
            continue
        }
        return
    }
}

ÄrEgenMenyApp(win) {
    if g_egenMeny = ""
        return false
    try return WinGetProcessName(win) ~= g_egenMeny
    catch
        return false
}

ÄrBandApp(win) {
    if g_bandAppar = ""
        return false
    try return WinGetProcessName(win) ~= g_bandAppar
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

JusteraStandardLägen(win, hSys) {
    stil := 0
    try stil := WinGetStyle(win)
    ärMax := (stil & 0x1000000) != 0    ; WS_MAXIMIZE
    ärMin := (stil & 0x20000000) != 0   ; WS_MINIMIZE
    på := (id, ok) => DllCall("EnableMenuItem", "ptr", hSys, "uint", id
        , "uint", ok ? 0 : 0x3)          ; MF_ENABLED / MF_GRAYED|MF_DISABLED
    på(0xF120, ärMax || ärMin)                            ; Restore
    på(0xF010, !ärMax)                                    ; Move
    på(0xF000, (stil & 0x40000) && !ärMax && !ärMin)      ; Size
    på(0xF020, (stil & 0x20000) && !ärMin)                ; Minimize
    på(0xF030, (stil & 0x10000) && !ärMax)                ; Maximize
    ; no SetMenuDefaultItem: the bold marking rendered a squeezed Stäng row
    ; in VS Code windows (any default set by the app itself is left alone)
}

; The bare move menu. Used as fallback for windows without a system menu,
; and by the MoveMenu hotkey (anchored near the window instead of the mouse).
VisaReplikaMeny(win, s, vidFönstret := false) {
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
    if vidFönstret {
        x := 0, y := 0
        try WinGetPos(&x, &y, , , win)
        CoordMode("Menu", "Screen")
        m.Show(x + 60, y + 50)
    } else {
        m.Show()
    }
}

FlyttaMenyVal(win, n, följ, *) {
    FlyttaFönsterTill(win, n, följ)
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

LäsRegler() {
    global g_regler
    g_regler := []
    sektion := IniRead(g_konfigFil, "Rules", , "")
    loop parse sektion, "`n", "`r" {
        if RegExMatch(A_LoopField, "^Rule\d+\s*=\s*(\d+)\s+(.+)$", &m)
            g_regler.Push({mål: Integer(m[1]), regex: m[2]})
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
                if !(titel ~= regel.regex)
                    continue
                if (gammal != "" && gammal ~= regel.regex)
                    continue   ; matched before too - no new event
            } catch {
                continue   ; broken regex in the config - skip the rule
            }
            nr := DllCall("VirtualDesktopAccessor\GetWindowDesktopNumber", "ptr", hwnd, "int")
            if (nr >= 0 && nr != regel.mål - 1)
                DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber"
                    , "ptr", hwnd, "int", regel.mål - 1, "int")
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
    global g_bricka, g_brickaText
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
    ; if Explorer restarted, the label died with its parent — rebuild
    if IsObject(g_bricka) && !DllCall("IsWindow", "ptr", g_bricka.Hwnd) {
        g_bricka := 0
        g_brickaText := ""
    }
    try WinGetPos(, , &fältBredd, &fältHöjd, fält)
    catch
        return
    try ControlGetPos(&ikonX, , , , "TrayNotifyWnd1", fält)
    catch
        ikonX := fältBredd - 260   ; rough fallback if the control disappears
    ljust := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        , "SystemUsesLightTheme", 0)
    rad1 := s.name != "" ? s.name : T("desktop") " " s.index
    rad2 := s.name != "" ? T("desktop") " " s.index " " T("of") " " s.count : ""
    innehåll := rad1 "|" rad2 "|" ljust
    if (innehåll != g_brickaText || !IsObject(g_bricka)) {
        g_brickaText := innehåll
        if IsObject(g_bricka)
            g_bricka.Destroy()
        skala := A_ScreenDPI / 96
        nyckel := ljust ? "EEEEEE" : "202020"
        b := Gui("-DPIScale -Caption +ToolWindow +E0x08000000 +E0x20", "VDA namnbricka")
        b.BackColor := nyckel
        b.MarginX := Round(10 * skala), b.MarginY := Round(3 * skala)
        b.SetFont("s9 q4 c" (ljust ? "1A1A1A" : "F5F5F5"), "Segoe UI Variable Display")
        b.Add("Text", "Center", rad2 != "" ? rad1 "`n" rad2 : rad1)
        b.Show("NoActivate Hide AutoSize")
        WinSetStyle("+0x40000000", b)                          ; WS_CHILD
        DllCall("SetParent", "ptr", b.Hwnd, "ptr", fält)
        WinSetTransColor(nyckel, b)
        g_bricka := b
    }
    g_bricka.GetPos(, , &bb, &bh)
    g_bricka.Show("NoActivate x" (ikonX - bb - Round(12 * A_ScreenDPI / 96))
        . " y" ((fältHöjd - bh) // 2))
    ; topmost among the bar's children so the composition surface never
    ; paints over it
    DllCall("SetWindowPos", "ptr", g_bricka.Hwnd, "ptr", 0
        , "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)   ; TOP, NOMOVE|NOSIZE|NOACTIVATE
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

InitTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add(T("trayShowName"), (*) => VisaOsd())
    A_TrayMenu.Add()
    A_TrayMenu.Add(T("trayOpenConfig"), (*) => Run('notepad.exe "' g_konfigFil '"'))
    A_TrayMenu.Add(T("trayReloadConfig"), LäsOmKonfig)
    språkMeny := Menu()
    språkMeny.Add("English", SättSpråk.Bind("en"))
    språkMeny.Add("Svenska", SättSpråk.Bind("sv"))
    språkMeny.Check(g_språk = "sv" ? "Svenska" : "English")
    A_TrayMenu.Add(T("trayLanguage"), språkMeny)
    A_TrayMenu.Add()
    A_TrayMenu.Add(T("trayRestart"), (*) => Reload())
    A_TrayMenu.Add(T("trayExit"), (*) => ExitApp())
    A_TrayMenu.Default := T("trayShowName")
    A_TrayMenu.ClickCount := 1
}

LäsOmKonfig(*) {
    LäsKonfig()
    InitTray()          ; the language may have changed in the config file
    UppdateraPilikoner()
    TrayTip(T("configLoaded"), "DeskPilot")
}

; Silent tray apps need a trace when something breaks; no dialog, or a
; crashing timer would spam a box every 250 ms.
LoggaFel(err, mode) {
    try FileAppend(FormatTime() "  " err.Message " (" err.File ":" err.Line ")`n"
        , A_ScriptDir "\error.log", "UTF-8")
    return 1
}
