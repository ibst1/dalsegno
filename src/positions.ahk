; =============================================================================
;  DalSegno Window Manager - Positions module
;
;  Move a window by hand and its position is saved; the next window with the
;  same identity is moved right back there. Positions are kept per monitor
;  setup and computer. The script's own moves are never saved: the Windows
;  event that triggers saving fires only for manual moves.
; =============================================================================

moveEnabled     := true
autoSaveEnabled := true
notifyEnabled   := true
g_autoSaveModOnly := true      ; autosave only when the modifier is held ([Positions] AutoSaveModifierOnly)

; Why the last SavePos failed: "" (it did not), "min", "gone" or "write" - the
; callers turn it into a message with SaveErrorText().
g_saveError := "", g_saveErrorText := ""

g_moveEndCb := 0, g_winEventHook := 0

PositionsLoadConfig() {
    global configIni, moveEnabled, autoSaveEnabled, notifyEnabled, g_autoSaveModOnly
    moveEnabled     := IniRead(configIni, "Positions", "MoveWindows", 1) != "0"
    autoSaveEnabled := IniRead(configIni, "Positions", "AutoSave", 1) != "0"
    notifyEnabled   := IniRead(configIni, "Positions", "Notify", 1) != "0"
    g_autoSaveModOnly := IniRead(configIni, "Positions", "AutoSaveModifierOnly", 1) != "0"
}

; Autosave: Windows tells us exactly when a drag ends. EVENT_SYSTEM_MOVESIZEEND
; fires when the user releases a window after moving or resizing it - but NOT
; when the script itself calls WinMove.
PositionsInit() {
    global posIni, g_moveEndCb, g_winEventHook
    EnsureIniUtf16(posIni, "; DalSegno - saved window positions. Best not edited by hand.`n")
    g_moveEndCb := CallbackCreate(OnMoveEnd, "F", 7)
    g_winEventHook := DllCall("SetWinEventHook",
        "uint", 0x000B, "uint", 0x000B,   ; EVENT_SYSTEM_MOVESIZEEND
        "ptr", 0, "ptr", g_moveEndCb,
        "uint", 0, "uint", 0,
        "uint", 0x2,                       ; OUTOFCONTEXT | SKIPOWNPROCESS
        "ptr")
    ; the callback must return 0/empty - a nonzero return value tells AHK to
    ; CANCEL the exit
    OnExit((*) => (DllCall("UnhookWinEvent", "ptr", g_winEventHook), 0))
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

; Positions are kept separate per monitor count + virtual desktop width + computer.
SetupKey() {
    return MonitorGetCount() "x" SysGet(78) "_" A_ComputerName
}

; Ini section name: hash of the key + setup. The hash turns arbitrary titles
; (with =, [, ] and line breaks) into valid section names. The key is also
; stored in clear text inside the section and verified on read.
SectionFor(key) {
    return "K" Hash32(key) "_" SetupKey()
}

Hash32(s) {
    h := 5381
    loop parse s
        h := (h * 33 + Ord(A_LoopField)) & 0xFFFFFFFF
    return Format("{:08X}", h)
}

; Saves the window's current position under its key. A maximized window is
; saved as its normal (restored) rectangle plus Max=1, so that a new window
; ends up maximized on the same monitor. Minimized windows are refused.
SavePos(key, hwnd) {
    global posIni, g_saveError, g_saveErrorText
    g_saveError := "", g_saveErrorText := ""
    if !WinExist(hwnd) {
        g_saveError := "gone"
        return false
    }
    try {
        mm := WinGetMinMax(hwnd)
        if (mm = -1) {
            g_saveError := "min"
            return false
        }
        if (mm != 1 || !NormalRect(hwnd, &x, &y, &w, &h))
            WinGetPos(&x, &y, &w, &h, hwnd)
        section := SectionFor(key)
        IniWrite(key, posIni, section, "Key")
        IniWrite(WinGetProcessName(hwnd) " | " SubStr(WinGetTitle(hwnd), 1, 60), posIni, section, "Info")
        IniWrite(x, posIni, section, "X")
        IniWrite(y, posIni, section, "Y")
        IniWrite(w, posIni, section, "W")
        IniWrite(h, posIni, section, "H")
        IniWrite(mm = 1 ? 1 : 0, posIni, section, "Max")
        return true
    } catch as e {
        g_saveError := "write", g_saveErrorText := e.Message
        return false
    }
}

; The reason the last SavePos failed, as a message for the user.
SaveErrorText() {
    global g_saveError, g_saveErrorText
    switch g_saveError {
        case "min":   return Tr("cannotSaveMin")
        case "gone":  return Tr("cannotSaveGone")
        case "write": return Tr("cannotSaveWrite") "`n" g_saveErrorText
    }
    return Tr("cannotSaveWin")
}

; The rectangle a maximized window returns to when restored, in screen
; coordinates. GetWindowPlacement reports it relative to the primary
; monitor's work area, hence the conversion.
NormalRect(hwnd, &x, &y, &w, &h) {
    wp := Buffer(44, 0)
    NumPut("UInt", 44, wp, 0)
    if !DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", wp)
        return false
    l := NumGet(wp, 28, "Int"), t := NumGet(wp, 32, "Int")
    r := NumGet(wp, 36, "Int"), b := NumGet(wp, 40, "Int")
    if (r <= l || b <= t)
        return false
    MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt)
    x := l + wl, y := t + wt, w := r - l, h := b - t
    return true
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
    return { x: Integer(x), y: Integer(y), w: Integer(w), h: Integer(h)
        , max: IniRead(posIni, section, "Max", 0) = 1 }
}

