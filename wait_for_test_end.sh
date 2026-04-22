#!/usr/bin/env bash
# Poll logs/server.log for TEST_GAME_OVER (winner declared) up to 300 seconds.
# Run after ./run_test.sh.
set -u
TIMEOUT="${TIMEOUT:-300}"
for i in $(seq 1 "$TIMEOUT"); do
	if [[ -f logs/server.log ]] && grep -q "TEST_GAME_OVER" logs/server.log 2>/dev/null; then
		echo "wait_for_test_end: TEST_GAME_OVER found after ${i}s"
		exit 0
	fi
	sleep 1
done
echo "wait_for_test_end: TIMEOUT after ${TIMEOUT}s - no TEST_GAME_OVER in logs/server.log"
exit 1
