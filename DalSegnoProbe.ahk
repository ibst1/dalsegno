;===============================================================================
; DalSegnoProbe - small helper for DalSegno Window Manager.
; Answers one question for the desktop label: what kind of UI Automation element
; sits at this screen point - is a taskbar button there yet?
;
; Why a process of its own: UI Automation calls into Explorer, and on one PC
; every such call took 9 s (2026-10-06). Made on the main script's thread they
; froze its keyboard and mouse hooks - which wait for that thread to judge their
; #HotIf conditions - and with them every key and click on the PC. Here a call
; may take as long as it likes: this process has no hooks and nothing waits on it.
;
; Protocol, registered messages, always posted, never sent:
;   DALSEGNO_PROBE_REQ  to this script's hidden window ("DalSegnoProbe"):
;                       wParam = request id,
;                       lParam = (x + 32768) | (y + 32768) << 16, screen pixels
;   DALSEGNO_PROBE_ANS  to the main script's hidden window:
;                       wParam = request id, lParam = control type (0 = unknown)
; Started by the main script when the label first needs an answer; exits by
; itself when the main script is gone.
;===============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
Persistent

; tag the hidden main window so the main script can find us
DllCall("SetWindowText", "ptr", A_ScriptHwnd, "str", "DalSegnoProbe")
; the label code works per-monitor-v2; the points mean the same pixels here
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

reqMsg := DllCall("RegisterWindowMessage", "str", "DALSEGNO_PROBE_REQ", "uint")
ansMsg := DllCall("RegisterWindowMessage", "str", "DALSEGNO_PROBE_ANS", "uint")
queue := []
OnMessage(reqMsg, OnRequest)
SetTimer(WatchMain, 3000)

; Only queue here and return at once: the work runs in a timer thread, so a
; request arriving during a slow UI Automation call is kept, not dropped.
OnRequest(wParam, lParam, *) {
    global queue
    queue.Push({ id: wParam, x: (lParam & 0xFFFF) - 32768, y: ((lParam >> 16) & 0xFFFF) - 32768 })
    SetTimer(Work, -1)
}

Work() {
    global queue, ansMsg
    while queue.Length {
        r := queue.RemoveAt(1)
        ; a newer request for the same point makes this one moot
        moot := false
        for q in queue
            if (q.x = r.x && q.y = r.y) {
                moot := true
                break
            }
        if moot
            continue
        typ := 0
        t0 := A_TickCount
        try typ := TypeAt(r.x, r.y)
        if (A_TickCount - t0 > 500)   ; beside the main script's SLOW notes
            try FileAppend(FormatTime(, "HH:mm:ss") "  SLOW probe " r.x "," r.y " "
                . (A_TickCount - t0) "ms`n", EnvGet("LOCALAPPDATA") "\DalSegno\trace.log", "UTF-8")
        if hwnd := MainWindow()
            PostMessage(ansMsg, r.id, typ, , hwnd)
    }
}

TypeAt(x, y) {
    static uia := 0
    if !uia {
        DllCall("ole32\CoCreateInstance"
            , "ptr", GuidBuffer("{FF48DBA4-60EF-4201-AA87-54103EEF594E}")   ; CUIAutomation
            , "ptr", 0, "uint", 0x17
            , "ptr", GuidBuffer("{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")   ; IUIAutomation
            , "ptr*", &p := 0, "hresult")
        uia := ComValue(13, p)
    }
    ComCall(7, uia, "int64", (x & 0xFFFFFFFF) | (y << 32), "ptr*", &pEl := 0)   ; ElementFromPoint
    if !pEl
        return 0
    el := ComValue(13, pEl)
    ComCall(21, el, "int*", &typ := 0)     ; get_CurrentControlType
    return typ
}

GuidBuffer(s) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", s, "ptr", buf, "hresult")
    return buf
}

MainWindow() {
    DetectHiddenWindows true
    SetTitleMatchMode 2
    ; the main script's hidden window is titled with its path: .ahk when run
    ; as a script, .exe when the renamed interpreter runs it
    hwnd := WinExist("DalSegno.ahk ahk_class AutoHotkey")
    return hwnd ? hwnd : WinExist("DalSegno.exe ahk_class AutoHotkey")
}

; without the main script there is no one to answer - vanish after ~6 s (two
; misses, so a reload of the main script does not tear the probe down)
WatchMain() {
    static missing := 0
    missing := MainWindow() ? 0 : missing + 1
    if missing >= 2
        ExitApp()
}
