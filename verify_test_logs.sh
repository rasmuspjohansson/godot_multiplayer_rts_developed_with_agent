#!/usr/bin/env bash
# Verify that the automated test run succeeded by checking markers from tests.json.
# For each entry in tests.json -> events[]: assert the marker appears in each log file
#   listed in its `logs` array.
# For each entry in tests.json -> other_tests[]: run the implementation command and
#   assert exit 0.
# Exits 0 if everything passes, 1 otherwise.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TESTS_JSON="tests.json"
if [[ ! -f "$TESTS_JSON" ]]; then
  echo "FAIL: $TESTS_JSON not found"
  exit 1
fi

FAIL=0
PASS=0

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

echo "=== Log-marker checks (from tests.json events[]) ==="
for row in "${EVENT_CHECKS[@]}"; do
  marker="${row%%$'\t'*}"
  log="${row##*$'\t'}"
  path="logs/$log"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: log file missing: $path (need marker $marker)"
    FAIL=$((FAIL+1))
    continue
  fi
  if grep -q -- "$marker" "$path"; then
    echo "ok   : $marker in $log"
    PASS=$((PASS+1))
  else
    echo "FAIL : $marker missing in $log"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "=== other_tests (from tests.json other_tests[]) ==="
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

for row in "${OTHER_TESTS[@]}"; do
  desc="${row%%$'\x1f'*}"
  impl="${row##*$'\x1f'}"
  echo "--- $desc"
  if bash -c "$impl" >/dev/null 2>&1; then
    echo "ok   : $desc"
    PASS=$((PASS+1))
  else
    echo "FAIL : $desc"
    echo "      cmd: $impl"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  echo "OK"
  exit 0
fi
exit 1
