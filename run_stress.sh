#!/usr/bin/env bash
# Stress run: server + two auto-test clients with N soldiers per player, then summarise
# TEST_PERF_* markers from the logs.
#
#   ./run_stress.sh                      # 1000 soldiers/player on XL, 90 s
#   ./run_stress.sh --units=500 --map=L --seconds=60
#
# Pass/fail thresholds (override via env): SERVER_TICK_MS_MAX (25), CLIENT_FPS_MIN (45).

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

UNITS=1000
MAP="XL"
SECONDS_TO_RUN=90
for arg in "$@"; do
  case "$arg" in
    --units=*) UNITS="${arg#*=}" ;;
    --map=*) MAP="${arg#*=}" ;;
    --seconds=*) SECONDS_TO_RUN="${arg#*=}" ;;
  esac
done
SERVER_TICK_MS_MAX="${SERVER_TICK_MS_MAX:-25}"
CLIENT_FPS_MIN="${CLIENT_FPS_MIN:-45}"

./run_test.sh --map="$MAP" --stress-units="$UNITS" || exit 1
echo "Stress run: units/player=$UNITS map=$MAP; sampling for ${SECONDS_TO_RUN}s..."
sleep "$SECONDS_TO_RUN"

pkill -9 -f -- '[g]odot.*-- --server' 2>/dev/null || true
pkill -9 -f -- '[g]odot.*-- --client' 2>/dev/null || true
sleep 1

summarise() {
  local file="$1" marker="$2"
  python3 - "$file" "$marker" <<'PY'
import re, sys
path, marker = sys.argv[1], sys.argv[2]
rows = []
for line in open(path, errors="replace"):
    if marker not in line:
        continue
    kv = dict(re.findall(r"(\w+)=(-?[\d.]+)", line))
    rows.append(kv)
if not rows:
    print(f"  {path}: no {marker} lines")
    sys.exit(0)
# Skip the first sample (spawn/load spike).
rows = rows[1:] if len(rows) > 1 else rows
def col(k):
    vals = [float(r[k]) for r in rows if k in r]
    return vals
def fmt(k):
    v = col(k)
    return f"{k}: avg={sum(v)/len(v):.2f} max={max(v):.2f}" if v else f"{k}: n/a"
keys = [k for k in ("avg", "max", "sim_avg", "sim_max", "phys_avg", "sim_hz", "fps", "units", "mem_mb", "rx_kbs", "tx_kbs") if any(k in r for r in rows)]
print(f"  {path} ({len(rows)} samples): " + " | ".join(fmt(k) for k in keys))
PY
}

echo "=== Stress summary ==="
grep -h "TEST_STRESS_SPAWN\|TEST_ARMIES_SPAWNED" logs/server.log | head -5
summarise logs/server.log TEST_PERF_TICK_MS
summarise logs/client_A.log TEST_PERF_FRAME_MS
summarise logs/client_B.log TEST_PERF_FRAME_MS
MTU=$(grep -c "above the MTU" logs/server.log || true)
echo "  MTU warnings: $MTU"
grep -h "TEST_SIM_" logs/server.log logs/client_A.log logs/client_B.log 2>/dev/null | sort | uniq -c | head -20

python3 - "$SERVER_TICK_MS_MAX" "$CLIENT_FPS_MIN" <<'PY'
import re, sys
tick_max, fps_min = float(sys.argv[1]), float(sys.argv[2])
def samples(path, marker):
    out = []
    for line in open(path, errors="replace"):
        if marker in line:
            out.append(dict(re.findall(r"(\w+)=(-?[\d.]+)", line)))
    return out[1:] if len(out) > 1 else out
ok = True
srv = samples("logs/server.log", "TEST_PERF_TICK_MS")
if srv:
    avg = sum(float(r["sim_avg"]) for r in srv) / len(srv)
    print(f"  server sim tick avg {avg:.2f} ms (limit {tick_max})", "OK" if avg <= tick_max else "FAIL")
    ok &= avg <= tick_max
    hz = [float(r["sim_hz"]) for r in srv if "sim_hz" in r]
    if hz:
        hz_avg = sum(hz) / len(hz)
        print(f"  server sim rate {hz_avg:.1f} Hz (min 19)", "OK" if hz_avg >= 19.0 else "FAIL")
        ok &= hz_avg >= 19.0
for c in ("A", "B"):
    cl = samples(f"logs/client_{c}.log", "TEST_PERF_FRAME_MS")
    if cl:
        fps = sum(float(r["fps"]) for r in cl) / len(cl)
        print(f"  client {c} fps {fps:.1f} (min {fps_min})", "OK" if fps >= fps_min else "FAIL")
        ok &= fps >= fps_min
print("STRESS_RESULT:", "PASS" if ok else "FAIL")
PY
