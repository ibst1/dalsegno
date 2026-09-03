# DalSegno Window Manager — design sketch

*Status: proposal, 2026-09-03. Nothing here is implemented yet. The open
decisions are collected at the end.*

DalSegno (window positions) and DeskPilot (virtual desktops) are two window
managers that apply title rules to the same windows, share one modifier key
and one window menu, and talk to each other over a window message that only
exists because they are two processes. This sketch merges them into one
application, **DalSegno Window Manager**, with the desktop and position
features as modules that can be switched on and off independently.

## 1. What the merge buys

| Today | Merged |
|---|---|
| Two rule tables in two formats: `RuleN=<desktop> [/exe:] [/follow] <regex>` and `alias = text` | One rule table: a match plus any of *desktop* and *position* |
| Two tray icons, two GUIs, two config files, two language settings | One of each |
| DeskPilot owns the menu and renders DalSegno's items through `DALSEGNO_CMD`; hook ownership decided by presence | One menu, no IPC between the halves, no hook race |
| Two windows-scanning timers (rule sweep once a second, placement scan every 800 ms) walking the same window list | One scan feeding both modules |
| Two window-identity notions (`ÄrRiktigtFönster`, `BaseInfo`/`KeyFor`) | One |
| The "always move to desktop" rule dialog and the "save position" dialog are different dialogs | One dialog: what the rule matches, which desktop, and whether to keep the position |

What does *not* change: the positions file and its keys, the per-monitor-setup
and per-computer separation, the hotkey principles of both halves, the
WebView2 GUI architecture, the portable-exe release format.

## 2. Modules

```
                 ┌──────────────────────────────────────────┐
                 │  core: config · window identity · rules   │
                 │        window scan · window menu · GUI    │
                 │        tray · language · logging          │
                 └───────────────┬──────────────┬───────────┘
                                 │              │
                  ┌──────────────┴───┐    ┌─────┴──────────────┐
                  │ Positions module │    │ Desktops module    │
                  │ save / restore   │    │ switch / move /    │
                  │ autosave on drag │    │ follow, OSD, tray  │
                  │ maximized state  │    │ number, taskbar    │
                  │ per setup+PC     │    │ label, wheel,      │
                  │                  │    │ pinning, DLL       │
                  └──────────────────┘    └────────────────────┘
```

- **Core** owns everything both halves need: the config file, `BaseInfo` /
  `KeyFor` (which windows may be touched, what identity they have), the rule
  table, one timer that walks the window list and hands new or retitled
  windows to the modules, the window menu with its dialog, the WebView2 GUI,
  the tray icon and menu, language, error log.
- **Positions** is DalSegno's engine: `SavePos` / `LoadPos` / `MoveToSaved`,
  the `EVENT_SYSTEM_MOVESIZEEND` hook for autosave, maximized handling, the
  CapsLock action hotkeys (D, S, A, Home, Backspace, F10).
- **Desktops** is DeskPilot's engine: registry polling for the current
  desktop, `VirtualDesktopAccessor.dll` for moves, the OSD, the numbered tray
  icon, the taskbar name label, wheel and arrow icons, pinning, the Win-based
  hotkeys, the `DESKPILOT_CMD` IPC.

`[Modules] Positions=1 Desktops=1` in the config; both also as toggles on the
Settings tab. A module switched off registers no hotkeys, runs no timer work,
shows no GUI tab and no menu items, and loads no DLL. With Desktops off the
app is today's DalSegno; with Positions off it is today's DeskPilot.

## 3. One rule model

A rule is a **match** plus **actions**. The match is what DalSegno already
has (text in the title, or `re:` regex) extended with DeskPilot's optional
program match. The actions are a target desktop (DeskPilot) and being a
position identity (DalSegno). Every rule is a position identity whether or
not a position has been saved under it, so a desktop rule for LIMS popups
also gives those popups a place to keep a position.

### Config line

DeskPilot's switch style, because it already exists and handles any
characters in the title text (the pattern is everything after the switches):

