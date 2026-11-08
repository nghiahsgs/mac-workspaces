#!/usr/bin/env bash
# End-to-end acceptance checks against a live AeroSpace + installed MacWorkspaces.app.
# Drives the real AeroSpace bindings with `aerospace trigger-binding`, so each check goes
# through the generated config -> exec-and-forget -> URL -> companion -> Terminal path.
#
# Only windows created by this script are closed. Terminal must already be allowed under
# Automation for mac-workspaces. Physical key-hold (auto-repeat) needs a human: see
# docs/VALIDATION.md.
set -uo pipefail
cd "$(dirname "$0")/.."

TERM_ID=com.apple.Terminal
FRAMES=.build/window-frames
[[ -x $FRAMES ]] || swiftc -O scripts/window-frames.swift -o $FRAMES
PASS=0; FAIL=0; CREATED=()
LAT_FILE=$(mktemp); latency(){ cat "$LAT_FILE"; }

ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1  [$2]"; return 1; fi; }
ids()  { aerospace list-windows --monitor all --app-bundle-id $TERM_ID --format '%{window-id}' | sort -n; }
# Window ids only grow, so "new" = greater than the largest id seen before. (Plain set
# differences mis-fire when an existing window briefly drops out of the list.)
newer_than(){ ids | awk -v m="${1:?baseline required}" '$1>m+0'; }
# Every Terminal window that existed before the run, including ones AeroSpace does not
# manage (other macOS Spaces, minimized). These are never closed, whatever happens.
PREEXISTING=$(osascript -e 'tell application "Terminal" to get id of every window' 2>/dev/null | tr -d ' ' | tr ',' '\n' | sort -n)
PRE_MAX=$(echo "$PREEXISTING" | tail -1); PRE_MAX=${PRE_MAX:-0}
# Baseline for "new": never lower than the newest pre-existing window, so a transiently
# incomplete AeroSpace window list cannot make an old window look new.
max_id(){ local a; a=$(ids | tail -1 | awk '{print $1+0}'); a=${a:-0}; (( a > PRE_MAX )) && echo $a || echo $PRE_MAX; }
safe_close(){ local id=$1; grep -qx "$id" <<<"$PREEXISTING" && { echo "      (refusing to close pre-existing window $id)"; return; }; aerospace close --window-id "$id" >/dev/null 2>&1; }
diag(){ echo "      focused ws=$(focused_ws) win=$(focused_win); ws $1: $(aerospace list-windows --workspace $1 --format '%{window-id}/%{window-layout}' | tr '\n' ' ')"; }
ws_of(){ aerospace list-windows --monitor all --app-bundle-id $TERM_ID --format '%{window-id} %{workspace}' | awk -v id="$1" '$1==id{print $2}'; }
focused_ws(){ aerospace list-workspaces --focused; }
focused_win(){ aerospace list-windows --focused --format '%{window-id}' 2>/dev/null; }
now(){ python3 -c 'import time;print(time.time())'; }
width_of(){ $FRAMES Terminal | awk -v id="$1" '$1==id{print $4}'; }
screen_w(){ aerospace list-monitors --focused --format '%{monitor-name}' >/dev/null; osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)' 2>/dev/null; }

# Press cmd-enter through AeroSpace and wait for exactly one new Terminal window.
# Prints the new id; writes the latency to $LAT_FILE.
launch() {
  local m t0 i
  m=$(max_id); t0=$(now)
  aerospace trigger-binding --mode main cmd-enter
  for i in $(seq 1 100); do
    [[ -n "$(newer_than $m)" ]] && break
    sleep 0.05
  done
  python3 -c "print(round($(now)-$t0,2))" > "$LAT_FILE"
  sleep 0.8  # let AeroSpace settle and the companion finish verifying placement/focus
  newer_than $m
}

cleanup() {
  for id in ${CREATED[@]+"${CREATED[@]}"}; do safe_close "$id"; done
  sleep 0.5
  aerospace workspace "$START_WS" >/dev/null 2>&1
}
trap cleanup EXIT

aerospace list-workspaces --focused >/dev/null || { echo "AeroSpace is not running"; exit 1; }
START_WS=$(focused_ws)
for w in 6 7 8 9; do
  [[ -z $(aerospace list-windows --workspace $w --format '%{window-id}') ]] || { echo "workspace $w must be empty for this test"; exit 1; }
