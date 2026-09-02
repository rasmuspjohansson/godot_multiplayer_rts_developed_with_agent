#!/usr/bin/env bash
# Poll repo-root logs/server.log for TEST_GAME_OVER (winner declared) up to 300 seconds.
# Run after ./run_test.sh from the repo root.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$SCRIPT_DIR/../logs/server.log"
TIMEOUT="${TIMEOUT:-300}"
for i in $(seq 1 "$TIMEOUT"); do
	if [[ -f "$LOG" ]] && grep -q "TEST_GAME_OVER" "$LOG" 2>/dev/null; then
		echo "wait_for_test_end: TEST_GAME_OVER found after ${i}s"
		exit 0
	fi
	sleep 1
done
echo "wait_for_test_end: TIMEOUT after ${TIMEOUT}s - no TEST_GAME_OVER in $LOG"
exit 1
