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

; Why the last SavePos failed: "" (it did not), "min", "gone", "size" or "write" - the
; callers turn it into a message with SaveErrorText().
g_saveError := "", g_saveErrorText := ""

g_moveEndCb := 0, g_winEventHook := 0
g_keepOnScreen := "off"   ; off | office | all  (see KeepOnScreenGuard)
; Office frame processes. Their document windows carry real titles, so the
; guard reaches them; the exe is what scopes the "office" setting.
g_officeExe := Map("winword.exe", 1, "excel.exe", 1, "powerpnt.exe", 1
    , "outlook.exe", 1, "onenote.exe", 1, "onenoteim.exe", 1, "mspub.exe", 1
    , "msaccess.exe", 1, "visio.exe", 1, "winproj.exe", 1, "lync.exe", 1)

PositionsLoadConfig() {
    global configIni, moveEnabled, autoSaveEnabled, notifyEnabled, g_autoSaveModOnly, g_keepOnScreen
    moveEnabled     := IniRead(configIni, "Positions", "MoveWindows", 1) != "0"
    autoSaveEnabled := IniRead(configIni, "Positions", "AutoSave", 1) != "0"
    notifyEnabled   := IniRead(configIni, "Positions", "Notify", 1) != "0"
    g_autoSaveModOnly := IniRead(configIni, "Positions", "AutoSaveModifierOnly", 1) != "0"
    v := StrLower(Trim(IniRead(configIni, "Positions", "KeepOnScreen", "office")))
    g_keepOnScreen := (v = "all") ? "all" : (v = "0" || v = "off" || v = "") ? "off" : "office"
    global g_rescueOn
    g_rescueOn := IniRead(configIni, "Positions", "RescueOnDisplayChange", 1) != "0"
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
    OnExit(PositionsExit)
    RescueInit()
}

; The exit hook. Returns 0: a nonzero return value tells AHK to CANCEL the
; exit. Traced, so a slow exit can be told from a slow exit REQUEST.
PositionsExit(reason, code) {
    global g_winEventHook
    Trace("exit: reason " reason ", unhooking")
    DllCall("UnhookWinEvent", "ptr", g_winEventHook)
    Trace("exit: cleanup done")
    return 0
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

; Positions are kept separate per monitor setup + computer. The setup is the
; monitor count, the virtual screen width and a hash of every monitor's
; rectangle: count + width alone let two docking stations with the same
; screens but a different arrangement (one above the other here, side by
; side there) share positions - and a position from the other arrangement
; can lie entirely outside the screens.
; Always measured system-DPI-aware: the window menu switches the thread to
; per-monitor awareness while it is shown, and in that mode the same screens
; measure differently (4x9600 instead of 4x10400 here) - a timer running
; then would see a "new setup" and move every window to its saved place.
SetupKey() {
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -2, "ptr")   ; SYSTEM_AWARE
    try return LiveMonitorCount() "x" LiveWidth() "_" Hash32(MonitorLayout()) "_" A_ComputerName
    finally {
        if prev
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
}

; The setup key as it was before the layout hash (2.0.x): positions saved
; under it are still read when the current layout has none of its own.
LegacySetupKey() {
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -2, "ptr")
    try return LiveMonitorCount() "x" LiveWidth() "_" A_ComputerName
    finally {
        if prev
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
}

; Every monitor's rectangle, sorted so that the enumeration order does not
; matter. Screens that are turned off (IsDeadMonitor) are left out: with them
; off the setup is the one of the screens still on.
MonitorLayout() {
    rects := []
    loop MonitorGetCount() {
        if IsDeadMonitor(A_Index)
            continue
        MonitorGet(A_Index, &l, &t, &r, &b)
        rects.Push(Format("{},{},{},{}", l, t, r, b))
    }
    ; insertion sort - a handful of items
    loop rects.Length - 1 {
        i := A_Index + 1
        v := rects[i]
        while (i > 1 && StrCompare(rects[i - 1], v) > 0)
            rects[i] := rects[i - 1], i--
        rects[i] := v
    }
    out := ""
    for r in rects
        out .= r ";"
    return out
}

; True when at least a 100 px wide piece of the rectangle's title band (its
; top 40 px) lies on some monitor, i.e. the window can be grabbed there.
RectOnScreen(x, y, w, h) {
    loop MonitorGetCount() {
        if IsDeadMonitor(A_Index)
            continue
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (Min(x + w, r) - Max(x, l) >= 100 && Min(y + 40, b) > Max(y, t))
            return true
    }
    return false
}

