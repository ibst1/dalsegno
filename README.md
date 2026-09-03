# DalSegno Window Keeper

*Dal segno (𝄋) — "from the sign": go back to the marked place. That is what your
windows do: move a window once, and every window like it returns to that spot.*

Drag a window where you want it and drop it — the position is saved
automatically. The next time a window with the same identity opens, DalSegno
moves it right back there. Works with every program.

Built for (but not limited to) applications that keep opening popup windows
in the wrong place.

## How it works

- **Saving** hooks the Windows event `EVENT_SYSTEM_MOVESIZEEND`, which fires
  only when *you* finish moving or resizing a window — never when the script
  moves one. So the script's own moves can never overwrite your saved
  positions, and no polling heuristics are needed.
- **Restoring** scans for new windows about once a second. A new window whose
  identity has a saved position is moved there (twice, so the size sticks when
  crossing monitors with different scaling). Windows that were already open
  when the script started are left alone.
- **Identity** is `program + window class` by default: all normal windows of
  an app share one position, and the last one you moved defines it. (Exact
  titles are useless as identity — every new Notepad or Explorer window has
  a different title.) **Title rules** carve out exceptions: all windows
  whose title contains a given text (or matches a regex) form their own
  group with its own position, regardless of program — that is how specific
  popups get their own spots even though they live in the same browser as
  everything else.
- **Per monitor setup and computer**: positions are keyed by monitor count +
  virtual desktop width + computer name, so laptop/docked layouts and
  different machines never overwrite each other. On docking, open windows
  snap to the saved layout for the new setup.
- New windows get a 10-second grace period to receive their real title
  (browser popups often retitle shortly after opening).
- If several windows share one identity, nothing is auto-saved until only one
  remains (you can still save deliberately with CapsLock + S).
- **Maximized windows** are saved as *maximized on that monitor*, together
  with the normal rectangle they restore to. A new window with that identity
  is moved to the rectangle (that is what picks the monitor) and maximized
  there; a window that opens maximized but was saved normal is restored to
  the saved rectangle. The saved state is reproduced whole, either way.
- Minimized windows are never saved or restored.
- **Rules-only programs** (`[RulesOnlyExe]`): a program listed there gets no
  program-wide identity — only its windows that match a title rule are
  managed, the rest are left alone. That is the natural setting for a
  browser, where every popup is a separate window: without it, the first
  popup you save becomes the position of every other browser window too.

## GUI

Left-click the tray icon (or press CapsLock + D). Three tabs:

- **Positions** — one row per identity for the selected monitor setup: every
  title rule (with its position, or *no position yet*) and every program
  identity that has a position. Rules and positions used to be two tabs that
  showed the same things twice; a rule is only interesting together with the
  place its windows go to. A rule's text and regex flag are edited right in
  the row and saved the moment you leave the field (Enter commits, Escape
  reverts). **Active** switches a rule off without deleting it: its windows
  then count as ordinary windows of their program, and its position waits.
  *+ Add rule* opens an empty row. Per row: *Move now*, *Forget* (the
  position) and *Delete rule* (the rule and its positions in every setup,
  after confirmation). Rows are described by what they apply to — *windows
  with "Whole Genome View" in the title*, *all ChAS.exe windows* — with the
  window the position was saved from in the tooltip.
- **Open windows** — the manageable windows right now; save or restore any of
  them, or *Similar…* for the one-dialog rule flow on a listed window.
- **Settings** — behavior toggles; which windows are managed (*rules only*
  mode, rules-only programs, ignore lists — saved as soon as you leave the
  field); hotkeys; language (English/Svenska; also in the tray menu); the
  two files.

The GUI is a WebView2 page (`ui/`), same architecture as Encore and Expanto.

## Window menu

Hold **CapsLock** and right-click a window. Three items: **Save window
position…**, *Move to saved position*, *Forget saved position*.

The save item opens one dialog that settles what the position applies to:

