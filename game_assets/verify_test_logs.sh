#!/usr/bin/env bash
# Verify that the automated test run succeeded by checking markers from tests.json.
# For each entry in tests.json -> events[]: assert the marker appears in each log file
#   listed in its `logs` array.
# For each entry in tests.json -> other_tests[]: run the implementation command and
#   assert exit 0.
# Exits 0 if everything passes, 1 otherwise.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOGS_DIR="$REPO_ROOT/logs"
cd "$SCRIPT_DIR"

TESTS_JSON="tests.json"
if [[ ! -f "$TESTS_JSON" ]]; then
  echo "FAIL: $TESTS_JSON not found"
  exit 1
fi

FAIL=0
PASS=0

# Print immediately even when stdout is redirected to a file (bash block-buffers it otherwise,
# so a long run looks stuck).
progress() { python3 -c 'import sys; print(sys.argv[1], flush=True)' "$*"; }

# Emit "marker<TAB>log_basename" lines for every (event, log) pair.
mapfile -t EVENT_CHECKS < <(python3 -c '
import json,sys
with open("tests.json") as f:
    d=json.load(f)
for e in d.get("events",[]):
    m=e.get("marker","")
    for lg in e.get("logs",[]):
        print(m+"\t"+lg)
')

progress "=== Log-marker checks (${#EVENT_CHECKS[@]} from tests.json events[]) ==="
n=0
for row in "${EVENT_CHECKS[@]}"; do
  n=$((n+1))
  marker="${row%%$'\t'*}"
  log="${row##*$'\t'}"
  path="$LOGS_DIR/$log"
  if [[ ! -f "$path" ]]; then
    progress "[$n/${#EVENT_CHECKS[@]}] FAIL: log file missing: $path (need marker $marker)"
    FAIL=$((FAIL+1))
    continue
  fi
  if grep -q -- "$marker" "$path"; then
    progress "[$n/${#EVENT_CHECKS[@]}] ok   : $marker in $log"
    PASS=$((PASS+1))
  else
    progress "[$n/${#EVENT_CHECKS[@]}] FAIL : $marker missing in $log"
    FAIL=$((FAIL+1))
  fi
done

mapfile -t OTHER_TESTS < <(python3 -c '
import json,sys
with open("tests.json") as f:
    d=json.load(f)
for t in d.get("other_tests",[]):
    desc=t.get("description_of_test","")
    impl=t.get("implementation","")
    # Use a separator unlikely to occur in either field.
    print(desc+"\x1f"+impl)
')

progress ""
progress "=== other_tests (${#OTHER_TESTS[@]} from tests.json; headless Godot checks, each can take a while) ==="
n=0
for row in "${OTHER_TESTS[@]}"; do
  n=$((n+1))
  desc="${row%%$'\x1f'*}"
  impl="${row##*$'\x1f'}"
  progress "[$n/${#OTHER_TESTS[@]}] running: $desc"
  start=$SECONDS
  if bash -c "$impl" >/dev/null 2>&1; then
    progress "[$n/${#OTHER_TESTS[@]}] ok   ($((SECONDS - start))s): $desc"
    PASS=$((PASS+1))
  else
    progress "[$n/${#OTHER_TESTS[@]}] FAIL ($((SECONDS - start))s): $desc"
    progress "      cmd: $impl"
    FAIL=$((FAIL+1))
  fi
done

progress ""
progress "=== Summary ==="
progress "Passed: $PASS"
progress "Failed: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  progress "OK"
  exit 0
fi
exit 1
