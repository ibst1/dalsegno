; =============================================================================
;  DalSegno Window Manager - Desktops module (from DeskPilot)
;
;  Virtual desktops: always see which desktop you are on, and move windows
;  between desktops with hotkeys, the mouse, the window menu or rules.
;
;  Detection reads Explorer's own registry values (no undocumented APIs):
;    HKCU\...\Explorer\VirtualDesktops\CurrentVirtualDesktop  (GUID, 16 bytes)
;    HKCU\...\Explorer\VirtualDesktops\VirtualDesktopIDs      (all GUIDs in order)
;    HKCU\...\Explorer\VirtualDesktops\Desktops\{GUID}\Name   (name, if renamed)
;  Moving windows requires VirtualDesktopAccessor.dll (Ciantic, MIT) in the
;  script folder - the public IVirtualDesktopManager::MoveWindowToDesktop
;  returns E_ACCESSDENIED for other processes' windows - and so does renaming
;  desktops. Without the dll everything else still works; switching falls
;  back to sending Ctrl+Win+arrow. The dll build must match the Windows
;  feature update (see VDA_DLL below).
;
;  IPC: other scripts post RegisterWindowMessage("DESKPILOT_CMD") (or
;  "DALSEGNO_CMD") to this script's hidden main window. wParam: 1=switch,
;  2=move active window, 3=move+follow, 4=show name OSD, 5=reload config,
;  6=next desktop, 7=previous, 8=open the GUI, 9=save/rule dialog for a
;  window, 10=query a window's flags, 11=rename prompt for a desktop,
;  100=ping (writes ping.txt). lParam: desktop N (cmd 1-3, 11) or hwnd (9, 10).
; =============================================================================

VD_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops"
; The dll is built against one Windows feature update's internal COM
; interfaces: 24H2 (build 26100) restructured the VTable, so the current
; release only fits 24H2 and later, while 23H2 (22631) needs the release
; built for it. Calls that sit before the inserted slot happen to work with
; the wrong dll (moving, switching); SetDesktopName does not. Both ship,
; the build decides.
; The 23H2 build keeps the file name, in its own folder, so the module name
; the DllCalls use ("VirtualDesktopAccessor") is the same whichever loads.
VDA_DLL := A_ScriptDir "\VirtualDesktopAccessor.dll"
if (VerCompare(A_OSVersion, "10.0.26100") < 0 && FileExist(A_ScriptDir "\23H2\VirtualDesktopAccessor.dll"))
    VDA_DLL := A_ScriptDir "\23H2\VirtualDesktopAccessor.dll"

g_dllLoaded := false
g_desktopHotkeys := []   ; what ApplyDesktopHotkeys registered
g_lastGuid := ""         ; GUID at last poll - separates a switch from startup/rename
g_lastState := ""        ; guid|name|count - update the tray only when something changed
g_lastStatus := 0        ; last read status, used by the taskbar name label
g_osd := 0
g_label := 0             ; the name label on the taskbar
g_labelText := ""        ; last rendered label content (avoids needless redraws)
g_nameInTray := true
g_wheel := true          ; mouse wheel over the taskbar switches desktop
g_arrowIcons := false    ; two tray icons (DalSegnoArrow.ahk) that switch desktop
g_screenSnapshot := ""   ; monitor layout at startup (spurious-event filter)
g_desktopsStarted := false

DesktopsLoadConfig() {
    global configIni, g_nameInTray, g_wheel, g_arrowIcons, g_labelText, g_modDesktops
    g_nameInTray := IniRead(configIni, "Desktops", "NameInTray", 1) != "0"
    g_wheel := IniRead(configIni, "Desktops", "Wheel", 1) != "0"
    g_arrowIcons := IniRead(configIni, "Desktops", "ArrowIcons", 0) != "0"
    g_labelText := ""      ; force a redraw with any new setting
    if (!g_nameInTray || !g_modDesktops)
        HideLabel()
    if g_desktopsStarted {
        ApplyDesktopHotkeys()
        UpdateArrowIcons()
    }
}

DesktopsInit() {
    global g_dllLoaded, g_screenSnapshot, g_desktopsStarted, VDA_DLL
    g_dllLoaded := FileExist(VDA_DLL) ? DllCall("LoadLibrary", "str", VDA_DLL, "ptr") != 0 : false
    g_screenSnapshot := ScreenSnapshot()
    g_desktopsStarted := true
    ApplyDesktopHotkeys()
    UpdateArrowIcons()
    OnMessage(0x7E, DisplayChangeGuard)   ; WM_DISPLAYCHANGE: restart on monitor changes
    HotIf(MouseOverLabel)
    Hotkey("LButton", LabelClick, "On")   ; label: left = desktop picker
    Hotkey("RButton", LabelRightClick, "On")   ; label: right = the GUI
    HotIf()
    PollDesktops()       ; set the icon right away; the first call shows no OSD
    SetTimer(PollDesktops, 250)
    SetTimer(LabelGuard, 250)   ; keeps the name label placed, visible and on top
}

