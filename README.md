# DalSegno Window Manager

*Dal segno (𝄋) — "from the sign": go back to the marked place. That is what
your windows do: they return to their marked place — the saved position on
the right monitor, and the right virtual desktop.*

An AutoHotkey v2 window manager for Windows 11 with two modules on one core,
each switchable on its own:

- **Positions** — move a window by hand and every window like it returns to
  that spot. Positions are kept per monitor setup and per computer;
  maximized windows come back maximized on the same monitor.
- **Desktops** — always see which virtual desktop you are on (numbered tray
  icon, overlay on every switch, the desktop name on the taskbar), and move
  windows between desktops with hotkeys, the mouse wheel, the window menu or
  rules.

One rule table serves both: a rule matches windows by title text (or regex)
and program, and gives them a place and/or a desktop. Built for (but not
limited to) applications that keep opening popup windows in the wrong place
and on the wrong desktop.

DalSegno Window Manager is the merger of DalSegno (positions) and
[DeskPilot](https://github.com/ibst1/deskpilot) (desktops). DeskPilot's history
lives on under `legacy/deskpilot/`; the design of the merge is in
`docs/window-manager-design.md`.

## How it works

- **Identity.** Every window that may be touched gets an identity: the first
  active rule that matches it (`rule:<alias>`), else its program and window
  class — so all normal windows of an app share one position, and the last
  one you moved defines it. Programs listed as *rules only* (browsers) get no
  program-wide identity: their popups are separate windows that would
  otherwise share one position with every other window of the browser.
- **Saving** hooks the Windows event `EVENT_SYSTEM_MOVESIZEEND`, which fires
  only when *you* finish moving or resizing a window — never when the script
  moves one. By default a drag saves only while the modifier (CapsLock) is
  held at the drop, so saving is a deliberate gesture.
- **Restoring** scans for new windows about once a second. A new window whose
  identity has a saved position is moved there; a window that opens
  maximized but was saved normal is restored, one saved maximized is
  maximized on the saved monitor. Windows already open when the script
  started are left alone. New windows get a 10-second grace period to receive
  their real title.
- **Desktop rules** fire when a window is new or its title changes into
  matching — a window you drag back by hand stays there. All existing windows
  are evaluated once at start.
- **Per monitor setup and computer**: positions are keyed by monitor count +
  virtual desktop width + computer name, so laptop/docked layouts and
  different machines never overwrite each other.

## The window menu

Hold **CapsLock** (configurable) and right-click anywhere in a window:

| Item | Does |
| --- | --- |
| **Save window position…** / **Edit rule…** | one dialog, see below |
| Move to saved position | puts the window where its identity's position is |
| Forget saved position | removes it for the current monitor setup |
| Move to desktop ▸ / Move and follow ▸ | the desktops, current one disabled |
| ☐ Show on all desktops | pins the window (checkable) |

The save item's dialog settles what the position applies to. For a window
that matches no rule: *all windows of this program*, or *windows with … in
the title* — a new rule, with the stable part of the title suggested
(`Whole Genome View - 26MD12102_….cychp` → `Whole Genome View`). Programs
marked rules-only get the title option alone. With the Desktops module on,
the dialog also has a **Desktop** row (with *follow*): the rule's windows are
moved there from now on; picking a desktop for "all windows of the program"
creates a program rule so the decision shows up in the list. For a window
that already matches an active rule, the item reads **Edit rule…** and the
dialog shows the rule's text, regex flag, Active tick and desktop, plus
whether to save this window's current position under it (ticked).

The modifier is read as **physical key state** and never registered as a
hotkey prefix, so it can be a key another script already owns. The menu is
shown per-monitor DPI aware for as long as it is up.

## Hotkeys

Position hotkeys are held with the modifier (`CapsLock` by default); desktop
hotkeys follow one principle — *Ctrl = switch, Alt = move the window,
Ctrl+Alt = move and follow*. All are configurable in the GUI.

| Hotkey | Action |
| --- | --- |
| CapsLock + D | open the DalSegno window |
| CapsLock + S | save the active window's position |
| CapsLock + A | save all open windows' positions |
| CapsLock + Backspace | forget the active window's saved position |
| CapsLock + Home | move every open window to its saved position |
| CapsLock + F10 | toggle automatic moving |
| CapsLock + F5 | restart the script |
| Win+Ctrl+←/→ | switch desktop (native Windows) |
| Win+Alt+←/→ | move the active window to the previous/next desktop |
| Win+Ctrl+Alt+←/→ | move the window and follow it |
| Win+Ctrl+1–9 / Win+Alt+1–9 / Win+Ctrl+Alt+1–9 | switch to / move to / move and follow to desktop N |
| Win+Alt+↓ | the window menu for the active window (Alt+Tab friendly) |

Mouse: scroll the wheel over the taskbar to switch desktop; left-click the
numbered tray icon or the taskbar name label for a desktop picker; right-click
the label for the GUI; two optional tray arrow icons switch one step.

## GUI

Left-click the tray icon opens the desktop picker when Desktops is on;
*Open DalSegno…* in the tray menu or CapsLock + D opens the GUI. Four tabs:

- **Positions** — one row per rule for the selected monitor setup (with its
  position, or *no position yet*), plus program identities that have a
  position. Text, regex flag, program and desktop are edited right in the
  row and saved when you leave the field; **Active** switches a rule off
  without deleting it; ▲▼ reorder rules (the first match wins). *Move now*,
  *Forget* and *Delete rule* per row; *+ Add rule* for a new row.
- **Windows** — the open windows: program, title, desktop (pick another to
  move it), identity, saved position; *Save position*, *Move there*, and
  *Rule…* / *Edit rule…* for the dialog.
- **Desktops** — the desktop hotkeys and digit prefixes, taskbar label, wheel,
  arrow icons. Hidden when the module is off.
- **Settings** — modules on/off; the window menu (modifier, button, whole
  window, excluded programs); positions behaviour (move new windows,
  autosave, modifier-only, toasts); which windows get positions (rules only,
  rules-only programs, ignore lists); position hotkeys; language; the files.

## Rules

```ini
[Rules]
; alias = [/exe:<program>] [/desktop:<n>] [/follow] [/off] <text or re:regex>
forhandsgranska = Förhandsgranska
patienthistorik = /exe:msedge.exe MED_PatientHistoryPopup
expanto         = /desktop:5 re:^Expanto$
spotify         = /exe:spotify.exe /desktop:2 /follow
old             = /desktop:2 /off re:^Something$
```

- The text is matched anywhere in the title; `re:` makes it a regular
  expression (PCRE, case-sensitive — prefix `(?i)` for case-insensitive;
  AutoHotkey's `\w` is ASCII-only). It may be empty when `/exe:` is given.
- `/exe:` matches the program name, case-insensitive; `re:` for a regex.
- `/desktop:<n>` moves matching windows there when they appear or their
  title changes into matching; `/follow` switches along.
- `/off` keeps the rule but switches it off.
- The alias names the rule and its saved positions (`rule:<alias>` in the
  positions file). **Order matters** — the first matching rule wins.

## Files

| File | Purpose |
| --- | --- |
| `DalSegno.ahk` | the entry script (AutoHotkey v2) |
| `src/core.ahk`, `src/positions.ahk`, `src/desktops.ahk`, `src/gui.ahk` | the core and the modules |
| `DalSegno config.ini` | settings and rules (UTF-16, created with defaults on first run) |
| `DalSegno positions.ini` | saved positions (UTF-16) |
| `DalSegnoArrow.ahk` | the tray arrow helper |
| `ui/` | the WebView2 GUI |
| `lib/`, `ComVar.ahk`, `Promise.ahk` | WebView2 + JSON libraries |
| `icons/`, `app.ico` | tray icons: the desktop numbers, the arrows, the segno |
| `VirtualDesktopAccessor.dll` | not in the repository — see Requirements |

The config file can be edited by hand (then *Reload settings* in the tray
menu) or from the GUI. Edits from the GUI rewrite the sections they touch,
dropping comments inside them.

```ini
[Modules]      Positions=1  Desktops=1
[Menu]         Modifier=CapsLock  Button=RButton  Enabled=1  WholeWindow=1  Exclude=
[Positions]    MoveWindows=1  AutoSave=1  AutoSaveModifierOnly=1  Notify=1  RulesOnly=0
[Desktops]     NameInTray=1  Wheel=1  ArrowIcons=0
[Hotkeys]      OpenUi=d … Reload=F5, MoveNext=!#Right … ShowName=
[Rules]        see above
[RulesOnlyExe] 1=msedge.exe          ; managed only through rules
[IgnoreExe]    1=mstsc.exe           ; never touched
[IgnoreTitles] 1=Bildfönster         ; never touched
[General]      Language=sv
```

## IPC

Other scripts control the desktops by posting the registered window message
`DESKPILOT_CMD` (or `DALSEGNO_CMD`, the same interface) to the script's
hidden main window:

| wParam | Action |
|---|---|
| 1 | Switch to desktop `lParam` |
| 2 | Move the active window to desktop `lParam` |
| 3 | Move and follow to desktop `lParam` |
| 4 | Show the name OSD |
| 5 | Reload the settings |
| 6 / 7 | Next / previous desktop |
| 8 | Open the GUI |
| 9 | Open the save/rule dialog for window `lParam` |
| 10 | Query window `lParam` (SendMessage): 1 = manageable, +2 = saved position, +4 = matches a rule |
| 100 | Ping — writes `ping.txt` next to the script (test hook) |

## Requirements

- Windows 11 (developed on build 22631 / 23H2).
- [AutoHotkey v2](https://www.autohotkey.com/) — the Microsoft Store edition
  works on locked-down machines.
- [VirtualDesktopAccessor.dll](https://github.com/Ciantic/VirtualDesktopAccessor)
  by Jarkko Pöyry (Ciantic), MIT — required for *moving windows between
  desktops*: **<https://github.com/Ciantic/VirtualDesktopAccessor/releases/latest/download/VirtualDesktopAccessor.dll>**
  next to `DalSegno.ahk`. Without it everything else works; desktop switching
  falls back to sending `Ctrl+Win+arrow`.
- WebView2 runtime (preinstalled on Windows 10/11) — only for the GUI.

## Installation

**Portable zip:** download `DalSegno-x.y.z.zip` from Releases and extract it
anywhere; run `DalSegno.exe` (the unmodified official AutoHotkey v2
interpreter, renamed — it loads `DalSegno.ahk` beside it, so all application
code ships as readable text). The dll is bundled.

**Script:** clone the repository, put the dll next to `DalSegno.ahk`, run it.

Either way: *Start with Windows* in the tray menu creates the startup
shortcut. `/selftest` writes the parsed state to `selftest.txt` and exits;
`/show` shows the OSD at startup.

## Notes

- The WebView2 profile lives in `%LOCALAPPDATA%\DalSegno\WebView2`; the
  error log in `%LOCALAPPDATA%\DalSegno\error.log` (per machine, outside the
  synced folder).
- Desktops beyond 9 get a generic tray icon and no digit hotkeys.

## License

MIT — see [LICENSE](LICENSE). Third-party components: [THIRD-PARTY.txt](THIRD-PARTY.txt).
