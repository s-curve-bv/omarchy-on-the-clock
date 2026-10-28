#!/bin/bash
# End-to-end smoke test against the running Omarchy shell, in demo mode:
# drives the plugin through IPC and real key presses (wtype) and checks the
# result with "omarchy-shell ontheclock state". Run it before a release.
#
# It only acts while demo mode is confirmed on, and checks at the end that
# your own hours.json and its backup repository did not change. The panel
# opens and closes on its own; keep your hands off the keyboard meanwhile.
#   tests/e2e.sh
set -euo pipefail

id=s-curve.on-the-clock
data="$HOME/.local/share/on-the-clock/hours.json"
failures=0

ipc() { omarchy-shell ontheclock "$@"; }
state() { ipc state | jq -c "$1"; }
keys() { for k in "$@"; do wtype -k "$k"; sleep 0.25; done; sleep 0.5; }
open() { omarchy-shell shell summon "$id" '{}' >/dev/null; sleep 1.2; }
close() { omarchy-shell shell hide "$id" >/dev/null; sleep 0.5; }
warnings() { quickshell log -p /usr/share/omarchy/shell 2>/dev/null | grep -c "on-the-clock.*\(WARN\|ERROR\)\|s-curve.on-the-clock/.*qml.*\(Error\|TypeError\|ReferenceError\)" || true; }

check() {  # check <description> <expected> <actual>
  if [[ $2 == "$3" ]]; then echo "ok    $1"
  else echo "FAIL  $1: expected $2, got $3"; failures=$((failures + 1)); fi
}

# Fresh demo data each time: off first, since "on" keeps the current data.
demo_on() {
  ipc demo off >/dev/null
  sleep 1
  [[ $(ipc demo quiet) == "demo data" ]] || { echo "demo mode did not switch on; stopping" >&2; exit 1; }
  sleep 1
  [[ $(state .demo) == true ]] || { echo "not in demo mode; stopping" >&2; exit 1; }
}

command -v wtype >/dev/null || { echo "needs wtype" >&2; exit 1; }
# Saving files in the plugin folder reloads the plugin; wait until it answers.
for _ in $(seq 20); do ipc status >/dev/null 2>&1 && break; sleep 0.5; done
ipc status >/dev/null || { echo "the plugin is not running" >&2; exit 1; }

real_sum=$(sha256sum "$data" 2>/dev/null || true)
real_head=$(git -C "$(dirname "$data")" rev-parse HEAD 2>/dev/null || true)
warnings_before=$(warnings)

finish() {
  local status=$?
  close || true
  ipc demo off >/dev/null || true
  sleep 1
  check "your hours.json is unchanged" "$real_sum" "$(sha256sum "$data" 2>/dev/null || true)"
  check "your backup repository is unchanged" "$real_head" "$(git -C "$(dirname "$data")" rev-parse HEAD 2>/dev/null || true)"
  check "no new QML warnings in the shell log" 0 $(( $(warnings) - warnings_before ))
  echo
  if (( status )); then echo "stopped early (exit $status)"; exit 1; fi
  if (( failures )); then echo "$failures check(s) failed"; exit 1; fi
  echo "all checks passed"
}
trap finish EXIT

echo "-- stopping the demo timer asks what you did"
demo_on
check "demo timer runs on Route planner API" '"p1"' "$(state .timer.projectId)"
check "stopping books 0:45" "booked 0:45" "$(ipc stop)"
sleep 1.5
check "the prompt is open" '"p1"' "$(state .notePrompt.projectId)"
wtype "Reviewed the routing PR"; keys Return Escape
check "the typed line became a note" '["Reviewed the routing PR"]' "$(state '.notesToday.p1')"
check "the prompt closed" null "$(state .notePrompt)"
close

echo "-- keys in Week"
demo_on
ipc stop >/dev/null; sleep 1.5; keys Escape   # stop the demo timer, dismiss its prompt
close
open
before=$(state '.entriesToday.p1 // 0')
keys w plus plus minus
check "+ + - adds 0:15 to the selected cell" $((before + 15)) "$(state '.entriesToday.p1 // 0')"
before=$(state '.entriesToday.p1 // 0')
wtype -M shift -k plus -m shift; sleep 0.5
check "shift + adds 1:00" $((before + 60)) "$(state '.entriesToday.p1 // 0')"
wtype -M shift -k minus -m shift; sleep 0.5
check "shift - removes 1:00" "$before" "$(state '.entriesToday.p1 // 0')"
keys Down Return
check "Enter makes the cursor's project the bar's" true "$(state '.selectedProjectId != "p1"')"
keys Up Return
check "Enter again selects it back" '"p1"' "$(state .selectedProjectId)"
keys n; wtype "Pair programming"; keys Return Escape
check "n adds a note line" '"Pair programming"' "$(state '.notesToday.p1[-1]')"
keys space
check "space starts the timer" '"p1"' "$(state .timer.projectId)"
keys space Escape
check "space again stops it" null "$(state .timer)"
close

echo "-- a dropdown used in another tab doesn't catch keys in Week"
demo_on
links=$(state .links)
open
keys c Tab Tab w Return Down Return
check "calendar links unchanged" "$links" "$(state .links)"
check "no timer started" '"p1"' "$(state .timer.projectId)"   # the demo timer, untouched
keys Escape
close
