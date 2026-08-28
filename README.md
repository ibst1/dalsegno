# DalSegno Window Keeper

*Dal segno (𝄋) — "from the sign": go back to the marked place. That is what your
windows do: move a window once, and every window like it returns to that spot.*

Drag a window where you want it and drop it — the position is saved
automatically. The next time a window with the same identity opens, DalSegno
moves it right back there. Works with every program.

Built for (but not limited to) applications that keep opening popup windows in
the wrong place, such as LabVantage LIMS.

## How it works

- **Saving** hooks the Windows event `EVENT_SYSTEM_MOVESIZEEND`, which fires
  only when *you* finish moving or resizing a window — never when the script
  moves one. So the script's own moves can never overwrite your saved
  positions, and no polling heuristics are needed.
- **Restoring** scans for new windows about once a second. A new window whose
  identity has a saved position is moved there (twice, so the size sticks when
  crossing monitors with different scaling). Windows that were already open
  when the script started are left alone.
- **Identity** is `program + window class + exact title` by default. **Title
  rules** make all windows whose title contains a given text (or matches a
  regex) share one identity regardless of program — needed for windows with
  varying titles (URLs, record ids).
- **Per monitor setup and computer**: positions are keyed by monitor count +
  virtual desktop width + computer name, so laptop/docked layouts and
  different machines never overwrite each other. On docking, open windows
  snap to the saved layout for the new setup.
- New windows get a 10-second grace period to receive their real title
  (browser popups often retitle shortly after opening).
- If several windows share one identity, nothing is auto-saved until only one
  remains (you can still save deliberately with § + S).
- Minimized and maximized windows are never saved or restored.

## GUI

Left-click the tray icon (or press § + D). Three tabs:

- **Saved positions** — every saved position per monitor setup, with
  *Move now* and *Forget* per row.
- **Open windows** — the manageable windows right now; save or restore any of
  them from here.
- **Rules** — edit title rules, the ignore lists and *rules only* mode.

Interface language (English/Svenska) is selectable in the top bar and in the
tray menu. The GUI is a WebView2 page (`ui/`), same architecture as Encore
and Expanto.

## Hotkeys

`§` is the key in the top-left corner on Nordic keyboards.

| Hotkey | Action |
| --- | --- |
| § + D | open the DalSegno window |
| § + S | save the active window's position |
| § + Backspace | forget the active window's saved position (current setup) |
| § + Home | move every open window to its saved position |
| § + F10 | toggle automatic moving |
| § + F5 | restart the script |

## Files

| File | Purpose |
| --- | --- |
| `DalSegno.ahk` | the script (AutoHotkey v2) |
| `DalSegno positions.ini` | saved positions + on/off state + language (UTF-16) |
| `DalSegno config.ini` | title rules, ignore lists, rules-only mode (UTF-16) |
| `ui/` | the WebView2 GUI |
| `lib/`, `ComVar.ahk`, `Promise.ahk` | WebView2 + JSON libraries |
| `app.ico` | the segno icon |

The config file can be edited by hand (then pick *Reload settings* in the tray
menu) or from the GUI's Rules tab. Note that saving rules from the GUI rewrites
the three rule sections, dropping any comments inside them.

### Config format

```ini
[Settings]
RulesOnly = 0        ; 1 = only windows matching a title rule are managed

[TitleRules]
alias = text         ; substring matched anywhere in the title
alias2 = re:pattern  ; regular expression

[IgnoreExe]
1 = mstsc.exe        ; never touch windows of these programs

[IgnoreTitles]
1 = some text        ; never touch windows whose title contains this
```

## Requirements

- AutoHotkey v2 (the Microsoft Store edition works on locked-down machines)
- WebView2 runtime (preinstalled on Windows 10/11) — only needed for the GUI;
  the engine runs fine without it

## Notes

- If the old **LIMS move** script runs at the same time and the LIMS titles
  are added as title rules here, both scripts will fight over the same
  windows. Disable automatic moving in one of them.
- The WebView2 profile lives in `%LOCALAPPDATA%\DalSegno\WebView2` (a shared
  or read-only default profile causes error 0x8007139F).
