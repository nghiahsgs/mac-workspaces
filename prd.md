# mac-workspaces — Product Requirements Document

Status: Draft
Date: 2026-11-08
Working name: mac-workspaces

## Product vision

Bring an Omarchy-inspired keyboard workflow to macOS: launch terminals, automatically arrange windows, and travel between windows and workspaces with predictable shortcuts and minimal setup.

The first release is a macOS companion to AeroSpace. AeroSpace handles tiling and virtual workspaces; this product provides setup, consistent defaults, a workspace indicator, and approachable settings. This repository initially contains planning documentation only.

## Problem

Users who enjoy Omarchy want the same fluid workflow on a Mac. Manually opening, resizing, arranging, and locating terminal windows interrupts work. Existing tools provide the building blocks but require configuration and learning multiple conventions.

## Target user

A developer or terminal-heavy Mac user who wants keyboard control, automatic layouts, and separate workspaces for coding, browsing, and communication. The initial user is familiar with Omarchy but should not need to learn AeroSpace configuration syntax.

## Primary experience

1. The user completes setup and enables the required macOS permissions.
2. Pressing Command + Enter opens one new terminal window in the active workspace and focuses it.
3. Pressing Command + Enter again opens another terminal window. AeroSpace tiles the two side by side.
4. Further terminal windows join the active workspace's tiling layout.
5. The user navigates between windows with directional shortcuts.
6. The user switches to another workspace and opens windows there independently.
7. Closing a window lets the remaining tiled windows fill the available area.

“Split” means arranging separate application windows. Terminal tabs, terminal multiplexer panes, and shell session restoration are outside the MVP.

## MVP requirements

### Terminal launching and tiling

- Command + Enter creates a new window on every deliberate press, even when the terminal is already running.
- Use Apple Terminal as the initial supported terminal. Other terminals are a later extension.
- The new window appears in the active AeroSpace workspace and receives focus.
- Ignore keyboard auto-repeat so holding the shortcut does not create many windows.
- Default to horizontal tiling for a landscape display; offer a horizontal/vertical layout toggle.
- Normal application windows participate in tiling; dialogs and utility windows follow appropriate floating rules.
- Resizing or closing a tiled window updates the layout without requiring manual rearrangement.

### Window navigation

- Provide directional focus, directional movement, resizing, and a floating toggle.
- Moving focus must not move the underlying window.
- At a layout edge, focus stays put unless the user explicitly switches monitors.
- Preserve normal terminal input and standard macOS shortcuts outside registered bindings.

### Workspaces

- Provide nine numbered workspaces with optional display names, such as Code, Web, and Chat.
- Switch directly to a workspace or move the focused window to one.
- Moving a window to another workspace keeps the user in the current workspace by default.
- Show the current workspace and occupied workspaces in a lightweight menu bar interface.
- Clicking a workspace switches to it.
- Explain during setup that these are AeroSpace virtual workspaces, separate from native macOS Spaces.
- Preserve configured names and bindings across app restarts. Do not promise to restore terminated applications or shell sessions.

### Setup and settings

- Detect whether AeroSpace is installed and running; guide the user through dependency setup.
- Explain and check Accessibility permission and any Automation permission required to control Terminal.
- Let the user review bindings before enabling them, especially Command + Enter, which some apps already use.
- Allow shortcut customization and detect conflicts within the product's bindings.
- Keep one owner for global shortcuts, preferably AeroSpace bindings, to avoid duplicate handling.
- Back up an existing AeroSpace configuration before applying changes and provide a restore path.
- Never silently replace an existing user configuration; support reviewed changes or a clean setup.
- Provide pause/resume controls, a shortcut reference, and a launch-at-login preference.
- If AeroSpace or a permission is unavailable, show a useful status and recovery action.

## Proposed default shortcuts

