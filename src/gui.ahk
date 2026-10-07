; =============================================================================
;  DalSegno Window Manager - the WebView2 GUI
;
;  One state object is pushed into window.receiveState; the page posts
;  {action:…} messages back. Created lazily on first open; closing only
;  hides it, so reopening is instant - for ten minutes. Then the WebView2
;  is let go (UiReleaseCheck): its half-dozen browser processes hold some
;  250 MB, which on a full machine is paging.
; =============================================================================

g_uiWin := 0, g_uiCtrl := 0, g_uiCore := 0, g_uiReady := false
UI_RELEASE_MS := 600000
SetTimer(UiReleaseCheck, 30000)

; Hidden for UI_RELEASE_MS: the controller is closed and the window
; destroyed; the next OpenUi creates both again (a second or so).
UiReleaseCheck() {
    global g_uiWin, g_uiCtrl, g_uiCore, g_uiReady
    static lastShown := A_TickCount
    if (!g_uiWin)
        return
    if DllCall("IsWindowVisible", "ptr", g_uiWin.Hwnd) {
        lastShown := A_TickCount
        return
    }
    if (A_TickCount - lastShown < UI_RELEASE_MS)
        return
    g_uiReady := false
    try g_uiCtrl.Close()
    g_uiCore := 0, g_uiCtrl := 0
    try g_uiWin.Destroy()
    g_uiWin := 0
    Trace("ui: released after " UI_RELEASE_MS // 60000 " min hidden")
}

OpenUi(*) {
    global g_uiWin, g_uiCtrl, g_uiCore
    if !g_uiWin {
        DllCall("shell32\SetCurrentProcessExplicitAppUserModelID", "str", "DalSegno.Application.2")
        g_uiWin := Gui("+Resize +MinSize700x460", Tr("appTitle"))
        g_uiWin.OnEvent("Close", (*) => (SaveUiGeometry(), g_uiWin.Hide()))
        g_uiWin.OnEvent("Size", UiResize)
        g_uiWin.Show(ReadUiGeometry())
        FitUiToScreen()
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g_uiWin.hwnd, "uint", 20, "int*", 1, "uint", 4)
        ; WM_SETICON covers the title bar, but with an explicit AppUserModelID
        ; the taskbar GROUP icon falls back to the window class icon - so the
        ; class icon is replaced too
        try {
            ico16 := LoadPicture(A_ScriptDir "\app.ico", "Icon1 w16 h16", &_it1)
            ico32 := LoadPicture(A_ScriptDir "\app.ico", "Icon1 w32 h32", &_it2)
            SendMessage(0x80, 0, ico16, , g_uiWin.hwnd)
            SendMessage(0x80, 1, ico32, , g_uiWin.hwnd)
            DllCall("SetClassLongPtr", "ptr", g_uiWin.hwnd, "int", -14, "ptr", ico32)   ; GCLP_HICON
            DllCall("SetClassLongPtr", "ptr", g_uiWin.hwnd, "int", -34, "ptr", ico16)   ; GCLP_HICONSM
        }
        try {
            ; explicit user data folder: the default lands next to the host
            ; exe and is shared with every other AHK script running WebView2
            dataDir := EnvGet("LOCALAPPDATA") "\DalSegno\WebView2"
            try DirCreate(dataDir)
            g_uiCtrl := WebView2.create(g_uiWin.hwnd, , 0, dataDir, "", 0
                , A_ScriptDir "\lib\WebView2Loader.dll")
            g_uiCtrl.Fill()
            g_uiCore := g_uiCtrl.CoreWebView2
            g_uiCore.add_WebMessageReceived(UiMessage)
            g_uiCore.Navigate("file:///" StrReplace(A_ScriptDir "\ui\index.html", "\", "/"))
        } catch {
            g_uiWin.Destroy()
            g_uiWin := 0, g_uiCtrl := 0, g_uiCore := 0
            Notify(Tr("uiFail"), Tr("appTitle"))
            return
        }
    } else {
        ; a hidden window comes back on the desktop it was last on; the user
        ; expects it where they are
        DesktopBringHere(g_uiWin.Hwnd)
        g_uiWin.Show()
        FitUiToScreen()
        PushStateSoon()
    }
}

; The window geometry is remembered between sessions, but always clamped to
; the work area of the monitor it lands on.
ReadUiGeometry() {
    global configIni
    w := 1000, h := 660
    try {
        w := Integer(IniRead(configIni, "Window", "W", "1000"))
        h := Integer(IniRead(configIni, "Window", "H", "660"))
    }
    x := IniRead(configIni, "Window", "X", "")
    y := IniRead(configIni, "Window", "Y", "")
    opt := "w" Max(700, w) " h" Max(460, h)
    if (x != "" && y != "")
        opt := "x" x " y" y " " opt
    return opt
}

SaveUiGeometry() {
    global g_uiWin, configIni
    if !g_uiWin
        return
    try {
        if (WinGetMinMax(g_uiWin.hwnd) != 0)   ; never store a max/minimized rect
            return
        ; position from the window rect, size from the CLIENT rect:
        ; Gui.Show("w… h…") sizes the client area
        WinGetPos(&x, &y, , , g_uiWin.hwnd)
        WinGetClientPos( , , &w, &h, g_uiWin.hwnd)
        IniWrite(x, configIni, "Window", "X")
        IniWrite(y, configIni, "Window", "Y")
        IniWrite(w, configIni, "Window", "W")
        IniWrite(h, configIni, "Window", "H")
    }
}

FitUiToScreen() {
    global g_uiWin
    if !g_uiWin
        return
    try {
        if (WinGetMinMax(g_uiWin.hwnd) != 0)
            return
        WinGetPos(&x, &y, &w, &h, g_uiWin.hwnd)
        MonitorGetWorkArea(MonitorFromWindow(g_uiWin.hwnd), &wl, &wt, &wr, &wb)
        w := Min(w, wr - wl), h := Min(h, wb - wt)
        x := Min(Max(x, wl), wr - w), y := Min(Max(y, wt), wb - h)
        WinMove(x, y, w, h, g_uiWin.hwnd)
    }
}

UiResize(guiObj, minMax, w, h) {
    global g_uiCtrl
    if (minMax != -1 && IsObject(g_uiCtrl))
        try g_uiCtrl.Fill()
}

UiSend(script) {
    global g_uiReady, g_uiCore
    if (!g_uiReady || !IsObject(g_uiCore))
        return
    try g_uiCore.ExecuteScriptAsync(script)
    catch
        g_uiReady := false
}

UiMessage(sender, args) {
    global g_uiReady
    try msg := JSON.Load(args.WebMessageAsJson)
    catch
        return
    if (!(msg is Map) || !msg.Has("action"))
        return
    switch msg["action"] {
        case "ready":
            g_uiReady := true
            PushState()
        case "refresh":
            PushState()
        case "toggle":
            UiToggle(msg["name"], msg["value"])
        case "setOption":
            UiSetOption(msg["section"], msg["name"], msg["value"])
        case "setModule":
            UiSetModule(msg["name"], msg["value"])
        case "applyAll":
            ApplyAll()
            PushState()
        case "saveAll":
            SaveAll()
            PushState()
        case "forget":
            UiForget(msg["section"])
        case "forgetMany":
            UiForgetMany(msg["sections"])
        case "forgetKey":
            UiForgetKey(msg["key"])
        case "moveKey":
            UiMoveKey(msg["key"])
        case "saveWin":
            UiSaveWin(msg["hwnd"])
        case "moveWin":
            UiMoveWin(msg["hwnd"])
        case "moveWinDesktop":
            MoveWindowToDesktop(Integer(msg["hwnd"]), Integer(msg["desktop"]), false)
            PushStateSoon()
        case "ruleFromWin":
            SetTimer(TmSaveOrRule.Bind(Integer(msg["hwnd"])), -1)
        case "setRule":
            UiSetRule(msg)
        case "addRule":
            UiAddRule(msg)
        case "promoteProgram":
            UiPromoteProgram(msg)
        case "deleteRule":
            UiDeleteRule(msg["alias"])
        case "moveRule":
            UiMoveRule(msg["alias"], Integer(msg["dir"]))
        case "setManaged":
            UiSetManaged(msg)
        case "setLang":
            SetLanguage(msg["lang"])
        case "setHotkey":
            UiSetHotkey(msg["name"], msg["key"])
        case "openPositions":
            OpenPositionsFile()
        case "openConfig":
            OpenConfigFile()
        case "reloadConfig":
            ReloadConfig()
    }
}

; Defers and coalesces updates: several changes in a row end up as a single
; push, and the slow ini reads stay out of event handlers that must be quick.
PushStateSoon() {
    global g_uiReady
    if g_uiReady
        SetTimer(PushState, -100)
}

PushState() {
    global g_uiReady, moveEnabled, autoSaveEnabled, notifyEnabled, rulesOnly, g_keepOnScreen, g_lang
    global g_autoSaveModOnly, g_modifier, g_menuButton, g_menuOn, g_menuWhole, g_menuExclude, g_hk
    global titleRules, ignoreExe, ignoreTitles, rulesOnlyExe, configIni
    global g_modPositions, g_modDesktops, g_nameInTray, g_wheel, g_arrowIcons, g_dllLoaded
    if !g_uiReady
        return
    rules := []
    for r in titleRules
        rules.Push(Map("alias", r.alias, "pattern", r.pattern, "regex", r.regex ? 1 : 0
            , "exe", r.exe, "exeRegex", r.exeRegex ? 1 : 0, "cls", RuleClass(r)
            , "computers", RuleComputers(r)
            , "desktop", r.desktop, "follow", r.follow ? 1 : 0
            , "enabled", r.enabled ? 1 : 0))
    dhk := Map()
    for namn in ["MoveNext", "MovePrevious", "MoveFollowNext", "MoveFollowPrevious"
        , "MoveMenu", "ShowName", "SwitchToPrefix", "MoveToPrefix", "MoveFollowToPrefix"]
        dhk[namn] := IniRead(configIni, "Hotkeys", namn, "")
    s := g_modDesktops ? ReadDesktopStatus() : 0
    state := Map("modules", Map("positions", g_modPositions ? 1 : 0, "desktops", g_modDesktops ? 1 : 0)
        , "settings", Map("move", moveEnabled ? 1 : 0, "autosave", autoSaveEnabled ? 1 : 0
            , "notify", notifyEnabled ? 1 : 0, "rulesOnly", rulesOnly ? 1 : 0
            , "keepOnScreen", g_keepOnScreen != "off" ? 1 : 0, "lang", g_lang
            , "modOnly", g_autoSaveModOnly ? 1 : 0, "modifier", g_modifier
            , "menuButton", g_menuButton, "menuOn", g_menuOn ? 1 : 0
            , "menuWhole", g_menuWhole ? 1 : 0, "menuExclude", g_menuExclude
            , "nameInTray", g_nameInTray ? 1 : 0, "wheel", g_wheel ? 1 : 0
            , "arrowIcons", g_arrowIcons ? 1 : 0, "dll", g_dllLoaded ? 1 : 0
            , "hotkeys", g_hk, "desktopHotkeys", dhk)
        , "desktops", Map("count", s ? s.count : 0, "index", s ? s.index : 0, "names", DesktopNames())
        , "currentSetup", SetupKey()
        , "computer", A_ComputerName
        , "positions", ListPositions()
        , "rules", rules
        , "ignoreExe", ignoreExe
        , "ignoreTitles", ignoreTitles
        , "rulesOnlyExe", rulesOnlyExe
        , "windows", ListWindows())
    UiSend("window.receiveState(" JSON.Dump(state) ")")
}

; Every open window DalSegno may touch: the managed ones, and those of
; rules-only programs that match no rule yet (managed = 0).
;
; Two filters keep the list to what can be acted on. A window on no virtual
; desktop (Task Switching, tray overflow, every hidden helper a program keeps
; around - titled top-level windows all) cannot be moved to one and is not a
; window the user sees; only skipped when the desktop number is trustworthy,
; i.e. the dll is loaded. And rows identical in program, title and desktop
; collapse into one with a count: their identity is the same, so saving from
; any of them saves the same thing.
ListWindows() {
    global g_modDesktops, g_dllLoaded
    global g_uiWin
    list := []
    seen := Map()
    for hwnd in WinGetList() {
        ; our own window is listed, greyed out: rules never apply to it (a
        ; settings window that walks off to another desktop while you edit
        ; the rules that move it is its own trap), and it needs no position
        if (IsObject(g_uiWin) && hwnd = g_uiWin.Hwnd) {
            list.Push(Map("hwnd", hwnd + 0, "exe", A_ScriptName, "title", Tr("appTitle")
                , "rule", "", "managed", 0, "own", 1, "n", 1
                , "desktop", g_modDesktops ? DesktopOf(hwnd) : "", "saved", 0))
            continue
        }
        ; windows parked on other desktops are cloaked but real - listed, so
        ; they can be brought here; ghosts on no desktop are dropped below
        info := BaseInfo(hwnd, g_modDesktops && g_dllLoaded)
        if (info = "")
            continue
        desktop := g_modDesktops ? DesktopOf(hwnd) : ""
        if (g_modDesktops && g_dllLoaded && desktop = "")
            continue
        dup := info.exe "|" info.title "|" desktop
        if seen.Has(dup) {
            seen[dup]["n"] := seen[dup]["n"] + 1
            continue
        }
        key := KeyForInfo(info)
        ; the window's rectangle as it is now: the list shows it for windows
        ; no row covers, so the user sees what a rule would save
        x := "", y := "", w := "", h := ""
        try WinGetPos(&x, &y, &w, &h, hwnd)
        row := Map("hwnd", hwnd + 0, "exe", info.exe, "title", SubStr(info.title, 1, 80)
            , "key", key
            , "rule", SubStr(key, 1, 5) = "rule:" ? SubStr(key, 6) : ""
            , "managed", key != "" ? 1 : 0
            , "desktop", desktop, "n", 1
            , "x", x, "y", y, "w", w, "h", h
            , "saved", key != "" && LoadPos(key) != "" ? 1 : 0)
        seen[dup] := row
        list.Push(row)
    }
    return list
}

UiToggle(name, value) {
    global moveEnabled, autoSaveEnabled, notifyEnabled, g_autoSaveModOnly, g_keepOnScreen, configIni
    v := value ? true : false
    switch name {
        case "move":
            if (moveEnabled != v)
                ToggleMove()
        case "autosave":
            if (autoSaveEnabled != v)
                ToggleAutoSave()
        case "modOnly":
            if (g_autoSaveModOnly != v) {
                g_autoSaveModOnly := v
                IniWrite(v ? 1 : 0, configIni, "Positions", "AutoSaveModifierOnly")
                BuildTrayMenu()
            }
        case "notify":
            if (notifyEnabled != v)
                ToggleToasts()
        case "keepOnScreen":
            if ((g_keepOnScreen != "off") != v) {
                IniWrite(v ? "office" : "off", configIni, "Positions", "KeepOnScreen")
                LoadConfig()
            }
    }
    PushState()
}

; A plain setting in a config section, written and reloaded.
UiSetOption(section, name, value) {
    global configIni
    static allowed := Map("Menu", "Modifier,Button,Enabled,WholeWindow,Exclude"
        , "Desktops", "NameInTray,Wheel,ArrowIcons")
    if (!allowed.Has(section) || !InStr("," allowed[section] ",", "," name ","))
        return
    IniWrite(value, configIni, section, name)
    LoadConfig()
    BuildTrayMenu()
    PushState()
}

UiSetModule(name, value) {
    global configIni
    if (name != "Positions" && name != "Desktops")
        return
    IniWrite(value ? 1 : 0, configIni, "Modules", name)
    LoadConfig()
    BuildTrayMenu()
    if (name = "Desktops")
        DesktopsModuleToggled()
    PushState()
}

; A hotkey edited in the GUI: the position hotkeys are validated here (the
; name must be a known action, the key must parse, no duplicate); the
; desktop hotkeys are written and validated by ApplyDesktopHotkeys.
UiSetHotkey(name, key) {
    global g_hk, configIni
    key := Trim(key)
    if g_hk.Has(name) {
        if (key != "") {
            for other, k in g_hk
                if (other != name && k != "" && StrLower(k) = StrLower(key)) {
                    Notify(Tr("dupHotkey") " " key, Tr("appTitle"))
                    PushState()
                    return
                }
            try {
                HotIf(ModifierHeld)
                Hotkey("*" key, (*) => 0, "Off")   ; syntax probe, never enabled
                HotIf()
            } catch {
                HotIf()
                Notify(Tr("badHotkey") " " key, Tr("appTitle"))
                PushState()
                return
            }
        }
        g_hk[name] := key
        IniWrite(key, configIni, "Hotkeys", name)
        ApplyActionHotkeys()
        BuildTrayMenu()
    } else {
        IniWrite(key, configIni, "Hotkeys", name)
        ApplyDesktopHotkeys()
    }
    PushState()
}

UiForget(section) {
    global posIni
    if !RegExMatch(section, "^K[0-9A-F]{8}_")   ; never touch [General]/[Window]
        return
    try IniDelete(posIni, section)
    PushState()
}

; Every position saved under the key, in every monitor setup - what
; "Remove" does to a program row (a rule row's Remove is DeleteRule).
UiForgetKey(key) {
    global posIni
    key := Trim(key)
    if (key = "" || SubStr(key, 1, 5) = "rule:" && RuleByAlias(SubStr(key, 6)) != "")
        return   ; a live rule is removed through deleteRule, positions included
    for p in ListPositions()
        if (p["key"] = key)
            try IniDelete(posIni, p["section"])
    PushState()
}

UiForgetMany(sections) {
    global posIni
    for sec in sections {
        if !RegExMatch(sec, "^K[0-9A-F]{8}_")
            continue
        try IniDelete(posIni, sec)
    }
    PushState()
}

; Every open window the row applies to is moved - a rule such as
; "Bildfönster.*" can match several at once, not just the topmost one.
UiMoveKey(key) {
    moved := 0
    for hwnd in WinGetList() {
        if (KeyFor(hwnd) = key) {
            MoveToSaved(hwnd, key)
            moved++
        }
    }
    if moved
        PushState()
    else
        Notify(Tr("noMatch"), Tr("appTitle"))
}

UiSaveWin(hwnd) {
    global winInfo
    hwnd := Integer(hwnd)
    key := KeyFor(hwnd)
    if (key = "") {
        Notify(Tr("cannotHandleWin"), Tr("appTitle"))
        return
    }
    if SavePos(key, hwnd) {
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        PushState()
    } else
        Notify(SaveErrorText(), Tr("appTitle"))
}

UiMoveWin(hwnd) {
    global winInfo
    hwnd := Integer(hwnd)
    key := KeyFor(hwnd)
    if (key != "" && MoveToSaved(hwnd, key)) {
        if winInfo.Has(hwnd)
            winInfo[hwnd].done := true
        PushState()
    }
}

; The list edits one rule at a time and saves at once - no dirty state and no
; Save button. The alias is the ini key and names the saved positions, so it
; is never edited here.
UiSetRule(msg) {
    alias := Trim(msg["alias"])
    r := RuleByAlias(alias)
    if (r = "")
        return
    if msg.Has("pattern")
        r.pattern := Trim(msg["pattern"])
    if msg.Has("regex")
        r.regex := msg["regex"] ? true : false
    if msg.Has("exe") {
        exe := Trim(msg["exe"])
        r.exeRegex := SubStr(exe, 1, 3) = "re:"
        r.exe := r.exeRegex ? SubStr(exe, 4) : exe
    }
    if msg.Has("computers")
        r.computers := RegExReplace(Trim(msg["computers"]), "\s*,\s*", ",")
    if msg.Has("desktop")
        r.desktop := Integer(msg["desktop"])
    if msg.Has("follow")
        r.follow := msg["follow"] ? true : false
    if msg.Has("enabled")
        r.enabled := msg["enabled"] ? true : false
    if (r.pattern = "" && r.exe = "")
        return   ; a rule needs a text or a program - keep the old line
    WriteRule(r)
    LoadConfig()
    PruneEmptyRules()
    PushState()
}

UiAddRule(msg) {
    pattern := Trim(msg.Has("pattern") ? msg["pattern"] : "")
    exe := Trim(msg.Has("exe") ? msg["exe"] : "")
    if (pattern = "" && exe = "")
        return
    exeRegex := SubStr(exe, 1, 3) = "re:"
    ; a rule made here is for this computer unless the field says otherwise
    computers := msg.Has("computers") ? RegExReplace(Trim(msg["computers"]), "\s*,\s*", ",") : A_ComputerName
    WriteRule({ alias: SuggestAlias(pattern, exe), pattern: pattern
        , regex: msg.Has("regex") && msg["regex"] ? true : false
        , exe: exeRegex ? SubStr(exe, 4) : exe, exeRegex: exeRegex, cls: "", computers: computers
        , desktop: msg.Has("desktop") ? Integer(msg["desktop"]) : 0
        , follow: msg.Has("follow") && msg["follow"] ? true : false, enabled: true })
    LoadConfig()
    PushState()
}

; A program row given a desktop or switched off in the list: it becomes a
; rule for the program and window class, positions included (PromoteProgram).
UiPromoteProgram(msg) {
    key := Trim(msg["key"])
    if (key = "" || SubStr(key, 1, 5) = "rule:")
        return
    PromoteProgram(key, msg.Has("desktop") ? Integer(msg["desktop"]) : 0
        , msg.Has("follow") && msg["follow"] ? true : false
        , msg.Has("enabled") && !msg["enabled"] ? false : true)
    LoadConfig()
    PushState()
}

UiDeleteRule(alias) {
    alias := Trim(alias)
    if (alias = "")
        return
    DeleteRule(alias)
    LoadConfig()
    PushState()
}

; Moves a rule up (-1) or down (+1) in the order. First match wins, so the
; order is part of the rule set.
UiMoveRule(alias, dir) {
    global titleRules
    idx := 0
    for i, r in titleRules
        if (r.alias = alias)
            idx := i
    if (!idx || idx + dir < 1 || idx + dir > titleRules.Length)
        return
    r := titleRules.RemoveAt(idx)
    titleRules.InsertAt(idx + dir, r)
    WriteRulesInOrder(titleRules)
    LoadConfig()
    PushState()
}

; The "which windows are managed" settings, rewritten as a whole whenever one
; of them changes on the Settings tab.
UiSetManaged(msg) {
    global configIni
    static sections := Map("IgnoreExe", "ignoreExe", "IgnoreTitles", "ignoreTitles"
        , "RulesOnlyExe", "rulesOnlyExe")
    for sec, field in sections {
        try IniDelete(configIni, sec)
        if !msg.Has(field)
            continue
        n := 0
        for v in msg[field]
            if (Trim(v) != "")
                IniWrite(Trim(v), configIni, sec, ++n)
    }
    if msg.Has("rulesOnly")
        IniWrite(msg["rulesOnly"] ? 1 : 0, configIni, "Positions", "RulesOnly")
    LoadConfig()
    PushState()
}