; The refusal above was visible in the trace only, so a position saved in the
; gap between two monitors looked like "DalSegno does nothing". Once per key
; and five minutes the overlay says so.
OffScreenNotice(hwnd, key) {
    static told := Map()
    if (told.Has(key) && A_TickCount - told[key] < 300000)
        return
    told[key] := A_TickCount
    Notify(Format(Tr("posOffScreen"), ShortTitle(hwnd)))
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
        ; a window without a size is not a window anyone sees (a Java frame
        ; before it is shown, a hidden helper): nothing worth remembering
        if (w <= 0 || h <= 0) {
            g_saveError := "size"
            return false
        }
        section := SectionFor(key)
        IniWrite(key, posIni, section, "Key")
        IniWrite(WinGetProcessName(hwnd) " | " SubStr(FastTitle(hwnd), 1, 60), posIni, section, "Info")
        IniWrite(x, posIni, section, "X")
        IniWrite(y, posIni, section, "Y")
        IniWrite(w, posIni, section, "W")
        IniWrite(h, posIni, section, "H")
        IniWrite(mm = 1 ? 1 : 0, posIni, section, "Max")
        Trace(Format("saved {} key={} {},{} {}x{} max={}", TraceWin(hwnd), key, x, y, w, h, mm = 1 ? 1 : 0))
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
        case "size":  return Tr("cannotSaveSize")
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
    p := ReadPosSection(key, section)
    if (p != "")
        return p
    ; nothing for this layout yet: a position saved before the layout became
    ; part of the setup key is adopted - copied to this layout's section - if
    ; it lies on the screens as they are now
    legacy := "K" Hash32(key) "_" LegacySetupKey()
    p := ReadPosSection(key, legacy)
    if (p = "" || !RectOnScreen(p.x, p.y, p.w, p.h))
        return ""
    try {
        IniWrite(key, posIni, section, "Key")
        IniWrite(IniRead(posIni, legacy, "Info", ""), posIni, section, "Info")
        IniWrite(p.x, posIni, section, "X")
        IniWrite(p.y, posIni, section, "Y")
        IniWrite(p.w, posIni, section, "W")
        IniWrite(p.h, posIni, section, "H")
        IniWrite(p.max ? 1 : 0, posIni, section, "Max")
    }
    return p
}

