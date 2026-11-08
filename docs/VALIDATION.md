# On-device validation (PRD milestones 1 and 4)

The PRD requires these checks on a real Mac. None of them have been run yet. During development, AeroSpace was deliberately **not installed** on the build machine, because it takes over global shortcuts. What has been verified so far:

- `swift build`, `swift test` (44 unit tests) and `scripts/bundle.sh` succeed on macOS 26.2 with Xcode 26.6, on Apple silicon.
- The generated config parses as valid TOML. AeroSpace itself has not loaded it yet.
- The app launches as a menu bar app without crashing.

Record each result below with the macOS version, AeroSpace version (`aerospace --version`) and keyboard layout.

## Preparation

```sh
brew install --cask nikitabobko/tap/aerospace
scripts/bundle.sh --install && open /Applications/MacWorkspaces.app
# Finish Setup, then check that AeroSpace accepts the generated config:
aerospace reload-config --no-gui --dry-run && echo CONFIG OK
aerospace config --config-path
```

## Technical spike checks

| # | Check | How | Result |
| --- | --- | --- | --- |
| S1 | AeroSpace accepts the generated config, with no warnings | `aerospace reload-config --no-gui --dry-run --warnings-as-errors` | ☐ |
| S2 | `exec-and-forget /usr/bin/open -g 'macworkspaces://…'` reaches the running app | Press ⌘ Return. A Terminal window appears | ☐ |
| S3 | The Automation prompt names **mac-workspaces**, not AeroSpace | First ⌘ Return after install | ☐ |
| S4 | `CGEventSource.keyState` sees the held Return key without Input Monitoring permission | Hold ⌘ Return for 3 s. Exactly 1 window should open | ☐ |
| S5 | Starting Terminal from closed opens exactly one window | Quit Terminal (⌘Q), press ⌘ Return | ☐ |
| S6 | `aerospace subscribe` exists in the installed version, and the indicator updates on switch | Press ⌥2. The menu bar shows `[2]` within about 200 ms | ☐ |
| S7 | Pause mode | Pause from the menu. ⌥H types normally (or `˙`). Resume restores it | ☐ |
| S8 | `list-windows --format` with `%{tab}` parses correctly | `aerospace list-windows --all --format '%{window-id}%{tab}%{workspace}%{tab}%{app-bundle-id}'` | ☐ |

## PRD acceptance scenarios

| Scenario | Steps | Expected | Result |
| --- | --- | --- | --- |
| Terminal closed, press ⌘ Return | Quit Terminal, press ⌘ Return | One window opens and gets focus in the current workspace | ☐ |
| One terminal open, press ⌘ Return | Press ⌘ Return again | A second, independent window opens and the layout splits side by side | ☐ |
| Three deliberate presses; holding does not repeat | Press ⌘ Return 3 times. Then hold it for 3 s | Exactly 3 new windows, then 1 more for the hold | ☐ |
| Navigate tiled windows | ⌥H/J/K/L | Focus moves and nothing is typed into the shell. At an edge, focus stays put | ☐ |
| Workspace 2 launch | ⌥2, then ⌘ Return | The window is in workspace 2. Workspace 1 still has its windows (⌥1) | ☐ |
| Move window to workspace 3 | ⌥⇧3 | Only the focused window moves. You stay in the current workspace | ☐ |
| Close a tiled terminal | ⌘W in one of two windows | The remaining window fills the area | ☐ |
| Restart the companion | Quit and reopen the app | Names and bindings persist. One ⌘ Return opens one window | ☐ |
| Existing AeroSpace config | Put any `~/.aerospace.toml` in place, open Setup | A diff is shown. A backup appears in Settings › Configuration › Backups before the write | ☐ |
| Permission denied | Deny Automation for Terminal, press ⌘ Return | A message explains the problem. Setup step 3 shows *Denied* with a link to Settings | ☐ |
| Pause | Pause, press ⌘ Return in Terminal, then resume | While paused, keys reach apps. After resume, the shortcuts work again | ☐ |

## Quality targets

| Target | How to measure | Result |
| --- | --- | --- |
| Workspace switch < 200 ms | Screen-record at 60 fps and count frames from key press to redraw | ☐ |
| ⌘ Return to a usable window < 1 s, with Terminal running | Screen recording | ☐ |
| Rapid press race: ⌘ Return then ⌥3 immediately | The window ends up in the workspace where ⌘ Return was pressed | ☐ |
| Non-US layout (e.g. German, Vietnamese Telex) | Check whether the ⌥ letter bindings block characters you need | ☐ |
| Recovery after AeroSpace restart | Quit and reopen AeroSpace. The indicator recovers within 2 s | ☐ |
| Monitor connect / disconnect | Plug in and unplug an external display | ☐ |

## Open decisions (from the PRD)

- **Minimum macOS:** currently 14, because the SwiftUI APIs used need it. Not yet tested on 14 or 15.
- **AeroSpace version:** written against the documentation dated 2026‑07‑16 (`config-version = 2`, `subscribe`, `--app-bundle-id`). The oldest working version is still to be determined.
- **Intel:** not tested.
- **Distribution:** the app is ad-hoc signed. Developer ID signing and notarization are still to be decided.
