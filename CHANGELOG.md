# Changelog

## Unreleased

- Fix: with DalSegno running, every key and mouse event on the PC could wait
  up to a second - typing driven from another PC through Glissando crawled.
  DalSegno's keyboard and mouse hooks run on the same thread as the window
  scan, every 800 ms, and the scan read window titles with WinGetTitle, which
  asks the window's program and waits for the answer; one busy program held
  the scan, and with it the hooks, until Windows gave up on them (1 s). Titles
  are now read with InternalGetWindowText, which never waits on the window.

- Fix, the larger part of the same lag: the desktop label asked UI Automation
  what sits on the taskbar left of it (to shrink the label when the app
  buttons reach it), and on LU every such call took 9 s, several times a
  minute, on the thread the hooks wait for to judge their #HotIf conditions.
  The probe now runs in a helper process, DalSegnoProbe.ahk (started when
  needed, gone when DalSegno is), and the label uses its last answer instead
  of waiting; it asks again only when the number of windows changes, at
  most every 5 minutes, since every question keeps Explorer busy too. Slow timers and #HotIf callbacks are now noted as
  "SLOW" in the trace file even with tracing off (for the Store edition of
  AutoHotkey the file is in %LOCALAPPDATA%\Packages\...AutoHotkeyv2StoreEdition...
  \LocalCache\Local\DalSegno\trace.log).

## 2.0.5 (2026-09-24)

- A rule that moves a window to another desktop without following now says
  so in the small overlay: "Flyttat av regel: Patienthistorik → 1 · LIMS".
  Until now the window simply vanished from the desktop the user was
  looking at, which reads as "the window closed itself" - and was chased
  as a bug in the script that had opened the window.

- A saved position that is refused because it lies off every screen (less
  than 100 px of its title band on a monitor) is reported in the overlay
  too, once per rule and five minutes: "Sparad position för Bildfönster
  ligger utanför skärmarna och används inte. Spara om den." The refusal was
  visible in the trace only, and a position saved in the gap between two
  monitors - the window had been parked there by another script - looked
  like DalSegno ignoring its rule.

- Fix: restarting (CapsLock + F5, the tray, a display change) could bring
  up AutoHotkey's "Could not close the previous instance of this script.
  Keep waiting?" box, and a box left unanswered left an instance that had
  never run the script - which the next restart waited on in turn, so the
  box kept coming back. AutoHotkey gives the previous instance two seconds,
  and DalSegno's window scan can hold the script longer than that (the
  first scan after a start walks every window; a display change re-places
  them all). DalSegno now closes the previous instance itself, with a long
  silent wait, ends one that still will not go, and clears any instance
  stuck in that box; the scan lets messages through every ten windows, so
  an exit request or a hotkey no longer waits for the end of it.

- The DalSegno window's WebView2 is let go ten minutes after the window was
  closed: its half-dozen browser processes held some 250 MB for as long as
  the script ran, which on a full machine is paging. The next open creates
  the window again (a second or so instead of instantly).

## 2.0.4 (2026-09-07)

- Rules can be limited to computers: `/computer:<name,name>` in the config,
  a *computer* field on every rule row in the GUI and an *Only on this
  computer* tick in the window menu's rule dialog. The config is shared
  between computers through the synced folder, and positions were already
  kept per computer; the rules were not, so a rule made at one desk fired
  at every other. New rules are for the computer they are made on; a rule
  without the flag applies everywhere, as before. A rule for other
  computers is listed dimmed in the setups of those computers and ignored
  on this one.

- The Windows tab lists every rule that applies on the setup's computer,
  position or not. It used to list a rule only where it had a desktop or a
  position, which made a rule look deleted in a setup where it still
  claimed its windows: nothing under *Windows with rules* matched
  "Patienthistorik", yet the window menu on that window said *Edit rule*,
  and saving it put the position under the rule again. Rules without a
  position here are dimmed, as newly created ones were.

- Fix: the autosave modifier could read as held when it was not. The hook's
  physical state phantoms after another script reinstalls its hook ahead
  of DalSegno's mid-hold, and with *modifier only* on, every window then
  dropped by hand was saved - which is how a computer given three new
  screens acquired rule positions nobody asked for and kept moving the
  windows back to them. The modifier is now read through Raw Input, which
  gets every keyboard event straight from the input thread whether or not
  a hook later blocks it, so it sees the release the hook missed; injected
  keystrokes never count. The ten-second cap from 2.0.3 stays as a net for
  a release on the secure desktop, which Raw Input misses too.

## 2.0.3 (2026-09-06)

- Fix: a window moved by hand was placed again when its title left a rule
  and came back. A second window with a rule's title is placed by the rule;
  move it by hand and it should stay - but when its title changed to
  something else and then back to the original, the return counted as a
  new identity and the rule placed it once more. A hand-moved window now
  keeps its place through any title change.