; The module switched on or off in the settings while running.
DesktopsModuleToggled() {
    global g_modDesktops, g_desktopsStarted, g_lastState
    if (g_modDesktops && !g_desktopsStarted) {
        DesktopsInit()
        return
    }
    if !g_modDesktops {
        HideLabel()
        UpdateArrowIcons()
        ApplyDesktopHotkeys()
        if FileExist(A_ScriptDir "\app.ico")
            TraySetIcon(A_ScriptDir "\app.ico")
        A_IconTip := Tr("appTitle")
    } else {
        ApplyDesktopHotkeys()
        UpdateArrowIcons()
        g_lastState := ""   ; the numbered icon comes back on the next poll
    }
}

DesktopsLanguageChanged() {
    global g_lastState, g_modDesktops
    if !g_modDesktops
        return
    g_lastState := ""      ; force tray tooltip/label refresh on next poll
    DetectHiddenWindows true
    SetTitleMatchMode 3
    for r in ["va", "ho"]
        if hwnd := WinExist("DalSegnoArrow " r)
            try WinClose(hwnd)
    SetTimer(UpdateArrowIcons, -600)   ; restart them once they have exited
}

; --- detection -----------------------------------------------------------------

; Reads the current desktop from the registry. Returns 0 if the values are
; missing (can happen right after logon before Explorer has written them).
ReadDesktopStatus() {
    global VD_KEY
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
    guid := HexToGuid(cur)
    name := index ? DesktopRawName(index, guid) : ""
    return {index: index, count: count, name: name, guid: guid}
}

; RegRead returns REG_BINARY as a hex string in byte order; the registry's
; Desktops keys use GUID string form where Data1-Data3 are little-endian.
HexToGuid(hex) {
    if StrLen(hex) != 32
        return ""
    b := []
    loop 16
        b.Push(SubStr(hex, A_Index * 2 - 1, 2))
    return "{" b[4] b[3] b[2] b[1] "-" b[6] b[5] "-" b[8] b[7] "-" b[9] b[10] "-"
        . b[11] b[12] b[13] b[14] b[15] b[16] "}"
}

NameForIndex(i) {
    name := DesktopRawName(i)
    return name != "" ? i " · " name : Tr("desktop") " " i
}

