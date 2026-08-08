#!/usr/bin/env bash
# QGIS_MCP phased rebuild - detached, survives agent cutoff
# Usage: ops/rebuild.sh <phase>   phase = 1 (pdal/grass) | 2 (full)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PHASE="${1:-1}"
TS=$(date +%Y%m%d-%H%M%S)
LOG=~/logs/qgis_rebuild_${PHASE}_${TS}.log
mkdir -p ~/logs
# Roll back to the LAST KNOWN-GOOD image, not the original snapshot.
# 2026-08-08: a failed build rolled back past the PDAL work and silently
# removed pdal/gdal 3.11 from the running container. Override with env.
ROLLBACK="${ROLLBACK_IMAGE:-qgis-streammcp:last-known-good}"
docker image inspect "$ROLLBACK" >/dev/null 2>&1 || \
  ROLLBACK=qgis-streammcp:rollback-pre-rebuild-20260806
NEW=qgis-streammcp:build-${TS}

exec > >(tee -a "$LOG") 2>&1
echo "=== QGIS rebuild phase=$PHASE start $(date) ==="

fail() { echo "[FAIL] $1"; echo "ROLLBACK: docker compose down; docker tag $ROLLBACK qgis-streammcp-qgisstreammcp:latest; docker compose up -d --no-build"; exit 1; }

echo "--- preflight: compose validates ---"
docker compose config >/dev/null || fail "compose config invalid"

echo "--- preflight: python compiles ---"
python3 -m py_compile main_mcp.py src/*.py helpers/*.py || fail "py_compile"

echo "--- build (target=final) ---"
docker build -t "$NEW" . || fail "docker build"

echo "[OK] image built: $NEW"
docker tag "$NEW" qgis-streammcp-qgisstreammcp:latest || fail "tag"
echo "=== build done $(date) ==="

echo "--- restart container on new image ---"
docker compose down || true
docker compose up -d --no-build || fail "compose up"

echo "--- wait for health (max 180s) ---"
OK=0
for i in $(seq 1 36); do
  S=$(docker inspect -f '{{.State.Health.Status}}' qgisstreammcp 2>/dev/null || echo none)
  [ "$S" = "healthy" ] && OK=1 && break
  sleep 5
done

rollback() {
  echo "[FAIL] $1 -- AUTO-ROLLBACK"
  docker compose down || true
  docker tag "$ROLLBACK" qgis-streammcp-qgisstreammcp:latest
  docker compose up -d --no-build
  sleep 30
  docker ps --filter name=qgisstreammcp --format '{{.Names}} {{.Status}}'
  echo "[ROLLED BACK] to $ROLLBACK"
  exit 1
}

[ "$OK" = "1" ] || rollback "container never became healthy"

echo "--- SECURITY GATES (must all pass) ---"
c() { curl -s -o /dev/null -w "%{http_code}" --max-time 8 "$@"; }
[ "$(c http://100.92.239.85:8113/api/tools)" = "401" ] || rollback "REST auth gate open"
[ "$(c http://100.92.239.85:6080/)" = "401" ] || rollback "noVNC auth gate open"
ss -ltn | grep -q '100.92.239.85:8130' || rollback "MCP not tailscale-bound"
ss -ltn | grep -q '0.0.0.0:8130' && rollback "MCP bound 0.0.0.0"
echo "[OK] security gates pass"

echo "--- CAPABILITY CHECKS (informational) ---"
docker exec qgisstreammcp bash -lc 'which pdal && pdal --version' || echo "[WARN] pdal missing"
docker exec qgisstreammcp bash -lc 'python3 -c "import pdal;print(\"pypdal\",pdal.__version__)"' || echo "[WARN] python pdal missing"
docker exec qgisstreammcp bash -lc 'python3 -c "from osgeo import gdal;print(\"gdal\",gdal.__version__)"' || echo "[WARN] gdal probe failed"
docker exec qgisstreammcp bash -lc 'python3 -c "
from qgis.core import QgsApplication
a=QgsApplication([],False); a.initQgis()
print(\"providers:\",sorted(p.id() for p in a.processingRegistry().providers()))
print(\"algs:\",len(a.processingRegistry().algorithms()))
"' 2>/dev/null || echo "[WARN] provider probe failed"

echo "=== PHASE $PHASE COMPLETE $(date) ==="
echo "log: $LOG"
