;===============================================================================
; DalSegno Window Manager — v2.0.0 (2026-09-03)
;
; Dal segno (𝄋) — "from the sign": go back to the marked place. Windows return
; to their marked places: the saved position on the right monitor, and the
; right virtual desktop.
;
; Two modules on one core, each switchable in the settings:
;   Positions  move a window by hand and every window like it returns there
;              (per monitor setup and computer); maximized state included
;   Desktops   see which virtual desktop you are on, move windows between
;              desktops with hotkeys, the mouse, the window menu or rules
; One rule table serves both: a rule matches windows by title text (or regex)
; and program, and gives them a place and/or a desktop.
;
; Hold CapsLock (configurable) and right-click a window for the window menu;
; CapsLock + D opens the GUI. See README.md.
;
; Arguments:  /selftest  - write parsed state to selftest.txt and exit
;             /show      - show the desktop name OSD at startup
;===============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#Include lib\WebView2.ahk
#Include lib\JSON.ahk
#Include src\core.ahk
#Include src\positions.ahk
#Include src\desktops.ahk
#Include src\gui.ahk

if (A_Args.Length && A_Args[1] = "/selftest") {
    LoadConfig()
    g_desktopsStarted := true   ; so the desktop hotkeys register and can be listed
    ApplyDesktopHotkeys()
    out := "modules=positions:" (g_modPositions ? 1 : 0) " desktops:" (g_modDesktops ? 1 : 0)
    out .= "`nlanguage=" g_lang
    out .= "`nmenu=" g_modifier "+" g_menuButton " enabled:" (g_menuOn ? 1 : 0) " whole:" (g_menuWhole ? 1 : 0)
    out .= "`nrules=" titleRules.Length
    for r in titleRules
        out .= "`n  " r.alias " = " RuleValue(r)
    out .= "`nrulesOnlyExe=" rulesOnlyExe.Length " ignoreExe=" ignoreExe.Length " ignoreTitles=" ignoreTitles.Length
    keys := ""
    for k in g_actionKeys
        keys .= (keys = "" ? "" : ", ") k
    out .= "`nactionHotkeys(" g_modifier " held)=" keys
    keys := ""
    for k in g_desktopHotkeys
        keys .= (keys = "" ? "" : ", ") k
    out .= "`ndesktopHotkeys(" g_desktopHotkeys.Length ")=" keys
    s := ReadDesktopStatus()
    out .= "`ndesktops=" (s ? "index:" s.index " count:" s.count " name:" s.name : "(registry not readable)")
    out .= "`ndll=" (FileExist(VDA_DLL) ? "present" : "missing")
    out .= "`nsetup=" SetupKey()
    try FileDelete(A_ScriptDir "\selftest.txt")
    FileAppend(out "`n", A_ScriptDir "\selftest.txt", "UTF-8")
    ExitApp
}

OnError(LogError)
; dark theme for this process's menus (undocumented uxtheme ordinals 135/136),
; so the window menu follows the system theme instead of classic light
try {
    hUx := DllCall("LoadLibrary", "str", "uxtheme", "ptr")
    DllCall(DllCall("GetProcAddress", "ptr", hUx, "ptr", 135, "ptr"), "int", 1)   ; AllowDark
    DllCall(DllCall("GetProcAddress", "ptr", hUx, "ptr", 136, "ptr"))             ; FlushMenuThemes
}

LoadConfig()
BuildTrayMenu()
if g_modPositions
    PositionsInit()
if g_modDesktops
    DesktopsInit()
; IPC: DeskPilot's name stays for other scripts; DalSegno's is the new one
OnMessage(DllCall("RegisterWindowMessage", "str", "DESKPILOT_CMD", "uint"), IpcCommand)
OnMessage(DllCall("RegisterWindowMessage", "str", "DALSEGNO_CMD", "uint"), IpcCommand)
OnMessage(0x404, OnTrayClick)   ; AHK_NOTIFYICON: left click on the tray icon
SetTimer(ScanWindows, 800)
SetTimer(ModifierWatchdog, 5000)   ; clears a logically stuck modifier

if (A_Args.Length && A_Args[1] = "/show")
    ShowOsd()