```ini
[Rules]
; alias = [/exe:<program>] [/desktop:<n>] [/follow] [/off] <text or re:regex>
forhandsgranska = Förhandsgranska
patienthistorik = /exe:msedge.exe MED_PatientHistoryPopup
whole           = Whole Genome View
expanto         = /desktop:5 re:^Expanto$
deskpilot       = /desktop:2 /off re:^DeskPilot$
spotify         = /exe:spotify.exe /desktop:2 /follow
```

- `alias` — the rule's name and the key of its saved positions
  (`rule:<alias>`, unchanged), so nothing in the positions file moves.
- text / `re:` — matched anywhere in the title; regex with `re:`. May be
  empty when `/exe:` is given: the rule then catches every window of that
  program.
- `/exe:` — program name, case-insensitive; `re:` for a regex.
- `/desktop:<n>` — move matching windows there when they appear or retitle
  into matching (DeskPilot's semantics: a window dragged back by hand stays).
  `/follow` switches along.
- `/off` — the rule is kept but inactive. Replaces DalSegno's
  `[DisabledRules]` section: the GUI rewrites the row anyway, and one line
  per rule is easier to read by hand.
- **Order matters, first match wins** — both engines already work that way.
  The list therefore needs a way to reorder rows.

### Migration

Run once at first start, from the old files if they are found, with the
originals kept as `*.bak`:

| From | To |
|---|---|
| DeskPilot `RuleN=<d> [/exe:<re>] [/follow] <regex>` | `<alias> = /desktop:<d> [/exe:re:<re>] [/follow] re:<regex>`; alias derived from the regex text the way `SuggestAlias` does (`^Expanto$` → `expanto`), made unique |
| DalSegno `[TitleRules]` + `[DisabledRules]` | same lines, `/off` appended for disabled aliases |
| DalSegno `[RulesOnlyExe]`, `[IgnoreExe]`, `[IgnoreTitles]`, `[Settings]` | unchanged |
| DeskPilot `[Hotkeys]`, `[Display]`, `[Mouse]` | `[Hotkeys]` (both sets side by side), `[Desktops]`, `[Menu]` — see §7 |
| `DalSegno positions.ini` | untouched |

## 4. Window identity (unchanged)

`BaseInfo` decides whether a window may be touched at all (title, not ours,
not shell furniture, not a tool window, not cloaked, not on the ignore
lists). `KeyFor` gives it an identity: the first active rule that matches
(`rule:<alias>`), else the program identity `exe|class` — except for
rules-only programs and in rules-only mode, where a window without a rule has
no identity and is left alone. DeskPilot's `ÄrRiktigtFönster` and its own
skip lists fold into `BaseInfo`; the desktop rule sweep uses the same
function, so both modules agree on which windows exist.

## 5. Window menu and dialog

One owner, one hook, one menu. Hold CapsLock (configurable) and right-click:

```
Spara fönstrets läge…      ← "Ändra regel…" when an active rule matches
Flytta till sparat läge
Glöm sparat läge
────────────────────────
Flytta till skrivbord   ▸  1 Klinik · 2 Lab · 3 …
Flytta och följ efter   ▸
☐ Visa på alla skrivbord
```

The first item's dialog is today's DalSegno dialog with one row added:

```
Vad ska läget gälla?
 ( ) Alla ChAS.exe-fönster
 (•) Fönster med [Whole Genome View     ] i titeln    [ ] regex
Skrivbord:  [ (inget) ▾ ]   [ ] följ efter
[x] Spara fönstrets nuvarande läge
                                         [ OK ]  [ Avbryt ]
```

- With a rule matching, the title reads *Ändra regel*, the text is the
  rule's, and the dialog also shows *Regeln är aktiv*.
- The *Skrivbord* row replaces DeskPilot's separate "always move windows like
  this to…" item and its regex InputBox. Picking a desktop for "all X
  windows" creates a program rule (`x = /exe:x.exe /desktop:n`) so that the
  decision shows up as a row in the list; without a desktop, "all X windows"
  keeps saving under the plain program identity as today.
- Rules-only programs get the title option only, as today.

## 6. GUI

Four tabs. The list tab is today's DalSegno list with a desktop column; the
Desktops tab is DeskPilot's hotkeys and taskbar settings; Settings gains the
module switches and DeskPilot's menu settings.

**Lägen** — one row per rule, plus program identities that have a position.

| Gäller | Identitet | Aktiv | Skrivbord | X | Y | Bredd | Höjd | |
|---|---|---|---|---|---|---|---|---|
| fönster med `Whole Genome View` i titeln | regel: whole | ☑ | (inget) ▾ | −1851 | 1142 | 1799 | 944 | Flytta nu · Glöm · Ta bort · ↑↓ |
| fönster med `Förhandsgranska` i titeln, msedge.exe | regel: forhandsgranska | ☑ | 3 Klinik ▾ ☐ följ | 1951 | 34 | 1026 | 1008 | … |
| fönster med `^Expanto$` (regex) i titeln | regel: expanto | ☑ | 5 ▾ | *inget läge ännu* | | | | |
| alla EXCEL.EXE-fönster | standard | – | – | 1952 | 2700 | 228 | 703 | Flytta nu · Glöm |

Editing stays in place and saves on leaving the field, as today. New: the
program field (blank = any), the desktop dropdown with *följ*, and row
reordering (↑↓ buttons; drag if it turns out to be worth the code). The
monitor-setup selector stays above the table; the desktop column is the same
in every setup.

**Fönster** — the open windows: program, title, desktop now, identity,
saved position; actions *Spara läge*, *Flytta hit*, *Regel…* / *Ändra
regel…*, and a desktop dropdown to move a window right there. DeskPilot's
window list and DalSegno's merge into this one.

**Skrivbord** — DeskPilot's hotkeys (move/switch/prefix), MoveMenu, ShowName,
taskbar label, wheel, arrow icons. Hidden when the module is off.

**Inställningar** — modules on/off; window menu (modifier, button, whole
window, exclude list); positions behaviour (move new windows, autosave,
modifier-only, toasts); which windows are managed (rules only, rules-only
programs, ignore lists); DalSegno's CapsLock hotkeys; language; the files.

## 7. Config file

`DalSegno config.ini`, UTF-16, next to the script; `DalSegno positions.ini`
as today.

```ini
[Modules]
Positions=1
Desktops=1

[Menu]                    ; from DeskPilot [Mouse] and DalSegno [Settings]
Modifier=CapsLock
Button=RButton
WholeWindow=1
Exclude=

[Positions]               ; from DalSegno [General]/[Settings]
MoveWindows=1
AutoSave=1
AutoSaveModifierOnly=1
Notify=1
RulesOnly=0

[Desktops]                ; from DeskPilot [Display]/[Mouse]
NameInTray=1
Wheel=1
ArrowIcons=0

[Hotkeys]                 ; both sets, one section
OpenUi=d                  ; CapsLock layer (Positions)
SaveActive=s
SaveAll=a
ApplyAll=Home
ForgetActive=Backspace
ToggleMove=F10
Reload=F5
MoveNext=!#Right          ; Win layer (Desktops)
MovePrevious=!#Left
MoveFollowNext=^!#Right
MoveFollowPrevious=^!#Left
SwitchToPrefix=^#
MoveToPrefix=!#
MoveFollowToPrefix=^!#
MoveMenu=!#Down
ShowName=

[Rules]                   ; §3
[RulesOnlyExe]
[IgnoreExe]
[IgnoreTitles]

[General]                 ; language, GUI window geometry
Language=sv
```

The on/off states DalSegno keeps in the positions file today (`MoveWindows`,
`AutoSave`, `Notify`) move to the config file; the positions file becomes
positions only.

## 8. Tray, hotkeys, IPC

- **Tray icon**: with Desktops on, DeskPilot's numbered icon (the current
  desktop is the one thing worth a glance); with Desktops off, the segno.
  Left-click opens the desktop picker when Desktops is on, the GUI otherwise;
  *Öppna DalSegno…* is always the first menu item, and CapsLock + D opens the
  GUI regardless.
