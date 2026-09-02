#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p logs/xl_runs

PASS=0
FAIL=0

for RUN in 1 2 3 4 5; do
  echo ""
  echo "========== XL run $RUN / 5 =========="
  RUN_DIR="logs/xl_runs/run_${RUN}"
  mkdir -p "$RUN_DIR"

  if ! ./run_test.sh --map=XL; then
    echo "FAIL run $RUN: run_test.sh failed to start"
    FAIL=$((FAIL + 1))
    continue
  fi

  if ! TIMEOUT=300 ./game_assets/wait_for_test_end.sh; then
    echo "FAIL run $RUN: no TEST_GAME_OVER within 300s"
    cp logs/server.log "$RUN_DIR/" 2>/dev/null || true
    cp logs/client_A.log "$RUN_DIR/" 2>/dev/null || true
    cp logs/client_B.log "$RUN_DIR/" 2>/dev/null || true
    FAIL=$((FAIL + 1))
    pkill -9 -f '[g]odot.*-- --server' 2>/dev/null || true
    pkill -9 -f '[g]odot.*-- --client' 2>/dev/null || true
    sleep 3
    continue
  fi

  cp logs/server.log "$RUN_DIR/"
  cp logs/client_A.log "$RUN_DIR/"
  cp logs/client_B.log "$RUN_DIR/"

  RUN_FAIL=""
  grep -qi 'above the MTU' "$RUN_DIR/server.log" && RUN_FAIL="${RUN_FAIL} MTU"
  grep -q 'TEST_CLIENT_DISCONNECT' "$RUN_DIR/client_A.log" "$RUN_DIR/client_B.log" 2>/dev/null && RUN_FAIL="${RUN_FAIL} CLIENT_DISCONNECT"
  grep -q 'TEST_PEER_DISCONNECT' "$RUN_DIR/server.log" && RUN_FAIL="${RUN_FAIL} PEER_DISCONNECT"
  grep -q 'TEST_GAME_START' "$RUN_DIR/server.log" || RUN_FAIL="${RUN_FAIL} NO_GAME_START"
  grep -q 'TEST_ARMIES_SPAWNED' "$RUN_DIR/server.log" || RUN_FAIL="${RUN_FAIL} NO_ARMIES"
  grep -q "MapConfig: loaded 'XL'" "$RUN_DIR/server.log" || RUN_FAIL="${RUN_FAIL} NOT_XL"

  if [ -n "$RUN_FAIL" ]; then
    echo "FAIL run $RUN:$RUN_FAIL"
    FAIL=$((FAIL + 1))
  else
    GO=$(grep -E 'TEST_GAME_OVER:' "$RUN_DIR/server.log" | tail -1)
    LOBBY_A=$(grep -c 'TEST_LOBBY_RETURN' "$RUN_DIR/client_A.log" || true)
    LOBBY_B=$(grep -c 'TEST_LOBBY_RETURN' "$RUN_DIR/client_B.log" || true)
    echo "PASS run $RUN: $GO | lobby_return A=$LOBBY_A B=$LOBBY_B"
    PASS=$((PASS + 1))
  fi

  pkill -9 -f '[g]odot.*-- --server' 2>/dev/null || true
  pkill -9 -f '[g]odot.*-- --client' 2>/dev/null || true
  sleep 3
done

echo ""
echo "========== SUMMARY =========="
echo "Passed: $PASS / 5"
echo "Failed: $FAIL / 5"
exit $FAIL
