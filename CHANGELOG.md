# Changelog

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