- **Hotkeys**: no conflict — DalSegno's live under a held CapsLock,
  DeskPilot's under Win. All stay configurable. The CapsLock modifier is read
  as physical state in both halves already; merged, there is one reader.
- **IPC**: `DESKPILOT_CMD` stays registered under that name for other
  scripts, and `DALSEGNO_CMD` is registered too with the same handler; the
  DalSegno↔DeskPilot query/command protocol goes away.
- **Startup**: one shortcut in `shell:startup` instead of DeskPilot's;
  DalSegno was never in there.

## 9. Code and packaging

- One repository and one script, `DalSegno.ahk`, with the modules as
  `#Include` files: `src/core.ahk` (config, identity, rules, scan, menu,
  dialog), `src/positions.ahk`, `src/desktops.ahk`, `src/gui.ahk`,
  `src/tray.ahk`, plus `lib/` (WebView2, JSON) and `ui/`. DeskPilot's
  `DeskPilotArrow.ahk` comes along as `DalSegnoArrow.ahk`.
- **Identifiers in English throughout.** DeskPilot's code is written with
  Swedish identifiers (`VisaFönstermenyn`, `LäsKonfig`, `g_regler`); DalSegno
  in English. Renaming while moving is the cost of one consistent codebase;
  comments stay as they are where they still hold.