; Moves the window to its saved position. True = the window is fully handled
; (a position existed and was applied, or the window is minimized and must be
; left alone). False = no saved position exists yet. The saved state is
; reproduced whole: a position saved from a maximized window puts the window
; at its normal rectangle first - that is what decides the monitor - and
; maximizes it there; a window that opens maximized but was saved normal is
; restored and moved.
MoveToSaved(hwnd, key) {
    p := LoadPos(key)
    if (p = "")
        return false
    try {
        mm := WinGetMinMax(hwnd)
        if (mm = -1)
            return true
        if (mm = 1) {
            if (p.max && MonitorFromWindow(hwnd) = MonitorAtPoint(p.x + p.w // 2, p.y + p.h // 2))
                return true
            WinRestore(hwnd)
        }
        WinMove(p.x, p.y, p.w, p.h, hwnd)
        ; twice: otherwise width/height do not stick when the window jumps to
        ; a monitor with different resolution/scaling
        Sleep 100
        WinMove(p.x, p.y, p.w, p.h, hwnd)
        if p.max
            WinMaximize(hwnd)
    }
    return true
}

MonitorAtPoint(x, y) {
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x >= l && x < r && y >= t && y < b)
            return A_Index
    }
    return 0
}

MonitorFromWindow(hwnd) {
    hMon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")   ; NEAREST
    info := Buffer(40, 0)
    NumPut("UInt", 40, info, 0)
    if !DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", info)
        return 0
    loop MonitorGetCount() {
        MonitorGet(A_Index, &ml, &mt, &mr, &mb)
        if (ml = NumGet(info, 4, "Int") && mt = NumGet(info, 8, "Int"))
            return A_Index
    }
    return 0
}

; Called from the window scan for every window: places new windows that have
; a saved position, within the grace period their title may still change in.
PositionsPlace(hwnd, info, setup) {
    global moveEnabled, PLACEMENT_GRACE_MS
    if (info.setup != setup) {
        ; the monitor setup changed (docking): give the window its saved
        ; position for the new setup
        info.setup := setup
        info.done := false
        info.seen := A_TickCount
    }
    if (info.done || !moveEnabled)
        return
    if (A_TickCount - info.seen > PLACEMENT_GRACE_MS) {
        info.done := true   ; never got a recognizable title - give up
        return
    }
    key := KeyFor(hwnd)
    if (key = "")
        return              ; the title may arrive later - keep watching
    if MoveToSaved(hwnd, key)
        info.done := true
}

