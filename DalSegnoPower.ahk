;===============================================================================
; DalSegnoPower - small helper for DalSegno Window Manager.
; Tells which screens are turned off although Windows still counts them.
;
; A DisplayPort screen turned off with its power button usually stays in the
; Windows layout: no WM_DISPLAYCHANGE, the windows on it stay there, and when it
; is the primary screen the taskbar and every new window go there too. The only
; one who knows is the screen itself: over DDC/CI (VCP code D6, power mode) it
; answers 1 when on and 4 or 5 when off. Every DDC question takes 50 ms to
; seconds - here, in a process of its own, as DalSegnoProbe does for UI
; Automation, since the main script's thread also serves the keyboard and
; mouse hooks.
;
; A screen counts as off after two answers in a row (about 5 s) saying so:
;   - it answers "off" (D6 = 2..5), or
;   - it has answered "on" before and now does not answer at all, or
;   - it never answers (no DDC, as some screens) while every screen that does
;     answer is off: screens are turned off together, leaving the desk.
; The built-in screen of a laptop is never off (no DDC there; the lid takes it
; out of the layout). While Windows has the displays off itself (idle, sleep)
; and for 20 s after they come back, nothing is asked: every screen says off.
;
; Protocol, a registered message posted to the main script's hidden window
; every poll:
;   DALSEGNO_POWER  wParam = bit n-1 set: \\.\DISPLAYn is off
;                   lParam = bit n-1 set: \\.\DISPLAYn is the built-in screen
; Started by the main script; exits by itself when the main script is gone.
; Argument /debug: write every poll to DalSegnoPower.log beside the script.
;===============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
Persistent

DllCall("SetWindowText", "ptr", A_ScriptHwnd, "str", "DalSegnoPower")

powerMsg := DllCall("RegisterWindowMessage", "str", "DALSEGNO_POWER", "uint")
debug := A_Args.Length && A_Args[1] = "/debug"
state := Map()          ; device -> { offRuns, seenOn }
displayOn := true, displayOnSince := 0

; GUID_CONSOLE_DISPLAY_STATE: the displays Windows itself turned off (0) / on (1) / dimmed (2)
guid := Buffer(16)
DllCall("ole32\CLSIDFromString", "wstr", "{6FE69556-704A-47A0-8F24-C28D936FDA47}", "ptr", guid, "hresult")
DllCall("RegisterPowerSettingNotification", "ptr", A_ScriptHwnd, "ptr", guid, "uint", 0, "ptr")
OnMessage(0x218, OnPowerBroadcast)   ; WM_POWERBROADCAST

SetTimer(Poll, 2500)
SetTimer(WatchMain, 3000)
Poll()

OnPowerBroadcast(wParam, lParam, *) {
    global displayOn, displayOnSince, state
    if (wParam != 0x8013)   ; PBT_POWERSETTINGCHANGE
        return
    on := NumGet(lParam, 20, "UInt") != 0
    if (on && !displayOn) {
        displayOnSince := A_TickCount
        for , s in state
            s.offRuns := 0   ; screens waking up answer "off" for a while
    }
    displayOn := on
    Log("console display " (on ? "on" : "off"))
}

Poll() {
    global displayOn, displayOnSince, state, powerMsg
    if (!displayOn || (displayOnSince && A_TickCount - displayOnSince < 20000))
        return
    internal := InternalScreens()
    mons := []
    for dev, h in Monitors() {
        n := DisplayNumber(dev)
        if (n < 1 || n > 32)
            continue
        if !state.Has(dev)
            state[dev] := { offRuns: 0, seenOn: false }
        s := state[dev]
        if internal.Has(dev) {
            mons.Push({ dev: dev, n: n, internal: true, answer: "on", s: s })
            continue
        }
        t0 := A_TickCount
        p := PowerMode(h)     ; 1 on, 2..5 off, -1 no answer
        answer := (p = 1) ? "on" : (p >= 2 && p <= 5) ? "off" : "none"
        if (answer = "on")
            s.seenOn := true, s.offRuns := 0
        else if (answer = "off" || s.seenOn)
            s.offRuns++
        mons.Push({ dev: dev, n: n, internal: false, answer: answer, s: s, ms: A_TickCount - t0, p: p })
    }
    ; screens without DDC follow the ones with: off when every answering one is off
    answering := 0, answeringOff := 0
    for m in mons
        if (!m.internal && (m.answer != "none" || m.s.seenOn))
            answering++, answeringOff += (m.s.offRuns >= 2)
    offMask := 0, intMask := 0, line := ""
    for m in mons {
        off := false
        if m.internal
            intMask |= 1 << (m.n - 1)
        else if (m.answer != "none" || m.s.seenOn)
            off := m.s.offRuns >= 2
        else
            off := answering > 0 && answeringOff = answering
        if off
            offMask |= 1 << (m.n - 1)
        line .= " " m.n (m.internal ? "=int" : "=" m.answer (m.HasProp("p") ? "(" m.p "," m.ms "ms)" : "")) (off ? "*OFF*" : "")
    }
    Log("poll" line)
    if hwnd := MainWindow()
        PostMessage(powerMsg, offMask, intMask, , hwnd)
}