; A desktop's own name, "" when it has none. From the dll when it is loaded:
; that is Explorer's live state, what Task View shows and what a rename
; changes at once. The registry value is Explorer's saved copy, which it
; writes back only now and then - a rename made through the dll does not
; reach it - so it is the fallback, not the source.
DesktopRawName(i, guid := "") {
    global g_dllLoaded, VD_KEY
    if g_dllLoaded {
        try {
            buf := Buffer(1024, 0)
            if (DllCall("VirtualDesktopAccessor\GetDesktopName", "int", i - 1, "ptr", buf, "uptr", 1024, "int") > 0)
                return StrGet(buf, "UTF-8")
        }
    }
    if (guid = "") {
        ids := RegRead(VD_KEY, "VirtualDesktopIDs", "")
        hex := SubStr(ids, (i - 1) * 32 + 1, 32)
        guid := StrLen(hex) = 32 ? HexToGuid(hex) : ""
    }
    return guid != "" ? RegRead(VD_KEY "\Desktops\" guid, "Name", "") : ""
}

; "1 · Klinik", "2 · Lab", ... for every desktop; empty when the registry has
; nothing (module off or Explorer not ready).
DesktopNames() {
    global g_modDesktops
    names := []
    if !g_modDesktops
        return names
    s := ReadDesktopStatus()
    if !s
        return names
    loop s.count
        names.Push(NameForIndex(A_Index))
    return names
}

PollDesktops() {
    global g_lastGuid, g_lastState, g_lastStatus, g_modDesktops
    if !g_modDesktops
        return
    s := ReadDesktopStatus()
    if !s
        return
    g_lastStatus := s
    state := s.guid "|" s.name "|" s.count
    if (state = g_lastState)
        return
    switched := g_lastGuid != "" && s.guid != g_lastGuid
    g_lastGuid := s.guid
    g_lastState := state
    UpdateTray(s)
    UpdateLabel()
    if switched
        ShowOsd(s)
}

; --- hotkeys ---------------------------------------------------------------------

ApplyDesktopHotkeys() {
    global configIni, g_desktopHotkeys, g_modDesktops, g_wheel
    for k in g_desktopHotkeys
        try Hotkey(k, "Off")
    g_desktopHotkeys := []
    HotIf(MouseOverTaskbar)
    Hotkey("WheelUp", WheelPrevious, (g_wheel && g_modDesktops) ? "On" : "Off")
    Hotkey("WheelDown", WheelNext, (g_wheel && g_modDesktops) ? "On" : "Off")
    HotIf()
    if !g_modDesktops
        return
    bad := ""
    simple := [
        ["MoveNext", "!#Right", MoveRelative.Bind(1, false)],
        ["MovePrevious", "!#Left", MoveRelative.Bind(-1, false)],
        ["MoveFollowNext", "^!#Right", MoveRelative.Bind(1, true)],
        ["MoveFollowPrevious", "^!#Left", MoveRelative.Bind(-1, true)],
        ["MoveMenu", "!#Down", ShowMenuForActive],
        ["ShowName", "", ShowOsdHotkey],
    ]
    for b in simple {
        key := IniRead(configIni, "Hotkeys", b[1], b[2])
        if key != ""
            RegisterDesktopHotkey(b[1], key, b[3], &bad)
    }
    prefixes := [
        ["SwitchToPrefix", "^#", (n) => SwitchTo.Bind(n)],
        ["MoveToPrefix", "!#", (n) => MoveAbsolute.Bind(n, false)],
        ["MoveFollowToPrefix", "^!#", (n) => MoveAbsolute.Bind(n, true)],
    ]
    for p in prefixes {
        pre := IniRead(configIni, "Hotkeys", p[1], p[2])
        if pre = ""
            continue
        loop 9
            RegisterDesktopHotkey(p[1], pre . A_Index, p[3](A_Index), &bad)
    }
    if bad != "" {
        TrayTip(Tr("invalidHotkeys") "`n" bad, Tr("appTitle"), "Iconx")
        try FileAppend(FormatTime() "  Invalid hotkeys: " StrReplace(bad, "`n", " / ") "`n"
            , ErrorLogPath(), "UTF-8")
    }
}

RegisterDesktopHotkey(name, key, handler, &bad) {
    global g_desktopHotkeys
    try {
        Hotkey(key, handler, "On")
        g_desktopHotkeys.Push(key)
    } catch {
        bad .= name ": " key "`n"
    }
}

; --- actions ---------------------------------------------------------------------

; Receiver for DESKPILOT_CMD / DALSEGNO_CMD (see the file header).
IpcCommand(wParam, lParam, msg, hwnd) {
    switch wParam {
        case 1: SwitchTo(lParam)
        case 2: MoveAbsolute(lParam, false)
        case 3: MoveAbsolute(lParam, true)
        case 4: ShowOsd()
        case 5: ReloadConfig()
        case 6: SwitchRelative(1)
        case 7: SwitchRelative(-1)
        case 8: OpenUi()
        case 9: SetTimer(TmSaveOrRule.Bind(lParam), -1)   ; the save/rule dialog for window lParam
        case 11: SetTimer(RenameDesktopPrompt.Bind(lParam), -1)   ; the rename prompt for desktop lParam (1-based)
        case 10:   ; flags for window lParam: 1 = manageable, +2 = saved position, +4 = matches a rule
            key := ""
            try key := KeyFor(lParam)
            if (key = "") {
                info := ""
                try info := BaseInfo(lParam)
                return (info != "") ? 1 : 0
            }
            return 1 | (LoadPos(key) != "" ? 2 : 0) | (SubStr(key, 1, 5) = "rule:" ? 4 : 0)
        case 100:
            try FileDelete(A_ScriptDir "\ping.txt")
            try FileAppend("pong " lParam "`n", A_ScriptDir "\ping.txt", "UTF-8")
    }
    return 1
}

ShowOsdHotkey(*) {
    ShowOsd()
}

SwitchTo(target, *) {
    s := ReadDesktopStatus()
    if !s || s.index = 0 || target = s.index || target < 1 || target > s.count
        return
    SwitchDesktop(target, s.index)
}

SwitchRelative(direction) {
    s := ReadDesktopStatus()
    if s && s.index
        SwitchTo(s.index + direction)
}

WheelPrevious(*) {
    SwitchRelative(-1)
}

WheelNext(*) {
    SwitchRelative(1)
}

MouseOverTaskbar(*) {
    MouseGetPos , , &over
    try return WinGetClass(over) ~= "^(Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
    catch
        return false
}

; Starts/stops the two arrow icon processes (DalSegnoArrow.ahk) according to
; the config. The helpers tag their hidden windows "DalSegnoArrow va/ho".
UpdateArrowIcons() {
    global g_arrowIcons, g_modDesktops
    DetectHiddenWindows true
    SetTitleMatchMode 3
    want := g_arrowIcons && g_modDesktops
    for r in ["va", "ho"] {
        hwnd := WinExist("DalSegnoArrow " r)
        if (want && !hwnd) {
            if A_IsCompiled {
                try Run('"' A_ScriptDir '\DalSegnoArrow.exe" ' r)
            } else {
                try Run('"' A_AhkPath '" "' A_ScriptDir '\DalSegnoArrow.ahk" ' r)
            }
        } else if (!want && hwnd) {
            try WinClose(hwnd)
        }
    }
}

MoveRelative(direction, follow, *) {
    s := ReadDesktopStatus()
    if s && s.index != 0
        MoveActiveWindow(s.index + direction, follow, s)
}

MoveAbsolute(target, follow, *) {
    s := ReadDesktopStatus()
    if s && s.index != 0
        MoveActiveWindow(target, follow, s)
}

MoveActiveWindow(target, follow, s) {
    hwnd := WinExist("A")
    if !hwnd
        return
    try cls := WinGetClass(hwnd)
    catch
        return
    if cls ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
        return
    MoveWindowToDesktop(hwnd, target, follow, s)
}

MoveWindowToDesktop(hwnd, target, follow, s := 0) {
    global g_dllLoaded
    if !IsObject(s)
        s := ReadDesktopStatus()
    if (!s || s.index = 0 || target < 1 || target > s.count || target = s.index)
        return
    if !g_dllLoaded {
        ShowOsdText(Tr("dllMissing"))
        return
    }
    if !DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber"
        , "ptr", hwnd, "int", target - 1, "int") {
        ShowOsdText(Tr("moveFailed"))
        return
    }
    if follow {
        SwitchDesktop(target, s.index)
        SetTimer(ActivateWindow.Bind(hwnd), -400)
    } else {
        ShowOsdText(Tr("windowTo") NameForIndex(target))
    }
}

