# Changelog

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