done
aerospace workspace 6
echo "AeroSpace $(aerospace --version | tail -1)"
echo

# S1: config valid
check "S1 generated config loads without warnings" "aerospace reload-config --no-gui --dry-run --warnings-as-errors >/dev/null"

# A2: one window -> press -> second window, layout splits
W1=$(launch); CREATED+=($W1); L1=$(latency)
check "Launch creates one new window (got: '$(echo $W1)')" "[[ \$(echo \"$W1\" | wc -w) -eq 1 ]]"
check "New window is in the current workspace (6)" "[[ \$(ws_of $W1) == 6 ]]"
check "New window receives focus" "[[ \$(focused_win) == $W1 ]]"
check "Launch latency < 1 s (${L1}s)" "python3 -c 'import sys; sys.exit(0 if $L1 < 1.0 else 1)'"

W2=$(launch); CREATED+=($W2); L2=$(latency)
check "Second press opens a second independent window (${L2}s)" "[[ \$(echo \"$W2\" | wc -w) -eq 1 && $W2 != $W1 ]]"
check "Layout splits: both windows tiled horizontally" "[[ \$(aerospace list-windows --workspace 6 --app-bundle-id $TERM_ID --format '%{window-layout}' | sort -u) == h_tiles ]]"
w1=$(width_of $W1); w2=$(width_of $W2)
check "Side by side: widths are similar ($w1 / $w2)" "[[ -n '$w1' && -n '$w2' ]] && python3 -c 'import sys; sys.exit(0 if abs($w1-$w2) < 60 else 1)'"

# A4: directional focus changes focus, does not move windows, stops at edges
before_frames=$($FRAMES Terminal | sort)
aerospace trigger-binding --mode main alt-h; sleep 0.3
check "Option+H focuses the left window" "[[ \$(focused_win) == $W1 ]]" || diag 6
aerospace trigger-binding --mode main alt-h; sleep 0.3
check "At the left edge focus stays put" "[[ \$(focused_win) == $W1 ]]"
aerospace trigger-binding --mode main alt-l; sleep 0.3
check "Option+L focuses the right window" "[[ \$(focused_win) == $W2 ]]"
check "Focusing does not move windows" "[[ \"\$($FRAMES Terminal | sort)\" == \"$before_frames\" ]]"

# A3: three deliberate presses -> exactly three windows
m3=$(max_id)
for i in 1 2 3; do aerospace trigger-binding --mode main cmd-enter; sleep 0.35; done
sleep 2
N3=$(newer_than $m3 | tr '\n' ' '); CREATED+=($N3); C3=$(echo $N3 | wc -w | tr -d ' ')
check "Three deliberate presses create exactly three windows (got $C3)" "[[ $C3 -eq 3 ]]"

# Auto-repeat stream (requests 30 ms apart, like a held key) -> one window
# AeroSpace runs each repeat's exec-and-forget concurrently, so fire them in the background
# at a typical 30 ms repeat interval. The key is not physically held here, so this exercises
# the timing safeguard; the key-state path needs a human (docs/VALIDATION.md, S4).
HOLD=.build/hold-key
[[ -x $HOLD ]] || swiftc -O scripts/hold-key.swift -o $HOLD
mh=$(max_id)
$HOLD 2 >/dev/null; sleep 2.5
NH=$(newer_than $mh | tr '\n' ' '); CREATED+=($NH); CH=$(echo $NH | wc -w | tr -d ' ')
check "Holding ⌘Return for 2 s (HID-level key-down + auto-repeat) creates one window (got $CH)" "[[ $CH -eq 1 ]]"
mt=$(max_id)
for i in 1 2 3; do $HOLD 0 press >/dev/null; sleep 0.25; done; sleep 3
NT=$(newer_than $mt | tr '\n' ' '); CREATED+=($NT); CT=$(echo $NT | wc -w | tr -d ' ')
check "Three HID-level ⌘Return taps 250 ms apart create three windows (got $CT)" "[[ $CT -eq 3 ]]"
# Safeguard only: AeroSpace never sends repeats (Carbon hotkeys ignore auto-repeat), but if
# requests arrive in a burst anyway, the companion's timing window thins them out.
mr=$(max_id)
for i in $(seq 1 40); do (/usr/bin/open -g 'macworkspaces://launch-terminal' &); sleep 0.03; done
sleep 3
NR=$(newer_than $mr | tr '\n' ' '); CREATED+=($NR)
echo "INFO  40 concurrent URL requests in 1.2 s produced $(echo $NR | wc -w | tr -d ' ') window(s) (timing safeguard)"

