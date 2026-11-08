# mac-workspaces

An Omarchy-inspired keyboard workflow for macOS: press **⌘ Return** for a new terminal window, let windows tile automatically, and move between nine numbered workspaces with predictable shortcuts.

mac-workspaces is a small menu bar companion for [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide). AeroSpace does the tiling and the virtual workspaces. mac-workspaces adds:

- a guided setup (AeroSpace install check, permissions, shortcut review),
- a generated AeroSpace config with consistent defaults (backed up and diffed, never silently replaced),
- a terminal launcher that opens a **new** Terminal window on every deliberate press, ignores key auto-repeat, and keeps the window in the workspace you pressed it on,
- a workspace indicator in the menu bar (click to switch),
- editable shortcuts with conflict detection, workspace names, pause/resume and launch at login.

See [prd.md](prd.md) for the product requirements and [docs/VALIDATION.md](docs/VALIDATION.md) for the on-device acceptance checklist.

> Status: private alpha. Validated on macOS 26.2 with AeroSpace 0.21.3-Beta: 45 unit tests, and 27 of 27 end-to-end checks through real AeroSpace bindings (`scripts/e2e.sh`). Two PRD scenarios still need a manual run: launching with Terminal quit, and permission denied. See [docs/VALIDATION.md](docs/VALIDATION.md).

## Default shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘ Return | Open a new terminal window |
| ⌥ H / J / K / L | Focus left / down / up / right |
| ⌥⇧ H / J / K / L | Move window left / down / up / right |
| ⌥ 1–9 | Switch workspace |
| ⌥⇧ 1–9 | Move focused window to workspace (you stay where you are) |
| ⌥ - / ⌥ = | Shrink / grow focused window |
| ⌥ / | Toggle horizontal / vertical tiling |

Floating, monitor actions, layout reset and pause/resume are in the menu bar menu. You can bind them too, in Settings › Shortcuts.

Option + letter shortcuts type special characters on some keyboard layouts. Setup warns about this. You can change any shortcut before applying it.

## Requirements

- macOS 26 on Apple silicon (validated). It builds for macOS 14+, but 14–15 are untested.
- AeroSpace 0.21.3-Beta (validated). See [docs/VALIDATION.md](docs/VALIDATION.md#supported-versions-alpha-selection).
- [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide): `brew install --cask nikitabobko/tap/aerospace`
- Apple Terminal (other terminals are planned)
- To build: Xcode 15 or later (Swift 5.10+)

## Install

```sh
git clone https://github.com/nghiahsgs/mac-workspaces.git
cd mac-workspaces
scripts/bundle.sh --install      # builds and copies MacWorkspaces.app to /Applications
open /Applications/MacWorkspaces.app
```

The app appears in the menu bar and opens Setup on first launch:

1. **Install AeroSpace** if it is missing.
2. **Start AeroSpace** and allow it under *Accessibility*. AeroSpace needs this to move windows.
3. **Allow mac-workspaces to control Terminal** (*Automation*). This lets it open a new window on each press.
4. **Review shortcuts.** ⌘ Return overrides "send" in some apps. Change anything you need to.
5. **Apply the configuration.** If you have no AeroSpace config, one is created at `~/.aerospace.toml`. If you already have one, you see a diff first, and the old file is backed up before anything is written.

## How it works

```
 key press ──▶ AeroSpace (owns every global shortcut)
                 ├─ ⌥H, ⌥1, ⌥⇧3 …  ─▶ AeroSpace command (focus, workspace, move-node-to-workspace …)
                 └─ ⌘Return ─▶ exec-and-forget open -g macworkspaces://launch-terminal
                                   │
                                   ▼
                     mac-workspaces (menu bar app)
                       1. ignore auto-repeat (launch key still held → drop)
                       2. use the workspace captured at press time (passed in the URL)
                       3. tell Terminal: do script ""  (always a new window)
                       4. wait for AeroSpace to report the window; move it back if it
                          landed in another workspace; focus it
```

- **One owner for global shortcuts.** Every binding lives in the AeroSpace config. The companion registers no hotkeys of its own, so restarting it can't duplicate handlers.
- **Terminal control belongs to the companion.** Because the launch goes through the URL scheme, macOS attributes the Automation permission to mac-workspaces, not to AeroSpace or `osascript`.
- **Auto-repeat.** AeroSpace's hotkeys fire once per physical press (verified: a 2 s hold produces one trigger). As a second layer, after it accepts a launch the companion ignores requests until the launch key is physically released, with a 110 ms sliding window on top.
- **Pause** switches AeroSpace into a `paused` binding mode that has no bindings (unless you assign a resume shortcut). Product shortcuts stop intercepting keys, and tiling keeps working. `aerospace enable off` was not used because it also stops window management and moves windows out of hidden workspaces.
- **Workspace indicator** listens to `aerospace subscribe` events and also polls every 2 s. Polling catches window closes and recovers after AeroSpace restarts.

## Files

| Path | What |
| --- | --- |
| `~/.aerospace.toml` (or `~/.config/aerospace/aerospace.toml` if that is the one you use) | AeroSpace config generated by the app |
| `~/Library/Application Support/MacWorkspaces/settings.json` | Shortcuts, workspace names and preferences |
| `~/Library/Application Support/MacWorkspaces/Backups/` | Timestamped config backups, made before every apply or restore |

If both AeroSpace config locations exist, the app refuses to write. AeroSpace treats that as ambiguous too.

## Restore or remove

- **Restore a previous config:** Settings › Configuration › Backups › Restore. The current file is backed up first.
- **Uninstall:**
  1. Quit mac-workspaces from its menu. Turn off "Open at login" first if you enabled it.
  2. Restore your old AeroSpace config from Backups, or delete `~/.aerospace.toml` to go back to AeroSpace's defaults.
  3. `rm -rf /Applications/MacWorkspaces.app ~/Library/Application\ Support/MacWorkspaces`
  4. Optionally remove the Automation entry in System Settings › Privacy & Security › Automation.

## Development

```sh
swift build                 # debug build
swift test                  # unit tests for MacWorkspacesCore (no AeroSpace needed)
swift run MacWorkspaces --print-config   # print the config generated from your settings
MacWorkspaces --apply-config             # write it (refuses hand-written configs without --force; backs up first)
scripts/e2e.sh                           # end-to-end checks against live AeroSpace (uses empty workspaces 6–9)
scripts/bundle.sh           # build/MacWorkspaces.app (ad-hoc signed)
```

- `Sources/MacWorkspacesCore` is UI-free logic: the shortcut and action model, conflict detection, config generation, backup/restore/diff, the auto-repeat gate, launch orchestration, and the AeroSpace CLI client behind a protocol.
- `Sources/MacWorkspaces` is the AppKit/SwiftUI menu bar app: the Terminal AppleScript adapter, permissions, setup and settings.

Not covered by the MVP: terminal tabs and panes, tmux, native macOS Spaces, session restoration, themes, sync and telemetry.

This is an independent project inspired by Omarchy. The working name and visual identity are provisional.