; Switches desktop: directly via the dll, otherwise by sending Ctrl+Win+arrow
; one step at a time.
SwitchDesktop(target, from) {
    global g_dllLoaded
    if g_dllLoaded {
        DllCall("VirtualDesktopAccessor\GoToDesktopNumber", "int", target - 1)
        return
    }
    diff := target - from
    loop Abs(diff) {
        Send(diff > 0 ? "^#{Right}" : "^#{Left}")
        if A_Index < Abs(diff)
            Sleep(60)
    }
}

ActivateWindow(hwnd) {
    try WinActivate(hwnd)
}

; The desktop number (1-based) a window is on, "" when unknown / no dll.
DesktopOf(hwnd) {
    global g_dllLoaded
    if !g_dllLoaded
        return ""
    n := 0
    try n := DllCall("VirtualDesktopAccessor\GetWindowDesktopNumber", "ptr", hwnd, "int")
    return (n >= 0 && n < 99) ? n + 1 : ""
}

; Moves a window of ours to the current desktop before it is shown again -
; a hidden window reappears on the desktop it was last on otherwise.
DesktopBringHere(hwnd) {
    global g_dllLoaded, g_modDesktops
    if (!g_modDesktops || !g_dllLoaded)
        return
    s := ReadDesktopStatus()
    if (!s || !s.index)
        return
    nr := -1
    try nr := DllCall("VirtualDesktopAccessor\GetWindowDesktopNumber", "ptr", hwnd, "int")
    if (nr >= 0 && nr != s.index - 1)
        try DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber", "ptr", hwnd, "int", s.index - 1, "int")
}

; A rule with a desktop, applied to one window: moved if it is elsewhere,
; followed if the rule says so.
DesktopApplyToWindow(hwnd, desktop, follow) {
    global g_dllLoaded, g_modDesktops
    if (!g_modDesktops || !g_dllLoaded || !desktop)
        return
    nr := -1
    try nr := DllCall("VirtualDesktopAccessor\GetWindowDesktopNumber", "ptr", hwnd, "int")
    if (nr < 0 || nr = desktop - 1)
        return
    if (DllCall("VirtualDesktopAccessor\MoveWindowToDesktopNumber"
        , "ptr", hwnd, "int", desktop - 1, "int") && follow) {
        SwitchTo(desktop)
        SetTimer(ActivateWindow.Bind(hwnd), -400)
    }
}