# Clean up the extra windows before workspace checks
for id in ${CREATED[@]+"${CREATED[@]}"}; do [[ $id == $W1 || $id == $W2 ]] || safe_close $id; done
CREATED=($W1 $W2); sleep 0.6

# A7: closing a tiled window -> remaining expands
safe_close $W2; CREATED=($W1); sleep 0.8
w1_after=$(width_of $W1)
check "After closing, remaining window expands ($w1 -> $w1_after)" "[[ -n '$w1_after' ]] && (( w1_after > w1 + 100 ))" || { diag 6; $FRAMES Terminal; }

# A5: workspace 2 launch
t0=$(now); aerospace trigger-binding --mode main alt-7
SWITCH=$(python3 -c "print(round(($(now)-$t0)*1000))")
check "Option+7 switches to workspace 7 (${SWITCH} ms incl. CLI round trip)" "[[ \$(focused_ws) == 7 ]]"
W3=$(launch); CREATED+=($W3)
check "Window launched on workspace 7 belongs to workspace 7" "[[ \$(ws_of $W3) == 7 ]]"
check "Workspace 6 keeps its window" "[[ \$(ws_of $W1) == 6 ]]"

# A6: move focused window to workspace 8; user stays on 7
W4=$(launch); CREATED+=($W4)
aerospace focus --window-id $W4; sleep 0.2
aerospace trigger-binding --mode main alt-shift-8; sleep 0.5
check "Option+Shift+8 moves only the focused window to 8" "[[ \$(ws_of $W4) == 8 && \$(ws_of $W3) == 7 ]]"
check "Active workspace stays 7 after moving" "[[ \$(focused_ws) == 7 ]]"

# Race: press launch, then switch workspace 100 ms later (a fast human) -> the window must
# land in the workspace where the shortcut was pressed.
aerospace workspace 9; m5=$(max_id)
aerospace trigger-binding --mode main cmd-enter; sleep 0.1; aerospace trigger-binding --mode main alt-7
sleep 2.5
W5=$(newer_than $m5); CREATED+=($W5)
check "Launch, switch 100 ms later: window lands in workspace 9 (got '$(ws_of $W5)')" "[[ \$(ws_of $W5) == 9 ]]"
# Stress variant with no gap at all (faster than any human); reported, not required.
aerospace workspace 9; m6=$(max_id)
aerospace trigger-binding --mode main cmd-enter; aerospace trigger-binding --mode main alt-7
sleep 2.5
W5b=$(newer_than $m6); CREATED+=($W5b)
echo "INFO  0 ms switch: window landed in workspace '$(ws_of $W5b)' (9 = press-time workspace)"

# A11: pause/resume through the companion
aerospace workspace 6
/usr/bin/open -g 'macworkspaces://toggle-pause'; sleep 1
check "Pause switches AeroSpace to the empty 'paused' mode" "[[ \$(aerospace list-modes --current) == paused ]]"
check "Paused mode has no bindings" "[[ \$(aerospace config --get mode.paused.binding --json | tr -d ' \n') == '{}' ]]"
/usr/bin/open -g 'macworkspaces://toggle-pause'; sleep 1
check "Resume restores the main bindings" "[[ \$(aerospace list-modes --current) == main ]]"

# Restart the companion: one press -> one window (no duplicate handlers)
pkill -x MacWorkspaces; sleep 0.5; open -g /Applications/MacWorkspaces.app; sleep 2
check "Companion restarted (single instance)" "[[ \$(pgrep -x MacWorkspaces | wc -l) -eq 1 ]]"
aerospace workspace 6 >/dev/null 2>&1; W6=$(launch); CREATED+=($W6)
check "After restart one press creates exactly one window (got '$(echo $W6)')" "[[ \$(echo \"$W6\" | wc -w) -eq 1 ]]"

echo
echo "$PASS passed, $FAIL failed"
exit $(( FAIL > 0 ))
