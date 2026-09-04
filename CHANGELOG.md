# Changelog

## 2.0.1 (2026-09-04)

- Fix: a rule's desktop was not applied to a window that had just appeared.
  Windows reports no desktop at all for a new window during its first tens
  of milliseconds (longer for heavy apps), and the one early
  attempt was silently lost. The desktop rules are now retried on every scan
  for up to ten seconds after a title change, until the window can be moved.
- Fix: the save dialog's text box wrapped and overlapped the controls below
  when the suggested title contained a line break; the suggestion and the
  typed text are now collapsed to one line, and the box is single-line.
- Fix: windows placed outside the screens. Positions were keyed by monitor
  count + virtual screen width only, so two docking stations with the same
  screens arranged differently shared positions. The monitors' arrangement
  is now part of the setup key (positions saved under the old key are
  adopted the first time they are needed, if they lie on the current
  screens), and a position whose title bar would land outside every monitor
  is never applied.
- Swedish: "läge" is now "position" throughout ("Spara fönstrets nuvarande
  position", "Sparad position", …).
- The save dialog's title option can be combined with the program: "only
  Viewer.exe windows" (ticked by default) writes `/exe:Viewer.exe Settings`, so
  the rule catches Viewer windows called Settings and nothing else. The rule
  editor shows the same box; the descriptions read "Viewer.exe windows with
  "Settings" in the title".
- Fix: a rule with both a desktop and a saved position gave a slow app (Java)
  the desktop but not the position. The scan now places the window before
  the desktop move, waits for a maximized window to finish restoring, and
  repeats the move until the rectangle sticks.
- A window moved or resized by hand is never pulled back by the scan,
  whatever state it is in.
- Fix: a Java app got neither position nor desktop at start. Its
  main frame is created 0x0, already titled, and shown for real only after
  login and loading; the 0x0 frame was "placed" and the desktop rule gave up
  on it, and when Java finally showed the frame with its own bounds nothing
  happened any more. A window is now left alone until it has a size (the
  grace periods start then), a title that changes a window's identity makes
  it a new placement, and for three seconds after a placement the window is
  watched: an app that applies its own bounds gets placed again (twice at
  most; a move by hand ends the watch).
- Placement trace: `Trace=1` under `[General]` writes what the scan decides
  for each window to `trace.log` next to `error.log`. Note that the Store
  edition of AutoHotkey redirects `%LOCALAPPDATA%` to its package folder
  (`…\Packages\53721Descolada.AutoHotkeyv2StoreEdition_…\LocalCache\Local\DalSegno`).
- Fix: picking an item in the window menu could snap every window with a
  saved position back to it (a maximized window lost its size on
  *Edit rule…*). The menu runs the thread per-monitor DPI aware while it is
  shown; a scan interrupting it measured the screens in that mode, got a
  different setup key (4x9600 instead of 4x10400) and treated every window
  as new. The setup key is now always measured system-DPI-aware, and the
  scan does not run while the menu is up.

## 2.0.0 (2026-09-03) — DalSegno Window Manager

DalSegno (window positions) and DeskPilot (virtual desktops) merged into one
application with two modules on a shared core. Nothing is migrated: the
config is a fresh file (see README), the positions file is unchanged.

- One rule table for both halves: a rule matches windows by title text (or
  regex) and program, and gives them a place and/or a virtual desktop.
  `alias = [/exe:] [/desktop:n] [/follow] [/off] <text or re:regex>`; first
  match wins, rows can be reordered in the list.
- One window menu (CapsLock + right-click) with one save item that reads
  *Edit rule…* when a rule matches; its dialog settles what the position
  applies to and which desktop the rule's windows go to.
- One GUI: Positions (rules and positions in one list, edited in place),
  Windows, Desktops, Settings (modules, menu, positions, which windows are
  managed, hotkeys, language).
- One tray icon (numbered by desktop when Desktops is on), one config file,
  one language setting, one window scan.
- The DalSegno↔DeskPilot IPC is gone; `DESKPILOT_CMD` stays for other scripts
  and `DALSEGNO_CMD` is the same interface under the new name.
- Identifiers in English throughout; DeskPilot's history lives on under
  `legacy/deskpilot/`.
- Rename the current desktop: in the desktop picker (left-click on the tray
  icon or the taskbar label) the checked entry opens a rename prompt; an
  empty name restores Windows' default.
- Two builds of VirtualDesktopAccessor.dll ship and the running Windows build
  picks one (the 23H2 build lives in the `23H2` folder). The latest
  release is built for 24H2; on 23H2 (22631) its
  internal COM VTable is off by one slot, which left moving and switching
  working but renaming failing.

The entries below are DeskPilot's, which this changelog continues.


## 1.5.0 (2026-08-28)

- The window menu moved from plain right-click to **CapsLock+right-click**
  (`MenuModifier` / `MenuButton`), and opens anywhere in the window rather
  than on the title bar only (`MenuWholeWindow`). The plain right-click is
  left to the app.
- The menu is now DeskPilot's own instead of the window's real system menu
  with our items appended. Appending to another process's `HMENU` meant the
  app rendered our items inside its own caption menu too, and competing for
  the plain right-click leaked clicks whenever the menu's modal loop blocked
  the hotkey criterion — between them that caused double menus, flicker, and
  menus built for the app's own menu popup instead of for the window.
- Fix: the menu was drawn at the wrong size and opened off-screen on every
  monitor whose scaling differs from the primary one. It is now shown
  per-monitor DPI aware; the script stays system DPI aware elsewhere, which
  is what the taskbar label and the OSD are built on.
- The modifier is read as physical key state rather than registered as a
  hotkey prefix, so it can be a key another script already hooks — a prefix
  registration makes AutoHotkey hold that key back from other hooks, which
  broke the combination outright when two scripts claimed the same key.
- `TitleMenuBand` is gone: with the menu no longer tied to the title bar
  there is no band to special-case.

## 1.4.0 (2026-08-25)

- Show a window on all desktops (window pinning) from the menu.

## 1.3.3 (2026-08-24)

- The release zip now ships the unmodified official AutoHotkey v2
  interpreter renamed to `DeskPilot.exe`, next to the plain-text scripts,
  instead of Ahk2Exe-compiled binaries. Compiled output was a unique,
  unsigned exe per release and kept tripping Defender's cloud heuristics
  on managed machines; the stock interpreter is byte-identical to the
  official release and keeps its reputation. `DeskPilotArrow.exe` is gone —
  the arrow helpers run through the interpreter instead.

## 1.3.2 (2026-08-21)

- Fix: the name label blinked whenever the taskbar's composition surface
  repainted (animated tray icons such as the OneDrive sync spinner painted
  over it). The label is a stand-alone topmost window again — the
  composition surface cannot paint over a separate top-level window — with
  the auto-hide/fullscreen guards restored and a faster position guard.

## 1.3.1 (2026-08-21)

- Fix: docked DisplayPort monitors fire spurious WM_DISPLAYCHANGE events,
  which put the display-change restart (1.1.1) into a restart loop —
  blinking tray icon and name label every few seconds. The restart now only
  happens when the monitor layout actually differs from the one the running
  instance started with.
- Fix: the desktop picker opened from the taskbar name label closed
  immediately (foreground lock) or was dismissed by the label guard timer.
  The label is click-through again (anything else flickers next to the
  taskbar's composition surface); clicks are caught by a hook over the
  label's rectangle, and the guard pauses while a picker menu is open.

## 1.3.0 (2026-08-21)

- Clicking the taskbar name label also opens the desktop picker menu.

## 1.2.0 (2026-08-21)

- Left-clicking the tray icon opens a desktop picker menu — choose any
  desktop to switch to (the current one is check-marked). The name OSD is
  still available from the tray menu and the ShowName hotkey.

## 1.1.1 (2026-08-21)

- Restart automatically when the display configuration changes
  (connect/disconnect of monitors) — the stale DPI captured at startup made
  the taskbar name label and the OSD render at the wrong size.

## 1.1.0 (2026-08-20)

- Rules 2.0: `/exe:<process regex>` matches the process name (title regex
  optional when given) and `/follow` switches along when a rule moves a
  window.
- "Start with Windows" toggle in the tray menu (creates/removes a Startup
  shortcut, works for both the script and the compiled exe).
- Reproducible release builds: `build.ps1` downloads the toolchain and
  produces the portable zip; a GitHub Actions workflow builds and attaches
  it automatically on version tags.

## 1.0.0 (2026-08-20)

First public release of DeskPilot.

- OSD with desktop number and name on every desktop switch.
- Numbered tray icon (1–9) plus clock-style desktop name label on the taskbar.
- Configurable hotkeys on one principle — Ctrl = switch, Alt = move window,
  Ctrl+Alt = move and follow — for both arrows and digits 1–9.
- Mouse control: wheel over the taskbar switches desktop; optional tray
  arrow icons.
- Title bar right-click menu: the window's real system menu (including items
  injected by the app or e.g. PowerToys) with move-to-desktop items appended.
- Window rules: regex-based auto-move of windows to specific desktops,
  creatable from the title bar menu.
- Hotkey that opens the move menu for the active window (Alt+Tab friendly).
- IPC via the registered window message `DESKPILOT_CMD`.
- Configuration in an ini file with live reload from the tray menu.
- English or Swedish UI, switchable from the tray menu (English default).
- Portable release build (`DeskPilot.exe` + `DeskPilotArrow.exe`) — no
  AutoHotkey installation required.