; Called from the window scan for a window that is new (old title "") or
; whose title changed. The first active rule WITH a desktop that matches is
; applied - and only when the title CHANGED into matching: a window dragged
; back by hand stays where it was put. Exe-only rules act on new windows.
DesktopRuleSweep(hwnd, title, oldTitle) {
    global titleRules, g_dllLoaded
    if !g_dllLoaded
        return
    info := BaseInfo(hwnd)
    if (info = "")
        return
    for rule in titleRules {
        if (!rule.enabled || !rule.desktop)
            continue
        if !RuleMatches(rule, info)
            continue
        if (rule.pattern != "") {
            if (oldTitle != "" && RuleTitleMatches(rule, oldTitle))
                continue   ; matched before too - no new event
        } else if (oldTitle != "")
            continue       ; exe-only rules act on new windows only
        DesktopApplyToWindow(hwnd, rule.desktop, rule.follow)
        break
    }
}

; The system DPI and font metrics are captured at process start, so the
; name label and OSD render at the wrong size after connecting/disconnecting
; monitors with a different scale - a clean restart is the simplest correct
; fix. Debounced: docking fires a burst of WM_DISPLAYCHANGE events.
DisplayChangeGuard(*) {
    SetTimer(RestartAfterDisplayChange, -2500)
}

; Docked DisplayPort monitors renegotiate periodically, firing spurious
; WM_DISPLAYCHANGE without any real change - only restart when the layout
; actually differs from the one this instance started with.
RestartAfterDisplayChange() {
    global g_screenSnapshot
    if (ScreenSnapshot() = g_screenSnapshot)
        return
    Reload()
}

ScreenSnapshot() {
    s := MonitorGetCount() "|" A_ScreenWidth "x" A_ScreenHeight
    loop MonitorGetCount() {
        try {
            MonitorGet(A_Index, &l, &t, &r, &b)
            s .= "|" l "," t "," r "," b
        }
    }
    return s
}

; The desktop picker: a menu with all desktops.
ShowDesktopPicker() {
    global g_menuOpen
    if g_menuOpen {   ; a second click closes the open menu instead
        DllCall("EndMenu")
        return
    }
    s := ReadDesktopStatus()
    if (!s || s.index = 0)
        return
    m := Menu()
    loop s.count {
        n := A_Index
        ; the desktop you are already on cannot be switched to - clicking it
        ; renames it instead
        m.Add(NameForIndex(n), n = s.index ? RenameDesktopPrompt.Bind(n) : PickDesktop.Bind(n))
        if (n = s.index)
            m.Check(NameForIndex(n))
    }
    ; the click never activates us (tray icon / click-through label), so
    ; claim the foreground or the menu closes instantly
    TakeForeground()
    g_menuOpen := true
    m.Show()
    g_menuOpen := false
}

PickDesktop(n, *) {
    SwitchTo(n)
}

; Renames desktop n (1-based) after asking for the name - the current name
; is prefilled, an empty name goes back to Windows' default. The prompt
; opens on the monitor the mouse is on (the picker was just clicked there).
RenameDesktopPrompt(n, *) {
    global g_lastState
    s := ReadDesktopStatus()
    if (!s || n < 1 || n > s.count)
        return
    current := DesktopRawName(n)
    opt := "w420 h140"
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if (mx >= l && mx < r && my >= t && my < b) {
            opt .= " x" ((l + r) // 2 - 210) " y" ((t + b) // 2 - 70)
            break
        }
    }
    ib := InputBox(Format(Tr("renamePrompt"), n), Tr("renameTitle"), opt, current)
    if (ib.Result != "OK")
        return
    name := Trim(ib.Value)
    if (name = current)
        return
    if !SetDesktopName(n, name) {
        ShowOsdText(Tr("renameFailed"))
        return
    }
    g_lastState := ""   ; the label and tray pick the new name up on the next poll
    ShowOsdText(name != "" ? n " · " name : Tr("desktop") " " n)
}

