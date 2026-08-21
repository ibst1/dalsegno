# Changelog

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