| Shortcut | Action |
| --- | --- |
| Command + Enter | Open a new terminal window |
| Option + H / J / K / L | Focus left / down / up / right |
| Option + Shift + H / J / K / L | Move window left / down / up / right |
| Option + 1–9 | Switch workspace |
| Option + Shift + 1–9 | Move focused window to workspace |
| Option + Minus / Equal | Shrink / grow focused window |
| Option + Slash | Toggle horizontal / vertical tiling |

These defaults are proposals to validate on a Mac. Option-letter bindings can conflict with character entry on some keyboard layouts, so setup must allow changes. Floating and monitor actions may initially be available through the menu rather than additional default bindings.

## Technical direction

- Build a native macOS menu bar companion; Swift and SwiftUI are the proposed implementation.
- Use AeroSpace's supported commands and configuration for window management rather than implementing another tiling engine.
- Implement a terminal launch adapter that explicitly creates a new Terminal window; simply activating Terminal is insufficient.
- Validate the launch sequence so rapid presses and workspace changes do not send a newly created window to the wrong workspace.
- Store product preferences locally. No account, backend, or telemetry is required for the MVP.
- Treat AeroSpace version compatibility, minimum macOS version, Intel support, distribution, and signing as decisions to validate during the technical spike.
- Start validation on Apple silicon with one display; verify monitor connection and disconnection before expanding multi-monitor support.

## Acceptance criteria

| Scenario | Expected result |
| --- | --- |
| Terminal is closed; press Command + Enter | One terminal window opens and receives focus in the current workspace |
| One terminal is open; press Command + Enter | A second independent window opens and the layout splits |
| Press the launch shortcut three times deliberately | Exactly three new windows are created; holding it does not repeat |
| Navigate among tiled windows | Directional shortcuts change focus predictably without typing into the shell |
| Switch to workspace 2 and launch Terminal | The new window belongs to workspace 2; workspace 1 retains its windows |
| Move a window to workspace 3 | Only the focused window moves; the active workspace stays unchanged |
| Close a tiled terminal | Remaining windows expand into the available area |
| Restart the companion | Names and bindings persist; shortcut handlers are not duplicated |
| Existing AeroSpace config is found | Setup shows proposed changes and creates a backup before applying them |
| Required permission is denied | Setup explains the blocked capability and how to enable it |
| Pause the workflow | Product-installed global bindings stop intercepting keys; resume restores them |

## Quality targets and validation

- Workspace switching should feel immediate; target less than 200 ms for switching between already open workspaces on the reference Mac.
- Target less than one second from shortcut to a usable new Terminal window when Terminal is already running.
- Check behavior with browser, editor, and Terminal windows, including dialogs, full-screen windows, rapid shortcut presses, and non-US keyboard layouts.
- Validate pause/resume, configuration backup/restore, and recovery after AeroSpace restarts.
- Measure targets on an actual Mac; this document does not claim tested performance or compatibility.

## Out of scope for the MVP

- A replacement operating system or complete Omarchy port.
- A custom window management engine.
- Terminal tabs, internal panes, or tmux management.
- Native Mission Control Spaces management.
- Themes across all installed apps, a full desktop shell, cloud sync, or a plugin marketplace.
- Automated restoration of complete projects, shell processes, or application sessions.

## Milestones

1. **Technical spike:** verify new-window creation, active-workspace placement, shortcut registration, permissions, and AeroSpace compatibility on a Mac.
2. **Core workflow:** implement terminal launch, automatic tiling, directional focus, and workspace shortcuts.
3. **Companion interface:** add setup, workspace indicator, editable bindings, configuration backup, and pause/resume.
4. **Private alpha:** run the acceptance scenarios, fix reliability issues, document installation and removal, and select supported macOS/AeroSpace versions.

## Later possibilities

Support additional terminals, per-app workspace rules, richer workspace previews, coordinated themes, and project launch presets after the core workflow is reliable.

## Reference

- [AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide): tiling, virtual workspaces, commands, and configuration.

This is an independent project inspired by Omarchy. The working name and visual identity remain provisional.