; Through the dll when it is loaded: Explorer then shows the name everywhere
; at once. The dll must match the Windows build - the wrong build's call
; returns -1 (see VDA_DLL) and an old build has no SetDesktopName at all -
; and then the rename fails rather than half-happens. The registry value is
; Explorer's saved copy of the name: it does not write it back itself for a
; while after a rename through the dll, so it is written here too, and
; without the dll it is all there is to write (Task View then keeps the old
; name until Explorer restarts).
SetDesktopName(n, name) {
    global g_dllLoaded, VD_KEY
    if g_dllLoaded {
        try {
            buf := Buffer(StrPut(name, "UTF-8"), 0)
            StrPut(name, buf, "UTF-8")
            if (DllCall("VirtualDesktopAccessor\SetDesktopName", "int", n - 1, "ptr", buf, "int") != 1)
                return false
        } catch {
            return false
        }
    }
    try {
        ids := RegRead(VD_KEY, "VirtualDesktopIDs", "")
        guid := HexToGuid(SubStr(ids, (n - 1) * 32 + 1, 32))
        if (guid = "")
            return !!g_dllLoaded
        RegWrite(name, "REG_SZ", VD_KEY "\Desktops\" guid, "Name")
    }
    return true
}

; True when the cursor is inside the (visible) name label's rectangle - the
; label itself is click-through, so hit-testing never reports it.
MouseOverLabel(*) {
    global g_label
    try {
        if (!IsObject(g_label) || !DllCall("IsWindowVisible", "ptr", g_label.Hwnd))
            return false
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        WinGetPos(&bx, &by, &bw, &bh, g_label)
        return (mx >= bx && mx < bx + bw && my >= by && my < by + bh)
    } catch {
        return false
    }
}

LabelClick(*) {
    ShowDesktopPicker()
}

; Right-click on the label opens the GUI. Two separate buttons need no
; timing, so both gestures are immediate.
LabelRightClick(*) {
    TakeForeground()      ; the click-through label never activates us
    OpenUi()
}

; The desktops items of the window menu: move to / move and follow submenus,
; and the pin toggle. True when something was added.
DesktopMenuItems(m, win) {
    global g_dllLoaded
    s := ReadDesktopStatus()
    if (!s || s.index = 0)
        return false
    moveTo := Menu(), followTo := Menu()
    loop s.count {
        n := A_Index
        label := NameForIndex(n) (n = s.index ? Tr("current") : "")
        moveTo.Add(label, MenuMoveChoice.Bind(win, n, false))
        followTo.Add(label, MenuMoveChoice.Bind(win, n, true))
        if (n = s.index) {
            moveTo.Disable(label)
            followTo.Disable(label)
        }
    }
    m.Add(Tr("menuMoveTo"), moveTo)
    m.Add(Tr("menuMoveFollow"), followTo)
    if g_dllLoaded {
        m.Add(Tr("menuPin"), TogglePin.Bind(win))
        if IsPinned(win)
            m.Check(Tr("menuPin"))
    }
    return true
}

MenuMoveChoice(win, n, follow, *) {
    MoveWindowToDesktop(win, n, follow)
}

; Is this window pinned to every desktop? Guarded: an older dll may not
; export IsPinnedWindow at all.
IsPinned(win) {
    global g_dllLoaded
    if !g_dllLoaded
        return false
    r := 0
    try r := DllCall("VirtualDesktopAccessor\IsPinnedWindow", "ptr", win, "int")
    return r = 1
}

TogglePin(win, *) {
    global g_dllLoaded
    if (!g_dllLoaded || !WinExist(win))
        return
    try {
        if IsPinned(win)
            DllCall("VirtualDesktopAccessor\UnPinWindow", "ptr", win)
        else
            DllCall("VirtualDesktopAccessor\PinWindow", "ptr", win)
    }
}

; --- taskbar name label ----------------------------------------------------------

LabelGuard() {
    UpdateLabel()
}

; Shows the desktop name the way the clock shows time/date: bare text on the
; taskbar, just left of the icon area. Reading the bar, its icon area and
; placing the label all happen under per-monitor-v2 so the three agree; the
; context is restored on the way out.
UpdateLabel() {
    global g_modDesktops
    if !g_modDesktops
        return
    prevDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try
        UpdateLabelCore()
    finally {
        if prevDpi
            DllCall("SetThreadDpiAwarenessContext", "ptr", prevDpi, "ptr")
    }
}

UpdateLabelCore() {
    ; never touch the label while one of our menus is open: the timer fires
    ; inside the menu's modal loop, and Show/SetWindowPos dismisses the menu
    if g_menuOpen
        return
    ; the poll and guard timers can interrupt each other mid-rebuild -
    ; without a latch, Destroy() runs before g_label is repointed
    static busy := false
    if busy
        return
    busy := true
    try UpdateLabelInner()
    busy := false
}

UpdateLabelInner() {
    global g_label, g_labelText, g_lastStatus, g_nameInTray
    s := g_lastStatus
    if (!g_nameInTray || !IsObject(s)) {
        HideLabel()
        return
    }
    bar := WinExist("ahk_class Shell_TrayWnd")
    if !bar {
        HideLabel()
        return
    }
    try WinGetPos(&barX, &barY, &barW, &barH, bar)
    catch
        return
    if LabelShouldHide(barY) {
        HideLabel()
        return
    }
    try ControlGetPos(&iconX, , , , "TrayNotifyWnd1", bar)
    catch
        iconX := barW - 260   ; rough fallback if the control disappears
    light := RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        , "SystemUsesLightTheme", 0)
    line1 := s.name != "" ? s.name : Tr("desktop") " " s.index
    line2 := s.name != "" ? Tr("desktop") " " s.index " " Tr("of") " " s.count : ""
    ; The app buttons grow rightwards as windows are opened and eventually
    ; reach the strip we live in. Try the forms from richest to barest and
    ; take the first one whose left edge lands on free bar; only if even the
    ; counter collides does the label go away. MSTaskListWClass1 is not
    ; usable for this on Windows 11 - the buttons are XAML, so the honest
    ; probe is asking UI Automation what sits at a given point.
    margin := Round(12 * LabelDpi(bar) / 96)
    midY := barY + barH // 2
    forms := [[line1, line2]]
    if (line2 != "")
        forms.Push([line1 " " s.index "/" s.count, ""])
    forms.Push([s.index "/" s.count, ""])
    line1 := "", line2 := ""
    for f in forms {
        width := LabelWidth(f[1], f[2], bar)
        if !UiaButtonAt(barX + iconX - width - margin, midY) {
            line1 := f[1], line2 := f[2]
            break
        }
    }
    if (line1 = "") {
        HideLabel()
        return
    }
    content := line1 "|" line2 "|" light
    if (content != g_labelText || !IsObject(g_label)
        || !DllCall("IsWindow", "ptr", g_label.Hwnd)) {
        g_labelText := content
        if IsObject(g_label)
            try g_label.Destroy()
        scale := LabelDpi(bar) / 96
        keyColor := light ? "EEEEEE" : "202020"
        ; a topmost STAND-ALONE window: as a taskbar child the composition
        ; surface repainted over the label on every tray icon animation.
        ; Click-through (E0x20); clicks are caught by an LButton hook hotkey
        ; over the label's rect.
        b := Gui("-DPIScale -Caption +ToolWindow +AlwaysOnTop +E0x08000000 +E0x20"
            , "DalSegno desktop label")
        b.BackColor := keyColor
        b.MarginX := Round(10 * scale), b.MarginY := Round(3 * scale)
        b.SetFont("s9 q4 c" (light ? "1A1A1A" : "F5F5F5"), "Segoe UI Variable Display")
        b.Add("Text", "Center", line2 != "" ? line1 "`n" line2 : line1)
        b.Show("NoActivate Hide AutoSize")
        WinSetTransColor(keyColor, b)
        g_label := b
    }
    g_label.GetPos(, , &bw, &bh)
    g_label.Show("NoActivate x" (barX + iconX - bw - Round(12 * LabelDpi(bar) / 96))
        . " y" (barY + (barH - bh) // 2))
    ; clicking the taskbar raises it within the topmost band - re-assert
    DllCall("SetWindowPos", "ptr", g_label.Hwnd, "ptr", 0
        , "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)   ; TOP, NOMOVE|NOSIZE|NOACTIVATE
}

; Is a taskbar button sitting at this screen point? UIA_ButtonControlTypeId
; is 50000. Answers false on any failure: a missing answer must not be what
; makes the label disappear. Cached briefly.
UiaButtonAt(x, y) {
    static last := 0, lastKey := "", lastAnswer := false
    key := x "," y
    if (key = lastKey && A_TickCount - last < 1000)
        return lastAnswer
    answer := false
    try {
        typ := UiaTypeAt(x, y)
        answer := (typ = 50000)
    }
    last := A_TickCount, lastKey := key, lastAnswer := answer
    return answer
}

UiaTypeAt(x, y) {
    static uia := 0
    if !uia {
        DllCall("ole32\CoCreateInstance"
            , "ptr", GuidBuffer("{FF48DBA4-60EF-4201-AA87-54103EEF594E}")   ; CUIAutomation
            , "ptr", 0, "uint", 0x17
            , "ptr", GuidBuffer("{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
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

GuidBuffer(s) {
    buf := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", s, "ptr", buf, "hresult")
    return buf
}

; How wide the label would be with this content, measured by rendering it in
; a hidden throwaway Gui with the same font and margins. Cached.
LabelWidth(line1, line2, bar) {
    static cache := Map()
    scale := LabelDpi(bar) / 96
    key := line1 "|" line2 "|" scale
    if cache.Has(key)
        return cache[key]
    w := 0
    try {
        g := Gui("-DPIScale -Caption +ToolWindow +E0x08000000")
        g.MarginX := Round(10 * scale), g.MarginY := Round(3 * scale)
        g.SetFont("s9 q4", "Segoe UI Variable Display")
        g.Add("Text", "Center", line2 != "" ? line1 "`n" line2 : line1)
        g.Show("NoActivate Hide AutoSize")
        g.GetPos(, , &w)
        g.Destroy()
    }
    if (cache.Count > 40)
        cache.Clear()
    return cache[key] := w
}

; The taskbar's own DPI - what the label must be scaled by.
LabelDpi(bar) {
    dpi := 0
    try dpi := DllCall("GetDpiForWindow", "ptr", bar, "uint")
    return dpi ? dpi : A_ScreenDPI
}

; Hide when the taskbar is auto-hidden or a fullscreen window covers the
; monitor it sits on.
LabelShouldHide(barY) {
    bottom := A_ScreenHeight
    try {
        bar := WinExist("ahk_class Shell_TrayWnd")
        if bar {
            WinGetPos(&fx, &fy, &fw, &fh, bar)
            loop MonitorGetCount() {
                MonitorGet(A_Index, &ml, &mt, &mr, &mb)
                if (fx + fw // 2 >= ml && fx + fw // 2 < mr) {
                    bottom := mb
                    break
                }
            }
        }
    }
    if (barY + 8 > bottom)
        return true
    fg := WinExist("A")
    if !fg
        return false
    try {
        if WinGetClass(fg) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
            return false
        WinGetPos(&ax, &ay, &aw, &ah, fg)
        MonitorGet(MonitorGetPrimary(), &ml, &mt, &mr, &mb)
        return (ax <= ml && ay <= mt && ax + aw >= mr && ay + ah >= mb)
    } catch {
        return false
    }
}

HideLabel() {
    global g_label
    if IsObject(g_label)
        g_label.Hide()
}

; --- tray and OSD ----------------------------------------------------------------

UpdateTray(s) {
    global g_modDesktops
    if !g_modDesktops
        return
    file := s.index = 0 ? "d_unknown.ico" : s.index > 9 ? "d_more.ico" : "d" s.index ".ico"
    path := A_ScriptDir "\icons\" file
    if FileExist(path)
        TraySetIcon(path, , 1)
    A_IconTip := OsdText(s) " (" Tr("of") " " s.count ")"
}

OsdText(s) {
    return s.name != "" ? s.index " · " s.name : Tr("desktop") " " s.index
}

ShowOsd(s := 0) {
    if !s
        s := ReadDesktopStatus()
    if !s
        return
    ShowOsdText(OsdText(s))
}

; The effective DPI of the monitor under a point.
ScreenDpiAtPoint(x, y) {
    try {
        hMon := DllCall("MonitorFromPoint", "int64", (x & 0xFFFFFFFF) | (y << 32)
            , "uint", 2, "ptr")
        if hMon {
            DllCall("shcore\GetDpiForMonitor", "ptr", hMon, "int", 0
                , "uint*", &dx := 0, "uint*", &dy := 0, "hresult")
            if dx
                return dx
        }
    }
    return A_ScreenDPI
}

; The overlay is placed on whichever monitor the mouse is on; the whole
; placement runs per-monitor-v2 so the rectangles line up, the Gui is
; -DPIScale so AHK adds no scaling of its own, and the font and margins are
; scaled by the TARGET monitor's DPI.
ShowOsdText(text) {
    prevDpi := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
    try
        ShowOsdTextCore(text)
    finally {
        if prevDpi
            DllCall("SetThreadDpiAwarenessContext", "ptr", prevDpi, "ptr")
    }
}

ShowOsdTextCore(text) {
    global g_osd
    if IsObject(g_osd) {
        g_osd.Destroy()
        g_osd := 0
    }
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    screen := 1
    loop MonitorGetCount() {
        MonitorGet(A_Index, &l, &t, &r, &b)
        if (mx >= l && mx < r && my >= t && my < b) {
            screen := A_Index
            break
        }
    }
    scale := ScreenDpiAtPoint(mx, my) / 96
    osd := Gui("-DPIScale +AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x20")
    osd.BackColor := "1E293B"
    osd.MarginX := Round(34 * scale), osd.MarginY := Round(18 * scale)
    osd.SetFont("s" Round(20 * scale) " w700 cWhite", "Segoe UI")
    osd.Add("Text", "Center", text)
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", osd.Hwnd
        , "uint", 33, "uint*", 2, "uint", 4)   ; DWMWA_WINDOW_CORNER_PREFERENCE = ROUND
    MonitorGetWorkArea(screen, &l, &t, &r, &b)
    osd.Show("NoActivate Hide AutoSize")
    osd.GetPos(, , &w, &h)
    osd.Show("NoActivate x" (l + (r - l - w) // 2) " y" (t + Round((b - t) * 0.10)))
    WinSetTransparent(242, osd)
    g_osd := osd
    SetTimer(HideOsd, -1500)
}

HideOsd() {
    global g_osd
    if IsObject(g_osd) {
        g_osd.Destroy()
        g_osd := 0
    }
}
