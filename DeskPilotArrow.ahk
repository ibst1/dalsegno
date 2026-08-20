;===============================================================================
; DeskPilotArrow - small helper for DeskPilot.
; Shows ONE tray icon (left or right arrow, chosen by the "va"/"ho" argument)
; that switches desktop on click, by posting DESKPILOT_CMD to the main script.
; Started and stopped by the main script (ArrowIcons in the config), and
; exits by itself if the main script disappears.
;===============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Off
Persistent

riktning := A_Args.Length && A_Args[1] = "va" ? "va" : "ho"
nästa := riktning = "ho"

; tag the hidden main window so the main script can see we are running
DllCall("SetWindowText", "ptr", A_ScriptHwnd, "str", "DeskPilotArrow " riktning)

; UI language from the main config (restarted by the main script on change)
språk := IniRead(A_ScriptDir "\DeskPilot config.ini"
    , "Display", "Language", "en") = "sv" ? "sv" : "en"

ikon := A_ScriptDir "\icons\" (nästa ? "pil_ho.ico" : "pil_va.ico")
if FileExist(ikon)
    TraySetIcon(ikon, , 1)
if (språk = "sv")
    A_IconTip := nästa ? "Nästa skrivbord" : "Föregående skrivbord"
else
    A_IconTip := nästa ? "Next desktop" : "Previous desktop"

A_TrayMenu.Delete()
A_TrayMenu.Add(A_IconTip, Klick)
A_TrayMenu.Add()
A_TrayMenu.Add(språk = "sv" ? "Avsluta" : "Exit", (*) => ExitApp())
A_TrayMenu.Default := A_IconTip
A_TrayMenu.ClickCount := 1

SetTimer(VaktaVda, 3000)

Klick(*) {
    static msg := DllCall("RegisterWindowMessage", "str", "DESKPILOT_CMD", "uint")
    hwnd := VdaFönster()
    if hwnd
        PostMessage(msg, nästa ? 6 : 7, 0, , hwnd)   ; 6 = next, 7 = previous
}

VdaFönster() {
    DetectHiddenWindows true
    SetTitleMatchMode 2
    ; the main script's hidden window is titled with its path: .ahk when run
    ; as a script, .exe when compiled
    hwnd := WinExist("DeskPilot.ahk ahk_class AutoHotkey")
    return hwnd ? hwnd : WinExist("DeskPilot.exe ahk_class AutoHotkey")
}

; without the main script the arrow is pointless — vanish after ~6 s (two
; misses, so a reload of the main script does not tear the arrows down)
VaktaVda() {
    static saknad := 0
    saknad := VdaFönster() ? 0 : saknad + 1
    if saknad >= 2
        ExitApp()
}