ReadPosSection(key, section) {
    global posIni
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
    ; never push a window off the screens: a position whose title bar would
    ; land outside every monitor is left unused (the window stays where the
    ; app put it, and the next deliberate save replaces the position)
    if !RectOnScreen(p.x, p.y, p.w, p.h) {
        Trace(Format("move {} saved {},{} {}x{} max={} is OFF SCREEN - not applied", hwnd, p.x, p.y, p.w, p.h, p.max))
        OffScreenNotice(hwnd, key)
        return true
    }
    try {
        mm := WinGetMinMax(hwnd)
        WinGetPos(&x, &y, &w, &h, hwnd)
        Trace(Format("move {} saved {},{} {}x{} max={}; now {},{} {}x{} minmax={}", hwnd, p.x, p.y, p.w, p.h, p.max, x, y, w, h, mm))
        if (mm = -1)
            return true
        if (mm = 1) {
            if (p.max && MonitorFromWindow(hwnd) = MonitorAtPoint(p.x + p.w // 2, p.y + p.h // 2))
                return true
            WinRestore(hwnd)
            ; a Java frame restores asynchronously and then applies
            ; its own bounds - moving before that is done gets undone
            loop 10 {
                Sleep 100
                if (WinGetMinMax(hwnd) = 0)
                    break
            }
            Trace("move " hwnd " restored after " A_Index "00 ms, minmax=" WinGetMinMax(hwnd))
        }
        ; repeated until the rectangle sticks: width/height do not take on
        ; the first try when the window jumps to a monitor with a different
        ; scaling, and a slow app may still be laying itself out
        loop 4 {
            WinMove(p.x, p.y, p.w, p.h, hwnd)
            Sleep 100
            WinGetPos(&x, &y, &w, &h, hwnd)
            Trace(Format("move {} try {}: now {},{} {}x{}", hwnd, A_Index, x, y, w, h))
            if (x = p.x && y = p.y && w = p.w && h = p.h)
                break
        }
        if p.max
            WinMaximize(hwnd)
    } catch as e
        Trace("move " hwnd " FAILED: " e.Message)
    return true
}

MonitorAtPoint(x, y) {
    loop MonitorGetCount() {
        if IsDeadMonitor(A_Index)
            continue
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

; --- keep windows on screen -------------------------------------------------
; Windows restores each app window - Office documents especially - to its last
; coordinates, which can land in a monitor "dead zone" (a gap in an L-shaped
; layout, or a screen that is now gone), opening the window where no monitor
; is. This nudges such a window the smallest distance onto the nearest real
; screen's work area. It acts ONLY on a window that sits entirely off every
; monitor, so one parked at a screen edge on purpose is left alone. Called
; from the scan for every ready window.
KeepOnScreenGuard(hwnd) {
    global g_keepOnScreen, g_officeExe
    if (g_keepOnScreen = "off")
        return
    info := BaseInfo(hwnd)          ; real, titled, non-cloaked, non-tool, not ignored
    if (info = "")
        return
    if (g_keepOnScreen = "office" && !g_officeExe.Has(StrLower(info.exe)))
        return
    mm := 0
    try mm := WinGetMinMax(hwnd)
    if (mm != 0)                    ; minimized (-1) or maximized (1): not off-screen
        return
    x := 0, y := 0, w := 0, h := 0
    try WinGetPos(&x, &y, &w, &h, hwnd)
    if (w <= 0 || h <= 0)
        return
    nx := 0, ny := 0
    if !OffScreenTarget(x, y, w, h, &nx, &ny)
        return
    try WinMove(nx, ny, , , hwnd)
    Trace("keep-on-screen " TraceWin(hwnd) " " x "," y " -> " nx "," ny)
}

; True (and sets nx,ny) when the rect is entirely off every monitor; nx,ny is
; then the smallest move onto the nearest monitor's work area. False when any
; part of the rect already overlaps a monitor (bounds, so a window under the
; taskbar still counts as on-screen).
OffScreenTarget(x, y, w, h, &nx, &ny) {
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (x < r && x + w > l && y < b && y + h > t)
            return false
    }
    best := ""
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        tx := (w >= r - l) ? l : Min(Max(x, l), r - w)
        ty := (h >= b - t) ? t : Min(Max(y, t), b - h)
        d := Abs(tx - x) + Abs(ty - y)
        if (best = "" || d < best)
            best := d, nx := tx, ny := ty
    }
    return true
}

; --- rescue after a monitor is unplugged -------------------------------------
; Turning a screen off or undocking can leave windows where no monitor is any
; longer - Windows moves most of them, but not all, and not the ones parked
; on other virtual desktops. RESCUE_DELAY_MS after the last WM_DISPLAYCHANGE
; (a burst while the screens renegotiate; each one restarts the wait) every
; window whose title bar cannot be grabbed on any monitor is moved onto the
; nearest remaining screen - normal, maximized (re-maximized there) and
; minimized (its restore rectangle) alike. Windows the user can reach are
; never touched. [Positions] RescueOnDisplayChange=0 turns it off.
; The Desktops module restarts the script 2.5 s after a layout change; a
; rescue still pending is handed over as /rescue=<ms left> (DalSegno.ahk).
RESCUE_DELAY_MS := 5000
g_rescueOn := true
g_rescueDue := 0     ; A_TickCount the pending rescue runs at, 0 = none

RescueInit() {
    OnMessage(0x7E, RescueDisplayChange)   ; WM_DISPLAYCHANGE
    PowerInit()
    for a in A_Args
        if RegExMatch(a, "i)^/rescue=(\d+)$", &m)
            RescueSchedule(Max(Integer(m[1]), 500))
}

RescueDisplayChange(*) {
    global g_rescueOn, RESCUE_DELAY_MS
    if g_rescueOn
        RescueSchedule(RESCUE_DELAY_MS)
}

RescueSchedule(ms) {
    global g_rescueDue
    g_rescueDue := A_TickCount + ms
    SetTimer(RescueRun, -ms)
    Trace("rescue in " ms " ms")
}

; Milliseconds left until the pending rescue, 0 when none is pending.
RescuePendingMs() {
    global g_rescueDue
    return g_rescueDue ? Max(g_rescueDue - A_TickCount, 1) : 0
}

RescueRun() {
    global g_rescueDue, g_menuOpen
    if g_menuOpen {   ; the menu runs the thread per-monitor aware - see ScanWindows
        RescueSchedule(1000)
        return
    }
    g_rescueDue := 0
    if !LiveMonitorCount()
        return
    prev := DllCall("SetThreadDpiAwarenessContext", "ptr", -2, "ptr")   ; SYSTEM_AWARE
    back := 0, n := 0
    try {
        back := ReturnRescued()
        n := RescueStranded()
    } finally {
        if prev
            DllCall("SetThreadDpiAwarenessContext", "ptr", prev, "ptr")
    }
    if back
        Notify(Format(Tr("returned"), back), Tr("appTitle"))
    if n
        Notify(Format(Tr("rescued"), n), Tr("appTitle"))
}

; Moves every stranded window onto a monitor; returns how many were moved.
RescueStranded() {
    global g_dllLoaded
    n := 0
    for hwnd in WinGetList() {
        ; windows on other desktops are cloaked but real; cloaked ghosts that
        ; are on no desktop (UWP leftovers) are not
        if IsCloaked(hwnd) && !(g_dllLoaded && DesktopOf(hwnd) != "")
            continue
        if (BaseInfo(hwnd, true) = "")
            continue
        try {
            if RescueWindow(hwnd)
                n++
        } catch as e
            Trace("rescue " hwnd " FAILED: " e.Message)
    }
    Trace("rescue done, " n " moved")
    return n
}

RescueWindow(hwnd) {
    mm := WinGetMinMax(hwnd)
    if (mm = 0) {
        WinGetPos(&x, &y, &w, &h, hwnd)
        if (w <= 0 || h <= 0 || RectOnScreen(x, y, w, h))
            return false
        chain := RescueChain(hwnd), hop := RescueHop(x, y, w, h, 0)
        FitOnScreen(&x, &y, &w, &h)
        WinMove(x, y, w, h, hwnd)
        RescueRecord(hwnd, chain, hop)
        Trace("rescue " TraceWin(hwnd) " -> " x "," y " " w "x" h)
        return true
    }
    if (mm = 1) {
        WinGetPos(&x, &y, &w, &h, hwnd)
        ; a maximized window overhangs its monitor by the frame - test the
        ; monitor rectangle it fills, i.e. its centre
        if MonitorAtPoint(x + w // 2, y + h // 2)
            return false
        chain := RescueChain(hwnd), hop := ""
        if NormalRect(hwnd, &nx, &ny, &nw, &nh)
            hop := RescueHop(nx, ny, nw, nh, 1)
        WinRestore(hwnd)
        WinGetPos(&x, &y, &w, &h, hwnd)
        FitOnScreen(&x, &y, &w, &h)
        WinMove(x, y, w, h, hwnd)
        WinMaximize(hwnd)
        RescueRecord(hwnd, chain, hop)
        Trace("rescue maximized " TraceWin(hwnd) " -> " x "," y)
        return true
    }
    ; minimized: only the restore rectangle (WINDOWPLACEMENT.rcNormalPosition,
    ; in workspace coordinates - see NormalRect) is moved, so it comes back
    ; on a screen; it stays minimized
    if (!NormalRect(hwnd, &x, &y, &w, &h) || RectOnScreen(x, y, w, h))
        return false
    chain := RescueChain(hwnd), hop := RescueHop(x, y, w, h, -1)
    FitOnScreen(&x, &y, &w, &h)
    SetNormalRect(hwnd, x, y, w, h)
    RescueRecord(hwnd, chain, hop)
    Trace("rescue minimized " TraceWin(hwnd) " -> " x "," y)
    return true
}

; Sets a minimized window's restore rectangle (screen coordinates); it stays
; minimized and does not take the focus.
SetNormalRect(hwnd, x, y, w, h) {
    wp := Buffer(44, 0)
    NumPut("UInt", 44, wp, 0)
    if !DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", wp)
        return false
    MonitorGetWorkArea(MonitorGetPrimary(), &wl, &wt)
    NumPut("Int", x - wl, "Int", y - wt, "Int", x + w - wl, "Int", y + h - wt, wp, 28)
    NumPut("UInt", 7, wp, 8)   ; showCmd SW_SHOWMINNOACTIVE
    return DllCall("SetWindowPlacement", "ptr", hwnd, "ptr", wp)
}

; --- and back again ----------------------------------------------------------
; A rescued window remembers where it was: the screen (device name) and its
; place relative to that screen's corner - the coordinates themselves change
; when the primary screen does. Rescued again before it went back (screen 2
; off: to screen 3; screen 3 off: to screen 1), it remembers every stop: the
; chain 2, 3. When a screen comes on again, the window goes to the FIRST stop
; in its chain that is on - screen 3 on: to 3; screen 2 on too: on to 2. Not
; when it has been moved, maximized, restored or minimized since it was put
; where it is: then the user (or a saved position) has placed it, and that
; wins. Kept in state.ini [Rescued] to outlive the restarts that layout
; changes bring:
;   hwnd = exe | stops | state | where
;   stops  dev,dx,dy,w,h,state;dev,dx,dy,w,h,state;...  (oldest first)
;   state  0 normal, 1 maximized, -1 minimized - the window's state now
;   where  dev,dx,dy,w,h - where it was put (normal windows; else empty)
; Only a screen that is off but still in the layout has a device to go back
; to; a window rescued from an unplugged screen stays (Windows itself brings
; windows back when a screen is plugged in again).

; The stop for a rectangle about to be rescued: "" when it is on no screen
; that is merely off.
RescueHop(x, y, w, h, st) {
    rect := Buffer(16)
    NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, rect)
    hMon := DllCall("MonitorFromRect", "ptr", rect, "uint", 0, "ptr")   ; DEFAULTTONULL
    if !hMon
        return ""
    dev := MonitorDevice(hMon, &ml, &mt)
    if (dev = "" || !IsDeadDevice(dev))
        return ""
    return dev "," (x - ml) "," (y - mt) "," w "," h "," st
}

; The stops a window already has, when it is still where the last rescue put
; it; "" otherwise.
RescueChain(hwnd) {
    v := IniRead(PowerStatePath(), "Rescued", hwnd, "")
    p := StrSplit(v, "|")
    return (p.Length >= 4 && RescueUntouched(hwnd, p)) ? p[2] : ""
}

; Writes the window's entry after a rescue: its earlier stops, the new one,
; and where it is now.
RescueRecord(hwnd, chain, hop) {
    f := PowerStatePath()
    stops := (chain != "" && hop != "") ? chain ";" hop : (hop != "" ? hop : chain)
    if (stops = "") {
        try IniDelete(f, "Rescued", hwnd)
        return
    }
    try IniWrite(WinGetProcessName(hwnd) "|" stops "|" WinGetMinMax(hwnd) "|" WhereNow(hwnd)
        , f, "Rescued", hwnd)
}

; A normal window's rectangle relative to the screen it is on: dev,dx,dy,w,h.
WhereNow(hwnd) {
    if (WinGetMinMax(hwnd) != 0)
        return ""
    WinGetPos(&x, &y, &w, &h, hwnd)
    rect := Buffer(16)
    NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, rect)
    dev := MonitorDevice(DllCall("MonitorFromRect", "ptr", rect, "uint", 2, "ptr"), &ml, &mt)
    return (dev = "") ? "" : dev "," (x - ml) "," (y - mt) "," w "," h
}

; True when the window is still as the last rescue left it (entry split on |).
RescueUntouched(hwnd, p) {
    if (WinGetMinMax(hwnd) != Integer(p[3]))
        return false
    return Integer(p[3]) != 0 || WhereNow(hwnd) = p[4]
}

; The monitor number with that device name, 0 when it is not in the layout.
MonitorByDevice(dev) {
    loop MonitorGetCount()
        if (MonitorGetName(A_Index) = dev)
            return A_Index
    return 0
}

; The device name and top-left corner of a monitor handle.
MonitorDevice(hMon, &l, &t) {
    mi := Buffer(104, 0)
    NumPut("UInt", 104, mi, 0)
    if !DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", mi)
        return ""
    l := NumGet(mi, 4, "Int"), t := NumGet(mi, 8, "Int")
    return StrGet(mi.Ptr + 40, 32, "UTF-16")
}

IsDeadDevice(dev) {
    global g_deadMon
    return g_deadMon.Has(dev)
}

; Moves the rescued windows whose screen is on again back; returns how many.
ReturnRescued() {
    f := PowerStatePath()
    section := ""
    try section := IniRead(f, "Rescued")
    if (section = "")
        return 0
    n := 0
    for line in StrSplit(section, "`n", "`r") {
        eq := InStr(line, "=")
        if !eq
            continue
        hwnd := Integer(SubStr(line, 1, eq - 1)), p := StrSplit(SubStr(line, eq + 1), "|")
        try {
            if (p.Length < 4 || !WinExist(hwnd) || WinGetProcessName(hwnd) != p[1]
                || !RescueUntouched(hwnd, p)) {
                IniDelete(f, "Rescued", hwnd)   ; gone, or placed by the user since
                continue
            }
            stops := StrSplit(p[2], ";")
            ; the first stop whose screen is on
            i := 0, m := 0
            for s in stops {
                dev := StrSplit(s, ",")[1]
                if ((m := MonitorByDevice(dev)) && !IsDeadMonitor(m)) {
                    i := A_Index
                    break
                }
            }
            if !i
                continue   ; every screen it was on is still off
            s := StrSplit(stops[i], ",")
            MonitorGet(m, &ml, &mt)
            x := ml + Integer(s[2]), y := mt + Integer(s[3]), w := Integer(s[4]), h := Integer(s[5])
            mm := WinGetMinMax(hwnd)
            if (mm = -1)
                SetNormalRect(hwnd, x, y, w, h)
            else {
                if (mm = 1)
                    WinRestore(hwnd)
                WinMove(x, y, w, h, hwnd)
                if (mm = 1 || Integer(s[6]) = 1)
                    WinMaximize(hwnd)
            }
            n++
            Trace("return " TraceWin(hwnd) " -> " s[1] " " x "," y " " w "x" h " (stop " i " of " stops.Length ")")
            ; the stops before it stay: their screens are still off
            rest := ""
            loop i - 1
                rest .= (rest = "" ? "" : ";") stops[A_Index]
            RescueRecord(hwnd, rest, "")
        } catch as e
            Trace("return " hwnd " FAILED: " e.Message)
    }
    return n
}

; Puts the rectangle inside the work area of the monitor nearest to it,
; shrinking it only when it is larger than that work area.
FitOnScreen(&x, &y, &w, &h) {
    best := "", bl := 0, bt := 0, br := 0, bb := 0
    loop MonitorGetCount() {
        if IsDeadMonitor(A_Index)
            continue
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        ; distance from the rectangle's centre to the work area
        cx := x + w // 2, cy := y + h // 2
        d := Max(l - cx, 0, cx - r) + Max(t - cy, 0, cy - b)
        if (best = "" || d < best)
            best := d, bl := l, bt := t, br := r, bb := b
    }
    if (best = "")
        return
    w := Min(w, br - bl), h := Min(h, bb - bt)
    x := Min(Max(x, bl), br - w), y := Min(Max(y, bt), bb - h)
}

; --- screens that are off but still in the layout ----------------------------
; A DisplayPort screen turned off with its button usually stays in the
; Windows layout - no WM_DISPLAYCHANGE, so the rescue above never runs, and
; when it was the primary screen the taskbar and every new window keep going
; to a dark screen. The helper process DalSegnoPower.ahk asks the screens
; themselves over DDC/CI and reports the ones that are off (how: see there).
; Here such a screen is treated as unplugged: it is left out of the setup
; (so the positions saved for the screens still on apply), the windows on it
; are rescued, and when it was the primary screen the built-in screen (or
; else the largest one still on) becomes primary - for the session only, the
; saved display configuration is not touched. When the old primary is on
; again, the saved configuration is put back.
; State that has to outlive the restart a layout change brings (Desktops
; module) is kept in %LOCALAPPDATA%\DalSegno\state.ini.
g_deadMon := Map()   ; device name (\\.\DISPLAYn) -> true: off although in the layout

IsDeadMonitor(n) {
    global g_deadMon
    if !g_deadMon.Count
        return false
    try return g_deadMon.Has(MonitorGetName(n))
    return false
}

LiveMonitorCount() {
    global g_deadMon
    c := MonitorGetCount()
    if !g_deadMon.Count
        return c
    n := 0
    loop c
        n += !IsDeadMonitor(A_Index)
    return n
}

; The width of the virtual screen, or with screens off, of the screens still
; on - SysGet(78) unchanged when all are on, so the saved setups keep their keys.
LiveWidth() {
    global g_deadMon
    if !g_deadMon.Count
        return SysGet(78)
    lo := "", hi := ""
    loop MonitorGetCount() {
        if IsDeadMonitor(A_Index)
            continue
        MonitorGet(A_Index, &l, , &r)
        lo := (lo = "") ? l : Min(lo, l), hi := (hi = "") ? r : Max(hi, r)
    }
    return (lo = "") ? 0 : hi - lo
}

PowerStatePath() {
    SplitPath(ErrorLogPath(), , &dir)
    return dir "\state.ini"
}

PowerInit() {
    global g_deadMon
    OnMessage(DllCall("RegisterWindowMessage", "str", "DALSEGNO_POWER", "uint"), PowerReport)
    ; the screens found off by the instance before a restart, if that was just now
    f := PowerStatePath()
    t := IniRead(f, "Power", "Time", "")
    if (t != "" && DateDiff(A_Now, t, "Seconds") < 60)
        for dev in StrSplit(IniRead(f, "Power", "Dead", ""), "|")
            if (dev != "")
                g_deadMon[dev] := true
    if g_deadMon.Count
        Trace("power: off at start " IniRead(f, "Power", "Dead", ""))
    OnExit(PowerExit)
    StartPowerHelper()
    SetTimer(StartPowerHelper, 30000)   ; brought back if it ever dies
}

; The screens that are off, for the next instance (PowerInit) - a restart
; follows every layout change.
PowerExit(*) {
    global g_deadMon
    s := ""
    for dev in g_deadMon
        s .= dev "|"
    f := PowerStatePath()
    try IniWrite(s, f, "Power", "Dead"), IniWrite(A_Now, f, "Power", "Time")
    return 0
}

StartPowerHelper() {
    global g_rescueOn
    if (!g_rescueOn || !FileExist(A_ScriptDir "\DalSegnoPower.ahk"))
        return   ; (a missing script would get AutoHotkey's error box)
    ; restored: set during the auto-execute section it would become every
    ; thread's default, and the scan would see every hidden window
    prevHidden := A_DetectHiddenWindows
    DetectHiddenWindows true
    try running := WinExist("DalSegnoPower ahk_class AutoHotkey")
    finally DetectHiddenWindows prevHidden
    if running
        return
    try Run('"' A_AhkPath '" "' A_ScriptDir '\DalSegnoPower.ahk"')
}

; DALSEGNO_POWER from the helper, every 2.5 s: wParam = the screens that are
; off, lParam = the built-in ones, bit n-1 for \\.\DISPLAYn.
PowerReport(wParam, lParam, *) {
    global g_deadMon, g_rescueOn
    dead := Map()
    if g_rescueOn
        loop 32
            if (wParam & (1 << (A_Index - 1)))
                dead["\\.\DISPLAY" A_Index] := true
    s := "", old := ""
    for dev in dead
        s .= dev "|"
    for dev in g_deadMon
        old .= dev "|"
    if (s != old) {
        Trace("power: off [" old "] -> [" s "]")
        g_deadMon := dead
        SetTimer(PowerChanged.Bind(lParam), -1)
    } else
        PowerRestorePrimary()
}

PowerChanged(internalMask) {
    global g_deadMon
    if PowerRestorePrimary()
        return   ; the layout change brings WM_DISPLAYCHANGE, and with it the return
    if !g_deadMon.Count {
        RescueSchedule(500)   ; screens on again: their windows go back
        return
    }
    live := LiveMonitorCount()
    if !live
        return   ; every screen off: nothing to move to
    prim := MonitorGetPrimary()
    if IsDeadMonitor(prim) {
        ; the new primary: the built-in screen, else the largest one still on
        best := 0, bestArea := -1
        loop MonitorGetCount() {
            if IsDeadMonitor(A_Index)
                continue
            MonitorGet(A_Index, &l, &t, &r, &b)
            area := (r - l) * (b - t)
            if RegExMatch(MonitorGetName(A_Index), "i)DISPLAY(\d+)$", &m)
                && (internalMask & (1 << (m[1] - 1)))
                area += 1 << 40
            if (area > bestArea)
                best := A_Index, bestArea := area
        }
        oldDev := MonitorGetName(prim), newDev := MonitorGetName(best)
        ; written BEFORE the change: SetDisplayConfig takes seconds, and the
        ; restart the layout change brings (Desktops module) can end this
        ; instance before it returns
        f := PowerStatePath()
        hadOrig := IniRead(f, "Power", "OrigPrimary", "") != ""
        if !hadOrig
            IniWrite(oldDev, f, "Power", "OrigPrimary")
        Trace("power: primary " oldDev " -> " newDev)
        if SetPrimaryScreen(newDev)
            return   ; the layout change brings WM_DISPLAYCHANGE, and with it the rescue
        if !hadOrig
            IniDelete(f, "Power", "OrigPrimary")
        Trace("power: primary " oldDev " -> " newDev " FAILED")
    }
    RescueSchedule(500)
}

; The old primary is on again: the saved display configuration goes back.
; True when it did.
PowerRestorePrimary() {
    f := PowerStatePath()
    orig := IniRead(f, "Power", "OrigPrimary", "")
    if (orig = "")
        return false
    present := false
    loop MonitorGetCount()
        if (MonitorGetName(A_Index) = orig) {
            present := true
            if IsDeadMonitor(A_Index)
                return false
            if (A_Index = MonitorGetPrimary()) {   ; already back (a reboot, by hand)
                IniDelete(f, "Power", "OrigPrimary")
                return false
            }
        }
    if !present
        return false   ; unplugged: undocked, the layout is Windows' own business
    IniDelete(f, "Power", "OrigPrimary")
    Trace("power: " orig " on again, restoring the saved layout")
    ; SDC_APPLY | SDC_USE_DATABASE_CURRENT: the configuration Windows has
    ; saved for these screens, which SetPrimaryScreen never wrote to. Takes
    ; seconds - this instance may be restarted before it returns.
    rc := DllCall("SetDisplayConfig", "uint", 0, "ptr", 0, "uint", 0, "ptr", 0, "uint", 0x80 | 0x0F)
    if rc
        Trace("power: restoring the saved layout FAILED rc=" rc)
    return rc = 0
}

; Makes the screen with that device name the primary one: the layout shifted
; so that it sits at 0,0 - applied for this session only (no
; SDC_SAVE_TO_DATABASE), so a reboot or PowerRestorePrimary brings back the
; saved layout.
SetPrimaryScreen(dev) {
    if DllCall("GetDisplayConfigBufferSizes", "uint", 2, "uint*", &np := 0, "uint*", &nm := 0)
        return false
    paths := Buffer(np * 72, 0), modes := Buffer(nm * 64, 0)
    if DllCall("QueryDisplayConfig", "uint", 2, "uint*", &np, "ptr", paths, "uint*", &nm, "ptr", modes, "ptr", 0)
        return false
    ; the source mode of that screen: its position is the shift
    dx := "", dy := ""
    loop nm {
        o := (A_Index - 1) * 64
        if (NumGet(modes, o, "UInt") != 1)   ; DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE
            continue
        req := Buffer(84, 0)
        NumPut("UInt", 1, "UInt", 84, req, 0)                     ; GET_SOURCE_NAME
        NumPut("Int64", NumGet(modes, o + 8, "Int64"), req, 8)    ; adapterId
        NumPut("UInt", NumGet(modes, o + 4, "UInt"), req, 16)     ; source id
        if DllCall("DisplayConfigGetDeviceInfo", "ptr", req)
            continue
        if (StrGet(req.Ptr + 20, 32, "UTF-16") = dev) {
            dx := NumGet(modes, o + 28, "Int"), dy := NumGet(modes, o + 32, "Int")
            break
        }
    }
    if (dx = "")
        return false
    loop nm {
        o := (A_Index - 1) * 64
        if (NumGet(modes, o, "UInt") != 1)
            continue
        NumPut("Int", NumGet(modes, o + 28, "Int") - dx, "Int", NumGet(modes, o + 32, "Int") - dy, modes, o + 28)
    }
    ; SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES
    rc := DllCall("SetDisplayConfig", "uint", np, "ptr", paths, "uint", nm, "ptr", modes, "uint", 0x80 | 0x20 | 0x400)
    return rc = 0
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
    if !moveEnabled
        return
    if info.done {
        PositionsSettle(hwnd, info)
        return
    }
    if !WindowReady(hwnd)
        return              ; 0x0 so far - the scan holds the grace for it
    if (A_TickCount - info.seen > PLACEMENT_GRACE_MS) {
        info.done := true   ; never got a recognizable title - give up
        Trace("place " TraceWin(hwnd) " - grace over, giving up")
        return
    }
    key := KeyFor(hwnd)
    if (key = "")
        return              ; the title may arrive later - keep watching
    Trace("place " TraceWin(hwnd) " key=" key)
    info.key := key
    if MoveToSaved(hwnd, key) {
        info.done := true
        ; the settling phase: see PositionsSettle
        info.placed := LoadPos(key), info.settleUntil := A_TickCount + SETTLE_MS, info.reapplied := 0
    } else
        Trace("place " hwnd " - no saved position, keep watching")
}

; For SETTLE_MS after a placement the window is watched: an app that applies
; its own bounds right after being shown (Java restores its last bounds and
; maximized state, some apps re-center themselves) undoes the placement, so
; it is applied again - at most twice; an app that insists wins. A move by
; the user's hand (OnMoveEnd) ends the watch at once.
SETTLE_MS := 3000
PositionsSettle(hwnd, info) {
    if !info.HasProp("settleUntil")
        return
    if (A_TickCount > info.settleUntil || info.HasProp("hand") || info.placed = "") {
        info.DeleteProp("settleUntil"), info.DeleteProp("placed"), info.DeleteProp("reapplied")
        return
    }
    try {
        p := info.placed
        mm := WinGetMinMax(hwnd)
        WinGetPos(&x, &y, &w, &h, hwnd)
        same := p.max ? (mm = 1) : (mm = 0 && x = p.x && y = p.y && w = p.w && h = p.h)
        if (same || mm = -1)
            return
        if (info.reapplied >= 2) {
            Trace(Format("settle {}: app keeps it at {},{} {}x{} minmax={} - giving up", hwnd, x, y, w, h, mm))
            info.DeleteProp("settleUntil"), info.DeleteProp("placed"), info.DeleteProp("reapplied")
            return
        }
        info.reapplied++
        Trace(Format("settle {}: app moved it to {},{} {}x{} minmax={} - placing again ({})", hwnd, x, y, w, h, mm, info.reapplied))
        MoveToSaved(hwnd, info.key)
        info.settleUntil := A_TickCount + SETTLE_MS
    }
}

; Called by Windows when the user has released a window after moving/resizing.
OnMoveEnd(hHook, event, hwnd, idObject, idChild, idThread, time) {
    global autoSaveEnabled, g_modPositions, winInfo
    if (idObject != 0 || !g_modPositions)
        return
    ; a window moved or resized by hand stays that way: the scan must never
    ; pull it back to the saved position, whatever state it is in
    if winInfo.Has(hwnd) {
        winInfo[hwnd].done := true, winInfo[hwnd].hand := true
        try winInfo[hwnd].key := KeyFor(hwnd)   ; so a later title change is not "new"
    }
    if !autoSaveEnabled
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
        Notify(Tr("cannotHandle"), Tr("appTitle"))
        return
    }
    if SavePos(key, hwnd) {
        p := LoadPos(key)
        where := (p != "") ? "`n(" p.x ", " p.y ", " p.w " × " p.h (p.max ? ", " Tr("maximized") : "") ")" : ""
        Notify(DescribeKey(key) where, Tr("savedTitle"))
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        PushStateSoon()
    } else
        Notify(SaveErrorText(), Tr("appTitle"))
}

ForgetActive() {
    global posIni
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd
        return
    key := KeyFor(hwnd)
    if (key = "" || LoadPos(key) = "") {
        Notify(Tr("nothingForget"), Tr("appTitle"))
        return
    }
    try IniDelete(posIni, SectionFor(key))
    Notify(Tr("forgot") "`n" DescribeKey(key), Tr("appTitle"))
    PushStateSoon()
}

; Saves the position of every open manageable window - a snapshot of the
; current layout, the counterpart of ApplyAll. Only windows that are real
; (have a size) and are on a virtual desktop: a titled top-level window on no
; desktop is a hidden helper the user never sees, and the Windows tab skips
; those the same way.
SaveAll(*) {
    global winInfo, g_modDesktops, g_dllLoaded
    n := 0
    for hwnd in WinGetList() {
        key := KeyFor(hwnd)
        if (key = "" || !WindowReady(hwnd))
            continue
        if (g_modDesktops && g_dllLoaded && DesktopOf(hwnd) = "")
            continue
        if SavePos(key, hwnd) {
            n++
            if winInfo.Has(hwnd)
                winInfo[hwnd].done := true
        }
    }
    Notify(Format(Tr("savedAll"), n), Tr("appTitle"))
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
    Notify(Format(Tr("movedAll"), n), Tr("appTitle"))
}

ToggleMove() {
    global moveEnabled, configIni, g_lblMove
    moveEnabled := !moveEnabled
    IniWrite(moveEnabled ? 1 : 0, configIni, "Positions", "MoveWindows")
    BuildTrayMenu()
    Notify(Tr(moveEnabled ? "moveOn" : "moveOff"))
    PushStateSoon()
}

ToggleAutoSave() {
    global autoSaveEnabled, configIni
    autoSaveEnabled := !autoSaveEnabled
    IniWrite(autoSaveEnabled ? 1 : 0, configIni, "Positions", "AutoSave")
    BuildTrayMenu()
    Notify(Tr(autoSaveEnabled ? "autoSaveOn" : "autoSaveOff"))
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

; Saved positions that can never apply again - an empty key, or a helper /
; message-only window class - dropped so the list is not padded with rows that
; match no real window. Run at startup and on reload.
PrunePositions() {
    global posIni
    removed := 0
    for p in ListPositions() {
        key := p["key"]
        junk := (key = "")
        if (!junk && SubStr(key, 1, 5) != "rule:" && InStr(key, "|")) {
            cls := SubStr(key, InStr(key, "|") + 1)
            if IsHelperClass(cls)
                junk := true
        }
        if junk
            (IniDelete(posIni, p["section"]), removed += 1)
    }
    return removed
}
