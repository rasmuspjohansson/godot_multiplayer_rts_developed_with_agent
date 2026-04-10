#!/usr/bin/env bash
# After ./run_test.sh completes the auto-test (~60–120s), run this to assert log markers.
# Exits 0 if client logs look good for 3D texture validation; 1 otherwise.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BAD_PATTERN='TEST_3D_TEXTURE_MISSING|TEST_3D_TEXTURES_BAD|TEST_3D_TEXTURE_LOAD_FAILED|TEST_3D_UNIT_HEIGHT_INVALID|TEST_SERVER_UNIT_POSITION_INVALID|TEST_TEXTURE_PATH_FAIL'
FAIL=0

for f in logs/client_A.log logs/client_B.log; do
	if [[ ! -f "$f" ]]; then
		echo "FAIL: $f not found (run ./run_test.sh first)"
		FAIL=1
		continue
	fi
	if grep -E "$BAD_PATTERN" "$f" >/dev/null 2>&1; then
		echo "FAIL: invalid markers in $f:"
		grep -E "$BAD_PATTERN" "$f" || true
		FAIL=1
	fi
done

if [[ -f logs/client_A.log ]] && ! grep -q "TEST_3D_TEXTURES_OK" logs/client_A.log; then
	echo "FAIL: logs/client_A.log must contain TEST_3D_TEXTURES_OK (3D auto-test not finished?)"
	FAIL=1
fi
if [[ -f logs/client_B.log ]] && ! grep -q "TEST_3D_TEXTURES_OK" logs/client_B.log; then
	echo "FAIL: logs/client_B.log must contain TEST_3D_TEXTURES_OK"
	FAIL=1
fi
if [[ -f logs/client_A.log ]] && ! grep -q "TEST_3D_CLIENT_UNITS_SPAWNED: units=40" logs/client_A.log; then
	echo "FAIL: logs/client_A.log must contain TEST_3D_CLIENT_UNITS_SPAWNED: units=40 (3D units not spawned?)"
	FAIL=1
fi
if [[ -f logs/client_B.log ]] && ! grep -q "TEST_3D_CLIENT_UNITS_SPAWNED: units=40" logs/client_B.log; then
	echo "FAIL: logs/client_B.log must contain TEST_3D_CLIENT_UNITS_SPAWNED: units=40"
	FAIL=1
fi

if [[ -f logs/server.log ]] && ! grep -q "TEST_GROUP_FORMATION: server" logs/server.log; then
	echo "FAIL: logs/server.log must contain TEST_GROUP_FORMATION (group formation RPC)"
	FAIL=1
fi
for f in logs/client_A.log logs/client_B.log; do
	if [[ -f "$f" ]] && ! grep -q "TEST_GROUP_FORMATION: client" "$f"; then
		echo "FAIL: $f must contain TEST_GROUP_FORMATION: client (events 1 mock)"
		FAIL=1
	fi
done

if [[ "$FAIL" -eq 0 ]]; then
	echo "OK: client logs contain TEST_3D_TEXTURES_OK, TEST_3D_CLIENT_UNITS_SPAWNED (40 units), and TEST_GROUP_FORMATION; no texture/height invalid markers."
fi
exit "$FAIL"
