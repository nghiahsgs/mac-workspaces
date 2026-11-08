# On-device validation

**Run on 2026-11-08** on a MacBook (Apple silicon, built-in Retina display only), macOS 26.2 (25C56), AeroSpace 0.21.3-Beta (`d56e163`), US keyboard layout. Xcode 26.6 / Swift 6.3.3.

Most checks are automated in [`scripts/e2e.sh`](../scripts/e2e.sh), which ran with **27 passed, 0 failed**. It drives the real AeroSpace bindings with `aerospace trigger-binding`, and synthesizes HID-level key events (`scripts/hold-key.swift`) for the hold and tap checks. Each check therefore goes through the whole path: generated config → AeroSpace binding → `exec-and-forget` → URL → companion → Terminal. The script only uses workspaces 6–9, refuses to start unless they are empty, and never closes a window that existed before it ran.

```sh
scripts/bundle.sh --install && open /Applications/MacWorkspaces.app   # finish Setup once
scripts/e2e.sh
```

## Technical spike

| # | Check | Result |
| --- | --- | --- |
| S1 | AeroSpace loads the generated config with no warnings (`reload-config --dry-run --warnings-as-errors`) | ✅ |
| S2 | `exec-and-forget open -g "macworkspaces://…"` reaches the running companion | ✅ |
| S3 | The Automation prompt names mac-workspaces. Afterwards Setup shows Terminal control as "Allowed" | ✅ |
| S4 | `CGEventSource.keyState` sees a held Return key without Input Monitoring (`keyState while held: true`, after release `false`) | ✅ |
| S4b | AeroSpace fires a binding **once** per physical press. Its Carbon hotkeys (soffes/HotKey) ignore auto-repeat: 1 trigger during a 2 s hold. The companion's gate is a second layer | ✅ |
| S5 | Starting Terminal from quit opens exactly one window | ⚠️ not run: Terminal hosted active sessions on the test Mac, so it was not quit |
| S6 | `aerospace subscribe` exists. The indicator updates within 0.4 s (`[1] Code` → `1 [3] Chat`) | ✅ |
| S7 | Pause enters the empty `paused` mode. Resume returns to `main` | ✅ |
| S8 | `list-windows --monitor all --app-bundle-id … --format …%{tab}…` parses | ✅ (`--all` with filters is rejected by AeroSpace, which is why `--monitor all` is used) |

## PRD acceptance scenarios

| Scenario | Result | Evidence |
| --- | --- | --- |
| Terminal is closed; press ⌘ Return → one window, focused, current workspace | ⚠️ not run | See S5. The code path uses Terminal's startup window instead of adding a second one |
| One terminal open; press ⌘ Return → second independent window, layout splits | ✅ | Two `h_tiles` windows, 755 / 755 px |
| Three deliberate presses → exactly three; holding does not repeat | ✅ | 3 binding presses → 3 windows. 3 HID taps → 3 windows. 2 s HID hold → 1 window |
| Directional navigation changes focus predictably, nothing typed into the shell | ✅ | ⌥H / ⌥L move focus. Stops at the left edge. Window frames unchanged |
| Switch to workspace 2 and launch → window belongs to 2; workspace 1 keeps its windows | ✅ | Run on workspaces 7 and 6 |
| Move a window to workspace 3 → only that window moves; active workspace unchanged | ✅ | Run with ⌥⇧8 |
| Close a tiled terminal → remaining windows expand | ✅ | 755 → 1511 px |
| Restart the companion → names and bindings persist; no duplicate handlers | ✅ | Single instance. One press → one window |
| Existing AeroSpace config found → proposed changes shown; backup before applying | ✅ | `--apply-config` on a hand-edited file: exit 2, diff printed, file untouched. `--force`: backup contains the user's edit |
| Required permission denied → setup explains it and how to enable | ⚠️ not run | Denying needs a human click in the macOS prompt. Code maps error −1743 to an explanation and Setup step 3 links to Automation settings |
| Pause → product bindings stop intercepting; resume restores them | ✅ | `paused` mode has `{}` bindings |
| Menu bar: current and occupied workspaces shown; clicking switches | ✅ | Read through Accessibility. Clicking "2 · Web" → workspace 2 |

## Quality targets

| Target | Result |
| --- | --- |
| Workspace switch < 200 ms | ✅ 38–54 ms, measured as the CLI round trip including `trigger-binding` (no frame-accurate video) |
| ⌘ Return → usable window < 1 s with Terminal running | ✅ 0.16–0.83 s until AeroSpace reports the window |
| Press ⌘ Return, then switch workspace 100 ms later → window stays where pressed | ✅ |
| Same with a 0 ms gap (faster than a human) | ℹ️ Can land in the new workspace: AeroSpace runs the switch before the binding's shell captures the workspace |
| Recovery after an AeroSpace restart | ✅ Companion re-subscribed within about 1 s, and launches worked |
| Non-US layouts, monitor connect/disconnect, Intel | ⚠️ not run (one built-in display, US layout) |

## Findings fixed during validation

1. **AeroSpace crash (0.21.3-Beta).** `focus` trapped in `TreeNode.bind` ← `makeFloatingWindowsSeenAsTiling` while floating windows existed, and the companion's own Setup window is one. Every focus the product issues now passes `--ignore-floating`. Floating windows stay reachable with the mouse.
2. **Workspace captured too late.** The companion read the focused workspace when the URL arrived, about 100 ms after the press, so a quick ⌥N switch sent the window to the wrong place. The binding now captures it at press time: `…launch-terminal?workspace=$(aerospace list-workspaces --focused)`.
3. **`list-windows --all --app-bundle-id`** is rejected by AeroSpace. It was replaced with `--monitor all` before the first live run, and confirmed live.

## Notes for users

- When AeroSpace starts, it adopts every open window into the focused workspace. After installing it or restarting it, expect your existing windows to be together in one workspace.
- Other window managers (for example Rectangle) can fight AeroSpace over window frames. Disable their shortcuts or quit them.

## Supported versions (alpha selection)

| | Supported | Notes |
| --- | --- | --- |
| macOS | **26 (Tahoe)**, Apple silicon | The only validated combination. 14–15 build (deployment target 14) but are unsupported until tested |
| AeroSpace | **0.21.3-Beta** | Needs `config-version = 2`, `subscribe`, `--app-bundle-id`. Older versions are unsupported |
| Terminal | Apple Terminal | Other terminals are a later extension (PRD) |
| Displays | One display | Monitor connect/disconnect not yet validated |
| Keyboard | US layout | Non-US layouts not validated. Setup warns about Option-key conflicts and every shortcut can be rebound |
| Intel | Unsupported | Not tested |
| Distribution | Build from source, ad-hoc signed | Developer ID signing and notarization are deferred to the first public release |

## Still to validate before widening support

- ⌘ Return with Terminal quit (S5), and the permission-denied path. Both need a person at the Mac.
- Non-US layouts (e.g. German, Vietnamese Telex), monitor connect/disconnect, Intel, macOS 14/15.
