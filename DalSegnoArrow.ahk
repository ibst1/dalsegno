;===============================================================================
; DalSegnoArrow - small helper for DalSegno Window Manager.
; Shows ONE tray icon (left or right arrow, chosen by the "va"/"ho" argument)
; that switches desktop on click, by posting DESKPILOT_CMD to the main script.
; Started and stopped by the main script (ArrowIcons in the config), and
; exits by itself if the main script disappears.
;===============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Off
Persistent

direction := A_Args.Length && A_Args[1] = "va" ? "va" : "ho"
next := direction = "ho"

; tag the hidden main window so the main script can see we are running
DllCall("SetWindowText", "ptr", A_ScriptHwnd, "str", "DalSegnoArrow " direction)

; UI language from the main config (restarted by the main script on change)
lang := IniRead(A_ScriptDir "\DalSegno config.ini", "General", "Language", "sv") = "sv" ? "sv" : "en"

icon := A_ScriptDir "\icons\" (next ? "pil_ho.ico" : "pil_va.ico")
if FileExist(icon)
    TraySetIcon(icon, , 1)
if (lang = "sv")
    A_IconTip := next ? "Nästa skrivbord" : "Föregående skrivbord"
else
    A_IconTip := next ? "Next desktop" : "Previous desktop"

A_TrayMenu.Delete()
A_TrayMenu.Add(A_IconTip, Click)
A_TrayMenu.Add()
A_TrayMenu.Add(lang = "sv" ? "Avsluta" : "Exit", (*) => ExitApp())
A_TrayMenu.Default := A_IconTip
A_TrayMenu.ClickCount := 1

SetTimer(WatchMain, 3000)

Click(*) {
    static msg := DllCall("RegisterWindowMessage", "str", "DESKPILOT_CMD", "uint")
    hwnd := MainWindow()
    if hwnd
        PostMessage(msg, next ? 6 : 7, 0, , hwnd)   ; 6 = next, 7 = previous
}

MainWindow() {
    DetectHiddenWindows true
    SetTitleMatchMode 2
    ; the main script's hidden window is titled with its path: .ahk when run
    ; as a script, .exe when the renamed interpreter runs it
    hwnd := WinExist("DalSegno.ahk ahk_class AutoHotkey")
    return hwnd ? hwnd : WinExist("DalSegno.exe ahk_class AutoHotkey")
}

; without the main script the arrow is pointless - vanish after ~6 s (two
; misses, so a reload of the main script does not tear the arrows down)
WatchMain() {
    static missing := 0
    missing := MainWindow() ? 0 : missing + 1
    if missing >= 2
        ExitApp()
}