- **Repository**: DeskPilot's history is merged into `dalsegno`
  (`git merge --allow-unrelated-histories` of a prefixed subtree, so `git
  log` and blame survive), and `deskpilot` is archived with a pointer in its
  README. DeskPilot's `build.ps1` and GitHub Actions release workflow move
  over and produce `DalSegno-x.y.z.zip` with the stock interpreter renamed
  `DalSegno.exe`, `VirtualDesktopAccessor.dll` and the icons — the release
  format DeskPilot settled on after the Defender false positives.
- **Version** 2.0.0; CHANGELOG continues DeskPilot's.
- README: one document, with the desktop and position halves as sections.

## 10. Plan and tests

1. **Core and rule model** — config sections, migration, unified `Rule`
   object, `BaseInfo`/`KeyFor` as the one identity, one window scan. Both
   modules moved in behind their switches without behaviour change. Test:
   the lifted-function harness against copies of both real config files;
   migration on both computers' files.
2. **Menu and dialog** — one owner, desktop submenus, the dialog's desktop
   row, program rules from the dialog. Test: driving the dialog with
   `ControlClick` as done today, plus `/selftest`.
3. **GUI** — list with desktop column and reordering, Fönster tab merged,
   Skrivbord tab, Settings with modules. Test: the browser render test with
   the real state.
4. **Packaging and hand-over** — build script, release, README, CHANGELOG,
   startup shortcut, archive DeskPilot. Run both machines on the merged app
   for a few days before the old scripts are deleted.

Each step leaves the app runnable; steps 1–3 can each be a release on this
machine before the next starts.

## 11. Decisions to make

1. **Repository**: merge DeskPilot's history into `dalsegno` and archive
   `deskpilot` (recommended), or rename `deskpilot` and pull DalSegno in.
2. **"All windows of program" with a desktop** creates a program rule so it
   shows in the list (recommended), or saves the desktop somewhere without a
   rule row.
3. **Tray left-click** with Desktops on: desktop picker (recommended, it is
   what the hand is used to) or the GUI.
4. **Disabled rules** as `/off` in the rule line (recommended) or a separate
   section as today.
5. **English identifiers** throughout, renaming DeskPilot's code
   (recommended), or leave DeskPilot's half in Swedish.
6. **Row reordering** with ↑↓ buttons (recommended for a first version) or
   drag and drop.