; device name -> HMONITOR, for every screen in the layout
Monitors() {
    static cb := CallbackCreate(EnumProc, "F", 4)
    global g_enum
    g_enum := Map()
    DllCall("EnumDisplayMonitors", "ptr", 0, "ptr", 0, "ptr", cb, "ptr", 0)
    return g_enum
}

EnumProc(hMon, hdc, pRect, data) {
    global g_enum
    mi := Buffer(104, 0)
    NumPut("UInt", 104, mi, 0)
    if DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", mi)
        g_enum[StrGet(mi.Ptr + 40, 32, "UTF-16")] := hMon
    return true
}

DisplayNumber(dev) {
    return RegExMatch(dev, "i)DISPLAY(\d+)$", &m) ? Integer(m[1]) : 0
}

; VCP D6 of the screen's first physical monitor; -1 when it does not answer
PowerMode(hMon) {
    if !DllCall("dxva2\GetNumberOfPhysicalMonitorsFromHMONITOR", "ptr", hMon, "uint*", &n := 0) || n < 1
        return -1
    arr := Buffer(n * (A_PtrSize + 256), 0)
    if !DllCall("dxva2\GetPhysicalMonitorsFromHMONITOR", "ptr", hMon, "uint", n, "ptr", arr)
        return -1
    h := NumGet(arr, 0, "ptr")
    cur := 0, mx := 0
    ok := DllCall("dxva2\GetVCPFeatureAndVCPFeatureReply", "ptr", h, "uchar", 0xD6, "ptr", 0, "uint*", &cur, "uint*", &mx)
    DllCall("dxva2\DestroyPhysicalMonitors", "uint", n, "ptr", arr)
    return ok ? cur : -1
}

; the device names of the built-in screens (laptop panel), from the display
; configuration: output technology INTERNAL, LVDS or embedded DisplayPort/UDI
InternalScreens() {
    out := Map()
    if DllCall("GetDisplayConfigBufferSizes", "uint", 2, "uint*", &np := 0, "uint*", &nm := 0)
        return out
    paths := Buffer(np * 72, 0), modes := Buffer(nm * 64, 0)
    if DllCall("QueryDisplayConfig", "uint", 2, "uint*", &np, "ptr", paths, "uint*", &nm, "ptr", modes, "ptr", 0)
        return out
    loop np {
        o := (A_Index - 1) * 72
        tech := NumGet(paths, o + 36, "UInt")
        if !(tech = 0x80000000 || tech = 6 || tech = 11 || tech = 13)
            continue
        req := Buffer(84, 0)
        NumPut("UInt", 1, "UInt", 84, req, 0)                          ; GET_SOURCE_NAME
        NumPut("Int64", NumGet(paths, o, "Int64"), req, 8)             ; adapterId
        NumPut("UInt", NumGet(paths, o + 8, "UInt"), req, 16)          ; source id
        if !DllCall("DisplayConfigGetDeviceInfo", "ptr", req)
            out[StrGet(req.Ptr + 20, 32, "UTF-16")] := true
    }
    return out
}

Log(msg) {
    global debug
    if debug
        try FileAppend(FormatTime(, "HH:mm:ss") "  " msg "`n", A_ScriptDir "\DalSegnoPower.log", "UTF-8")
}

MainWindow() {
    DetectHiddenWindows true
    SetTitleMatchMode 2
    hwnd := WinExist("DalSegno.ahk ahk_class AutoHotkey")
    return hwnd ? hwnd : WinExist("DalSegno.exe ahk_class AutoHotkey")
}

; without the main script there is no one to tell - vanish after ~9 s (three
; misses, so a restart of the main script does not tear the helper down)
WatchMain() {
    global debug
    static missing := 0
    missing := MainWindow() ? 0 : missing + 1
    if (missing >= 3 && !debug)
        ExitApp()
}
