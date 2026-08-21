# Changelog

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