- Fix: the modifier could get stuck in DalSegno's own keyboard hook. When
  another script reinstalls its hook ahead of DalSegno's while CapsLock is
  held (a modifier-layer script curing a stuck key of its own does exactly
  that), the key-up can pass DalSegno by, and its hook then believes
  CapsLock is held for good: every plain "a" was *Save all*, "d" opened the
  window, Backspace forgot a position, F5 restarted the script - until the
  old watchdog sent a synthetic key-up after 30 seconds. The modifier now
  counts for ten seconds from the moment DalSegno's hook saw it go down
  (the position hotkeys are single presses, never long holds); a stale
  "down" is harmless once the time is up, and the next real press and
  release clears it. No synthetic key events and no hook reinstalls: the
  OS's own state of the key cannot be used either, since a modifier-layer
  script that keeps CapsLock's toggle off hides the key from the OS for the
  whole hold.

- Fix: hidden helper windows got saved positions. The arrow-icon helper
  lookup switched hidden-window detection on from the auto-execute section
  at startup, which in AutoHotkey makes it the default for every later timer
  and hotkey thread - so the window scan, *Save all* and the Windows tab saw
  every titled top-level window a program keeps hidden (DDE server, GDI+
  hook, Office power manager, .NET broadcast windows, …). *Save all* then
  wrote a row per helper, most of them 0×0, and the positions list showed
  the same program several times over. The detection is now confined to
  that one lookup, *Save all* skips windows without a size or on no virtual
  desktop (the Windows tab's own filter), and a window with no size is never
  saved at all. Rows already written for such windows must be forgotten by
  hand (tick them, *Forget selected*).
- The Positions and Windows tabs are one tab, *Windows*, in two foldable
  sections. *Windows with rules* is what DalSegno acts on in the selected
  monitor setup - the rules and program rows of the old Positions tab, each
  now saying how many open windows it applies to right now. *Windows
  without rules* is every open window no row above covers, with its
  desktop and where it is right now, and a *Make a rule…* button that opens
  the window menu's dialog. The old Windows tab's identity and saved-
  position columns and its Save/Move buttons are gone: a window either has
  a row above, or it is listed below.
- Every row in *Windows with rules* has the same controls: tick box,
  Active, Desktop, *Move now*, *Forget*, *Remove* and ▲▼ - disabled where
  they cannot apply (Move now without a position, ▲▼ on program rows, which
  come after every rule and are sorted by program). *Forget* drops the
  position saved in the selected setup and keeps the row; *Remove* drops the
  row everywhere - a rule with its positions in every setup, a program row
  with its positions in every setup. The tick boxes feed *Remove selected*.
- The positions list lost its Identity column. It showed a rule's alias
  (`rule: reportview`) - the rule's key in the config and positions files,
  generated from the text when the rule is created and never typed by
  anyone - or a *standard* badge with the window class. Neither said
  anything the *Applies to* column does not: a rule is known by its text
  and program, a program row by its program. The window class, the one
  thing that tells a program's rows apart, now follows the text on those
  rows, and only when the program has more than one row. The Windows tab
  describes the matching rule in words ("windows with … in the title"),
  and so does the delete confirmation. The filter box no longer matches
  aliases.
- Program rows in the positions list are sorted by program, then window
  class, so one program's rows sit together; rules keep their own order.
- A rule is listed only in the monitor setups where it moves windows - where
  it has a desktop or a position. The rule table is shared by every setup
  and computer, so a rule with positions on another machine used to sit in
  the list here as a row saying *no position yet*. The status bar counts
  the rules left out ("3 rules with no effect in this setup"); a rule just
  created from the list stays in view until another setup is picked, so it
  can be given a desktop or a position; the ▲▼ buttons step over the rules
  the setup does not list.
- The *maximized* badge moved from the Applies to column to the Height
  cell: it qualifies the saved size, not the rule.
- Program rows ("all Notepad.exe windows") have the Active tick and the
  Desktop choice too. Using either turns the row into a rule for the
  program and its window class - the new `/class:` condition, so the rule
  catches exactly the windows the row stood for - and its saved positions in
  every setup move under the rule. Previously those rows showed dashes in
  both columns, and a desktop for a whole program could only be set from
  the window menu's dialog (which creates a `/exe:` rule).

## 2.0.2 (2026-09-04)

- Keep windows on screen: a window that opens entirely off every monitor -
  Office restores each document to coordinates a screen no longer covers, so
  Word can open a document in the empty space beside an L-shaped layout - is
  slid the smallest distance onto the nearest screen. On by default for Office
  apps ([Positions] KeepOnScreen = office; all = every managed window, off =
  never); a checkbox in Settings. A window parked at a screen edge on purpose
  is left alone.

- The positions list has a filter box in its toolbar: type part of a program
  name, window class, rule name, rule text or the title the position was
  saved from, and only matching rows remain. Esc clears it. The status bar
  shows how many rows the filter lets through.
- The Identity column now says what it is for: a standard row shows the
  window class next to the "standard" badge, so the several rows one
  program can have (main window, dialogs, helper windows) can be told
  apart. Previously every such row showed just the badge.
- Feedback for the hotkeys and the menu actions (position saved or
  forgotten, all saved, moving on/off, rule created, settings reloaded,
  errors) is an on-screen overlay on the monitor the mouse is on, in place
  of Windows notifications. Windows 11 drops those silently under
  do-not-disturb and for a process whose app id has no Start menu shortcut,
  which DalSegno's becomes once the GUI has been opened - so CapsLock+S,
  +A, +Backspace and +F10 looked like they did nothing.

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