; Called by Windows when the user has released a window after moving/resizing.
OnMoveEnd(hHook, event, hwnd, idObject, idChild, idThread, time) {
    global autoSaveEnabled, g_modPositions
    if (idObject != 0 || !autoSaveEnabled || !g_modPositions)
        return
    ; default: a drag only saves when the modifier is held while dropping -
    ; saving is then a deliberate gesture. Read HERE, at the drop.
    if (g_autoSaveModOnly && !ModifierHeld())
        return
    ; deferred out of the event callback; with Aero snap the window is resized
    ; just AFTER the drag ends
    SetTimer(AutoSave.Bind(hwnd), -200)
}

AutoSave(hwnd) {
    global winInfo
    key := ""
    try key := KeyFor(hwnd)
    if (key = "")
        return
    if SavePos(key, hwnd) {
        Toast(Tr("toastSaved"))
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true   ; do not move back what was just dropped
        PushStateSoon()
    }
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

; --- commands (hotkeys + tray) -----------------------------------------------

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
        p := LoadPos(key)
        where := (p != "") ? "`n(" p.x ", " p.y ", " p.w " × " p.h (p.max ? ", " Tr("maximized") : "") ")" : ""
        TrayTip DescribeKey(key) where, Tr("savedTitle")
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        PushStateSoon()
    } else
        TrayTip SaveErrorText(), Tr("appTitle")
}

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
    TrayTip Tr("forgot") "`n" DescribeKey(key), Tr("appTitle")
    PushStateSoon()
}

; Saves the position of every open manageable window - a snapshot of the
; current layout, the counterpart of ApplyAll.
SaveAll(*) {
    global winInfo
    n := 0
    for hwnd in WinGetList() {
        key := KeyFor(hwnd)
        if (key = "")
            continue
        if SavePos(key, hwnd) {
            n++
            if winInfo.Has(hwnd)
                winInfo[hwnd].done := true
        }
    }
    TrayTip Format(Tr("savedAll"), n), Tr("appTitle")
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

ToggleMove() {
    global moveEnabled, configIni, g_lblMove
    moveEnabled := !moveEnabled
    IniWrite(moveEnabled ? 1 : 0, configIni, "Positions", "MoveWindows")
    BuildTrayMenu()
    TrayTip Tr(moveEnabled ? "moveOn" : "moveOff")
    PushStateSoon()
}

ToggleAutoSave() {
    global autoSaveEnabled, configIni
    autoSaveEnabled := !autoSaveEnabled
    IniWrite(autoSaveEnabled ? 1 : 0, configIni, "Positions", "AutoSave")
    BuildTrayMenu()
    TrayTip Tr(autoSaveEnabled ? "autoSaveOn" : "autoSaveOff")
    PushStateSoon()
}

ToggleToasts() {
    global notifyEnabled, configIni
    notifyEnabled := !notifyEnabled
    IniWrite(notifyEnabled ? 1 : 0, configIni, "Positions", "Notify")
    BuildTrayMenu()
    PushStateSoon()
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
        key := IniRead(posIni, sec, "Key", "")
        list.Push(Map("section", sec, "setup", m[1]
            , "info", IniRead(posIni, sec, "Info", "")
            , "key", key, "pattern", PatternFor(key)
            , "x", IniRead(posIni, sec, "X", ""), "y", IniRead(posIni, sec, "Y", "")
            , "w", IniRead(posIni, sec, "W", ""), "h", IniRead(posIni, sec, "H", "")
            , "max", IniRead(posIni, sec, "Max", 0) = 1 ? 1 : 0))
    }
    return list
}