- A window that matches no rule: *all windows of this program*, or *windows
  with … in the title* — a new rule, with the stable part of the title
  suggested (`Whole Genome View - 26MD12102_….cychp` → `Whole Genome View`,
  `Förhandsgranska 26MD12097 - …` → `Förhandsgranska`). Programs marked
  rules-only get the title option alone. OK writes the rule *and* saves this
  window's position under it in one step; the alias is derived from the text
  (`wholegenomeview`) and made unique. If an earlier rule in the config also
  matches the title, that one takes precedence and the notification says so.
- A window that already matches an active rule: the item reads **Edit rule…**
  instead, and the dialog shows the rule's text, regex flag and Active tick,
  plus *save this window's current position as the rule's position* (ticked).

Windows of rules-only programs that match no rule yet still get the menu,
since a rule is exactly what they need. The *Rule…* / *Edit rule…* button on
the Open windows tab opens the same dialog for a listed window.

With [DeskPilot](https://github.com/ibst1/deskpilot) running, these items
appear as a *DalSegno* submenu inside its larger window menu instead, on the
same combination. The two scripts talk over the `DALSEGNO_CMD` registered
window message, and DalSegno stands down from the mouse button while DeskPilot
is there: two scripts hooking the same button race each other, which produced
double and misplaced menus.

The modifier is read as **physical key state** and is never registered as a
hotkey prefix. Registering `CapsLock & RButton` as a combination would make
AutoHotkey hold CapsLock back from other scripts' keyboard hooks — which is
exactly what broke this when the modifier was `§` and two scripts claimed it.
Reading the state instead means the modifier can be a key another script
already owns.

## Hotkeys

Hold the modifier — `CapsLock` by default, set with `Modifier` in the settings.

| Hotkey | Action |
| --- | --- |
| CapsLock + D | open the DalSegno window |
| CapsLock + S | save the active window's position |
| CapsLock + Backspace | forget the active window's saved position (current setup) |
| CapsLock + Home | move every open window to its saved position |
| CapsLock + F10 | toggle automatic moving |
| CapsLock + F5 | restart the script |
| CapsLock + right-click | window menu: save/restore/forget/create rule |

These are registered as plain keys under a criterion that checks whether the
modifier is physically down, not as `CapsLock & key` combinations — see the
window menu section for why. One consequence worth knowing: if the script's
main thread is busy the criterion can time out, and the key then falls through
as an ordinary keystroke rather than firing the action.

## Files

| File | Purpose |
| --- | --- |
| `DalSegno.ahk` | the script (AutoHotkey v2) |
| `DalSegno positions.ini` | saved positions + on/off state + language (UTF-16) |
| `DalSegno config.ini` | title rules (and which are switched off), rules-only programs, ignore lists, rules-only mode (UTF-16) |
| `ui/` | the WebView2 GUI |
| `lib/`, `ComVar.ahk`, `Promise.ahk` | WebView2 + JSON libraries |
| `app.ico` | the segno icon |

The config file can be edited by hand (then pick *Reload settings* in the tray
menu) or from the GUI. Note that edits from the GUI rewrite the list sections
they touch, dropping any comments inside them.

### Config format

```ini
[Settings]
RulesOnly = 0        ; 1 = only windows matching a title rule are managed

[TitleRules]
alias = text         ; substring matched anywhere in the title
alias2 = re:pattern  ; regular expression

[RulesOnlyExe]
1 = msedge.exe       ; these programs are managed ONLY through title rules

[DisabledRules]
alias = 1            ; rules switched off in the GUI (kept in [TitleRules])

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

- If another window-moving script runs at the same time and the same titles
  are added as title rules here, both scripts will fight over the same
  windows. Disable automatic moving in one of them.
- The WebView2 profile lives in `%LOCALAPPDATA%\DalSegno\WebView2` (a shared
  or read-only default profile causes error 0x8007139F).
